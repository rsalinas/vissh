_vissh() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$COMP_CWORD" in
        1)
            local hosts
            hosts=$(vissh --list-hosts 2>/dev/null)
            COMPREPLY=($(compgen -W "git $hosts" -- "$cur"))
            ;;
        2)
            if [[ "${COMP_WORDS[1]}" == "git" ]]; then
                COMPREPLY=($(compgen -W "init log diff status show blame add commit reset restore clean push fetch" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "--all" -- "$cur"))
            fi
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}

complete -F _vissh vissh
