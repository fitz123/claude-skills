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
# then fall back to @copilot comment. The fallback is idempotent per PR head
# for a short cooldown so an explicit re-request plus the poller's pre-flight
# does not spam duplicate comments.
#
# Usage:
#   request-copilot-rereview.sh <pr-number>
set -eu

pr="${1:?usage: $0 <pr-number>}"
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
[ -z "$repo" ] && { echo "ERROR: couldn't determine repo"; exit 1; }

cooldown_seconds="${COPILOT_REREVIEW_COOLDOWN_SECONDS:-1800}"
case "$cooldown_seconds" in
    ''|*[!0-9]*) cooldown_seconds=1800 ;;
esac
head_sha=$(gh pr view "$pr" --json headRefOid --jq .headRefOid)
head_commit_at=$(gh pr view "$pr" --json commits --jq '.commits[-1].committedDate // ""' 2>/dev/null || echo "")
request_marker="<!-- github-pr-rereview-head:$head_sha -->"
request_body="@copilot please re-review — fixes pushed since the last review

$request_marker"

recent_fallback_requests() {
    local cutoff
    cutoff=$(( $(date -u +%s) - cooldown_seconds ))
    gh api "repos/$repo/issues/$pr/comments?per_page=100" 2>/dev/null | \
        jq --arg marker "$request_marker" \
           --arg head_commit_at "$head_commit_at" \
           --argjson cutoff "$cutoff" \
           '[.[] | select(
               ((.body // "") | contains($marker)) or
               ($head_commit_at != "" and .created_at >= $head_commit_at and ((.body // "") | contains("@copilot please re-review")))
             ) | select((.created_at | fromdateiso8601) >= $cutoff)] | length' 2>/dev/null || echo 0
}

skip_if_recent_fallback_exists() {
    local recent
    recent=$(recent_fallback_requests)
    recent="${recent:-0}"
    if [ "$recent" -gt 0 ]; then
        echo "Recent @copilot re-review request already exists for head ${head_sha:0:7} (count=$recent, cooldown=${cooldown_seconds}s); skipping duplicate comment."
        exit 0
    fi
}

skip_if_recent_fallback_exists

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
# should watch for both. Re-check before commenting to avoid races with another
# poller or an explicit request that posted while REST was sleeping.
skip_if_recent_fallback_exists
echo "REST endpoint silently no-op'd (rate-limit/dedup). Falling back to @copilot comment."
gh pr comment "$pr" --body "$request_body" > /dev/null
echo "@copilot comment posted on $repo PR #$pr for head ${head_sha:0:7}"
