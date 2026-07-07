#!/usr/bin/env bash
# codex-verify.sh - Snapshot and verify repository safety invariants.
# Symlinks are recorded by link target; changes behind the target are not tracked.
set -euo pipefail

ERROR="[CODEX_VERIFY_ERROR]"
VIOLATION="[CODEX_VERIFY_VIOLATION]"
ALLOWED="[CODEX_VERIFY_ALLOWED]"

die() {
    printf '%s %s\n' "$ERROR" "$*" >&2
    exit 1
}

b64_encode() { printf '%s' "$1" | base64 | tr -d '\r\n'; }
b64_decode() { printf '%s' "$1" | base64 --decode; }

hash_file() {
    local value
    if [[ -L "$1" ]]; then
        value="$(readlink "$1")" || return 1
        printf 'symlink:%s' "$value"
    elif command -v sha256sum >/dev/null 2>&1; then
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
requested_repo="$(cd "$repo_path" && pwd -P)" || die "Unable to resolve repository path."
repo_path="$(git -C "$requested_repo" rev-parse --show-toplevel 2>/dev/null)" ||
    die "Not a git repository: $requested_repo"
repo_path="$(cd "$repo_path" && pwd -P)" || die "Unable to resolve repository root."
if [[ "$requested_repo" != "$repo_path" ]]; then
    printf 'Note: repo normalized to %s\n' "$repo_path" >&2
fi

git_in_repo() { git -C "$repo_path" "$@"; }
config_path="$(git_in_repo rev-parse --path-format=absolute --git-path config 2>/dev/null)" ||
    die "Unable to resolve git config path."
hooks_path="$(git_in_repo rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" ||
    die "Unable to resolve git hooks path."

canonical_candidate() {
    local path="$1" parent
    parent="$(dirname "$path")"
    [[ -d "$parent" ]] || die "Snapshot parent directory not found: $parent"
    parent="$(cd "$parent" && pwd -P)" || die "Unable to resolve snapshot path."
    printf '%s/%s' "$parent" "$(basename "$path")"
}

validate_snapshot_path() {
    local path="$1" full
    full="$(canonical_candidate "$path")"
    if [[ "$full" == "$repo_path" || "$full" == "$repo_path/"* ]]; then
        die "snapshot file must be outside the repository"
    fi
    [[ ! -L "$path" ]] || die "Snapshot file must not be a symlink."
    printf '%s' "$full"
}

relative_path() {
    local path="$1"
    if [[ "$path" == "$config_path" ]]; then
        printf '.git/config'
    elif [[ "$path" == "$hooks_path/"* ]]; then
        printf '.git/hooks/%s' "${path#"$hooks_path/"}"
    else
        printf '%s' "${path#"$repo_path/"}"
    fi
}

enumerate_protected() {
    local output="$1" file
    : >"$output" || return 1
    find "$repo_path" -maxdepth 1 -mindepth 1 \( -type f -o -type l \) \
        \( -name '.env' -o -name '.env.*' \) ! -name '.env.\*' \
        -print0 >>"$output" || return 1
    find "$repo_path" -path "$repo_path/.git" -prune -o \
        \( -type f -o -type l \) \
        \( -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \) \
        -print0 >>"$output" || return 1
    if [[ -e "$config_path" || -L "$config_path" ]]; then
        printf '%s\0' "$config_path" >>"$output"
    fi
    if [[ -d "$hooks_path" ]]; then
        find "$hooks_path" -maxdepth 1 \( -type f -o -type l \) ! -name '*.sample' \
            -print0 >>"$output" || return 1
    fi
}

tmp_listing="$(mktemp "${TMPDIR:-/tmp}/codex_verify_files.XXXXXX")" ||
    die "Unable to create temporary file."
trap 'rm -f "$tmp_listing"' EXIT

if [[ "$command_name" == "snapshot" ]]; then
    [[ -z "$snapshot_file" ]] || die "--snapshot is only valid with check."
    if [[ -z "$out_file" ]]; then
        out_file="$(mktemp -u "${TMPDIR:-/tmp}/codex_verify_snap_$(date +%Y%m%d-%H%M%S).XXXXXX")"
    fi
    full_out="$(validate_snapshot_path "$out_file")"
    [[ ! -e "$full_out" ]] || die "Snapshot file already exists: $full_out"
    enumerate_protected "$tmp_listing" || die "Unable to enumerate protected files."
    head_value="$(git_in_repo rev-parse HEAD 2>/dev/null)" || die "Unable to read HEAD."
    branch_value="$(git_in_repo branch --show-current 2>/dev/null)" || die "Unable to read branch."
    status_value="$(git_in_repo status --porcelain=v1 --untracked-files=all 2>/dev/null)" ||
        die "Unable to read git status."
    set -o noclobber
    {
        printf 'format=1\n'
        printf 'head=%s\n' "$head_value"
        printf 'branch=%s\n' "$(b64_encode "$branch_value")"
        printf 'status=%s\n' "$(b64_encode "$status_value")"
        while IFS= read -r -d '' file; do
            rel="$(relative_path "$file")"
            digest="$(hash_file "$file")" || die "Unable to hash protected file: $rel"
            printf 'protected=%s:%s\n' "$(b64_encode "$rel")" "$digest"
        done <"$tmp_listing"
    } >"$full_out" || die "Unable to write snapshot: $full_out"
    set +o noclobber
    printf 'SNAPSHOT: %s\n' "$full_out"
    exit 0
fi

[[ -z "$out_file" ]] || die "--out is only valid with snapshot."
[[ -n "$snapshot_file" ]] || die "check requires --snapshot."
full_snapshot="$(validate_snapshot_path "$snapshot_file")"
[[ -f "$full_snapshot" && -r "$full_snapshot" ]] ||
    die "Snapshot file is not readable: $full_snapshot"

old_head=""
old_branch_b64=""
format_count=0
head_count=0
branch_count=0
declare -A old_hashes=()
while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
        format=*) format_count=$((format_count + 1)); [[ "$line" == "format=1" ]] ||
            die "Invalid snapshot format." ;;
        head=*) head_count=$((head_count + 1)); old_head="${line#head=}" ;;
        branch=*) branch_count=$((branch_count + 1)); old_branch_b64="${line#branch=}" ;;
        protected=*)
            entry="${line#protected=}"
            [[ "$entry" == *:* ]] || die "Invalid protected entry in snapshot."
            encoded="${entry%%:*}"
            digest="${entry#*:}"
            [[ "$digest" =~ ^[[:xdigit:]]{64}$ || "$digest" == symlink:* ]] ||
                die "Invalid protected hash in snapshot."
            path="$(b64_decode "$encoded" 2>/dev/null)" || die "Invalid snapshot protected path."
            [[ -n "$path" ]] || die "Invalid snapshot protected path."
            [[ ! -v "old_hashes[$path]" ]] || die "Duplicate protected path in snapshot."
            old_hashes["$path"]="$digest"
            ;;
    esac
done <"$full_snapshot" || die "Unable to read snapshot file."
[[ $format_count -eq 1 && $head_count -eq 1 && $branch_count -eq 1 && -n "$old_head" ]] ||
    die "Invalid snapshot file: $full_snapshot"
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

enumerate_protected "$tmp_listing" || die "Unable to enumerate protected files."
declare -A current_hashes=()
while IFS= read -r -d '' file; do
    rel="$(relative_path "$file")"
    digest="$(hash_file "$file")" || die "Unable to hash protected file: $rel"
    current_hashes["$rel"]="$digest"
done <"$tmp_listing"

for path in "${!old_hashes[@]}"; do
    if [[ ! -v "current_hashes[$path]" ]]; then action="deleted"
    elif [[ "${old_hashes[$path]}" != "${current_hashes[$path]}" ]]; then action="modified"
    else continue
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
