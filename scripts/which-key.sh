#!/usr/bin/env bash
# tmux-which-key - LazyVim-style which-key popup for tmux
# Usage: which-key.sh [--config <path>] [--client <target-client>] <pane_id>

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE=""
PANE_ID=""
CLIENT_ID=""
SESSION_ID=""
WINDOW_ID=""
VERSION_INFO=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --client)
            CLIENT_ID="$2"
            shift 2
            ;;
        *)
            PANE_ID="$1"
            shift
            ;;
    esac
done

# Resolve config file: explicit > XDG > user home > plugin default
if [[ -z "$CONFIG_FILE" ]]; then
    local_xdg="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-which-key/config.json"
    local_home="$HOME/.tmux-which-key.json"
    if [[ -f "$local_xdg" ]]; then
        CONFIG_FILE="$local_xdg"
    elif [[ -f "$local_home" ]]; then
        CONFIG_FILE="$local_home"
    else
        CONFIG_FILE="$PLUGIN_DIR/configs/default.json"
    fi
fi

# Nord theme colors
C_KEY=$'\033[38;2;235;203;139m'       # #EBCB8B - yellow
C_GRP=$'\033[38;2;136;192;208m'       # #88C0D0 - cyan
C_DESC=$'\033[38;2;216;222;233m'      # #D8DEE9 - light gray
C_SEP=$'\033[38;2;76;86;106m'         # #4C566A - dark gray
C_HDR=$'\033[38;2;129;161;193m'       # #81A1C1 - blue
C_R=$'\033[0m'

if [[ -z "$PANE_ID" ]]; then
    echo "Usage: which-key.sh [--config <path>] [--client <target-client>] <pane_id>"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

# Read entire config into memory once
CONFIG=$(cat "$CONFIG_FILE")

# Resolve the originating tmux context once. Commands may run after this popup
# exits, so implicit tmux targets are not reliable.
SESSION_ID=$(tmux display-message -t "$PANE_ID" -p '#{session_id}')
WINDOW_ID=$(tmux display-message -t "$PANE_ID" -p '#{window_id}')
if [[ -z "$CLIENT_ID" ]]; then
    CLIENT_ID=$(tmux display-message -p '#{client_tty}' 2>/dev/null || true)
fi

get_version_info() {
    local tag commit

    tag=$(git -C "$PLUGIN_DIR" describe --tags --abbrev=0 2>/dev/null || true)
    commit=$(git -C "$PLUGIN_DIR" rev-parse --short HEAD 2>/dev/null || true)

    [[ -n "$tag" ]] || tag="none"
    [[ -n "$commit" ]] || commit="unknown"

    printf "tag %s | commit %s" "$tag" "$commit"
}

VERSION_INFO=$(get_version_info)

# Navigation stack (jq path indices)
NAV_STACK=()

shell_quote() {
    printf "%q" "$1"
}

expand_tmux_formats() {
    local command="$1"
    local token="__TMUX_WHICH_KEY_PERCENT_PLACEHOLDER__"
    command="${command//%%/$token}"
    command=$(tmux display-message -t "$PANE_ID" -p "$command")
    command="${command//$token/%%}"
    printf "%s" "$command"
}

with_tmux_target() {
    local command="$1"
    local flag="$2"
    local target="$3"
    local name rest

    if [[ -z "$target" ]]; then
        printf "%s" "$command"
        return
    fi

    name="${command%%[[:space:]]*}"
    if [[ "$name" == "$command" ]]; then
        rest=""
    else
        rest="${command#"$name"}"
    fi

    printf "%s %s %s%s" "$name" "$flag" "$(shell_quote "$target")" "$rest"
}

exec_tmux() {
    local command="$1"
    eval "tmux $command"
}

run_tmux_command() {
    local command="$1"
    local expanded name targeted

    expanded=$(expand_tmux_formats "$command")
    name="${expanded%%[[:space:]]*}"

    case "$name" in
        command-prompt|confirm-before)
            targeted=$(with_tmux_target "$expanded" "-t" "$CLIENT_ID")
            tmux run-shell -b "sleep 0.1 && tmux $targeted"
            ;;
        display-panes)
            targeted=$(with_tmux_target "$expanded" "-t" "$CLIENT_ID")
            tmux run-shell -b "sleep 0.1 && tmux $targeted"
            ;;
        choose-tree|choose-buffer|choose-client|customize-mode|copy-mode)
            targeted=$(with_tmux_target "$expanded" "-t" "$PANE_ID")
            tmux run-shell -b "sleep 0.1 && tmux $targeted"
            ;;
        split-window|select-pane|resize-pane|kill-pane|join-pane|selectp|resizep|killp|joinp|swap-pane|swapp|clear-history|clearhist|capture-pane|capturep|respawn-pane|respawnp|paste-buffer|pasteb|clock-mode|clock)
            targeted=$(with_tmux_target "$expanded" "-t" "$PANE_ID")
            exec_tmux "$targeted"
            ;;
        break-pane|breakp)
            targeted=$(with_tmux_target "$expanded" "-s" "$PANE_ID")
            exec_tmux "$targeted"
            ;;
        new-window|neww|kill-window|killw|rename-window|renamew|move-window|movew|swap-window|swapw|rotate-window|rotatew|next-layout|nextl|previous-layout|prevl|select-layout|selectl|last-pane|lastp)
            targeted=$(with_tmux_target "$expanded" "-t" "$WINDOW_ID")
            exec_tmux "$targeted"
            ;;
        last-window|last|next-window|next|previous-window|prev)
            targeted=$(with_tmux_target "$expanded" "-t" "$SESSION_ID")
            exec_tmux "$targeted"
            ;;
        show-options|show)
            if [[ "$expanded" == *" -g"* ]]; then
                exec_tmux "$expanded"
            else
                targeted=$(with_tmux_target "$expanded" "-t" "$PANE_ID")
                exec_tmux "$targeted"
            fi
            ;;
        show-window-options|showw)
            if [[ "$expanded" == *" -g"* ]]; then
                exec_tmux "$expanded"
            else
                targeted=$(with_tmux_target "$expanded" "-t" "$WINDOW_ID")
                exec_tmux "$targeted"
            fi
            ;;
        rename-session|rename|kill-session|lock-session|lock-server)
            targeted=$(with_tmux_target "$expanded" "-t" "$SESSION_ID")
            exec_tmux "$targeted"
            ;;
        switch-client|switchc)
            targeted=$(with_tmux_target "$expanded" "-c" "$CLIENT_ID")
            exec_tmux "$targeted"
            ;;
        detach-client|detach|refresh-client|refresh|suspend-client|suspendc|lock-client|lockc)
            targeted=$(with_tmux_target "$expanded" "-t" "$CLIENT_ID")
            exec_tmux "$targeted"
            ;;
        load-buffer|loadb|show-messages|showmsgs)
            targeted=$(with_tmux_target "$expanded" "-t" "$CLIENT_ID")
            exec_tmux "$targeted"
            ;;
        *)
            exec_tmux "$expanded"
            ;;
    esac
}

# Get current items as tab-separated lines: key\ttype\tdescription\tcommand\timmediate
# Single jq call per menu level instead of per-item
get_current_items() {
    local path=".items"
    for idx in "${NAV_STACK[@]}"; do
        path="${path}[${idx}].items"
    done
    echo "$CONFIG" | jq -r "${path}[] | [.key, .type, .description, (.command // \"\"), (if .immediate then \"true\" else \"false\" end)] | @tsv" 2>/dev/null
}

get_breadcrumb() {
    local path=".items"
    local parts=("root")
    for idx in "${NAV_STACK[@]}"; do
        parts+=("$(echo "$CONFIG" | jq -r "${path}[${idx}].description")")
        path="${path}[${idx}].items"
    done
    local IFS=" > "
    echo "${parts[*]}"
}

render_menu() {
    clear

    local breadcrumb
    breadcrumb=$(get_breadcrumb)

    # Header
    printf "%s  Which Key%s  %s│%s  %s%s%s  %s│%s  %s%s%s\n" "$C_HDR" "$C_R" "$C_SEP" "$C_R" "$C_DESC" "$breadcrumb" "$C_R" "$C_SEP" "$C_R" "$C_SEP" "$VERSION_INFO" "$C_R"
    printf "%s" "$C_SEP"
    printf '%.0s─' {1..98}
    printf "%s\n" "$C_R"

    # Parse all items in one jq call
    local keys=() types=() descs=()
    while IFS=$'\t' read -r key type desc _cmd; do
        keys+=("$key")
        types+=("$type")
        descs+=("$desc")
    done < <(get_current_items)

    local total=${#keys[@]}
    if [[ $total -eq 0 ]]; then
        printf "  %s(empty)%s\n" "$C_DESC" "$C_R"
        return
    fi

    # Column layout
    local col_width=32
    local num_cols=3
    local num_rows=$(( (total + num_cols - 1) / num_cols ))

    for ((row = 0; row < num_rows; row++)); do
        printf "  "
        for ((col = 0; col < num_cols; col++)); do
            local i=$((col * num_rows + row))
            if [[ $i -lt $total ]]; then
                local k="${keys[$i]}" t="${types[$i]}" d="${descs[$i]}"
                local prefix="" dc="$C_DESC"
                if [[ "$t" == "group" ]]; then
                    prefix="+"
                    dc="$C_GRP"
                fi
                local visible_len=$(( ${#k} + 4 + ${#prefix} + ${#d} ))
                local pad=$((col_width - visible_len))
                [[ $pad -lt 1 ]] && pad=1
                printf "%s%s%s  %s→%s %s%s%s%s" "$C_KEY" "$k" "$C_R" "$C_SEP" "$C_R" "$dc" "$prefix" "$d" "$C_R"
                printf '%*s' "$pad" ""
            fi
        done
        printf "\n"
    done

    # Footer
    printf "\n%s" "$C_SEP"
    printf '%.0s─' {1..98}
    printf "%s\n" "$C_R"
    if [[ ${#NAV_STACK[@]} -gt 0 ]]; then
        printf "  %sesc  close    ⌫  back%s\n" "$C_SEP" "$C_R"
    else
        printf "  %sesc  close%s\n" "$C_SEP" "$C_R"
    fi
}

handle_key() {
    local keypress="$1"
    local i=0

    while IFS=$'\t' read -r key type desc command immediate; do
        if [[ "$key" == "$keypress" ]]; then
            case "$type" in
                group)
                    NAV_STACK+=("$i")
                    return 0
                    ;;
                action)
                    tmux send-keys -t "$PANE_ID" -l "$command"
                    if [[ "$immediate" == "true" ]]; then
                        tmux send-keys -t "$PANE_ID" Enter
                    fi
                    exit 0
                    ;;
                popup)
                    local pane_path
                    local popup_target_args
                    pane_path=$(tmux display-message -t "$PANE_ID" -p '#{pane_current_path}')
                    popup_target_args="-t $(shell_quote "$PANE_ID")"
                    if [[ -n "$CLIENT_ID" ]]; then
                        popup_target_args="-c $(shell_quote "$CLIENT_ID") $popup_target_args"
                    fi
                    tmux run-shell -b "sleep 0.1 && tmux display-popup -E -h 80% -w 80% $popup_target_args -d $(shell_quote "$pane_path") $(shell_quote "$command")"
                    exit 0
                    ;;
                tmux)
                    run_tmux_command "$command"
                    exit 0
                    ;;
                script)
                    tmux run-shell "$command"
                    exit 0
                    ;;
            esac
        fi
        ((i++))
    done < <(get_current_items)
}

# Main loop
while true; do
    render_menu

    IFS= read -rsn1 keypress

    # Escape
    if [[ "$keypress" == $'\x1b' ]]; then
        read -rsn1 -t 0.1 seq1 || true
        if [[ -z "$seq1" ]]; then
            if [[ ${#NAV_STACK[@]} -gt 0 ]]; then
                unset 'NAV_STACK[${#NAV_STACK[@]}-1]'
            else
                exit 0
            fi
        fi
        continue
    fi

    # Backspace
    if [[ "$keypress" == $'\x7f' || "$keypress" == $'\x08' ]]; then
        if [[ ${#NAV_STACK[@]} -gt 0 ]]; then
            unset 'NAV_STACK[${#NAV_STACK[@]}-1]'
        else
            exit 0
        fi
        continue
    fi

    # Regular key
    if [[ -n "$keypress" ]]; then
        handle_key "$keypress"
    fi
done
