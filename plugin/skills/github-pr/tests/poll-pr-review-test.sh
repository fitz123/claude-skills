#!/usr/bin/env bash
set -euo pipefail

# This file is both the regression-test runner and, through symlinks created by
# the runner, the fake `gh` and `sleep` executables used by the poller.

fake_gh() {
    local command_name="${1:-}"
    shift || true

    mkdir -p "$FAKE_GH_STATE_DIR"
    printf '%s %s\n' "$command_name" "$*" >> "$FAKE_GH_STATE_DIR/calls.log"

    local jq_filter=""
    local expect_filter="no"
    local arg
    for arg in "$@"; do
        if [ "$expect_filter" = "yes" ]; then
            jq_filter="$arg"
            break
        fi
        if [ "$arg" = "--jq" ]; then
            expect_filter="yes"
        fi
    done

    emit_json() {
        local json="$1"
        if [ -n "$jq_filter" ]; then
            printf '%s\n' "$json" | jq -r "$jq_filter"
        else
            printf '%s\n' "$json"
        fi
    }

    next_call() {
        local name="$1"
        local state_file="$FAKE_GH_STATE_DIR/$name"
        local count=0
        if [ -f "$state_file" ]; then
            read -r count < "$state_file"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$state_file"
        printf '%s\n' "$count"
    }

    local head_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local current_marker="<!-- github-pr-rereview-head:$head_sha -->"

    case "$command_name" in
        repo)
            emit_json '{"nameWithOwner":"example/widgets"}'
            ;;
        pr)
            local subcommand="${1:-}"
            shift || true
            case "$subcommand" in
                checks)
                    if [[ " $* " == *" --json state,completedAt "* ]] || [[ " $* " == *" --json completedAt "* ]]; then
                        local check_call
                        check_call=$(next_call checks)
                        case "$TEST_SCENARIO" in
                            correlated_failure|in_flight_marker|in_flight_rest|timeline_refresh_error|ci_pending_then_success|release_dash)
                                if [ "$check_call" -lt 3 ]; then
                                    emit_json '[{"state":"IN_PROGRESS","completedAt":null}]'
                                else
                                    emit_json '[{"state":"SUCCESS","completedAt":"2026-07-14T10:10:00Z"}]'
                                fi
                                ;;
                            zero_completed_at)
                                if [ "$check_call" -lt 3 ]; then
                                    emit_json '[{"state":"IN_PROGRESS","completedAt":"0001-01-01T00:00:00Z"}]'
                                else
                                    emit_json '[{"state":"SUCCESS","completedAt":"2026-07-14T10:10:00Z"}]'
                                fi
                                ;;
                            ci_failure)
                                emit_json '[{"state":"FAILURE","completedAt":"2026-07-14T10:10:00Z"}]'
                                return 1
                                ;;
                            ready_replaced_at_start|ready_replaced_in_wait)
                                if [ "$TEST_SCENARIO" = ready_replaced_at_start ] || [ "$check_call" -gt 1 ]; then
                                    touch "$FAKE_GH_STATE_DIR/replacement"
                                    emit_json '[{"state":"FAILURE","completedAt":"2026-07-14T10:10:00Z"}]'
                                    return 1
                                fi
                                emit_json '[{"state":"IN_PROGRESS","completedAt":null}]'
                                ;;
                            empty_checks_register)
                                if [ "$check_call" -eq 1 ]; then
                                    return 1
                                elif [ "$check_call" -eq 2 ]; then
                                    emit_json '[{"state":"IN_PROGRESS","completedAt":null}]'
                                else
                                    emit_json '[{"state":"SUCCESS","completedAt":"2026-07-14T10:10:00Z"}]'
                                fi
                                ;;
                            empty_checks_*|ready_empty_checks)
                                printf '%s\n' 'no checks reported on the branch' >&2
                                return 1
                                ;;
                            malformed_checks)
                                printf '%s\n' 'not JSON'
                                return 1
                                ;;
                            ready_checks_partial)
                                emit_json '[{"state":"SUCCESS","completedAt":"2026-07-14T10:10:00Z"}]'
                                return 1
                                ;;
                            ready_checks_incomplete)
                                emit_json '[{"state":"SUCCESS","completedAt":"invalid"}]'
                                ;;
                            ready_checks_regressed|ready_checks_failed_at_end)
                                if [ "$check_call" -gt 2 ]; then
                                    if [ "$TEST_SCENARIO" = ready_checks_regressed ]; then
                                        emit_json '[{"state":"IN_PROGRESS","completedAt":null}]'
                                    else
                                        emit_json '[{"state":"FAILURE","completedAt":"2026-07-14T10:10:00Z"}]'
                                        return 1
                                    fi
                                else
                                    emit_json '[{"state":"SUCCESS","completedAt":"2026-07-14T10:10:00Z"}]'
                                fi
                                ;;
                            no_checks|no_checks_default)
                                emit_json '[]'
                                ;;
                            *)
                                emit_json '[{"state":"SUCCESS","completedAt":"2026-07-14T10:10:00Z"}]'
                                ;;
                        esac
                    else
                        printf '%s\n' 'ci  pass  10s'
                    fi
                    ;;
                view)
                    if [[ " $* " == *" --json headRefOid,statusCheckRollup "* ]]; then
                        case "$TEST_SCENARIO" in
                            empty_checks_failed)
                                return 1
                                ;;
                            empty_checks_failed_json)
                                emit_json "{\"headRefOid\":\"$head_sha\",\"statusCheckRollup\":[]}"
                                return 1
                                ;;
                            empty_checks_nonempty)
                                emit_json "{\"headRefOid\":\"$head_sha\",\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]}"
                                ;;
                            empty_checks_malformed)
                                printf '%s\n' 'not JSON'
                                ;;
                            empty_checks_wrong_head)
                                emit_json '{"headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","statusCheckRollup":[]}'
                                ;;
                            empty_checks_null)
                                emit_json "{\"headRefOid\":\"$head_sha\",\"statusCheckRollup\":null}"
                                ;;
                            empty_checks_missing)
                                emit_json "{\"headRefOid\":\"$head_sha\"}"
                                ;;
                            empty_checks_multiple)
                                emit_json "{\"headRefOid\":\"$head_sha\",\"statusCheckRollup\":[]}"
                                emit_json "{\"headRefOid\":\"$head_sha\",\"statusCheckRollup\":[]}"
                                ;;
                            *)
                                emit_json "{\"headRefOid\":\"$head_sha\",\"statusCheckRollup\":[]}"
                                ;;
                        esac
                    elif [[ " $* " == *" --json headRefOid "* || " $* " == *" --json headRefOid,state "* ]]; then
                        local head_call state=OPEN
                        head_call=$(next_call head)
                        case "$TEST_SCENARIO" in
                            head_changed) [ "$head_call" -eq 1 ] || head_sha="${head_sha//a/b}" ;;
                            ready_replaced_*) [ ! -e "$FAKE_GH_STATE_DIR/replacement" ] || head_sha="${head_sha//a/b}" ;;
                            ready_closed) state=CLOSED ;;
                            ready_merged) state=MERGED ;;
                            ready_closed_in_wait) [ "$head_call" -le 3 ] || state=CLOSED ;;
                            ready_head_at_end) [ ! -e "$FAKE_GH_STATE_DIR/readiness" ] || head_sha="${head_sha//a/b}" ;;
                            ready_head_at_request) [ ! -e "$FAKE_GH_STATE_DIR/requested-reviewers" ] || head_sha="${head_sha//a/b}" ;;
                            ready_closed_at_request) [ ! -e "$FAKE_GH_STATE_DIR/requested-reviewers" ] || state=CLOSED ;;
                            ready_head_at_rest) [ ! -e "$FAKE_GH_STATE_DIR/request-timeline" ] || head_sha="${head_sha//a/b}" ;;
                            ready_head_at_fallback) [ ! -e "$FAKE_GH_STATE_DIR/rest-post" ] || head_sha="${head_sha//a/b}" ;;
                            ready_closed_at_fallback) [ ! -e "$FAKE_GH_STATE_DIR/rest-post" ] || state=CLOSED ;;
                        esac
                        emit_json "{\"headRefOid\":\"$head_sha\",\"state\":\"$state\"}"
                    elif [[ " $* " == *" --json commits "* ]]; then
                        emit_json '{"commits":[{"committedDate":"2026-07-14T09:00:00Z"}]}'
                    elif [[ " $* " == *" --json headRefName,title "* ]]; then
                        case "$TEST_SCENARIO" in
                            release_dash)
                                emit_json '{"headRefName":"release-2026.8.0","title":"chore: release 2026.8.0"}'
                                ;;
                            release_slash|ready_release_reclassified*)
                                emit_json '{"headRefName":"release/v2026.7.43","title":"Release v2026.7.43"}'
                                ;;
                            *)
                                emit_json '{"headRefName":"fix/example","title":"Fix example"}'
                                ;;
                        esac
                    elif [[ " $* " == *" --json reviews "* ]]; then
                        emit_json '{"reviews":[]}'
                    elif [[ " $* " == *" --json comments "* ]]; then
                        local comments='[]'
                        if [ "$TEST_SCENARIO" = "ready_previous_comment" ]; then
                            comments='[{"author":{"login":"copilot-swe-agent"},"createdAt":"2026-07-14T10:02:00Z","body":"Review complete"}]'
                        elif [ "$TEST_SCENARIO" = "normal_comment" ]; then
                            if [[ "$jq_filter" == *"| length"* ]]; then
                                local comment_call
                                comment_call=$(next_call comments)
                                if [ "$comment_call" -gt 1 ]; then
                                    comments='[{"author":{"login":"copilot-swe-agent"},"createdAt":"2026-07-14T10:02:00Z","body":"Review complete"}]'
                                fi
                            else
                                comments='[{"author":{"login":"copilot-swe-agent"},"createdAt":"2026-07-14T10:02:00Z","body":"Review complete"}]'
                            fi
                        fi
                        emit_json "{\"comments\":$comments}"
                    else
                        printf '%s\n' "unexpected fake gh pr view call: $*" >&2
                        return 1
                    fi
                    ;;
                comment)
                    touch "$FAKE_GH_STATE_DIR/comment-post"
                    ;;
                *)
                    printf '%s\n' "unexpected fake gh pr call: $subcommand $*" >&2
                    return 1
                    ;;
            esac
            ;;
        api)
            local endpoint="${1:-}"
            case "$endpoint" in
                repos/example/widgets/pulls/42/reviews)
                    local review_call
                    review_call=$(next_call reviews)
                    local review_after=0
                    case "$TEST_SCENARIO" in
                        ready_head_at_request|ready_head_at_rest|ready_head_at_fallback|ready_timeline_error|ready_closed|ready_closed_at_*|ready_closed_in_wait|ready_release_reclassified|ready_*comment*) ;;
                        ready_requested) [ ! -e "$FAKE_GH_STATE_DIR/comment-post" ] || review_after=-1 ;;
                        ready_*) review_after=-1 ;;
                        normal_review|partial_timeline_error|zero_completed_at) review_after=1 ;;
                        ci_pending_then_success|empty_checks_register) review_after=3 ;;
                        ci_success_request|no_checks|empty_checks_*) review_after=2 ;;
                        stale_failure|same_head_retry|superseded_rest|same_second_superseded|unrelated_trigger) review_after=2 ;;
                        in_flight_marker|in_flight_rest) review_after=3 ;;
                        timeline_refresh_error) review_after=4 ;;
                    esac
                    if [ "$review_after" -ne 0 ] && [ "$review_call" -gt "$review_after" ]; then
                        emit_json "[{\"user\":{\"login\":\"copilot-pull-request-reviewer[bot]\"},\"commit_id\":\"$head_sha\"}]"
                    else
                        emit_json '[]'
                    fi
                    ;;
                repos/example/widgets/pulls/42/requested_reviewers)
                    case "$TEST_SCENARIO" in
                        ci_pending_then_success|ci_failure|ci_success_request|head_changed|no_checks|empty_checks_*|release_dash|release_slash|correlated_failure|ready_head_at_request|ready_head_at_rest|ready_head_at_fallback|ready_requested|ready_timeline_error|ready_closed_at_request|ready_closed_at_fallback)
                            touch "$FAKE_GH_STATE_DIR/requested-reviewers"
                            emit_json '{"users":[]}'
                            ;;
                        *)
                            emit_json '{"users":[{"login":"copilot-pull-request-reviewer"}]}'
                            ;;
                    esac
                    ;;
                'repos/example/widgets/issues/42/timeline?per_page=100')
                    local timeline_call
                    timeline_call=$(next_call timeline)
                    case "$TEST_SCENARIO" in
                        ready_previous_comment|ready_marker_comment|ready_copilot_bot_comment|ready_copilot_user_comment|ready_copilot_old_comment|ready_push_comment|ready_comment_before_push|ready_comment_wrong_push|ready_comment_old_trigger)
                            local reply='{"event":"commented","id":101,"created_at":"2026-07-14T10:02:00Z","user":{"login":"copilot-swe-agent"}}'
                            local marker="$current_marker"
                            case "$TEST_SCENARIO" in
                                ready_previous_comment) marker="<!-- github-pr-rereview-head:${head_sha//a/b} -->" ;;
                                ready_marker_comment) ;;
                                ready_copilot_*_comment)
                                    local reply_type=Bot
                                    [ "$TEST_SCENARIO" != ready_copilot_user_comment ] || reply_type=User
                                    [ "$TEST_SCENARIO" != ready_copilot_old_comment ] || marker="<!-- github-pr-rereview-head:${head_sha//a/b} -->"
                                    reply="{\"event\":\"commented\",\"id\":101,\"created_at\":\"2026-07-14T10:02:00Z\",\"user\":{\"login\":\"Copilot\",\"type\":\"$reply_type\"},\"body\":\"> @copilot please re-review\\n> $marker\\n\\nReview complete.\"}"
                                    ;;
                                ready_comment_old_trigger)
                                    emit_json "[{\"event\":\"review_requested\",\"created_at\":\"2026-07-14T10:00:00Z\",\"requested_reviewer\":{\"login\":\"Copilot\"}},$reply]"
                                    return
                                    ;;
                                *) emit_json "[$reply]"; return ;;
                            esac
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:01:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$marker\"},$reply]"
                            ;;
                        correlated_failure)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"}]"
                            ;;
                        partial_timeline_error|ready_timeline_error)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"}]"
                            return 1
                            ;;
                        timeline_refresh_error)
                            if [ "$timeline_call" -eq 1 ]; then
                                emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"}]"
                            else
                                emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"},{\"event\":\"review_requested\",\"created_at\":\"2026-07-14T10:01:00Z\",\"requested_reviewer\":{\"login\":\"Copilot\"}}]"
                            fi
                            if [ "$timeline_call" -gt 1 ] && [ "$timeline_call" -lt 4 ]; then
                                return 1
                            fi
                            ;;
                        stale_failure)
                            emit_json "[{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:00Z\"},{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:05:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"}]"
                            ;;
                        delayed_marker)
                            if [ "$timeline_call" -eq 1 ]; then
                                emit_json '[]'
                            else
                                emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"}]"
                            fi
                            ;;
                        same_head_retry)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:02:00Z\"},{\"event\":\"commented\",\"id\":101,\"created_at\":\"2026-07-14T10:05:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"}]"
                            ;;
                        superseded_rest)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:01:00Z\"},{\"event\":\"review_requested\",\"created_at\":\"2026-07-14T10:02:00Z\",\"requested_reviewer\":{\"login\":\"Copilot\"}}]"
                            ;;
                        same_second_failure)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:00Z\"}]"
                            ;;
                        same_second_superseded)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:00Z\"},{\"event\":\"review_requested\",\"created_at\":\"2026-07-14T10:00:00Z\",\"requested_reviewer\":{\"login\":\"Copilot\"}}]"
                            ;;
                        unrelated_trigger)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"commented\",\"id\":101,\"created_at\":\"2026-07-14T10:01:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot implement the requested change\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:01:05Z\"}]"
                            ;;
                        in_flight_marker)
                            if [ "$timeline_call" -lt 3 ]; then
                                emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"}]"
                            else
                                emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"},{\"event\":\"commented\",\"id\":101,\"created_at\":\"2026-07-14T10:01:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"}]"
                            fi
                            ;;
                        in_flight_rest)
                            if [ "$timeline_call" -lt 3 ]; then
                                emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"}]"
                            else
                                emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"},{\"event\":\"review_requested\",\"created_at\":\"2026-07-14T10:01:00Z\",\"requested_reviewer\":{\"login\":\"Copilot\"}}]"
                            fi
                            ;;
                        *)
                            emit_json '[]'
                            ;;
                    esac
                    ;;
                graphql)
                    if [[ "$*" == *HEAD_REF_FORCE_PUSHED_EVENT* ]]; then
                        local push_head="$head_sha" pushed_at='2026-07-14T10:01:00Z'
                        case "$TEST_SCENARIO" in
                            ready_comment_before_push) pushed_at='2026-07-14T10:03:00Z' ;;
                            ready_comment_wrong_push) push_head="${head_sha//a/b}" ;;
                            ready_push_comment|ready_comment_old_trigger) ;;
                            *) emit_json "{\"data\":{\"repository\":{\"pullRequest\":{\"headRefOid\":\"$head_sha\",\"timelineItems\":{\"nodes\":[]}}}}}"; return ;;
                        esac
                        emit_json "{\"data\":{\"repository\":{\"pullRequest\":{\"headRefOid\":\"$head_sha\",\"timelineItems\":{\"nodes\":[{\"afterCommit\":{\"oid\":\"$push_head\"},\"createdAt\":\"$pushed_at\"}]}}}}}"
                        return
                    fi
                    if [[ " $* " != *" --paginate "* ]]; then
                        emit_json '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
                        return
                    fi
                    [[ "$*" == *"after: \$endCursor"* && "$*" == *'hasNextPage endCursor'* ]] || return 1
                    touch "$FAKE_GH_STATE_DIR/readiness"
                    local state='"OPEN"' draft=false merge_state=CLEAN mergeable=MERGEABLE decision=null
                    local branch='fix/example' title='Fix example'
                    local next=false cursor=null total=0 nodes='[]' errors='[]' readiness_rc=0
                    case "$TEST_SCENARIO" in
                        ready_closed_final) state='"CLOSED"' ;;
                        ready_draft) draft=true ;;
                        ready_unclean) merge_state=BLOCKED ;;
                        ready_conflicting) mergeable=CONFLICTING ;;
                        ready_review_blocked) decision='"CHANGES_REQUESTED"'; merge_state=BLOCKED ;;
                        ready_review_required) decision='"REVIEW_REQUIRED"'; mergeable=UNKNOWN ;;
                        ready_unknown) mergeable=UNKNOWN ;;
                        ready_unknown_state) merge_state=UNKNOWN ;;
                        ready_unknown_with_blocker) mergeable=UNKNOWN; merge_state=BLOCKED ;;
                        ready_review_approved) decision='"APPROVED"' ;;
                        ready_threads) merge_state=BLOCKED; next=true; cursor='"cursor-1"'; total=2; nodes='[{"id":"thread-1","isResolved":true}]' ;;
                        ready_second_page|ready_missing_page|ready_head_on_second_page) next=true; cursor='"cursor-1"'; total=2; nodes='[{"id":"thread-1","isResolved":true}]' ;;
                        ready_threads_incomplete) total=1; nodes='[{"id":"thread-1"}]' ;;
                        ready_missing_state) state=null ;;
                        ready_graphql_errors) errors='[{"message":"fixture error"}]' ;;
                        ready_graphql_failed) readiness_rc=1 ;;
                        release_slash|ready_now_release) branch='release/v2026.7.43'; title='Release v2026.7.43' ;;
                        ready_release_reclassified*) branch='release/v2026.7.43'; title='Needs review' ;;
                    esac
                    emit_readiness_page() {
                        emit_json "{\"errors\":$errors,\"data\":{\"repository\":{\"pullRequest\":{\"headRefOid\":\"$head_sha\",\"state\":$state,\"headRefName\":\"$branch\",\"title\":\"$title\",\"isDraft\":$draft,\"mergeStateStatus\":\"$merge_state\",\"mergeable\":\"$mergeable\",\"reviewDecision\":$decision,\"reviewThreads\":{\"totalCount\":$total,\"nodes\":$nodes,\"pageInfo\":{\"hasNextPage\":$next,\"endCursor\":$cursor}}}}}}"
                    }
                    emit_readiness_page
                    case "$TEST_SCENARIO" in
                        ready_threads|ready_second_page|ready_head_on_second_page)
                            next=false; cursor='"cursor-2"'
                            nodes='[{"id":"thread-2","isResolved":true}]'
                            [ "$TEST_SCENARIO" != ready_threads ] || nodes='[{"id":"thread-2","isResolved":false}]'
                            [ "$TEST_SCENARIO" != ready_head_on_second_page ] || head_sha="${head_sha//a/b}"
                            emit_readiness_page
                            ;;
                    esac
                    return "$readiness_rc"
                    ;;
                'repos/example/widgets/issues/42/comments?per_page=100')
                    emit_json '[]'
                    ;;
                repos/example/widgets/issues/42/timeline)
                    touch "$FAKE_GH_STATE_DIR/request-timeline"
                    printf '0\n'
                    ;;
                -X)
                    [[ "$*" == *'POST /repos/example/widgets/pulls/42/requested_reviewers'* ]] || return 1
                    touch "$FAKE_GH_STATE_DIR/rest-post"
                    ;;
                *)
                    printf '%s\n' "unexpected fake gh api call: $*" >&2
                    return 1
                    ;;
            esac
            ;;
        *)
            printf '%s\n' "unexpected fake gh command: $command_name $*" >&2
            return 1
            ;;
    esac
}

case "$(basename "$0")" in
    gh)
        fake_gh "$@"
        exit
        ;;
    sleep)
        exit 0
        ;;
esac

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local output="$1"
    local expected="$2"
    local label="$3"
    [[ "$output" == *"$expected"* ]] || fail "$label: missing '$expected'"
}

assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local label="$3"
    [[ "$output" != *"$unexpected"* ]] || fail "$label: unexpectedly found '$unexpected'"
}

test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
poller="$test_dir/../scripts/poll-pr-review.sh"
unset GH_PR_EXPECTED_HEAD
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"
ln -s "$test_dir/$(basename "${BASH_SOURCE[0]}")" "$tmp_dir/bin/gh"
ln -s "$test_dir/$(basename "${BASH_SOURCE[0]}")" "$tmp_dir/bin/sleep"
cat > "$tmp_dir/bin/fake-request-copilot.sh" <<'EOF'
#!/usr/bin/env bash
printf 'request %s\n' "$*" >> "$FAKE_GH_STATE_DIR/requests.log"
cat "$FAKE_GH_STATE_DIR/checks" >> "$FAKE_GH_STATE_DIR/request-checks.log"
EOF
chmod +x "$tmp_dir/bin/fake-request-copilot.sh"

CASE_OUTPUT=""
CASE_RC=0
run_case_raw() {
    local scenario="$1"
    local policy="${2-unset}"
    local state_dir="$tmp_dir/$scenario"
    mkdir -p "$state_dir"
    set +e
    CASE_OUTPUT=$(
        unset GH_PR_ALLOW_NO_CHECKS
        if [ "$policy" != "unset" ]; then
            export GH_PR_ALLOW_NO_CHECKS="$policy"
        fi
        PATH="$tmp_dir/bin:$PATH" FAKE_GH_STATE_DIR="$state_dir" TEST_SCENARIO="$scenario" \
        GH_PR_NOTIFY_TARGET= GH_PR_REQUEST_SCRIPT="$tmp_dir/bin/fake-request-copilot.sh" bash "$poller" 42 2 2>&1)
    CASE_RC=$?
    set -e
}

run_case() {
    local scenario="$1"
    run_case_raw "$scenario" "${2-unset}"
    if [ "$CASE_RC" -ne 0 ]; then
        printf '%s\n' "$CASE_OUTPUT" >&2
        fail "$scenario: poller exited non-zero (rc=$CASE_RC)"
    fi
    printf '%s' "$CASE_OUTPUT"
}

output=$(run_case empty_checks_valid 1)
assert_contains "$output" "no CI checks" 'confirmed empty checks'
no_ci_output="$output"
[ "$(wc -l < "$tmp_dir/empty_checks_valid/requests.log")" -eq 1 ] || fail 'confirmed empty checks: expected exactly one request'
[ "$(grep -cF -- '--json headRefOid,statusCheckRollup' "$tmp_dir/empty_checks_valid/calls.log")" -eq "$(cat "$tmp_dir/empty_checks_valid/checks")" ] || fail 'confirmed empty checks: expected one confirmation per empty checks query'
printf '%s\n' 'ok - real gh empty stdout rc1 requires same-head empty rollup confirmation'


output=$(run_case empty_checks_register)
[ "$(wc -l < "$tmp_dir/empty_checks_register/requests.log")" -eq 1 ] || fail 'CI registration: expected exactly one request'
[ "$(cat "$tmp_dir/empty_checks_register/request-checks.log")" -eq 3 ] || fail 'CI registration: requested before checks succeeded'
assert_contains "$output" 'CI pending — deferring Copilot request' 'CI registration default gate'
printf '%s\n' 'ok - default empty then pending CI requests only after success'

for scenario in empty_checks_default empty_checks_zero empty_checks_other no_checks_default; do
    policy=unset
    case "$scenario" in
        empty_checks_zero) policy=0 ;;
        empty_checks_other) policy=true ;;
    esac
    run_case_raw "$scenario" "$policy"
    [ "$CASE_RC" -eq 124 ] || fail "$scenario: expected timeout rc=124, got rc=$CASE_RC"
    [ ! -e "$tmp_dir/$scenario/requests.log" ] || fail "$scenario: Copilot request was attempted"
    assert_contains "$CASE_OUTPUT" 'checks_state=pending' "$scenario"
    printf 'ok - %s without explicit policy times out without requesting\n' "$scenario"
done
assert_contains "$no_ci_output" 'explicit no-CI policy' 'explicit policy output'
assert_contains "$no_ci_output" 'checks_state=none' 'explicit policy preserves none'
assert_not_contains "$no_ci_output" 'CI green' 'no checks are not green CI'
assert_not_contains "$no_ci_output" 'green CI' 'no checks completion is not green CI'

output=$(run_case ci_pending_then_success)
assert_contains "$output" 'CI pending — deferring Copilot request' 'pending CI request gate'
[ "$(wc -l < "$tmp_dir/ci_pending_then_success/requests.log" 2>/dev/null || echo 0)" -eq 1 ] || fail 'pending CI request gate: expected exactly one request after CI became green'
printf '%s\n' 'ok - pending CI defers Copilot until success'

run_case_raw ci_failure
[ "$CASE_RC" -eq 2 ] || fail "failed CI: expected rc=2, got rc=$CASE_RC"
assert_contains "$CASE_OUTPUT" 'CI checks failed — Copilot was not requested' 'failed CI'
[ ! -e "$tmp_dir/ci_failure/requests.log" ] || fail 'failed CI: Copilot request was attempted'
printf '%s\n' 'ok - failed CI exits non-successfully without requesting Copilot'

output=$(run_case ci_success_request)
assert_contains "$output" 'CI green — requesting Copilot review' 'successful CI request gate'
[ "$(wc -l < "$tmp_dir/ci_success_request/requests.log" 2>/dev/null || echo 0)" -eq 1 ] || fail 'successful CI request gate: expected exactly one request'
printf '%s\n' 'ok - successful CI requests Copilot exactly once'

run_case_raw head_changed
[ "$CASE_RC" -eq 3 ] || fail "head change fence: expected rc=3, got rc=$CASE_RC"
assert_contains "$CASE_OUTPUT" 'PR head changed while polling' 'head change fence'
[ ! -e "$tmp_dir/head_changed/requests.log" ] || fail 'head change fence: stale head triggered Copilot request'
printf '%s\n' 'ok - changed PR head cannot reuse stale CI or review evidence'

output=$(run_case no_checks 1)
assert_contains "$output" "explicit no-CI policy" 'legacy no-check behavior'
[ "$(wc -l < "$tmp_dir/no_checks/requests.log" 2>/dev/null || echo 0)" -eq 1 ] || fail 'legacy no-check behavior: expected exactly one Copilot request'
printf '%s\n' 'ok - existing zero-check eligibility is preserved explicitly'
assert_not_contains "$(cat "$tmp_dir/no_checks/calls.log")" '--json headRefOid,statusCheckRollup' 'array compatibility needs no confirmation'


for scenario in empty_checks_failed empty_checks_failed_json empty_checks_nonempty empty_checks_malformed empty_checks_wrong_head empty_checks_null empty_checks_missing empty_checks_multiple; do
    run_case_raw "$scenario" 1
    [ "$CASE_RC" -eq 4 ] || fail "$scenario: expected query error rc=4, got rc=$CASE_RC"
    assert_contains "$CASE_OUTPUT" 'could not classify current-head CI checks' "$scenario"
    [ ! -e "$tmp_dir/$scenario/requests.log" ] || fail "$scenario: Copilot request was attempted"
    [ "$(grep -cF -- '--json headRefOid,statusCheckRollup' "$tmp_dir/$scenario/calls.log")" -eq 1 ] || fail "$scenario: expected exactly one confirmation"
    printf 'ok - %s rejects unconfirmed zero checks\n' "$scenario"
done

run_case_raw malformed_checks
[ "$CASE_RC" -eq 4 ] || fail "malformed checks: expected rc=4, got rc=$CASE_RC"
[ ! -e "$tmp_dir/malformed_checks/requests.log" ] || fail 'malformed checks: Copilot request was attempted'
assert_not_contains "$(cat "$tmp_dir/malformed_checks/calls.log")" '--json headRefOid,statusCheckRollup' 'nonempty malformed checks must not trigger confirmation'
printf '%s\n' 'ok - nonempty malformed checks fail without confirmation'

output=$(run_case release_dash)
assert_contains "$output" 'version-release PR detected' 'dash release detection'
assert_contains "$output" 'release_pr=yes checks_state=pending' 'dash release CI wait'
[ ! -e "$tmp_dir/release_dash/requests.log" ] || fail 'dash release: Copilot request was attempted'
assert_not_contains "$(cat "$tmp_dir/release_dash/calls.log")" 'repos/example/widgets/pulls/42/reviews' 'dash release review wait'
assert_not_contains "$(cat "$tmp_dir/release_dash/calls.log")" 'requested_reviewers' 'dash release pending-review query'
printf '%s\n' 'ok - dash version-release PR waits for CI and skips Copilot'

output=$(run_case release_slash)
assert_contains "$output" 'release/v2026.7.43 / Release v2026.7.43' 'slash release detection'
[ ! -e "$tmp_dir/release_slash/requests.log" ] || fail 'slash release: Copilot request was attempted'
assert_not_contains "$(cat "$tmp_dir/release_slash/calls.log")" 'repos/example/widgets/pulls/42/reviews' 'slash release review wait'
printf '%s\n' 'ok - slash version-release PR skips Copilot after green CI'

output=$(run_case correlated_failure)
assert_contains "$output" 'current-head fallback request ended with copilot_work_finished_failure' 'correlated failure'
assert_contains "$output" 'waiting for green CI only' 'correlated failure'
assert_contains "$output" 'iter=2' 'correlated failure preserves CI gating'
assert_contains "$output" 'green CI + Copilot terminal failure observed' 'correlated failure completion'
printf '%s\n' 'ok - correlated terminal failure waits only for CI'

output=$(run_case partial_timeline_error)
assert_contains "$output" 'could not read the complete PR timeline' 'partial timeline failure'
assert_contains "$output" 'new_review=yes' 'partial timeline failure keeps polling'
assert_contains "$output" 'green CI + Copilot activity observed' 'partial timeline failure normal completion'
assert_not_contains "$output" 'fallback request ended with copilot_work_finished_failure' 'partial timeline failure rejection'
printf '%s\n' 'ok - partial timeline failure cannot create terminal evidence'

output=$(run_case timeline_refresh_error)
assert_contains "$output" 'current-head fallback request ended with copilot_work_finished_failure' 'timeline refresh error initial state'
assert_contains "$output" 'preserving the last known fallback state' 'timeline refresh error retention'
assert_contains "$output" 'checks_state=success checks_done=true activity_seen=no terminal_failure_seen=yes fallback_state_fresh=no' 'timeline refresh error rejects stale terminal evidence'
assert_contains "$output" 'newer Copilot trigger superseded the prior terminal failure' 'timeline refresh error observes hidden superseding request after recovery'
assert_contains "$output" 'iter=4' 'timeline refresh error keeps polling for activity'
assert_contains "$output" 'green CI + Copilot activity observed' 'timeline refresh error normal completion'
assert_not_contains "$output" 'green CI + Copilot terminal failure observed' 'timeline refresh error cannot exit from stale terminal evidence'
printf '%s\n' 'ok - timeline refresh failure cannot act on stale terminal evidence'

output=$(run_case stale_failure)
assert_contains "$output" 'new_review=yes' 'stale failure normal review'
assert_contains "$output" 'iter=2' 'stale failure rejection keeps polling'
assert_contains "$output" 'green CI + Copilot activity observed' 'stale failure normal completion'
assert_not_contains "$output" 'fallback request ended with copilot_work_finished_failure' 'stale failure rejection'
printf '%s\n' 'ok - failure before current-head marker is rejected'

output=$(run_case delayed_marker)
assert_contains "$output" 'fallback_request_at=none' 'delayed marker initial lookup'
assert_contains "$output" 'newest current-head fallback marker became visible at 2026-07-14T10:00:00Z' 'delayed marker retry'
assert_contains "$output" 'current-head fallback request ended with copilot_work_finished_failure' 'delayed marker failure'
assert_contains "$output" 'green CI + Copilot terminal failure observed' 'delayed marker completion'
printf '%s\n' 'ok - delayed fallback marker discovery is retried'

output=$(run_case same_head_retry)
assert_contains "$output" 'new_review=yes' 'same-head retry normal review'
assert_contains "$output" 'iter=2' 'same-head retry rejection keeps polling'
assert_contains "$output" 'green CI + Copilot activity observed' 'same-head retry normal completion'
assert_not_contains "$output" 'fallback request ended with copilot_work_finished_failure' 'same-head retry rejection'
printf '%s\n' 'ok - failure before newest same-head marker is rejected'

output=$(run_case superseded_rest)
assert_contains "$output" 'new_review=yes' 'superseding REST request normal review'
assert_contains "$output" 'iter=2' 'superseding REST request keeps polling'
assert_contains "$output" 'green CI + Copilot activity observed' 'superseding REST request normal completion'
assert_not_contains "$output" 'fallback request ended with copilot_work_finished_failure' 'superseding REST request rejection'
printf '%s\n' 'ok - newer REST request supersedes old fallback failure'

output=$(run_case same_second_failure)
assert_contains "$output" 'current-head fallback request ended with copilot_work_finished_failure' 'same-second failure'
assert_contains "$output" 'green CI + Copilot terminal failure observed' 'same-second failure completion'
printf '%s\n' 'ok - same-second terminal failure follows marker by timeline order'

output=$(run_case same_second_superseded)
assert_contains "$output" 'new_review=yes' 'same-second supersession normal review'
assert_contains "$output" 'green CI + Copilot activity observed' 'same-second supersession completion'
assert_not_contains "$output" 'fallback request ended with copilot_work_finished_failure' 'same-second supersession rejection'
printf '%s\n' 'ok - same-second newer REST request supersedes fallback failure'

output=$(run_case unrelated_trigger)
assert_contains "$output" 'new_review=yes' 'unrelated trigger normal review'
assert_contains "$output" 'green CI + Copilot activity observed' 'unrelated trigger completion'
assert_not_contains "$output" 'fallback request ended with copilot_work_finished_failure' 'unrelated trigger rejection'
printf '%s\n' 'ok - unrelated later Copilot trigger rejects generic failure'

output=$(run_case in_flight_marker)
assert_contains "$output" 'current-head fallback request ended with copilot_work_finished_failure' 'in-flight marker initial failure'
assert_contains "$output" 'newest current-head fallback marker became visible at 2026-07-14T10:01:00Z' 'in-flight marker refresh'
assert_contains "$output" 'newer Copilot trigger superseded the prior terminal failure' 'in-flight marker resets failure'
assert_contains "$output" 'iter=3' 'in-flight marker keeps polling'
assert_contains "$output" 'green CI + Copilot activity observed' 'in-flight marker completion'
printf '%s\n' 'ok - in-flight fallback retry clears latched terminal failure'

output=$(run_case in_flight_rest)
assert_contains "$output" 'current-head fallback request ended with copilot_work_finished_failure' 'in-flight REST initial failure'
assert_contains "$output" 'newer Copilot trigger superseded the prior terminal failure' 'in-flight REST resets failure'
assert_contains "$output" 'iter=3' 'in-flight REST keeps polling'
assert_contains "$output" 'green CI + Copilot activity observed' 'in-flight REST completion'
printf '%s\n' 'ok - in-flight REST request clears latched terminal failure'

output=$(run_case normal_review)
assert_contains "$output" 'new_review=yes' 'normal review'
assert_contains "$output" 'green CI + Copilot activity observed' 'normal review completion'
printf '%s\n' 'ok - normal Copilot review activity is preserved'

output=$(run_case normal_comment)
assert_contains "$output" 'new_comment=yes' 'normal comment'
assert_contains "$output" 'green CI + Copilot activity observed' 'normal comment completion'
printf '%s\n' 'ok - normal Copilot comment activity is preserved'

output=$(run_case zero_completed_at)
assert_contains "$output" 'checks_done=false' 'zero completedAt is pending'
assert_contains "$output" 'iter=2' 'zero completedAt keeps polling'
assert_contains "$output" 'green CI + Copilot activity observed' 'zero completedAt completion'
printf '%s\n' 'ok - Go zero-time completedAt is treated as in-progress'

# Completion notification: absent-safe by default, delivered when a target is set.
notify_log="$tmp_dir/notify.log"
cat > "$tmp_dir/bin/fake-notify.sh" <<EOF
#!/usr/bin/env bash
printf 'args=%s message=%s\n' "\$*" "\$(cat)" >> "$notify_log"
EOF
chmod +x "$tmp_dir/bin/fake-notify.sh"

state_dir="$tmp_dir/notify_target"
mkdir -p "$state_dir"
output=$(PATH="$tmp_dir/bin:$PATH" FAKE_GH_STATE_DIR="$state_dir" TEST_SCENARIO=normal_review \
    GH_PR_ALLOW_NO_CHECKS= GH_PR_NOTIFY_TARGET=12345 GH_PR_NOTIFY_THREAD=678 GH_PR_NOTIFY_SCRIPT="$tmp_dir/bin/fake-notify.sh" \
    bash "$poller" 42 2 2>&1) || fail 'notify_target: poller exited non-zero'
[ -f "$notify_log" ] || fail 'notify_target: no delivery attempted'
notify_line=$(cat "$notify_log")
assert_contains "$notify_line" 'args=12345 --thread 678' 'notify target and thread'
assert_contains "$notify_line" 'checks_done=true' 'notify summary content'
printf '%s\n' 'ok - completion notification delivered to configured chat/thread'

rm -f "$notify_log"
state_dir="$tmp_dir/notify_absent"
mkdir -p "$state_dir"
output=$(PATH="$tmp_dir/bin:$PATH" FAKE_GH_STATE_DIR="$state_dir" TEST_SCENARIO=normal_review \
    GH_PR_ALLOW_NO_CHECKS= GH_PR_NOTIFY_TARGET= GH_PR_NOTIFY_SCRIPT="$tmp_dir/bin/fake-notify.sh" \
    bash "$poller" 42 2 2>&1) || fail 'notify_absent: poller exited non-zero'
[ ! -f "$notify_log" ] || fail 'notify_absent: delivery attempted without a target'
printf '%s\n' 'ok - no notification without GH_PR_NOTIFY_TARGET'

expected_head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run_readiness() {
    local scenario="$1" rc="$2" reason="$3" checks="$4" copilot="$5"
    local head="${6-$expected_head}" repo="${7-example/widgets}" policy="${8-}" budget="${9-2}"
    local state_dir="$tmp_dir/expected-$scenario-$reason-$policy"
    local request="$tmp_dir/bin/fake-request-copilot.sh"
    case "$scenario" in
        ready_head_at_rest|ready_head_at_fallback|ready_closed_at_fallback|ready_requested) request="$test_dir/../scripts/request-copilot-rereview.sh" ;;
    esac
    mkdir -p "$state_dir"
    CASE_RC=0
    CASE_OUTPUT=$(PATH="$tmp_dir/bin:$PATH" FAKE_GH_STATE_DIR="$state_dir" TEST_SCENARIO="$scenario" \
        GH_REPO="$repo" GH_PR_EXPECTED_HEAD="$head" GH_PR_ALLOW_NO_CHECKS="$policy" GH_PR_NOTIFY_TARGET='' \
        GH_PR_REQUEST_SCRIPT="$request" bash "$poller" 42 "$budget" 2>"$state_dir/stderr.log") || CASE_RC=$?
    [ "$CASE_RC" -eq "$rc" ] || fail "$scenario: expected readiness exit $rc, got $CASE_RC ($CASE_OUTPUT)"
    jq -se --arg reason "$reason" --arg checks "$checks" --arg copilot "$copilot" --arg head "$head" --arg repo "$repo" '
        length == 1 and (.[0] | .ready == ($reason == "ready") and .reason == $reason and
            .checks == $checks and .copilot == $copilot and .expected_head == $head and
            .pr == 42 and .repo == $repo)
    ' <<< "$CASE_OUTPUT" >/dev/null || fail "$scenario: unexpected readiness result $CASE_OUTPUT"
    if [ "$reason" = invalid_input ]; then
        [ ! -e "$state_dir/calls.log" ] || fail "$scenario: invalid input reached gh"
    fi
    [ ! -e "$state_dir/requests.log" ] || fail "$scenario: unexpected Copilot request"
    case "$scenario" in
        ready_requested)
            [ -e "$state_dir/rest-post" ] && [ -e "$state_dir/comment-post" ] || fail "$scenario: expected a REST request and fallback comment"
            assert_contains "$(cat "$state_dir/calls.log")" "github-pr-rereview-head:$head" "$scenario: fallback head marker"
            ;;
        ready_head_at_fallback|ready_closed_at_fallback)
            [ -e "$state_dir/rest-post" ] && [ ! -e "$state_dir/comment-post" ] || fail "$scenario: expected only the REST request"
            ;;
        *)
            [ ! -e "$state_dir/rest-post" ] && [ ! -e "$state_dir/comment-post" ] || fail "$scenario: unexpected REST request or fallback comment"
            ;;
    esac
    printf 'ok - expected-head %s -> %s\n' "$scenario" "$reason"
}

run_readiness ready_previous_comment 124 timeout success pending
run_readiness ready_marker_comment 0 ready success activity
run_readiness ready_copilot_bot_comment 0 ready success activity
run_readiness ready_copilot_user_comment 124 timeout success pending
run_readiness ready_copilot_old_comment 124 timeout success pending
run_readiness ready_push_comment 0 ready success activity
run_readiness ready_comment_before_push 124 timeout success pending
run_readiness ready_comment_wrong_push 124 timeout success pending
run_readiness ready_comment_old_trigger 124 timeout success pending
run_readiness ready_second_page 0 ready success activity
run_readiness ready_review_approved 0 ready success activity
run_readiness ready_requested 0 ready success activity
run_readiness correlated_failure 0 ready success terminal_no_review
run_readiness release_slash 0 ready success release_skip
run_readiness ready_release_reclassified 5 copilot_pending success pending
run_readiness ready_release_reclassified_reviewed 0 ready success activity
run_readiness ready_now_release 0 ready success release_skip
run_readiness ready_empty_checks 0 ready none activity "$expected_head" example/widgets 1
run_readiness ready_empty_checks 124 timeout pending activity
run_readiness ready_empty_checks 124 timeout pending activity "$expected_head" example/widgets true
run_readiness ready_short_sha 1 invalid_input unknown pending aaaaaaa
run_readiness ready_no_repo 1 invalid_input unknown pending "$expected_head" ''
run_readiness ready_invalid_timeout 1 invalid_input unknown pending "$expected_head" example/widgets '' invalid
run_readiness ready_stale 3 head_changed unknown pending "${expected_head//a/b}"
run_readiness ready_head_at_request 3 head_changed success pending
run_readiness ready_head_at_rest 3 head_changed success pending
run_readiness ready_head_at_fallback 3 head_changed success pending
run_readiness ready_head_at_end 3 head_changed success activity
run_readiness ready_head_on_second_page 3 head_changed success activity
run_readiness ready_replaced_at_start 3 head_changed unknown pending
run_readiness ready_replaced_in_wait 3 head_changed pending activity
run_readiness ready_timeline_error 124 timeout success pending
run_readiness ci_failure 2 checks_failed failure pending
run_readiness ready_checks_partial 4 query_error query_error pending
run_readiness ready_checks_incomplete 4 query_error query_error pending
run_readiness ready_checks_regressed 5 checks_pending pending activity
run_readiness ready_checks_failed_at_end 2 checks_failed failure activity
run_readiness ready_closed 5 pr_not_open unknown pending
run_readiness ready_merged 5 pr_not_open unknown pending
run_readiness ready_closed_in_wait 5 pr_not_open success pending
run_readiness ready_closed_at_request 5 pr_not_open success pending
run_readiness ready_closed_at_fallback 5 pr_not_open success pending
run_readiness ready_closed_final 5 pr_not_open success activity
run_readiness ready_draft 5 draft success activity
run_readiness ready_unclean 5 merge_blocked success activity
run_readiness ready_conflicting 5 merge_blocked success activity
run_readiness ready_unknown 4 query_error success activity
run_readiness ready_unknown_state 4 query_error success activity
run_readiness ready_unknown_with_blocker 5 merge_blocked success activity
run_readiness ready_review_blocked 5 review_blocked success activity
run_readiness ready_review_required 5 review_blocked success activity
run_readiness ready_threads 5 unresolved_threads success activity
for scenario in ready_missing_page ready_threads_incomplete ready_missing_state ready_graphql_errors ready_graphql_failed; do
    run_readiness "$scenario" 4 query_error success activity
done

printf '%s\n' 'PASS: poll-pr-review regression tests'
