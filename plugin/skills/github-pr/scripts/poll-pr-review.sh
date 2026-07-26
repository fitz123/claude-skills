#!/usr/bin/env bash
# Poll a GitHub PR until Copilot activity for the CURRENT PR head is present
# and all CI checks are completed. Emits visible progress so a watching agent can
# see liveness instead of staring at an empty file.
#
# Why current-head activity: if this script starts after Copilot has already
# reviewed the latest commit, that completed review is success. It must not be
# treated as the baseline and then wait forever for one more review.
#
# Why "or a fresh Copilot comment": when GitHub's REST review-request endpoint
# silently dedupes after a few rapid reviews, the `@copilot please re-review`
# comment fallback causes Copilot to reply as a COMMENT (`copilot-swe-agent`),
# not as a formal review. A watcher that only checks `reviews[]` waits forever.
#
# Why a terminal fallback failure also completes the Copilot wait: GitHub can
# accept the fallback comment, start Copilot Agent, and then record a generic
# `copilot_work_finished_failure` timeline event without posting a review or
# comment. Correlating that event by timeline order to the current head's marked
# request, unless a newer Copilot trigger supersedes it, lets the poller stop
# waiting for review activity while still requiring CI to finish.
#
# Usage:
#   poll-pr-review.sh <pr-number> [timeout-seconds]
#   poll-pr-review.sh 15
#   poll-pr-review.sh 15 900
#
# Optional completion notification (absent-safe — nothing is sent unless set):
#   GH_PR_NOTIFY_TARGET=<chat_id>   deliver a one-line completion summary to
#                                   this Telegram chat via the Minime notify
#                                   helper when polling finishes
#   GH_PR_NOTIFY_THREAD=<topic_id>  optional forum topic for the delivery
#   GH_PR_NOTIFY_SCRIPT=<path>      override the notify helper (default:
#                                   $MINIME_CONTROL_WORKSPACE_ROOT/scripts/
#                                   notify-telegram-configured.sh)
#
# Exits 0 when both conditions are met OR timeout is reached (still emits final state).
set -u

pr="${1:?usage: $0 <pr-number> [timeout-seconds]}"
budget="${2:-600}"

# Login forms used by GitHub's Copilot PR-review integration:
#   requested reviewer / gh pr view review author: copilot-pull-request-reviewer
#   REST pull-review author: copilot-pull-request-reviewer[bot]
#   @mention comment reply author: copilot-swe-agent
review_author="copilot-pull-request-reviewer"
review_author_api="copilot-pull-request-reviewer[bot]"
comment_author="copilot-swe-agent"

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
[ -z "$repo" ] && { echo "ERROR: couldn't determine repo (run inside a gh-tracked clone)"; exit 1; }

head_sha=$(gh pr view "$pr" --json headRefOid --jq .headRefOid)
[ -z "$head_sha" ] && { echo "ERROR: couldn't determine PR head sha"; exit 1; }
head_commit_at=$(gh pr view "$pr" --json commits --jq '.commits[-1].committedDate // ""' 2>/dev/null || echo "")

checks_complete() {
    # CI: all checks have a real completedAt (i.e., nothing in flight).
    # NOTE: do NOT compare state == "COMPLETED" — `gh pr checks --json state`
    # returns SUCCESS/FAILURE/IN_PROGRESS/PENDING etc, not COMPLETED.
    # NOTE: current gh emits the Go zero time "0001-01-01T00:00:00Z" for an
    # in-progress check instead of null — treat it as pending, not settled.
    gh pr checks "$pr" --json completedAt \
        --jq '[.[].completedAt] | all(. != null and . != "" and (startswith("0001-01-01") | not))' 2>/dev/null || echo false
}

current_head_reviews() {
    # REST exposes commit_id, unlike `gh pr view --json reviews`. Restricting to
    # commit_id=head prevents an old Copilot review from a previous push from
    # satisfying a new round.
    gh api "repos/$repo/pulls/$pr/reviews" \
        --jq "[.[] | select((.user.login == \"$review_author\" or .user.login == \"$review_author_api\") and .commit_id == \"$head_sha\")] | length" \
        2>/dev/null || echo 0
}

copilot_comments_since_head() {
    if [ -z "$head_commit_at" ]; then
        echo 0
        return
    fi
    gh pr view "$pr" --json comments \
        --jq "[.comments[] | select(.author.login == \"$comment_author\" and .createdAt >= \"$head_commit_at\")] | length" \
        2>/dev/null || echo 0
}

current_head_fallback_state() {
    # Evaluate the timeline as an ordered stream instead of comparing GitHub's
    # second-resolution timestamps. This keeps an immediate failure visible and
    # lets a newer fallback, REST request, or unrelated @copilot trigger
    # supersede an older failure while the poller is still running.
    local request_marker="<!-- github-pr-rereview-head:$head_sha -->"
    local timeline_json
    if ! timeline_json=$(gh api "repos/$repo/issues/$pr/timeline?per_page=100" \
        -H "Accept: application/vnd.github+json" --paginate 2>/dev/null); then
        return 1
    fi

    jq -sr --arg marker "$request_marker" \
            'def event_login:
                ((.user.login // .actor.login // "") | ascii_downcase);
             def is_copilot_actor:
                event_login as $login |
                ($login == "copilot" or
                 ($login | startswith("copilot-")) or
                 ($login | startswith("github-copilot")));
             def is_marked_fallback:
                (.event == "commented") and
                (is_copilot_actor | not) and
                (((.body // "") | startswith("@copilot please re-review"))) and
                (((.body // "") | contains($marker)));
             def is_copilot_review_request:
                (.event == "review_requested") and
                (((.requested_reviewer.login // "") | ascii_downcase) as $login |
                    ($login == "copilot" or
                     $login == "copilot-pull-request-reviewer" or
                     $login == "copilot-pull-request-reviewer[bot]"));
             def is_copilot_trigger_comment:
                (.event == "commented") and
                (is_copilot_actor | not) and
                (((.body // "") | test("@copilot"; "i")));
             [.[][]?] as $events |
             ([$events | to_entries[] | select(.value | is_marked_fallback)] | last) as $request |
             if $request == null then
                ["none", "none", "no"] | @tsv
             else
                [$events | to_entries[] | select(.key > $request.key) | .value] as $after |
                [
                    (($request.value.id // $request.value.node_id // $request.key) | tostring),
                    ($request.value.created_at // "unknown"),
                    (if any($after[]; is_copilot_review_request or is_copilot_trigger_comment)
                     then "no"
                     elif any($after[]; .event == "copilot_work_finished_failure")
                     then "yes"
                     else "no"
                     end)
                ] | @tsv
             end' 2>/dev/null <<< "$timeline_json"
}

notify_completion() {
    # Push the poll outcome back to the chat that launched the cycle instead of
    # leaving it only in a background log. Absent-safe: without a target this
    # is a no-op and delivery failures never change the poller's exit code.
    local target="${GH_PR_NOTIFY_TARGET:-}"
    [ -z "$target" ] && return 0
    local notify_script="${GH_PR_NOTIFY_SCRIPT:-${MINIME_CONTROL_WORKSPACE_ROOT:-$HOME/.minime/control-workspace}/scripts/notify-telegram-configured.sh}"
    if [ ! -x "$notify_script" ]; then
        echo "[poll] WARNING: GH_PR_NOTIFY_TARGET is set but notify helper is unavailable: $notify_script"
        return 0
    fi
    local summary="github-pr poll finished: $repo PR #$pr — checks_done=$checks_done copilot_activity=$activity_seen copilot_terminal_failure=$terminal_failure_seen"
    if [ -n "${GH_PR_NOTIFY_THREAD:-}" ]; then
        printf '%s\n' "$summary" | "$notify_script" "$target" --thread "$GH_PR_NOTIFY_THREAD" \
            || echo "[poll] WARNING: completion notification delivery failed"
    else
        printf '%s\n' "$summary" | "$notify_script" "$target" \
            || echo "[poll] WARNING: completion notification delivery failed"
    fi
}

print_final_state() {
    echo
    echo "=== FINAL STATE — pr=#$pr ==="
    gh pr checks "$pr"
    echo
    echo "=== REVIEWS ==="
    gh pr view "$pr" --json reviews --jq '[.reviews[] | {author: .author.login, state, submittedAt}]'
    echo
    echo "=== RECENT COPILOT COMMENTS (last 3) ==="
    gh pr view "$pr" --json comments \
        --jq "[.comments[] | select(.author.login == \"$comment_author\") | {created: .createdAt, body: (.body[0:300])}] | .[-3:]"
    echo
    echo "=== UNRESOLVED REVIEW THREADS ==="
    gh api graphql -f query="{repository(owner:\"${repo%/*}\",name:\"${repo#*/}\"){pullRequest(number:$pr){reviewThreads(first:50){nodes{id isResolved comments(last:1){nodes{path line author{login} body}}}}}}}" \
        --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {id, path: .comments.nodes[0].path, line: .comments.nodes[0].line, author: .comments.nodes[0].author.login, body_head: (.comments.nodes[0].body[0:300])}]'
}

# Baselines: count Copilot activity that already belongs to the current PR head.
start_reviews=$(current_head_reviews)
start_comments=$(copilot_comments_since_head)
activity_seen=$([ "$start_reviews" -gt 0 ] || [ "$start_comments" -gt 0 ] && echo "yes" || echo "no")
checks_done=$(checks_complete)

terminal_failure_seen="no"
if [ "$activity_seen" = "yes" ] && [ "$checks_done" = "true" ]; then
    echo "[poll] current head already has Copilot activity and CI is done — no re-request needed"
    print_final_state
    notify_completion
    exit 0
fi

# Pre-flight: if Copilot isn't pending AND no current-head Copilot activity
# exists yet, request one before polling. If activity already exists but CI is
# still running, wait for CI only instead of posting a duplicate @copilot nudge.
#
# `requested_reviewers` lists the BOT login `copilot-pull-request-reviewer`,
# even though the POST endpoint takes the literal token `Copilot`. Check the
# listing form here.
pending=$(gh api "repos/$repo/pulls/$pr/requested_reviewers" \
    --jq "[.users[]? | select(.login == \"$review_author\")] | length" 2>/dev/null || echo 0)
if [ "$pending" -eq 0 ] && [ "$activity_seen" = "no" ]; then
    echo "[poll] no pending Copilot review request and no current-head activity — invoking request-copilot-rereview.sh first"
    "$(dirname "$0")/request-copilot-rereview.sh" "$pr" || \
        echo "[poll] WARNING: pre-flight request returned non-zero; polling anyway"
elif [ "$pending" -eq 0 ]; then
    echo "[poll] current head already has Copilot activity — waiting for CI only"
else
    echo "[poll] Copilot already pending as reviewer — skipping pre-flight request"
fi

fallback_request_id="none"
fallback_request_at="none"
terminal_failure_seen="no"
if fallback_state=$(current_head_fallback_state); then
    IFS=$'\t' read -r fallback_request_id fallback_request_at terminal_failure_seen <<< "$fallback_state"
else
    echo "[poll] WARNING: could not read the complete PR timeline — fallback state remains unknown and will be retried"
fi

if [ "$terminal_failure_seen" = "yes" ]; then
    echo "[poll] current-head fallback request ended with copilot_work_finished_failure — no Copilot review activity expected; waiting for CI only"
fi

echo "[poll] repo=$repo pr=#$pr head=$head_sha baseline: current_head_reviews=$start_reviews copilot_comments_since_head=$start_comments activity_seen=$activity_seen fallback_request_at=$fallback_request_at budget=${budget}s"

deadline=$((SECONDS + budget))
iter=0
while [ $SECONDS -lt $deadline ]; do
    iter=$((iter + 1))
    elapsed=$SECONDS
    fallback_state_fresh="no"

    checks_done=$(checks_complete)
    cur_reviews=$(current_head_reviews)
    cur_comments=$(copilot_comments_since_head)

    new_review=$([ "$cur_reviews" -gt "$start_reviews" ] && echo "yes" || echo "no")
    new_comment=$([ "$cur_comments" -gt "$start_comments" ] && echo "yes" || echo "no")
    if [ "$new_review" = "yes" ] || [ "$new_comment" = "yes" ]; then
        activity_seen="yes"
    fi

    if [ "$activity_seen" = "no" ]; then
        if fallback_state=$(current_head_fallback_state); then
            fallback_state_fresh="yes"
            previous_fallback_request_id="$fallback_request_id"
            previous_terminal_failure_seen="$terminal_failure_seen"
            IFS=$'\t' read -r fallback_request_id fallback_request_at terminal_failure_seen <<< "$fallback_state"

            if [ "$fallback_request_id" != "none" ] && [ "$fallback_request_id" != "$previous_fallback_request_id" ]; then
                echo "[poll] newest current-head fallback marker became visible at $fallback_request_at"
            fi
            if [ "$previous_terminal_failure_seen" = "yes" ] && [ "$terminal_failure_seen" = "no" ]; then
                echo "[poll] newer Copilot trigger superseded the prior terminal failure — resuming Copilot review wait"
            elif [ "$previous_terminal_failure_seen" = "no" ] && [ "$terminal_failure_seen" = "yes" ]; then
                echo "[poll] current-head fallback request ended with copilot_work_finished_failure — no Copilot review activity expected; waiting for CI only"
            fi
        else
            echo "[poll] WARNING: could not refresh the complete PR timeline — preserving the last known fallback state"
        fi
    fi

    printf '[poll] iter=%d t=%ds checks_done=%s activity_seen=%s terminal_failure_seen=%s fallback_state_fresh=%s new_review=%s new_comment=%s (head_reviews %s→%s comments_since_head %s→%s)\n' \
        "$iter" "$elapsed" "$checks_done" "$activity_seen" "$terminal_failure_seen" "$fallback_state_fresh" "$new_review" "$new_comment" \
        "$start_reviews" "$cur_reviews" "$start_comments" "$cur_comments"

    if [ "$checks_done" = "true" ] && [ "$activity_seen" = "yes" ]; then
        echo "[poll] CI done + Copilot activity observed — exiting loop"
        break
    fi
    if [ "$checks_done" = "true" ] && [ "$terminal_failure_seen" = "yes" ] && [ "$fallback_state_fresh" = "yes" ]; then
        echo "[poll] CI done + Copilot terminal failure observed — exiting loop"
        break
    fi
    sleep 20
done

print_final_state
notify_completion
