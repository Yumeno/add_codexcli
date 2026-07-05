#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="$SCRIPT_DIR/../codex-verify.sh"
ROOT="${TMPDIR:-/tmp}/codex_verify_test_$$"
total=0
passed=0

SNAPSHOT_FILE="$ROOT.snapshot.txt"
LINK_PATH="$ROOT-link"
cleanup() {
    rm -rf "$ROOT"
    rm -f "$SNAPSHOT_FILE" "$LINK_PATH" 2>/dev/null || true
    rmdir "$LINK_PATH" 2>/dev/null || true
}
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
    rm -f "$SNAPSHOT_FILE" "$LINK_PATH" 2>/dev/null || true
    rmdir "$LINK_PATH" 2>/dev/null || true
    mkdir -p "$ROOT"
    git -C "$ROOT" init -q
    git -C "$ROOT" config user.email test@example.com
    git -C "$ROOT" config user.name Test
    printf 'initial\n' >"$ROOT/tracked.txt"
    git -C "$ROOT" add tracked.txt
    git -C "$ROOT" commit -qm initial
}

snapshot() {
    bash "$VERIFY" snapshot --repo "$ROOT" --out "$SNAPSHOT_FILE" >/dev/null
}

run_check() {
    set +e
    CHECK_OUTPUT="$(bash "$VERIFY" check --repo "$ROOT" --snapshot "$SNAPSHOT_FILE" "$@" 2>&1)"
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
case_env_suffix_modified() {
    new_repo; printf 'A=1\n' >"$ROOT/.env.foo"; snapshot
    printf 'A=2\n' >"$ROOT/.env.foo"; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file modified: .env.foo"* ]]
}
case_literal_env_glob_ignored() {
    new_repo; printf 'A=1\n' >"$ROOT/.env.*"; snapshot
    printf 'A=2\n' >"$ROOT/.env.*"; run_check
    [[ $CHECK_CODE -eq 0 && "$CHECK_OUTPUT" != *"protected file modified: .env.*"* ]]
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
case_git_config_modified() {
    new_repo; snapshot; git -C "$ROOT" config verify.test changed; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file modified: .git/config"* ]]
}
case_hook_added() {
    new_repo; snapshot; printf 'echo hook\n' >"$ROOT/.git/hooks/pre-commit"; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file added: .git/hooks/pre-commit"* ]]
}
case_subdir_normalized() {
    new_repo; mkdir "$ROOT/sub"; printf 'A=1\n' >"$ROOT/.env"
    bash "$VERIFY" snapshot --repo "$ROOT/sub" --out "$SNAPSHOT_FILE" >/dev/null 2>&1
    printf 'A=2\n' >"$ROOT/.env"; set +e
    output="$(bash "$VERIFY" check --repo "$ROOT/sub" --snapshot "$SNAPSHOT_FILE" 2>&1)"; code=$?; set -e
    [[ $code -eq 2 && "$output" == *"Note: repo normalized to"* &&
        "$output" == *"protected file modified: .env"* ]]
}
case_env_deleted() {
    new_repo; printf 'A=1\n' >"$ROOT/.env"; snapshot; rm "$ROOT/.env"; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file deleted: .env"* ]]
}
case_snapshot_tampered() {
    new_repo; printf 'A=1\n' >"$ROOT/.env"; snapshot
    sed -i 's/:[0-9a-f]\{64\}$/:bad/' "$SNAPSHOT_FILE"
    run_check
    [[ $CHECK_CODE -eq 1 && "$CHECK_OUTPUT" == *"[CODEX_VERIFY_ERROR]"* ]]
}
case_empty_protected_path() {
    new_repo; printf 'A=1\n' >"$ROOT/.env"; snapshot
    sed -i 's/^protected=[^:]*:/protected=:/' "$SNAPSHOT_FILE"
    run_check
    [[ $CHECK_CODE -eq 1 &&
        "$CHECK_OUTPUT" == "[CODEX_VERIFY_ERROR] Invalid snapshot protected path."* ]]
}
case_invalid_base64_protected_path() {
    new_repo; printf 'A=1\n' >"$ROOT/.env"; snapshot
    sed -i 's/^protected=[^:]*:/protected=!:/' "$SNAPSHOT_FILE"
    run_check
    [[ $CHECK_CODE -eq 1 && "$CHECK_OUTPUT" == "[CODEX_VERIFY_ERROR]"* ]]
}
case_detached_head() {
    new_repo; git -C "$ROOT" checkout -q --detach HEAD; snapshot; run_check
    [[ $CHECK_CODE -eq 0 && "$CHECK_OUTPUT" != *"[CODEX_VERIFY_VIOLATION]"* ]]
}
case_allow_case_sensitive() {
    new_repo; printf 'A=1\n' >"$ROOT/.env"; snapshot
    printf 'A=2\n' >"$ROOT/.env"; run_check --allow .ENV
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file modified: .env"* ]]
}
case_snapshot_inside_repo() {
    new_repo; set +e
    output="$(bash "$VERIFY" snapshot --repo "$ROOT" --out "$ROOT/inside.txt" 2>&1)"; code=$?; set -e
    [[ $code -eq 1 && "$output" == *"[CODEX_VERIFY_ERROR] snapshot file must be outside the repository"* ]]
}
case_missing_snapshot_parent() {
    new_repo
    missing_parent="${TMPDIR:-/tmp}/codex_verify_missing_$RANDOM"
    set +e
    output="$(bash "$VERIFY" snapshot --repo "$ROOT" --out "$missing_parent/snapshot.txt" 2>&1)"
    code=$?
    set -e
    [[ $code -eq 1 &&
        "$output" == "[CODEX_VERIFY_ERROR] Snapshot parent directory not found:"* ]]
}
case_snapshot_symlink_parent_into_repo() {
    new_repo
    ln -s "$ROOT" "$LINK_PATH" 2>/dev/null || true
    if [[ ! -L "$LINK_PATH" ]]; then
        printf '%s\n' "SKIP: symlinks are not available"
        return 0
    fi
    set +e
    output="$(bash "$VERIFY" snapshot --repo "$ROOT" --out "$LINK_PATH/snapshot.txt" 2>&1)"
    code=$?
    set -e
    [[ $code -eq 1 &&
        "$output" == "[CODEX_VERIFY_ERROR] snapshot file must be outside the repository"* ]]
}
case_symlink_target_changed() {
    new_repo; printf 'one\n' >"$ROOT/target-one"; printf 'two\n' >"$ROOT/target-two"
    ln -s target-one "$ROOT/.env" 2>/dev/null || true
    if [[ ! -L "$ROOT/.env" ]]; then
        printf '%s\n' "SKIP: symlinks are not available"
        return 0
    fi
    snapshot; rm "$ROOT/.env"; ln -s target-two "$ROOT/.env"; run_check
    [[ $CHECK_CODE -eq 2 && "$CHECK_OUTPUT" == *"protected file modified: .env"* ]]
}

printf '%s\n' '=== codex-verify bash tests ==='
test_case "snapshot then unchanged check" case_unchanged
test_case "ordinary tracked edit is allowed" case_tracked_edit
test_case "HEAD change is a violation" case_head_change
test_case "branch change is a violation" case_branch_change
test_case "protected .env modification is a violation" case_env_modified
test_case "allowed .env modification is informational" case_env_allowed
test_case "new protected .env is a violation" case_env_added
test_case "protected .env suffix modification is a violation" case_env_suffix_modified
test_case "literal .env glob name is ignored" case_literal_env_glob_ignored
test_case "ordinary untracked file is allowed" case_untracked
test_case "snapshot outside git repository fails" case_not_repo
test_case "missing snapshot fails" case_missing_snapshot
test_case "git config modification is a violation" case_git_config_modified
test_case "non-sample hook addition is a violation" case_hook_added
test_case "subdirectory repo is normalized" case_subdir_normalized
test_case "protected .env deletion is a violation" case_env_deleted
test_case "invalid protected hash fails" case_snapshot_tampered
test_case "empty protected path fails" case_empty_protected_path
test_case "invalid base64 protected path fails" case_invalid_base64_protected_path
test_case "detached HEAD is supported" case_detached_head
test_case "allow matching is case-sensitive" case_allow_case_sensitive
test_case "snapshot inside repository fails" case_snapshot_inside_repo
test_case "missing snapshot parent fails clearly" case_missing_snapshot_parent
test_case "snapshot through symlink into repository fails" case_snapshot_symlink_parent_into_repo
test_case "symlink target change is a violation" case_symlink_target_changed
printf 'Passed: %d / %d\n' "$passed" "$total"
[[ $passed -eq $total ]]
