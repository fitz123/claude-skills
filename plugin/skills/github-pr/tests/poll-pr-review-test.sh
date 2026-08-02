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
                            no_checks)
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
                    if [[ " $* " == *" --json headRefOid "* ]]; then
                        local head_call
                        head_call=$(next_call head)
                        if [ "$TEST_SCENARIO" = "head_changed" ] && [ "$head_call" -gt 1 ]; then
                            emit_json '{"headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'
                        else
                            emit_json "{\"headRefOid\":\"$head_sha\"}"
                        fi
                    elif [[ " $* " == *" --json commits "* ]]; then
                        emit_json '{"commits":[{"committedDate":"2026-07-14T09:00:00Z"}]}'
                    elif [[ " $* " == *" --json headRefName,title "* ]]; then
                        case "$TEST_SCENARIO" in
                            release_dash)
                                emit_json '{"headRefName":"release-2026.8.0","title":"chore: release 2026.8.0"}'
                                ;;
                            release_slash)
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
                        if [ "$TEST_SCENARIO" = "normal_comment" ]; then
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
                        normal_review|partial_timeline_error|zero_completed_at) review_after=1 ;;
                        ci_pending_then_success) review_after=3 ;;
                        ci_success_request|no_checks) review_after=2 ;;
                        stale_failure|same_head_retry|superseded_rest|same_second_superseded|unrelated_trigger) review_after=2 ;;
                        in_flight_marker|in_flight_rest) review_after=3 ;;
                        timeline_refresh_error) review_after=4 ;;
                    esac
                    if [ "$review_after" -gt 0 ] && [ "$review_call" -gt "$review_after" ]; then
                        emit_json "[{\"user\":{\"login\":\"copilot-pull-request-reviewer[bot]\"},\"commit_id\":\"$head_sha\"}]"
                    else
                        emit_json '[]'
                    fi
                    ;;
                repos/example/widgets/pulls/42/requested_reviewers)
                    case "$TEST_SCENARIO" in
                        ci_pending_then_success|ci_failure|ci_success_request|head_changed|no_checks|release_dash|release_slash)
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
                        correlated_failure)
                            emit_json "[{\"event\":\"commented\",\"id\":100,\"created_at\":\"2026-07-14T10:00:00Z\",\"user\":{\"login\":\"reviewer\"},\"body\":\"@copilot please re-review\\n\\n$current_marker\"},{\"event\":\"copilot_work_finished_failure\",\"created_at\":\"2026-07-14T10:00:05Z\"}]"
                            ;;
                        partial_timeline_error)
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
                    emit_json '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
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
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"
ln -s "$test_dir/$(basename "${BASH_SOURCE[0]}")" "$tmp_dir/bin/gh"
ln -s "$test_dir/$(basename "${BASH_SOURCE[0]}")" "$tmp_dir/bin/sleep"
cat > "$tmp_dir/bin/fake-request-copilot.sh" <<'EOF'
#!/usr/bin/env bash
printf 'request %s\n' "$*" >> "$FAKE_GH_STATE_DIR/requests.log"
EOF
chmod +x "$tmp_dir/bin/fake-request-copilot.sh"

CASE_OUTPUT=""
CASE_RC=0
run_case_raw() {
    local scenario="$1"
    local state_dir="$tmp_dir/$scenario"
    mkdir -p "$state_dir"
    set +e
    CASE_OUTPUT=$(PATH="$tmp_dir/bin:$PATH" FAKE_GH_STATE_DIR="$state_dir" TEST_SCENARIO="$scenario" \
        GH_PR_REQUEST_SCRIPT="$tmp_dir/bin/fake-request-copilot.sh" bash "$poller" 42 2 2>&1)
    CASE_RC=$?
    set -e
}

run_case() {
    local scenario="$1"
    run_case_raw "$scenario"
    if [ "$CASE_RC" -ne 0 ]; then
        printf '%s\n' "$CASE_OUTPUT" >&2
        fail "$scenario: poller exited non-zero (rc=$CASE_RC)"
    fi
    printf '%s' "$CASE_OUTPUT"
}

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

output=$(run_case no_checks)
assert_contains "$output" "preserving the poller's existing no-check eligibility" 'legacy no-check behavior'
[ "$(wc -l < "$tmp_dir/no_checks/requests.log" 2>/dev/null || echo 0)" -eq 1 ] || fail 'legacy no-check behavior: expected exactly one Copilot request'
printf '%s\n' 'ok - existing zero-check eligibility is preserved explicitly'

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
    GH_PR_NOTIFY_TARGET=12345 GH_PR_NOTIFY_THREAD=678 GH_PR_NOTIFY_SCRIPT="$tmp_dir/bin/fake-notify.sh" \
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
    GH_PR_NOTIFY_SCRIPT="$tmp_dir/bin/fake-notify.sh" \
    bash "$poller" 42 2 2>&1) || fail 'notify_absent: poller exited non-zero'
[ ! -f "$notify_log" ] || fail 'notify_absent: delivery attempted without a target'
printf '%s\n' 'ok - no notification without GH_PR_NOTIFY_TARGET'

printf '%s\n' 'PASS: poll-pr-review regression tests'
