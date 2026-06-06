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
# Usage:
#   poll-pr-review.sh <pr-number> [timeout-seconds]
#   poll-pr-review.sh 15
#   poll-pr-review.sh 15 900
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
    # CI: all checks have a non-null completedAt (i.e., nothing in flight).
    # NOTE: do NOT compare state == "COMPLETED" — `gh pr checks --json state`
    # returns SUCCESS/FAILURE/IN_PROGRESS/PENDING etc, not COMPLETED.
    gh pr checks "$pr" --json completedAt \
        --jq '[.[].completedAt] | all(. != null and . != "")' 2>/dev/null || echo false
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

if [ "$activity_seen" = "yes" ] && [ "$checks_done" = "true" ]; then
    echo "[poll] current head already has Copilot activity and CI is done — no re-request needed"
    print_final_state
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

echo "[poll] repo=$repo pr=#$pr head=$head_sha baseline: current_head_reviews=$start_reviews copilot_comments_since_head=$start_comments activity_seen=$activity_seen budget=${budget}s"

deadline=$((SECONDS + budget))
iter=0
while [ $SECONDS -lt $deadline ]; do
    iter=$((iter + 1))
    elapsed=$SECONDS

    checks_done=$(checks_complete)
    cur_reviews=$(current_head_reviews)
    cur_comments=$(copilot_comments_since_head)

    new_review=$([ "$cur_reviews" -gt "$start_reviews" ] && echo "yes" || echo "no")
    new_comment=$([ "$cur_comments" -gt "$start_comments" ] && echo "yes" || echo "no")
    if [ "$new_review" = "yes" ] || [ "$new_comment" = "yes" ]; then
        activity_seen="yes"
    fi

    printf '[poll] iter=%d t=%ds checks_done=%s activity_seen=%s new_review=%s new_comment=%s (head_reviews %s→%s comments_since_head %s→%s)\n' \
        "$iter" "$elapsed" "$checks_done" "$activity_seen" "$new_review" "$new_comment" \
        "$start_reviews" "$cur_reviews" "$start_comments" "$cur_comments"

    if [ "$checks_done" = "true" ] && [ "$activity_seen" = "yes" ]; then
        echo "[poll] CI done + Copilot activity observed — exiting loop"
        break
    fi
    sleep 20
done

print_final_state
