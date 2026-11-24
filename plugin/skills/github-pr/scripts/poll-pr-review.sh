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
# Zero checks remain pending unless GH_PR_ALLOW_NO_CHECKS=1 explicitly declares
# the caller-established repository no-CI policy. No other value opts in; this
# exception permits review without claiming green CI or review approval.
#
# Usage:
#   poll-pr-review.sh <pr-number> [timeout-seconds]
#   poll-pr-review.sh 15
#   poll-pr-review.sh 15 900
#   GH_REPO=OWNER/REPO GH_PR_EXPECTED_HEAD=<full-sha> poll-pr-review.sh 15
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
#
# Exits 0 only after green CI plus Copilot activity (or a correlated terminal
# Copilot failure), or after green CI alone for a version-release PR. CI
# failure, head changes, query errors, and timeout are non-zero outcomes.
# GH_PR_ALLOW_NO_CHECKS=1 permits the same outcomes under explicit no-CI policy.
# GH_PR_EXPECTED_HEAD adds a merge-readiness gate and reserves stdout for JSON.
set -u

pr="${1-}"
budget="${2:-600}"
request_script="${GH_PR_REQUEST_SCRIPT:-$(dirname "$0")/request-copilot-rereview.sh}"
expected_head="${GH_PR_EXPECTED_HEAD:-}"
readiness_mode="no"
if [ "${GH_PR_EXPECTED_HEAD+x}" = "x" ]; then
    readiness_mode="yes"
    exec 3>&1 1>&2
else
    : "${pr:?usage: $0 <pr-number> [timeout-seconds]}"
fi

checks_state="unknown"
checks_summary="green CI"
checks_done="false"
is_release_pr="no"
activity_seen="no"
terminal_failure_seen="no"
fallback_state_fresh="no"
request_gate_done="no"

# Login forms used by GitHub's Copilot PR-review integration:
#   requested reviewer / gh pr view review author: copilot-pull-request-reviewer
#   REST pull-review author: copilot-pull-request-reviewer[bot]
#   @mention comment reply author: copilot-swe-agent
review_author="copilot-pull-request-reviewer"
review_author_api="copilot-pull-request-reviewer[bot]"
comment_author="copilot-swe-agent"

finish_readiness() {
    local exit_code="$1" reason="$2" copilot="pending"
    if [ "$is_release_pr" = "yes" ]; then
        copilot="release_skip"
    elif [ "$activity_seen" = "yes" ]; then
        copilot="activity"
    elif [ "$terminal_failure_seen" = "yes" ] && [ "$fallback_state_fresh" = "yes" ]; then
        copilot="terminal_no_review"
    fi
    jq -cn --arg reason "$reason" --arg repo "${GH_REPO:-}" --arg pr "$pr" \
        --arg head "$expected_head" --arg checks "$checks_state" --arg copilot "$copilot" '
        {ready: ($reason == "ready"), $reason, $repo, pr: ($pr | tonumber? // $pr),
         expected_head: $head, $checks, $copilot}
    ' >&3 || exit 4
    exit "$exit_code"
}

setup_error() {
    echo "ERROR: $3" >&2
    [ "$readiness_mode" = "no" ] || finish_readiness "$1" "$2"
    exit 1
}

checks_status() {
    # `gh pr checks` can return non-zero for a completed failed check while
    # still emitting valid JSON, so classify the payload rather than its exit
    # code. A real completedAt is required even when state looks terminal;
    # current gh uses Go's zero time for some in-progress checks.
    local checks_json status result=0
    checks_json=$(gh pr checks "$pr" --json state,completedAt 2>/dev/null) || result=$?
    # gh can exit before JSON export when no checks exist. Confirm only that
    # empty-output case with a successful, same-head structured snapshot.
    if [ -z "$checks_json" ]; then
        local confirmation_json
        if { [ "$readiness_mode" = "no" ] || [ "$result" -eq 1 ]; } &&
           confirmation_json=$(gh pr view "$pr" --json headRefOid,statusCheckRollup 2>/dev/null) &&
           jq -se --arg head "$head_sha" '
               length == 1 and (.[0] | type == "object" and
                   .headRefOid == $head and .statusCheckRollup == [])
           ' >/dev/null 2>&1 <<< "$confirmation_json"; then
            echo "none"
        else
            echo "query_error"
        fi
        return
    fi
    status=$(jq -sr --arg strict "$readiness_mode" '
        def valid_check:
            type == "object" and (.state | type == "string" and length > 0) and
            has("completedAt") and (.completedAt |
                . == null or . == "" or (type == "string" and
                    test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$")));
        if length != 1 or (.[0] | type != "array") then error("invalid checks response") else .[0] end |
        if $strict == "yes" and any(.[]; valid_check | not) then "query_error"
        elif length == 0 then "none"
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
    ' <<< "$checks_json" 2>/dev/null) || status="query_error"
    # A failed command with green or empty JSON is insufficient for readiness.
    if [ "$readiness_mode" = "yes" ] && [ "$result" -ne 0 ]; then
        case "$status:$result" in
            failure:1|pending:8) ;;
            *) status="query_error" ;;
        esac
    fi
    echo "$status"
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
    # The commit's timestamp is only a baseline for the legacy poller.
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

    jq -sr --arg marker "$request_marker" --arg strict "$readiness_mode" --arg reply_author "$comment_author" \
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
             def is_copilot_reply:
                .event == "commented" and event_login == $reply_author;
             def push_reply_evidence:
                ([to_entries[] | select(.value | is_copilot_reply)] | last) as $reply |
                if $reply == null then ["none", "none"]
                else
                    ([.[:$reply.key][] | select(is_copilot_review_request or is_copilot_trigger_comment)] | last) as $trigger |
                    if (($trigger.body // "") | contains("<!-- github-pr-rereview-head:")) and
                       ($trigger | is_marked_fallback | not)
                    then ["none", "none"]
                    else [($reply.value.created_at // "none"),
                          (if $trigger == null then "none" else $trigger.created_at // "unknown" end)]
                    end
                end;
             if $strict == "yes" and (length == 0 or any(.[]; type != "array"))
             then error("invalid timeline pages") else . end |
             [.[][]?] as $events |
             ([$events | to_entries[] | select(.value | is_marked_fallback)] | last) as $request |
             (if $strict == "yes" then ($events | push_reply_evidence) else ["none", "none"] end) as $push_reply |
             (if $request == null then ["none", "none", "no", "no"]
              else
                $events[($request.key + 1):] as $after |
                ($after | map(is_copilot_review_request or is_copilot_trigger_comment) | index(true)) as $next_trigger |
                [
                    (($request.value.id // $request.value.node_id // $request.key) | tostring),
                    ($request.value.created_at // "unknown"),
                    (if $next_trigger != null then "no"
                     elif any($after[]; .event == "copilot_work_finished_failure")
                     then "yes"
                     else "no"
                     end),
                    (if $strict == "yes" and any($after[:($next_trigger // ($after | length))][]; is_copilot_reply)
                     then "yes" else "no"
                     end)
                ]
              end) + $push_reply | @tsv' 2>/dev/null <<< "$timeline_json"
}

observed_push_before_comment() {
    # GitHub exposes the actual push time and resulting SHA for head force-pushes.
    local push
    # shellcheck disable=SC2016
    push=$(gh api graphql -f owner="${repo%/*}" -f name="${repo#*/}" -F number="$pr" -f query='
        query($owner: String!, $name: String!, $number: Int!) {
            repository(owner: $owner, name: $name) {
                pullRequest(number: $number) {
                    headRefOid
                    timelineItems(last: 1, itemTypes: [HEAD_REF_FORCE_PUSHED_EVENT]) {
                        nodes { ... on HeadRefForcePushedEvent { createdAt afterCommit { oid } } }
                    }
                }
            }
        }
    ' 2>/dev/null) || return 1
    jq -se --arg head "$head_sha" --arg reply "$1" --arg trigger "$2" '
        length == 1 and (.[0] | (has("errors") | not) or .errors == []) and
        (.[0].data.repository.pullRequest | .headRefOid == $head and
            (.timelineItems.nodes | length == 1 and (.[0] |
                (.createdAt | fromdateiso8601) as $pushed_at |
                .afterCommit.oid == $head and $pushed_at < ($reply | fromdateiso8601) and
                ($trigger == "none" or $pushed_at < ($trigger | fromdateiso8601)))))
    ' >/dev/null 2>&1 <<< "$push"
}

record_fallback_evidence() {
    local marked_reply reply_at trigger_at
    IFS=$'\t' read -r fallback_request_id fallback_request_at terminal_failure_seen marked_reply reply_at trigger_at <<< "$1"
    fallback_state_fresh="yes"
    if [ "$readiness_mode" = "yes" ] && [ "$activity_seen" = "no" ]; then
        if [ "$marked_reply" = "yes" ] ||
           { [ "$terminal_failure_seen" = "no" ] && [ "$reply_at" != "none" ] && observed_push_before_comment "$reply_at" "$trigger_at"; }; then
            activity_seen="yes"
        fi
    fi
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
    local summary="github-pr poll finished: $repo PR #$pr — release_pr=$is_release_pr checks_state=$checks_state checks_done=$checks_done copilot_activity=$activity_seen copilot_terminal_failure=$terminal_failure_seen"
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

finish_with_error() {
    local exit_code="$1" reason="${3:-query_error}"
    echo "$2"
    if [ "$readiness_mode" = "yes" ]; then
        case "$exit_code" in
            2) reason="checks_failed" ;;
            3) reason="head_changed" ;;
            124) reason="timeout" ;;
        esac
        notify_completion
        finish_readiness "$exit_code" "$reason"
    fi
    print_final_state
    notify_completion
    exit "$exit_code"
}

ensure_current_pr() {
    local current_head state snapshot
    if [ "$readiness_mode" = "yes" ]; then
        snapshot=$(gh pr view "$pr" --json headRefOid,state --jq '[.headRefOid, .state] | @tsv' 2>/dev/null) &&
            [[ "$snapshot" =~ ^[0-9a-f]{40}$'\t'(OPEN|CLOSED|MERGED)$ ]] ||
            finish_with_error 4 "[poll] ERROR: could not verify the current PR head and state"
        IFS=$'\t' read -r current_head state <<< "$snapshot"
    else
        current_head=$(gh pr view "$pr" --json headRefOid --jq .headRefOid 2>/dev/null) ||
            finish_with_error 4 "[poll] ERROR: could not verify the current PR head"
    fi
    [ "$current_head" = "$head_sha" ] || \
        finish_with_error 3 "[poll] ERROR: PR head changed while polling (expected ${head_sha:0:12}, current ${current_head:0:12})"
    if [ "$readiness_mode" = "yes" ] && [ "$state" != "OPEN" ]; then
        finish_with_error 5 "[poll] PR state is $state" pr_not_open
    fi
}

refresh_checks() {
    local verdict
    verdict=$(checks_status)
    # Attribute each checks response to the head before applying its verdict.
    if [ "$readiness_mode" = "yes" ]; then
        ensure_current_pr
    fi
    checks_state="$verdict"
    checks_summary="green CI"
    case "$checks_state" in
        success) checks_done="true" ;;
        pending) checks_done="false" ;;
        failure)
            checks_done="true"
            if [ "$readiness_mode" = "yes" ]; then
                finish_with_error 2 "[poll] ERROR: CI checks failed"
            fi
            finish_with_error 2 "[poll] ERROR: CI checks failed — Copilot was not requested for this head"
            ;;
        none)
            if [ "${GH_PR_ALLOW_NO_CHECKS:-}" = "1" ]; then
                echo "[poll] no CI checks; eligible under explicit no-CI policy"
                checks_summary="explicit no-CI policy"
                checks_done="true"
            else
                echo "[poll] no CI checks; pending without GH_PR_ALLOW_NO_CHECKS=1"
                checks_state="pending"
                checks_done="false"
            fi
            ;;
        *) checks_done="false"; finish_with_error 4 "[poll] ERROR: could not classify current-head CI checks" ;;
    esac
}

classify_release() {
    is_release_pr="no"
    if [[ "$1" =~ ^release(-|/v)[0-9]+\.[0-9]+\.[0-9]+$ ]] &&
       [[ "$2" =~ ^(chore:\ release|Release)\ v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        is_release_pr="yes"
    fi
}

merge_readiness_status() {
    local pages
    # The dollar-prefixed names in the query are GraphQL variables.
    # shellcheck disable=SC2016
    pages=$(gh api graphql --paginate -f owner="${repo%/*}" -f name="${repo#*/}" -F number="$pr" -f query='
        query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
            repository(owner: $owner, name: $name) {
                pullRequest(number: $number) {
                    headRefOid state isDraft mergeStateStatus mergeable reviewDecision headRefName title
                    reviewThreads(first: 100, after: $endCursor) {
                        totalCount nodes { id isResolved } pageInfo { hasNextPage endCursor }
                    }
                }
            }
        }
    ') || return 1

    jq -ser --arg head "$head_sha" '
        def nonempty_string: type == "string" and length > 0;
        def valid_pr:
            (.headRefOid | type == "string" and test("^[0-9a-f]{40}$")) and
            (.state | nonempty_string) and (.isDraft | type == "boolean") and
            (.headRefName | nonempty_string) and (.title | nonempty_string) and
            (.mergeStateStatus | nonempty_string) and (.mergeable | nonempty_string) and
            has("reviewDecision") and (.reviewDecision | . == null or nonempty_string);
        def valid_page:
            (.nodes | type == "array" and all(.[];
                (.id | nonempty_string) and (.isResolved | type == "boolean"))) and
            (.pageInfo.hasNextPage | type == "boolean");
        if length == 0 or any(.[]; has("errors") and .errors != []) then error("invalid PR response") else . end |
        [.[].data.repository.pullRequest] as $prs |
        if any($prs[]; valid_pr | not) then error("missing PR fields")
        elif any($prs[]; .headRefOid != $head) then "head_changed"
        else
            [$prs[].reviewThreads] as $pages |
            if any($pages[]; valid_page | not) then error("invalid review thread page") else . end |
            [$pages[].nodes[]] as $threads |
            if $pages[-1].pageInfo.hasNextPage or
               any($pages[0:-1][]; .pageInfo.hasNextPage != true or (.pageInfo.endCursor | nonempty_string | not)) or
               any($pages[]; .totalCount != ($threads | length)) or
               ($threads | unique_by(.id) | length) != ($threads | length)
            then error("incomplete review thread pagination")
            else
                $prs[-1] |
                [(if .state != "OPEN" then "pr_not_open"
                  elif .isDraft then "draft"
                  elif .reviewDecision != null and .reviewDecision != "APPROVED" then "review_blocked"
                  elif any($threads[]; .isResolved == false) then "unresolved_threads"
                  elif (.mergeStateStatus != "CLEAN" and .mergeStateStatus != "UNKNOWN") or .mergeable == "CONFLICTING" then "merge_blocked"
                  elif .mergeStateStatus == "UNKNOWN" or .mergeable != "MERGEABLE" then "query_error"
                  else "ready"
                  end), .headRefName, .title] | @tsv
            end
        end
    ' <<< "$pages"
}

request_copilot_if_ready() {
    [ "$request_gate_done" = "no" ] || return
    [ "$checks_done" = "true" ] || return
    [ "$activity_seen" = "no" ] || { request_gate_done="yes"; return; }
    [ "$terminal_failure_seen" = "no" ] || { request_gate_done="yes"; return; }
    # A complete timeline is needed to rule out an existing terminal outcome.
    [ "$readiness_mode" = "no" ] || [ "$fallback_state_fresh" = "yes" ] || return

    ensure_current_pr
    local pending
    pending=$(gh api "repos/$repo/pulls/$pr/requested_reviewers" \
        --jq "[.users[]? | select(.login == \"$review_author\")] | length" 2>/dev/null) || \
        finish_with_error 4 "[poll] ERROR: could not read pending Copilot reviewers"
    if [ "$readiness_mode" = "yes" ] && ! [[ "$pending" =~ ^[0-9]+$ ]]; then
        finish_with_error 4 "[poll] ERROR: invalid pending Copilot reviewer count"
    fi
    local request_basis="CI green"
    [ "$checks_state" != "none" ] || request_basis="explicit no-CI policy"
    if [ "$pending" -eq 0 ]; then
        if [ "$readiness_mode" = "yes" ]; then
            ensure_current_pr
        fi
        echo "[poll] $request_basis — requesting Copilot review for head ${head_sha:0:12}"
        local result=0
        "$request_script" "$pr" || result=$?
        if [ "$readiness_mode" = "yes" ]; then
            case "$result" in
                3) finish_with_error 3 "[poll] ERROR: PR head changed before a Copilot review write" ;;
                4) finish_with_error 4 "[poll] ERROR: could not verify PR head and state before a Copilot review write" ;;
                5) finish_with_error 5 "[poll] PR closed before a Copilot review write" pr_not_open ;;
            esac
        fi
        [ "$result" -eq 0 ] || echo "[poll] WARNING: CI-gated review request returned non-zero; polling anyway"
    else
        echo "[poll] $request_basis and Copilot is already pending — no duplicate request"
    fi
    request_gate_done="yes"
}

if [ "$readiness_mode" = "yes" ]; then
    [ -n "${GH_REPO:-}" ] && [[ "$expected_head" =~ ^[0-9a-f]{40}$ && "$pr" =~ ^[1-9][0-9]*$ ]] ||
        setup_error 1 invalid_input "expected a PR number, explicit GH_REPO and a full lowercase SHA in GH_PR_EXPECTED_HEAD"
    [[ "$budget" =~ ^(0|[1-9][0-9]*)$ ]] || setup_error 1 invalid_input "timeout must be a non-negative number of seconds"
fi

# Keep repo view (which otherwise uses cwd) aligned with gh pr's selection.
if [ -n "${GH_REPO:-}" ]; then
    if [[ "$GH_REPO" == -* ]] ||
       ! [[ "$GH_REPO" =~ ^([^/@[:space:]]+/)?[^/@:[:space:]]+/[^/@:[:space:]]+$ ]]; then
        setup_error 1 invalid_input "GH_REPO must be OWNER/REPO or HOST/OWNER/REPO"
    fi
    # gh api uses GH_HOST, while gh pr also reads the host from GH_REPO.
    case "$GH_REPO" in
        */*/*)
            repo_host="${GH_REPO%%/*}"
            repo_host="$(printf '%s' "$repo_host" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
            export GH_HOST="${repo_host#www.}"
            ;;
    esac
fi
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner -- ${GH_REPO:+"$GH_REPO"}) ||
    setup_error 4 query_error "couldn't resolve repository"
[ -n "$repo" ] || setup_error 4 query_error "couldn't determine repo"

head_commit_at=""
if [ "$readiness_mode" = "yes" ]; then
    [[ "$repo" =~ ^[^/@:[:space:]]+/[^/@:[:space:]]+$ ]] ||
        setup_error 4 query_error "invalid repository response"
    head_sha="$expected_head"
    ensure_current_pr
else
    head_sha=$(gh pr view "$pr" --json headRefOid --jq .headRefOid)
    [ -z "$head_sha" ] && { echo "ERROR: couldn't determine PR head sha"; exit 1; }
    head_commit_at=$(gh pr view "$pr" --json commits --jq '.commits[-1].committedDate // ""' 2>/dev/null || echo "")
fi
pr_metadata=$(gh pr view "$pr" --json headRefName,title 2>/dev/null) ||
    setup_error 4 query_error "couldn't determine PR branch/title"
if [ "$readiness_mode" = "yes" ]; then
    jq -se 'length == 1 and (.[0] | all(.headRefName, .title; type == "string" and length > 0))' \
        >/dev/null 2>&1 <<< "$pr_metadata" || setup_error 4 query_error "invalid PR branch/title response"
fi
head_ref=$(jq -r '.headRefName // ""' <<< "$pr_metadata")
pr_title=$(jq -r '.title // ""' <<< "$pr_metadata")
classify_release "$head_ref" "$pr_title"

refresh_checks
start_reviews=0
start_comments=0
fallback_request_id="none"
fallback_request_at="none"

if [ "$is_release_pr" = "yes" ]; then
    echo "[poll] version-release PR detected ($head_ref / $pr_title) — skipping Copilot review"
else
    start_reviews=$(current_head_reviews)
    start_comments=$(copilot_comments_since_head)
    activity_seen=$([ "$start_reviews" -gt 0 ] || [ "$start_comments" -gt 0 ] && echo "yes" || echo "no")

    if fallback_state=$(current_head_fallback_state); then
        record_fallback_evidence "$fallback_state"
    else
        echo "[poll] WARNING: could not read the complete PR timeline — fallback state remains unknown and will be retried"
    fi

    if [ "$terminal_failure_seen" = "yes" ]; then
        echo "[poll] current-head fallback request ended with copilot_work_finished_failure — waiting for $checks_summary only"
    fi
    if [ "$checks_done" = "true" ]; then
        request_copilot_if_ready
    else
        echo "[poll] CI pending — deferring Copilot request for head ${head_sha:0:12}"
    fi
fi

echo "[poll] repo=$repo pr=#$pr head=$head_sha release_pr=$is_release_pr checks_state=$checks_state fallback_request_at=$fallback_request_at budget=${budget}s"

deadline=$((SECONDS + budget))
iter=0
completed="no"
while [ $SECONDS -lt $deadline ]; do
    iter=$((iter + 1))
    fallback_state_fresh="no"

    if [ "$readiness_mode" = "no" ]; then
        ensure_current_pr
    fi
    refresh_checks

    if [ "$is_release_pr" = "yes" ]; then
        printf '[poll] iter=%d t=%ds release_pr=yes checks_state=%s copilot=skipped\n' \
            "$iter" "$SECONDS" "$checks_state"
        if [ "$checks_done" = "true" ]; then
            completed="yes"
            break
        fi
        sleep 20
        continue
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
            previous_fallback_request_id="$fallback_request_id"
            previous_terminal_failure_seen="$terminal_failure_seen"
            record_fallback_evidence "$fallback_state"
            if [ "$activity_seen" = "yes" ]; then
                new_comment="yes"
            fi
            if [ "$fallback_request_id" != "none" ] && [ "$fallback_request_id" != "$previous_fallback_request_id" ]; then
                echo "[poll] newest current-head fallback marker became visible at $fallback_request_at"
            fi
            if [ "$previous_terminal_failure_seen" = "yes" ] && [ "$terminal_failure_seen" = "no" ]; then
                echo "[poll] newer Copilot trigger superseded the prior terminal failure — resuming Copilot review wait"
            elif [ "$previous_terminal_failure_seen" = "no" ] && [ "$terminal_failure_seen" = "yes" ]; then
                echo "[poll] current-head fallback request ended with copilot_work_finished_failure"
            fi
        else
            echo "[poll] WARNING: could not refresh the complete PR timeline — preserving the last known fallback state"
        fi
    fi

    request_copilot_if_ready
    printf '[poll] iter=%d t=%ds checks_state=%s checks_done=%s activity_seen=%s terminal_failure_seen=%s fallback_state_fresh=%s new_review=%s new_comment=%s\n' \
        "$iter" "$SECONDS" "$checks_state" "$checks_done" "$activity_seen" "$terminal_failure_seen" "$fallback_state_fresh" "$new_review" "$new_comment"

    if [ "$checks_done" = "true" ] && [ "$activity_seen" = "yes" ]; then
        completed="yes"
        echo "[poll] $checks_summary + Copilot activity observed — exiting loop"
        break
    fi
    if [ "$checks_done" = "true" ] && [ "$terminal_failure_seen" = "yes" ] && [ "$fallback_state_fresh" = "yes" ]; then
        completed="yes"
        echo "[poll] $checks_summary + Copilot terminal failure observed — exiting loop"
        break
    fi
    sleep 20
done

if [ "$completed" != "yes" ]; then
    finish_with_error 124 "[poll] ERROR: timed out without a successful current-head outcome"
fi

if [ "$readiness_mode" = "yes" ]; then
    readiness_snapshot=$(merge_readiness_status) || finish_with_error 4 "[poll] ERROR: could not verify PR state and review threads"
    IFS=$'\t' read -r readiness final_ref final_title <<< "$readiness_snapshot"
    [ "$readiness" != "head_changed" ] || finish_with_error 3 "[poll] ERROR: PR head changed during the readiness query"
    previously_release="$is_release_pr"
    classify_release "$final_ref" "$final_title"
    refresh_checks
    [ "$readiness" != "query_error" ] || finish_with_error 4 "[poll] ERROR: mergeability is incomplete"
    [ "$readiness" = "ready" ] || finish_with_error 5 "[poll] PR is not ready: $readiness" "$readiness"
    [ "$checks_done" = "true" ] || finish_with_error 5 "[poll] CI checks are pending in the final check" checks_pending
    if [ "$previously_release" = "yes" ] && [ "$is_release_pr" = "no" ]; then
        # The poll skipped Copilot under the original title. Check for evidence
        # once under the final classification before deciding readiness.
        if [ "$(current_head_reviews)" -gt 0 ]; then
            activity_seen="yes"
        elif fallback_state=$(current_head_fallback_state); then
            record_fallback_evidence "$fallback_state"
        fi
        ensure_current_pr
        if [ "$activity_seen" = "no" ] && [ "$terminal_failure_seen" = "no" ]; then
            finish_with_error 5 "[poll] PR no longer qualifies for the release skip and is awaiting Copilot" copilot_pending
        fi
    fi
    notify_completion
    finish_readiness 0 ready
fi

print_final_state
notify_completion
exit 0
