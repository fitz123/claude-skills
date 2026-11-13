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
# Keep repo view (which otherwise uses cwd) aligned with gh pr's selection.
if [ -n "${GH_REPO:-}" ]; then
    if [[ "$GH_REPO" == -* ]] ||
       ! [[ "$GH_REPO" =~ ^([^/@[:space:]]+/)?[^/@:[:space:]]+/[^/@:[:space:]]+$ ]]; then
        echo "ERROR: GH_REPO must be OWNER/REPO or HOST/OWNER/REPO" >&2
        exit 1
    fi
    # gh api uses GH_HOST, while gh pr also reads the host from GH_REPO.
    case "$GH_REPO" in
        */*/*)
            repo_host="${GH_REPO%%/*}"
            export GH_HOST="$(printf '%s' "${repo_host#www.}" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
            ;;
    esac
fi
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner -- ${GH_REPO:+"$GH_REPO"}) || {
    echo "ERROR: couldn't resolve repository" >&2
    exit 1
}
[ -n "$repo" ] || { echo "ERROR: couldn't determine repo" >&2; exit 1; }
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
