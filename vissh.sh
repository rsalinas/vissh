#!/usr/bin/env bash

set -euo pipefail

EDITOR="${EDITOR:-vim}"

if [[ $# -lt 1 ]]; then
    echo "Usage: vissh <host> [--all]"
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

    # més llarg = més específic
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
    echo "Host '$TARGET' no trobat"
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

exec "$EDITOR" "+$line" "$file"
