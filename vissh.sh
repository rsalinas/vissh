#!/usr/bin/env bash

set -euo pipefail

EDITOR="${EDITOR:-vim}"
SSH_DIR="${HOME}/.ssh"

# ---------------------------------------------------------------------------
# Git versioning helpers
# ---------------------------------------------------------------------------

_ssh_git_available() {
    [[ -d "${SSH_DIR}/.git" ]]
}

_check_ssh_git_warn() {
    if ! _ssh_git_available; then
        echo "Note: ${SSH_DIR} has no git repository. Run 'vissh git init' to enable versioning." >&2
    fi
}

_ssh_auto_commit() {
    local file="$1"
    local host="$2"

    _ssh_git_available || return 0

    local rel_file
    rel_file="$(realpath --relative-to="${SSH_DIR}" "$file")"

    git -C "${SSH_DIR}" add -- "$rel_file" 2>/dev/null || return 0

    # Nothing staged means file is not tracked (excluded by .gitignore, etc.)
    if git -C "${SSH_DIR}" diff --cached --quiet 2>/dev/null; then
        return 0
    fi

    local commit_msg="Edit host ${host} in ${rel_file}"
    if git -C "${SSH_DIR}" commit -m "$commit_msg" --quiet 2>/dev/null; then
        local sha
        sha=$(git -C "${SSH_DIR}" rev-parse --short HEAD)
        echo "Committed to ${SSH_DIR} git: [${sha}] ${commit_msg}"
    else
        echo "Warning: auto-commit failed (git user may not be configured). Run 'vissh git status'." >&2
    fi
}

# Detect git subcommands that can cause data loss.
_is_destructive_git() {
    local subcmd="$1"
    shift || true
    local args="${*:-}"

    case "$subcmd" in
        reset|clean|restore) return 0 ;;
        push)    [[ "$args" =~ (-f|--force) ]] && return 0 ;;
        checkout)[[ "$args" =~ -- ]]            && return 0 ;;
        branch)  [[ "$args" =~ (-D|-d) ]]       && return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# vissh git <subcommand>
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "git" ]]; then
    shift

    if [[ $# -eq 0 ]]; then
        echo "Usage: vissh git <subcommand> [args...]" >&2
        echo "" >&2
        echo "  vissh git init        Initialize a git repo in ${SSH_DIR}" >&2
        echo "  vissh git log         Show commit history" >&2
        echo "  vissh git diff        Show uncommitted changes" >&2
        echo "  vissh git status      Show repo status" >&2
        echo "  vissh git show <ref>  Inspect a specific commit" >&2
        exit 1
    fi

    if [[ "$1" == "init" ]]; then
        if _ssh_git_available; then
            echo "${SSH_DIR} is already a git repository."
            exit 0
        fi
        git -C "${SSH_DIR}" init
        if [[ ! -f "${SSH_DIR}/.gitignore" ]]; then
            cat > "${SSH_DIR}/.gitignore" << 'GITIGNORE'
# Exclude all files by default to avoid accidentally committing private keys
*
# Explicitly allow safe files
!.gitignore
!config
!*.pub
!known_hosts
!authorized_keys
GITIGNORE
            echo "Created ${SSH_DIR}/.gitignore (private keys are excluded from tracking)."
        fi
        echo "Git repository initialized in ${SSH_DIR}."
        echo "Tip: run 'vissh git add config && vissh git commit -m \"Initial commit\"' to start tracking."
        exit 0
    fi

    if _is_destructive_git "$@"; then
        echo "Warning: 'git $*' is a potentially destructive operation on ${SSH_DIR}." >&2
        printf "Continue? [y/N] "
        read -r _confirm
        [[ "$_confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
    fi

    git -C "${SSH_DIR}" "$@"
    exit $?
fi

# ---------------------------------------------------------------------------
# Main: find SSH config host and edit
# ---------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    echo "Usage: vissh <host> [--all]"
    echo "       vissh git <subcommand> [args...]"
    exit 1
fi

TARGET="$1"
SHOW_ALL="${2:-}"

declare -a visited=()
declare -a matches=()


expand_includes() {
    local file="$1"
    local base_dir

    [[ -f "$file" ]] || return

    for f in "${visited[@]:-}"; do
        [[ "$f" == "$file" ]] && return
    done

    visited+=("$file")

    echo "$file"

    base_dir="$(dirname "$file")"

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Include[[:space:]]+(.+) ]]; then
            includes="${BASH_REMATCH[1]}"

            for inc in $includes; do
                if [[ "$inc" != /* ]]; then
                    inc="$base_dir/$inc"
                fi

                for resolved in $inc; do
                    expand_includes "$resolved"
                done
            done
        fi
    done < "$file"
}

if [[ "$TARGET" == "--list-hosts" ]]; then
    while IFS= read -r file; do
        awk '
            tolower($1)=="host" {
                for(i=2;i<=NF;i++) print $i
            }
        ' "$file"
    done < <(expand_includes "$HOME/.ssh/config")
    exit 0
fi

pattern_matches() {
    local pattern="$1"
    case "$TARGET" in
        $pattern) return 0 ;;
        *) return 1 ;;
    esac
}

specificity_score() {
    local pattern="$1"
    echo "${#pattern}"
}

scan_file() {
    local file="$1"
    awk '
        BEGIN { lineno=0 }
        {
            lineno++
            if (tolower($1) == "host") {
                printf "%s:%d:%s\n", FILENAME, lineno, substr($0, index($0,$2))
            }
        }
    ' "$file"
}


while IFS= read -r file; do
    while IFS=: read -r fname line patterns; do
        for p in $patterns; do
            if pattern_matches "$p"; then
                score=$(specificity_score "$p")
                matches+=("$score:$fname:$line:$p")
            fi
        done
    done < <(scan_file "$file")
done < <(expand_includes "$HOME/.ssh/config")


if [[ ${#matches[@]} -eq 0 ]]; then
    echo "Host '$TARGET' not found"
    exit 1
fi


IFS=$'\n' sorted=($(sort -nr <<<"${matches[*]}"))
unset IFS


if [[ "$SHOW_ALL" == "--all" ]]; then
    for m in "${sorted[@]}"; do
        echo "$m"
    done
    exit 0
fi


best="${sorted[0]}"
IFS=: read -r score file line pattern <<<"$best"

# ---------------------------------------------------------------------------
# SSH config syntax validation
# For the main config file, use -F to avoid touching real files.
# For included files, temporarily swap them in place to let ssh parse the
# full config chain, then immediately restore the original.
# ---------------------------------------------------------------------------

_validate_ssh_config() {
    local tmpfile="$1"
    local real_file="$2"

    if ! command -v ssh > /dev/null 2>&1; then
        echo "Validation skipped: ssh not found in PATH." >&2
        return 0
    fi

    local cmd output rc=0

    if [[ "$real_file" == "${HOME}/.ssh/config" ]]; then
        cmd="ssh -G \"*\" -F \"${tmpfile}\""
        echo "Validating: ${cmd}" >&2
        output=$(ssh -G "*" -F "$tmpfile" 2>&1) || rc=$?
    else
        local _bak
        _bak=$(mktemp)
        cp "$real_file" "$_bak"
        cp "$tmpfile" "$real_file"
        cmd="ssh -G \"*\"  [${real_file} temporarily swapped with temp copy]"
        echo "Validating: ${cmd}" >&2
        output=$(ssh -G "*" 2>&1) || rc=$?
        cp "$_bak" "$real_file"
        rm -f "$_bak"
    fi

    echo "Exit code: ${rc}" >&2
    if [[ -n "$output" ]]; then
        echo "Output:" >&2
        echo "$output" >&2
    fi

    # Some OpenSSH versions exit 0 even on bad options but print to stderr.
    # Patterns sourced from OpenSSH readconf.c error messages.
    local error_in_output=0
    echo "$output" | grep -qiE "bad configuration option|no argument after keyword|unknown configuration option|unsupported option|parse error|bad.*option|terminating.*bad configuration" && error_in_output=1

    if [[ $rc -ne 0 ]] || [[ $error_in_output -eq 1 ]]; then
        echo "SSH config validation FAILED." >&2
        return 1
    fi
    echo "SSH config validation OK." >&2
    return 0
}

# ---------------------------------------------------------------------------
# Edit via temp file: open editor → validate → show diff → confirm → apply
# ---------------------------------------------------------------------------

_check_ssh_git_warn

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

cp "$file" "$tmpfile"

while true; do
    "$EDITOR" "+$line" "$tmpfile"

    if diff -q "$file" "$tmpfile" > /dev/null 2>&1; then
        echo "No changes made."
        exit 0
    fi

    if _validate_ssh_config "$tmpfile" "$file"; then
        break
    fi

    printf "Re-edit to fix the error? [Y/n] "
    read -r _confirm
    [[ "$_confirm" =~ ^[Nn]$ ]] && { echo "Aborted. No changes applied."; exit 1; }
done

echo ""
diff --color=always -u "$file" "$tmpfile" || true
echo ""
printf "Apply changes to %s? [y/N] " "$file"
read -r _confirm

if [[ "$_confirm" =~ ^[Yy]$ ]]; then
    cp "$tmpfile" "$file"
    echo "Changes applied."
    _ssh_auto_commit "$file" "$TARGET"
else
    echo "Aborted. No changes applied."
fi
