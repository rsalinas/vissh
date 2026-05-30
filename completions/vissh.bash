_vissh() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    case "$COMP_CWORD" in
        1)
            local hosts
            hosts=$(vissh --list-hosts 2>/dev/null)
            COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
            ;;
        2)
            COMPREPLY=($(compgen -W "--all" -- "$cur"))
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}

complete -F _vissh vissh
