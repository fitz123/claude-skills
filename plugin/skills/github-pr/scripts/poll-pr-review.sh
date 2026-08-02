#!/usr/bin/env bash
# Poll a GitHub PR until the CURRENT PR head has successful CI and then
# current-head Copilot activity. CI is a strict gate: the poller never spends a
# Copilot request while checks are pending or failed. Emits visible progress so
# a watching agent can see liveness instead of staring at an empty file.
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
# waiting for review activity while still requiring green CI.
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
#   GH_PR_REQUEST_SCRIPT=<path>     override the bundled Copilot request helper
#                                   (primarily for regression tests)
#   GH_PR_ALLOW_NO_CHECKS=1         explicitly treat a PR with zero checks as
#                                   eligible for review; absent by default
#
# The timeout budget applies separately to the CI wait and Copilot wait. Exits
# 0 only after green CI plus Copilot activity (or a correlated terminal Copilot
# failure). CI failure, head changes, query/policy errors, and timeout are
# machine-distinguishable non-zero outcomes.
set -u

pr="${1:?usage: $0 <pr-number> [timeout-seconds]}"
budget="${2:-600}"
request_script="${GH_PR_REQUEST_SCRIPT:-$(dirname "$0")/request-copilot-rereview.sh}"
allow_no_checks="${GH_PR_ALLOW_NO_CHECKS:-0}"

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

checks_status() {
    # `gh pr checks` can return non-zero for a completed failed check while
    # still emitting valid JSON, so classify the payload rather than its exit
    # code. A real completedAt is required even when state looks terminal;
    # current gh uses Go's zero time for some in-progress checks.
    local checks_json
    checks_json=$(gh pr checks "$pr" --json state,completedAt 2>/dev/null)
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$checks_json"; then
        echo "query_error"
        return
    fi

    jq -r '
        if length == 0 then "none"
        elif any(.[];
            ((.state // "") == "IN_PROGRESS") or
            ((.state // "") == "PENDING") or
            ((.state // "") == "QUEUED") or
            ((.state // "") == "WAITING") or
            ((.state // "") == "REQUESTED") or
            (.completedAt == null) or
            (.completedAt == "") or
            ((.completedAt // "") | startswith("0001-01-01")))
        then "pending"
        elif all(.[];
            ((.state // "") == "SUCCESS") or
            ((.state // "") == "SKIPPED") or
            ((.state // "") == "NEUTRAL"))
        then "success"
        else "failure"
        end
    ' <<< "$checks_json" 2>/dev/null || echo "query_error"
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
    local summary="github-pr poll finished: $repo PR #$pr — outcome=$poll_outcome checks_state=$checks_state checks_done=$checks_done copilot_activity=$activity_seen copilot_terminal_failure=$terminal_failure_seen"
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
checks_state="unknown"
checks_done="false"
terminal_failure_seen="no"
poll_outcome="running"
request_gate_done="no"
review_budget_started="no"

finish_with_error() {
    poll_outcome="$1"
    local exit_code="$2"
    local message="$3"
    echo "$message"
    print_final_state
    notify_completion
    exit "$exit_code"
}

ensure_current_head() {
    local current_head
    if ! current_head=$(gh pr view "$pr" --json headRefOid --jq .headRefOid 2>/dev/null) || [ -z "$current_head" ]; then
        finish_with_error "head-query-error" 4 "[poll] ERROR: could not verify the current PR head; refusing stale CI/review evidence"
    fi
    if [ "$current_head" != "$head_sha" ]; then
        finish_with_error "head-changed" 3 "[poll] ERROR: PR head changed while polling (expected ${head_sha:0:12}, current ${current_head:0:12}); refusing stale CI/review evidence"
    fi
}

refresh_checks() {
    checks_state=$(checks_status)
    case "$checks_state" in
        success)
            checks_done="true"
            ;;
        pending)
            checks_done="false"
            ;;
        failure)
            checks_done="true"
            if [ "$request_gate_done" = "no" ]; then
                finish_with_error "ci-failed" 2 "[poll] ERROR: CI checks failed — Copilot was not requested"
            fi
            finish_with_error "ci-failed" 2 "[poll] ERROR: CI checks failed after the review gate; stopping"
            ;;
        none)
            if [ "$allow_no_checks" = "1" ]; then
                echo "[poll] no CI checks; GH_PR_ALLOW_NO_CHECKS=1 explicitly permits review"
                checks_state="success"
                checks_done="true"
            else
                checks_done="false"
                finish_with_error "no-check-policy" 4 "[poll] ERROR: no CI checks found; set GH_PR_ALLOW_NO_CHECKS=1 only when repository policy explicitly permits review"
            fi
            ;;
        *)
            checks_done="false"
            finish_with_error "checks-query-error" 4 "[poll] ERROR: could not classify current-head CI checks"
            ;;
    esac
}

request_copilot_if_ready() {
    [ "$request_gate_done" = "no" ] || return 0
    [ "$checks_state" = "success" ] || return 0
    [ "$activity_seen" = "no" ] || { request_gate_done="yes"; return 0; }
    [ "$terminal_failure_seen" = "no" ] || { request_gate_done="yes"; return 0; }

    ensure_current_head
    # `requested_reviewers` lists the bot login even though the POST endpoint
    # takes the literal token `Copilot`.
    local pending
    if ! pending=$(gh api "repos/$repo/pulls/$pr/requested_reviewers" \
        --jq "[.users[]? | select(.login == \"$review_author\")] | length" 2>/dev/null); then
        finish_with_error "review-request-query-error" 4 "[poll] ERROR: could not determine whether Copilot is already pending; refusing a possible duplicate request"
    fi
    case "$pending" in
        ''|*[!0-9]*)
            finish_with_error "review-request-query-error" 4 "[poll] ERROR: invalid pending-reviewer response; refusing a possible duplicate request"
            ;;
    esac
    if [ "$pending" -eq 0 ]; then
        echo "[poll] CI green — requesting Copilot review for head ${head_sha:0:12}"
        "$request_script" "$pr" || \
            echo "[poll] WARNING: CI-gated review request returned non-zero; polling anyway"
    else
        echo "[poll] CI green and Copilot is already pending — no duplicate request"
    fi
    request_gate_done="yes"
}

refresh_checks
if [ "$activity_seen" = "yes" ] && [ "$checks_state" = "success" ]; then
    ensure_current_head
    poll_outcome="success"
    echo "[poll] current head already has Copilot activity and green CI — no re-request needed"
    print_final_state
    notify_completion
    exit 0
fi

fallback_request_id="none"
fallback_request_at="none"
fallback_state_fresh="no"
if fallback_state=$(current_head_fallback_state); then
    fallback_state_fresh="yes"
    IFS=$'\t' read -r fallback_request_id fallback_request_at terminal_failure_seen <<< "$fallback_state"
else
    echo "[poll] WARNING: could not read the complete PR timeline — fallback state remains unknown and will be retried"
fi

if [ "$terminal_failure_seen" = "yes" ]; then
    echo "[poll] current-head fallback request ended with copilot_work_finished_failure — no Copilot review activity expected; waiting for green CI only"
fi

if [ "$checks_state" = "success" ]; then
    review_budget_started="yes"
    request_copilot_if_ready
else
    echo "[poll] CI pending — deferring Copilot request for head ${head_sha:0:12}"
fi

echo "[poll] repo=$repo pr=#$pr head=$head_sha baseline: checks_state=$checks_state current_head_reviews=$start_reviews copilot_comments_since_head=$start_comments activity_seen=$activity_seen fallback_request_at=$fallback_request_at budget=${budget}s-per-phase"

deadline=$((SECONDS + budget))
iter=0
completed="no"
while [ $SECONDS -lt $deadline ]; do
    iter=$((iter + 1))
    elapsed=$SECONDS
    fallback_state_fresh="no"

    ensure_current_head
    previous_checks_state="$checks_state"
    refresh_checks
    if [ "$checks_state" = "success" ] && [ "$review_budget_started" = "no" ]; then
        review_budget_started="yes"
        deadline=$((SECONDS + budget))
        echo "[poll] CI became green — starting the bounded Copilot-review phase"
    fi

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
                echo "[poll] current-head fallback request ended with copilot_work_finished_failure — no Copilot review activity expected"
            fi
        else
            echo "[poll] WARNING: could not refresh the complete PR timeline — preserving the last known fallback state"
        fi
    fi

    if [ "$checks_state" = "success" ]; then
        request_copilot_if_ready
    fi

    printf '[poll] iter=%d t=%ds checks_state=%s checks_done=%s activity_seen=%s terminal_failure_seen=%s fallback_state_fresh=%s new_review=%s new_comment=%s (head_reviews %s→%s comments_since_head %s→%s)\n' \
        "$iter" "$elapsed" "$checks_state" "$checks_done" "$activity_seen" "$terminal_failure_seen" "$fallback_state_fresh" "$new_review" "$new_comment" \
        "$start_reviews" "$cur_reviews" "$start_comments" "$cur_comments"

    if [ "$checks_state" = "success" ] && [ "$activity_seen" = "yes" ]; then
        poll_outcome="success"
        completed="yes"
        echo "[poll] green CI + Copilot activity observed — exiting loop"
        break
    fi
    if [ "$checks_state" = "success" ] && [ "$terminal_failure_seen" = "yes" ] && [ "$fallback_state_fresh" = "yes" ]; then
        poll_outcome="copilot-terminal-failure"
        completed="yes"
        echo "[poll] green CI + Copilot terminal failure observed — exiting loop"
        break
    fi
    if [ "$previous_checks_state" = "pending" ] && [ "$checks_state" = "pending" ]; then
        echo "[poll] CI still pending — Copilot request remains deferred"
    fi
    sleep 20
done

if [ "$completed" != "yes" ]; then
    finish_with_error "timeout" 124 "[poll] ERROR: timed out while waiting for $([ "$checks_state" = "success" ] && echo 'Copilot' || echo 'green CI'); no success reported"
fi

print_final_state
notify_completion
exit 0
