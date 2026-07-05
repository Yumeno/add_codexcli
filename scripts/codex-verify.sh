#!/usr/bin/env bash
# codex-verify.sh - Snapshot and verify repository safety invariants.
set -euo pipefail

ERROR="[CODEX_VERIFY_ERROR]"
VIOLATION="[CODEX_VERIFY_VIOLATION]"
ALLOWED="[CODEX_VERIFY_ALLOWED]"

die() {
    local message="$*"
    printf '%s %s\n' "$ERROR" "$message"
    printf '%s %s\n' "$ERROR" "$message" >&2
    exit 1
}

b64_encode() { printf '%s' "$1" | base64 | tr -d '\r\n'; }
b64_decode() { printf '%s' "$1" | base64 --decode; }

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

repo_path=""
out_file=""
snapshot_file=""
command_name=""
allows=()

[[ $# -gt 0 ]] || die "Expected snapshot or check."
command_name="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) [[ $# -ge 2 ]] || die "--repo requires a value."; repo_path="$2"; shift 2 ;;
        --out) [[ $# -ge 2 ]] || die "--out requires a value."; out_file="$2"; shift 2 ;;
        --snapshot) [[ $# -ge 2 ]] || die "--snapshot requires a value."; snapshot_file="$2"; shift 2 ;;
        --allow) [[ $# -ge 2 ]] || die "--allow requires a value."; allows+=("$2"); shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ "$command_name" == "snapshot" || "$command_name" == "check" ]] ||
    die "Unknown subcommand: $command_name"
[[ -n "$repo_path" ]] || repo_path="$PWD"
[[ -d "$repo_path" ]] || die "Repository directory not found: $repo_path"
repo_path="$(cd "$repo_path" && pwd)"

git_in_repo() { git -C "$repo_path" "$@"; }
git_in_repo rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "Not a git repository: $repo_path"

protected_files() {
    local file
    for file in "$repo_path"/.env "$repo_path"/.env.*; do
        [[ -f "$file" ]] && printf '%s\0' "$file"
    done
    while IFS= read -r -d '' file; do
        printf '%s\0' "$file"
    done < <(find "$repo_path" -path "$repo_path/.git" -prune -o -type f \
        \( -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \) -print0)
    if [[ -d "$repo_path/.git/hooks" ]]; then
        while IFS= read -r -d '' file; do
            [[ "$file" == *.sample ]] || printf '%s\0' "$file"
        done < <(find "$repo_path/.git/hooks" -maxdepth 1 -type f -perm -111 -print0)
    fi
}

relative_path() {
    local path="$1"
    if [[ "$path" == "$repo_path/.git/"* ]]; then
        printf '.git/%s' "${path#"$repo_path/.git/"}"
    else
        printf '%s' "${path#"$repo_path/"}"
    fi
}

if [[ "$command_name" == "snapshot" ]]; then
    [[ -z "$snapshot_file" ]] || die "--snapshot is only valid with check."
    if [[ -z "$out_file" ]]; then
        out_file="${TMPDIR:-/tmp}/codex_verify_snap_$(date +%Y%m%d-%H%M%S).txt"
    fi
    head_value="$(git_in_repo rev-parse HEAD 2>/dev/null)" ||
        die "Unable to read HEAD."
    branch_value="$(git_in_repo branch --show-current 2>/dev/null)" ||
        die "Unable to read branch."
    status_value="$(git_in_repo status --porcelain=v1 --untracked-files=all 2>/dev/null)" ||
        die "Unable to read git status."
    {
        printf 'format=1\n'
        printf 'head=%s\n' "$head_value"
        printf 'branch=%s\n' "$(b64_encode "$branch_value")"
        printf 'status=%s\n' "$(b64_encode "$status_value")"
        while IFS= read -r -d '' file; do
            rel="$(relative_path "$file")"
            printf 'protected=%s:%s\n' "$(b64_encode "$rel")" "$(hash_file "$file")"
        done < <(protected_files)
    } >"$out_file" || die "Unable to write snapshot: $out_file"
    out_file="$(cd "$(dirname "$out_file")" && pwd)/$(basename "$out_file")"
    printf 'SNAPSHOT: %s\n' "$out_file"
    exit 0
fi

[[ -z "$out_file" ]] || die "--out is only valid with snapshot."
[[ -n "$snapshot_file" ]] || die "check requires --snapshot."
[[ -r "$snapshot_file" ]] || die "Snapshot file is not readable: $snapshot_file"

old_head=""
old_branch_b64=""
declare -A old_hashes=()
while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
        head=*) old_head="${line#head=}" ;;
        branch=*) old_branch_b64="${line#branch=}" ;;
        protected=*)
            entry="${line#protected=}"
            encoded="${entry%%:*}"
            hash="${entry#*:}"
            path="$(b64_decode "$encoded" 2>/dev/null)" || die "Invalid snapshot protected path."
            old_hashes["$path"]="$hash"
            ;;
    esac
done <"$snapshot_file"
[[ -n "$old_head" && -n "$old_branch_b64" ]] || die "Invalid snapshot file: $snapshot_file"
old_branch="$(b64_decode "$old_branch_b64" 2>/dev/null)" || die "Invalid snapshot branch."

current_head="$(git_in_repo rev-parse HEAD 2>/dev/null)" || die "Unable to read HEAD."
current_branch="$(git_in_repo branch --show-current 2>/dev/null)" || die "Unable to read branch."
violations=0
if [[ "$old_head" != "$current_head" ]]; then
    printf '%s HEAD changed: %s -> %s\n' "$VIOLATION" "$old_head" "$current_head"
    violations=1
fi
if [[ "$old_branch" != "$current_branch" ]]; then
    printf '%s branch changed: %s -> %s\n' "$VIOLATION" "$old_branch" "$current_branch"
    violations=1
fi

is_allowed() {
    local path="$1" pattern
    for pattern in "${allows[@]}"; do
        [[ "$path" == $pattern ]] && return 0
    done
    return 1
}

declare -A current_hashes=()
while IFS= read -r -d '' file; do
    rel="$(relative_path "$file")"
    current_hashes["$rel"]="$(hash_file "$file")"
done < <(protected_files)

for path in "${!old_hashes[@]}"; do
    if [[ ! -v "current_hashes[$path]" ]]; then
        action="deleted"
    elif [[ "${old_hashes[$path]}" != "${current_hashes[$path]}" ]]; then
        action="modified"
    else
        continue
    fi
    if is_allowed "$path"; then
        printf '%s protected file %s (allowed): %s\n' "$ALLOWED" "$action" "$path"
    else
        printf '%s protected file %s: %s\n' "$VIOLATION" "$action" "$path"
        violations=1
    fi
done
for path in "${!current_hashes[@]}"; do
    [[ -v "old_hashes[$path]" ]] && continue
    if is_allowed "$path"; then
        printf '%s protected file added (allowed): %s\n' "$ALLOWED" "$path"
    else
        printf '%s protected file added: %s\n' "$VIOLATION" "$path"
        violations=1
    fi
done

printf '%s\n' '--- git status --porcelain=v1 --untracked-files=all ---'
git_in_repo status --porcelain=v1 --untracked-files=all || die "Unable to read git status."
printf '%s\n' '--- git diff HEAD --stat ---'
git_in_repo diff HEAD --stat || die "Unable to read git diff."
[[ "$violations" -eq 0 ]] || exit 2
exit 0
