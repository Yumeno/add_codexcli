#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="$SCRIPT_DIR/../codex-verify.sh"
ROOT="${TMPDIR:-/tmp}/codex_verify_test_$$"
total=0
passed=0

cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

pass() { printf 'PASS: %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL: %s - %s\n' "$1" "$2"; }
test_case() {
    local name="$1"; shift
    total=$((total + 1))
    if "$@"; then pass "$name"; else fail "$name" "assertion failed"; fi
}

new_repo() {
    rm -rf "$ROOT"
    mkdir -p "$ROOT"
    git -C "$ROOT" init -q
    git -C "$ROOT" config user.email test@example.com
    git -C "$ROOT" config user.name Test
    printf 'initial\n' >"$ROOT/tracked.txt"
    git -C "$ROOT" add tracked.txt
    git -C "$ROOT" commit -qm initial
}

snapshot() {
    bash "$VERIFY" snapshot --repo "$ROOT" --out "$ROOT/snapshot.txt" >/dev/null
}

run_check() {
    set +e
    CHECK_OUTPUT="$(bash "$VERIFY" check --repo "$ROOT" --snapshot "$ROOT/snapshot.txt" "$@" 2>&1)"
    CHECK_CODE=$?
    set -e
}

case_unchanged() {
    new_repo; snapshot; run_check
    [[ $CHECK_CODE -eq 0 && "$CHECK_OUTPUT" != *"[CODEX_VERIFY_VIOLATION]"* ]]
}
case_tracked_edit() {
    new_repo; snapshot; printf 'changed\n' >>"$ROOT/tracked.txt"; run_check
    [[ $CHECK_CODE -eq 0 && "$CHECK_OUTPUT" == *"tracked.txt"* ]]
}
case_head_change() {
    new_repo; snapshot; printf 'next\n' >>"$ROOT/tracked.txt"
    git -C "$ROOT" add tracked.txt; git -C "$ROOT" commit -qm next; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"[CODEX_VERIFY_VIOLATION] HEAD changed:"* ]]
}
case_branch_change() {
    new_repo; snapshot; git -C "$ROOT" checkout -qb other; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"[CODEX_VERIFY_VIOLATION] branch changed:"* ]]
}
case_env_modified() {
    new_repo; printf 'A=1\n' >"$ROOT/.env"; snapshot
    printf 'A=2\n' >"$ROOT/.env"; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file modified: .env"* ]]
}
case_env_allowed() {
    new_repo; printf 'A=1\n' >"$ROOT/.env"; snapshot
    printf 'A=2\n' >"$ROOT/.env"; run_check --allow .env
    [[ $CHECK_CODE -eq 0 && "$CHECK_OUTPUT" == *"[CODEX_VERIFY_ALLOWED] protected file modified (allowed): .env"* ]]
}
case_env_added() {
    new_repo; snapshot; printf 'A=1\n' >"$ROOT/.env"; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file added: .env"* ]]
}
case_untracked() {
    new_repo; snapshot; printf 'new\n' >"$ROOT/untracked.txt"; run_check
    [[ $CHECK_CODE -eq 0 && "$CHECK_OUTPUT" == *"untracked.txt"* ]]
}
case_not_repo() {
    rm -rf "$ROOT"; mkdir -p "$ROOT"; set +e
    output="$(bash "$VERIFY" snapshot --repo "$ROOT" 2>&1)"; code=$?; set -e
    [[ $code -eq 1 && "$output" == *"[CODEX_VERIFY_ERROR]"* ]]
}
case_missing_snapshot() {
    new_repo; set +e
    output="$(bash "$VERIFY" check --repo "$ROOT" --snapshot "$ROOT/missing.txt" 2>&1)"; code=$?; set -e
    [[ $code -eq 1 && "$output" == *"[CODEX_VERIFY_ERROR]"* ]]
}

printf '%s\n' '=== codex-verify bash tests ==='
test_case "snapshot then unchanged check" case_unchanged
test_case "ordinary tracked edit is allowed" case_tracked_edit
test_case "HEAD change is a violation" case_head_change
test_case "branch change is a violation" case_branch_change
test_case "protected .env modification is a violation" case_env_modified
test_case "allowed .env modification is informational" case_env_allowed
test_case "new protected .env is a violation" case_env_added
test_case "ordinary untracked file is allowed" case_untracked
test_case "snapshot outside git repository fails" case_not_repo
test_case "missing snapshot fails" case_missing_snapshot
printf 'Passed: %d / %d\n' "$passed" "$total"
[[ $passed -eq $total ]]
