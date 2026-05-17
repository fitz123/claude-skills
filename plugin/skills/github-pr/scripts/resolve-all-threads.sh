#!/usr/bin/env bash
# Resolve all currently-unresolved review threads on a GitHub PR.
# Use AFTER pushing fixes that address every open thread — leaving them
# unresolved (or relying on Copilot to auto-resolve) blocks merge readiness
# even when the underlying code is fixed.
#
# Usage:
#   resolve-all-threads.sh <pr-number>
set -eu

pr="${1:?usage: $0 <pr-number>}"
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
owner="${repo%/*}"; name="${repo#*/}"

ids=$(gh api graphql -f query="{repository(owner:\"$owner\",name:\"$name\"){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved}}}}}" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .id')

if [ -z "$ids" ]; then
    echo "no unresolved threads on $repo PR #$pr"
    exit 0
fi

count=0
while IFS= read -r id; do
    [ -z "$id" ] && continue
    gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{id isResolved}}}' \
        -f id="$id" > /dev/null
    count=$((count + 1))
done <<< "$ids"

echo "resolved $count thread(s) on $repo PR #$pr"
