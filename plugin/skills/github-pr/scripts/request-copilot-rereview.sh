#!/usr/bin/env bash
# Re-request a Copilot code review on a GitHub PR after pushing fixes.
#
# Copilot does NOT auto-re-review on every push. Two trigger paths:
#
#   1. `POST /repos/.../pulls/N/requested_reviewers` with reviewers[]=Copilot
#      Works for the FIRST few re-requests on a PR, then silently dedupes
#      (returns HTTP 201 with empty requested_reviewers and never fires a
#      review_requested event — observed empirically after ~4 rapid reviews).
#
#   2. PR comment with `@copilot please re-review`
#      Works reliably after the REST endpoint starts dedup'ing. Copilot may
#      respond as a COMMENT (`copilot-swe-agent`) rather than a formal review,
#      so any waiting watcher needs to look at both reviews[] and comments[].
#
# Strategy: try REST first (cheaper, surfaces formal review when it works),
# then fall back to @copilot comment.
#
# Usage:
#   request-copilot-rereview.sh <pr-number>
set -eu

pr="${1:?usage: $0 <pr-number>}"
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
[ -z "$repo" ] && { echo "ERROR: couldn't determine repo"; exit 1; }

# Snapshot timeline BEFORE the request so we can detect whether the REST call
# actually fires a review_requested event (vs. silently no-op'ing).
before=$(gh api "repos/$repo/issues/$pr/timeline" -H "Accept: application/vnd.github+json" --paginate \
    --jq '[.[] | select(.event == "review_requested" and .requested_reviewer.login == "Copilot")] | length' 2>/dev/null || echo 0)

gh api -X POST "/repos/$repo/pulls/$pr/requested_reviewers" -f 'reviewers[]=Copilot' > /dev/null 2>&1 || true

# Sleep briefly for the timeline event to materialize, then re-check.
sleep 3
after=$(gh api "repos/$repo/issues/$pr/timeline" -H "Accept: application/vnd.github+json" --paginate \
    --jq '[.[] | select(.event == "review_requested" and .requested_reviewer.login == "Copilot")] | length' 2>/dev/null || echo 0)

if [ "$after" -gt "$before" ]; then
    echo "Copilot re-review requested on $repo PR #$pr (via REST; $before→$after review_requested events)"
    exit 0
fi

# REST silently deduped. Fall back to @copilot comment. Copilot's reply often
# arrives as a comment (`copilot-swe-agent`), not a formal review — pollers
# should watch for both.
echo "REST endpoint silently no-op'd (rate-limit/dedup). Falling back to @copilot comment."
gh pr comment "$pr" --body "@copilot please re-review — fixes pushed since the last review" > /dev/null
echo "@copilot comment posted on $repo PR #$pr"
