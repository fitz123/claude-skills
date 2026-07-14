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
                    if [[ " $* " == *" --json completedAt "* ]]; then
                        local check_call
                        check_call=$(next_call checks)
                        if [ "$TEST_SCENARIO" = "correlated_failure" ] && [ "$check_call" -lt 3 ]; then
                            emit_json '[{"completedAt":null}]'
                        else
                            emit_json '[{"completedAt":"2026-07-14T10:10:00Z"}]'
                        fi
                    else
                        printf '%s\n' 'ci  pass  10s'
                    fi
                    ;;
                view)
                    if [[ " $* " == *" --json headRefOid "* ]]; then
                        emit_json "{\"headRefOid\":\"$head_sha\"}"
                    elif [[ " $* " == *" --json commits "* ]]; then
                        emit_json '{"commits":[{"committedDate":"2026-07-14T09:00:00Z"}]}'
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
                    if { [ "$TEST_SCENARIO" = "normal_review" ] && [ "$review_call" -gt 1 ]; } || \
                       { [ "$TEST_SCENARIO" = "stale_failure" ] && [ "$review_call" -gt 2 ]; }; then
                        emit_json "[{\"user\":{\"login\":\"copilot-pull-request-reviewer[bot]\"},\"commit_id\":\"$head_sha\"}]"
                    else
                        emit_json '[]'
                    fi
                    ;;
                repos/example/widgets/pulls/42/requested_reviewers)
                    emit_json '{"users":[{"login":"copilot-pull-request-reviewer"}]}'
                    ;;
                'repos/example/widgets/issues/42/comments?per_page=100')
                    case "$TEST_SCENARIO" in
                        correlated_failure)
                            emit_json "[{\"created_at\":\"2026-07-14T10:00:00Z\",\"body\":\"@copilot please re-review\\n\\n$current_marker\"}]"
                            ;;
                        stale_failure)
                            emit_json "[{\"created_at\":\"2026-07-14T09:00:00Z\",\"body\":\"<!-- github-pr-rereview-head:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb -->\"},{\"created_at\":\"2026-07-14T10:05:00Z\",\"body\":\"$current_marker\"}]"
                            ;;
                        *)
                            emit_json '[]'
                            ;;
                    esac
                    ;;
                'repos/example/widgets/issues/42/timeline?per_page=100')
                    case "$TEST_SCENARIO" in
                        correlated_failure)
                            emit_json '[{"event":"copilot_work_finished_failure","created_at":"2026-07-14T10:00:05Z"}]'
                            ;;
                        stale_failure)
                            emit_json '[{"event":"copilot_work_finished_failure","created_at":"2026-07-14T10:00:00Z"}]'
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

run_case() {
    local scenario="$1"
    local state_dir="$tmp_dir/$scenario"
    local output
    mkdir -p "$state_dir"
    if ! output=$(PATH="$tmp_dir/bin:$PATH" FAKE_GH_STATE_DIR="$state_dir" TEST_SCENARIO="$scenario" bash "$poller" 42 2 2>&1); then
        printf '%s\n' "$output" >&2
        fail "$scenario: poller exited non-zero"
    fi
    printf '%s' "$output"
}

output=$(run_case correlated_failure)
assert_contains "$output" 'current-head fallback request ended with copilot_work_finished_failure' 'correlated failure'
assert_contains "$output" 'waiting for CI only' 'correlated failure'
assert_contains "$output" 'iter=2' 'correlated failure preserves CI gating'
assert_contains "$output" 'CI done + Copilot terminal failure observed' 'correlated failure completion'
printf '%s\n' 'ok - correlated terminal failure waits only for CI'

output=$(run_case stale_failure)
assert_contains "$output" 'new_review=yes' 'stale failure normal review'
assert_contains "$output" 'iter=2' 'stale failure rejection keeps polling'
assert_contains "$output" 'CI done + Copilot activity observed' 'stale failure normal completion'
assert_not_contains "$output" 'fallback request ended with copilot_work_finished_failure' 'stale failure rejection'
printf '%s\n' 'ok - failure before current-head marker is rejected'

output=$(run_case normal_review)
assert_contains "$output" 'new_review=yes' 'normal review'
assert_contains "$output" 'CI done + Copilot activity observed' 'normal review completion'
printf '%s\n' 'ok - normal Copilot review activity is preserved'

output=$(run_case normal_comment)
assert_contains "$output" 'new_comment=yes' 'normal comment'
assert_contains "$output" 'CI done + Copilot activity observed' 'normal comment completion'
printf '%s\n' 'ok - normal Copilot comment activity is preserved'

printf '%s\n' 'PASS: poll-pr-review regression tests'
