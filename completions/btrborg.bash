# Bash completion for btrborg.

_btrborg() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD - 1]}
    local commands="list init create info check prune compact run"
    local options="-c --config -n --dry-run -v --verbose -h --help -V --version"
    local i have_command=0

    case $prev in
        -c | --config)
            compopt -o filenames 2> /dev/null
            mapfile -t COMPREPLY < <(compgen -f -- "$cur")
            return
            ;;
    esac

    if [[ $cur == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$options" -- "$cur")
        return
    fi

    for ((i = 1; i < COMP_CWORD; i++)); do
        case ${COMP_WORDS[i]} in
            list | init | create | info | check | prune | compact | run) have_command=1 ;;
        esac
    done

    if ((have_command)); then
        # Subvolume names; listing them needs access to the btrfs volume, so
        # this may legitimately produce nothing for unprivileged users.
        mapfile -t COMPREPLY < <(compgen -W "$(btrborg list 2> /dev/null | cut -f1)" -- "$cur")
    else
        mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
    fi
}

complete -F _btrborg btrborg
