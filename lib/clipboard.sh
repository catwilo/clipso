#!/usr/bin/env bash
# clipboard.sh -- environment detection and clipboard backends
# envs: termux | wayland | x11 | pbcopy | osc52
# sets CLIP_ENV, CLIP_BACKEND. do_copy reads from $TMP.

detect_env() {
    if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
        if has_cmd termux-clipboard-set; then
            echo "termux"; return
        else
            warn "Termux detected but termux-api missing -- fix: pkg install termux-api"
            echo "osc52"; return
        fi
    fi
    [ -n "${WAYLAND_DISPLAY:-}" ] && { echo "wayland"; return; }
    [ -n "${DISPLAY:-}" ] && { echo "x11"; return; }
    if has_cmd xclip; then
        for _xs in /tmp/.X11-unix/X*; do
            [ -S "$_xs" ] || continue
            export DISPLAY=":${_xs##*/X}"
            echo "x11"; return
        done
    fi
    has_cmd pbcopy && { echo "pbcopy"; return; }
    echo "osc52"
}

copy_termux() {
    require_cmd termux-clipboard-set
    if safe_timeout 5s termux-clipboard-set < "$TMP" 2>/dev/null; then
        CLIP_BACKEND="Android clipboard"
    else
        die "termux-clipboard-set failed -- confirm Termux:API app is installed and running"
    fi
}

copy_wayland() {
    require_cmd wl-copy
    if safe_timeout 5s wl-copy < "$TMP" 2>/dev/null; then
        CLIP_BACKEND="Wayland clipboard"
    else
        if [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
            warn "wl-copy failed -- falling back to OSC52"
            copy_osc52
        fi
    fi
}

copy_x11() {
    require_cmd xclip
    if safe_timeout 5s xclip -selection clipboard < "$TMP" 2>/dev/null; then
        CLIP_BACKEND="X11 clipboard"
    else
        if [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
            warn "xclip failed -- falling back to OSC52"
            copy_osc52
        fi
    fi
}

copy_pbcopy() {
    if safe_timeout 5s pbcopy < "$TMP" 2>/dev/null; then
        CLIP_BACKEND="macOS pbcopy"
    else
        die "pbcopy failed"
    fi
}

copy_osc52() {
    local bytes="$1"
    if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] && (( bytes > 20000 )); then
        CLIP_BACKEND="cache-only"; return 0
    fi
    local encoded
    encoded="$(base64 -w0 < "$TMP" 2>/dev/null || base64 < "$TMP" | tr -d '\n')"
    if (( bytes > 1000000 )); then
        warn "large OSC52 payload (${bytes} bytes) -- some terminals may truncate"
    fi
    local tty
    { true >/dev/tty; } 2>/dev/null && tty=/dev/tty || tty=/dev/stderr
    if [ -n "${TMUX:-}" ]; then
        _pt="$(tmux show-options -gv allow-passthrough 2>/dev/null || true)"
        [ "$_pt" = "on" ] || { CLIP_BACKEND="OSC52-skipped"; return 0; }
        printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded" > "$tty"
    elif [ -n "${STY:-}" ]; then
        printf '\033P\033]52;c;%s\a\033\\' "$encoded" > "$tty"
    else
        printf '\033]52;c;%s\a' "$encoded" > "$tty"
    fi
    CLIP_BACKEND="OSC52"
}

# do_copy <bytes> -- send $TMP to the clipboard; also cache for paste-back.
do_copy() {
    local bytes="${1:-0}"
    case "$CLIP_ENV" in
        termux)  copy_termux  ;;
        wayland) copy_wayland ;;
        x11)     copy_x11     ;;
        pbcopy)  copy_pbcopy  ;;
        osc52)   copy_osc52 "$bytes" ;;
        *)       die "unrecognized clipboard environment: $CLIP_ENV" ;;
    esac
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/clipso"
    mkdir -p "$cache_dir"
    cp "$TMP" "$cache_dir/last"
}

# platform_label -- human-readable platform for the OK summary line
platform_label() {
    case "$CLIP_ENV" in
        termux)  echo "Termux" ;;
        wayland) echo "Debian" ;;
        x11)     echo "Debian" ;;
        pbcopy)  echo "Mac"    ;;
        osc52)
            case "$(uname -s 2>/dev/null)" in
                Darwin) echo "Mac"   ;;
                Linux)  echo "Linux" ;;
                *)      echo "local" ;;
            esac ;;
        *) echo "local" ;;
    esac
}
