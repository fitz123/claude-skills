#!/usr/bin/env bash
# Poll a GitHub PR for any NEW Copilot activity (a fresh formal review OR a
# fresh Copilot comment) AND all CI checks completed. Emits visible progress
# so a watching agent can see liveness instead of staring at an empty file.
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
# Exits 0 when both conditions met OR timeout reached (still emits final state).
set -u

pr="${1:?usage: $0 <pr-number> [timeout-seconds]}"
budget="${2:-600}"

# Login forms used by GitHub's Copilot PR-review integration:
#   formal review event author: copilot-pull-request-reviewer
#   @mention comment reply author: copilot-swe-agent
review_author="copilot-pull-request-reviewer"
comment_author="copilot-swe-agent"

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
[ -z "$repo" ] && { echo "ERROR: couldn't determine repo (run inside a gh-tracked clone)"; exit 1; }

# Pre-flight: if Copilot isn't a pending requested reviewer, request one before
# polling — otherwise the loop just burns its timeout waiting for a review that
# was never queued (e.g. when the repo doesn't auto-request Copilot on PR open,
# or after a prior review completed and the user forgot to re-request).
#
# `requested_reviewers` lists the BOT login `copilot-pull-request-reviewer`,
# even though the POST endpoint takes the literal token `Copilot`. Check the
# listing form here.
pending=$(gh api "repos/$repo/pulls/$pr/requested_reviewers" \
    --jq "[.users[]? | select(.login == \"$review_author\")] | length" 2>/dev/null || echo 0)
if [ "$pending" -eq 0 ]; then
    echo "[poll] no pending Copilot review request — invoking request-copilot-rereview.sh first"
    "$(dirname "$0")/request-copilot-rereview.sh" "$pr" || \
        echo "[poll] WARNING: pre-flight request returned non-zero; polling anyway"
else
    echo "[poll] Copilot already pending as reviewer — skipping pre-flight request"
fi

# Baselines: count formal reviews + count of Copilot comments at start. ANY
# increase in either is a fresh signal.
start_reviews=$(gh pr view "$pr" --json reviews \
    --jq "[.reviews[] | select(.author.login == \"$review_author\")] | length")
start_comments=$(gh pr view "$pr" --json comments \
    --jq "[.comments[] | select(.author.login == \"$comment_author\")] | length")

echo "[poll] repo=$repo pr=#$pr baseline: reviews=$start_reviews copilot_comments=$start_comments budget=${budget}s"

deadline=$((SECONDS + budget))
iter=0
while [ $SECONDS -lt $deadline ]; do
    iter=$((iter + 1))
    elapsed=$SECONDS

    # CI: all checks have a non-null completedAt (i.e., nothing in flight).
    # NOTE: do NOT compare state == "COMPLETED" — `gh pr checks --json state`
    # returns SUCCESS/FAILURE/IN_PROGRESS/PENDING etc, not COMPLETED.
    checks_done=$(gh pr checks "$pr" --json completedAt \
        --jq '[.[].completedAt] | all(. != null and . != "")' 2>/dev/null || echo false)

    cur_reviews=$(gh pr view "$pr" --json reviews \
        --jq "[.reviews[] | select(.author.login == \"$review_author\")] | length" 2>/dev/null || echo "$start_reviews")
    cur_comments=$(gh pr view "$pr" --json comments \
        --jq "[.comments[] | select(.author.login == \"$comment_author\")] | length" 2>/dev/null || echo "$start_comments")

    new_review=$([ "$cur_reviews" -gt "$start_reviews" ] && echo "yes" || echo "no")
    new_comment=$([ "$cur_comments" -gt "$start_comments" ] && echo "yes" || echo "no")

    printf '[poll] iter=%d t=%ds checks_done=%s new_review=%s new_comment=%s (reviews %s→%s comments %s→%s)\n' \
        "$iter" "$elapsed" "$checks_done" "$new_review" "$new_comment" \
        "$start_reviews" "$cur_reviews" "$start_comments" "$cur_comments"

    if [ "$checks_done" = "true" ] && { [ "$new_review" = "yes" ] || [ "$new_comment" = "yes" ]; }; then
        echo "[poll] CI done + new Copilot activity — exiting loop"
        break
    fi
    sleep 20
done

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
