#!/usr/bin/env bash
# clipso — copy local files, remote files, or stdin to clipboard
#
# targets : Termux (ARM64, no-root) · Debian · Arch Linux
# backends: termux-clipboard-set · wl-copy · xclip · OSC52
#
# usage:
#   clipso <file>
#   clipso user@host:/path/file
#   clipso -p 2222 user@host:/file
#   clipso -
#   echo hello | clipso

set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# guard — must run under bash 4+ (Termux/Debian/Arch all ship bash 5.x)
# ─────────────────────────────────────────────────────────────────────────────

if (( BASH_VERSINFO[0] < 4 )); then
    printf '[ERROR] bash 4+ required (found %s)\n' "$BASH_VERSION" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# colors
# ─────────────────────────────────────────────────────────────────────────────

# NO_COLOR: honor https://no-color.org — also strip colors when stderr is not a tty
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m' CYAN='\033[0;36m' RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi

info() { :; }

# ─────────────────────────────────────────────────────────────────────────────
# config
# ─────────────────────────────────────────────────────────────────────────────

CLIPSO_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/clipso/config"
[ -f "$CLIPSO_CFG" ] && source "$CLIPSO_CFG"
CLIPSO_NUMBERS="${CLIPSO_NUMBERS:-1}"
ok()   { printf "${GREEN}[OK]${RESET}    %s\n" "$*" >&2; }
warn() { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*" >&2; }
die()  { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# args
# ─────────────────────────────────────────────────────────────────────────────

SSH_PORT=22
_NO_SPINNER=0

# ── paste mode — read from local cache (mesh clipboard) ─────────────────────
if [ "${1:-}" = "--paste" ] || [ "${1:-}" = "-P" ]; then
    _paste_cache="${XDG_CACHE_HOME:-$HOME/.cache}/clipso/last"
    if [ ! -f "$_paste_cache" ]; then
        printf '[ERROR] no clipboard cache found — nothing copied yet via clipso\n' >&2
        exit 1
    fi
    cat "$_paste_cache"
    exit 0
fi

while getopts ":p:nqh" opt; do
    case "$opt" in
        p) SSH_PORT="$OPTARG" ;;
        n)
            if [ "${CLIPSO_NUMBERS:-1}" = "1" ]; then
                CLIPSO_NUMBERS=0; msg="line numbers OFF"
            else
                CLIPSO_NUMBERS=1; msg="line numbers ON"
            fi
            mkdir -p "$(dirname "$CLIPSO_CFG")"
            printf 'CLIPSO_NUMBERS=%s
' "$CLIPSO_NUMBERS" > "$CLIPSO_CFG"
            ok "saved: $msg ($CLIPSO_CFG)"; exit 0
            ;;
        q) _NO_SPINNER=1 ;;
        h)
            printf 'clipso — copy local files, remote files, or stdin to clipboard\n\n'
            printf 'usage:\n'
            printf '  clipso <file>                 copy a local file\n'
            printf '  clipso user@host:/path/file   copy a remote file over SSH\n'
            printf '  clipso -p <port> user@host:/f remote with a custom SSH port\n'
            printf '  clipso -                       read stdin\n'
            printf '  echo hello | clipso            read piped stdin\n'
            printf '  clipso --paste / -P            paste from mesh clipboard cache\n'
            exit 0
            ;;
        :) die "option -p requires a port number" ;;
        *) die "unknown option: -$OPTARG" ;;
    esac
done

shift $((OPTIND - 1))

# ─────────────────────────────────────────────────────────────────────────────
# helpers
# ─────────────────────────────────────────────────────────────────────────────

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1  →  install it first"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

safe_timeout() {
    # timeout is present on Debian/Arch/Termux; wrapper guards edge cases
    if has_cmd timeout; then
        timeout "$@"
    else
        shift; "$@"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# tmp — TMPDIR form works on Linux and Termux (avoids mktemp -t portability gap)
# ─────────────────────────────────────────────────────────────────────────────

TMP="$(mktemp "${TMPDIR:-/tmp}/clipso.XXXXXX")"
TMPERR="$(mktemp "${TMPDIR:-/tmp}/clipso-err.XXXXXX")"
trap 'rm -f "$TMP" "$TMPERR"' EXIT INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# input detection
# ─────────────────────────────────────────────────────────────────────────────

IS_REMOTE=false
IS_STDIN=false
REMOTE_USER="" REMOTE_HOST="" REMOTE_PATH=""
TARGET="${1:-}"

# stdin: piped input with no argument
if [ ! -t 0 ] && [ -z "$TARGET" ]; then IS_STDIN=true; fi

# stdin: explicit dash
if [ "$TARGET" = "-" ]; then IS_STDIN=true; fi

# remote: user@host:/path
if [ "$IS_STDIN" = false ] && [[ "$TARGET" =~ ^([^@]+)@([^:]+):(.+)$ ]]; then
    IS_REMOTE=true
    REMOTE_USER="${BASH_REMATCH[1]}"
    REMOTE_HOST="${BASH_REMATCH[2]}"
    REMOTE_PATH="${BASH_REMATCH[3]}"
fi

if [ "$IS_STDIN" = false ] && [ -z "$TARGET" ]; then
    die "usage:
  clipso <file>
  clipso user@host:/path/file
  clipso -p <port> user@host:/file
  clipso -
  echo hello | clipso"
fi

# ─────────────────────────────────────────────────────────────────────────────
# input handling
# ─────────────────────────────────────────────────────────────────────────────

if [ "$IS_STDIN" = true ]; then
    info "reading from stdin"
    if [ "${CLIPSO_NO_SPINNER:-0}" = "0" ] && [ "$_NO_SPINNER" = "0" ] && [ -w /dev/tty ]; then
        # spinner on /dev/tty; cat reads stdin synchronously first
        _spin_idle() {
            local s='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
            while true; do
                printf "\r${CYAN}%s${RESET} running..." "${s:$((i % ${#s})):1}" >/dev/tty
                sleep 0.1
                i=$((i + 1))
            done
        }
        _spin_idle &
        SPIN_PID=$!
        cat > "$TMP"
        kill "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
        printf "\r\033[K" >/dev/tty
    else
        cat > "$TMP"
    fi

elif [ "$IS_REMOTE" = true ]; then
    require_cmd ssh
    info "remote: ${REMOTE_USER}@${REMOTE_HOST} port ${SSH_PORT}"

    # single-quote-escape path — prevents remote shell injection on paths
    # with spaces, $vars, or backticks; GNU sed compatible
    SAFE_PATH="$(printf '%s' "$REMOTE_PATH" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"

    # stderr captured — shown verbatim on failure (auth errors, host unreachable, etc.)
    if ! ssh \
        -p "$SSH_PORT" \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "cat ${SAFE_PATH}" > "$TMP" 2>"$TMPERR"
    then
        SSH_ERR="$(cat "$TMPERR")"
        [ -n "$SSH_ERR" ] && warn "ssh said: ${SSH_ERR}"
        die "failed to read remote file — check host, port, key auth, and path"
    fi
    ok "remote file streamed"

else
    info "local: $TARGET"
    [ -f "$TARGET" ] || die "file not found: $TARGET"
    [ -r "$TARGET" ] || die "file not readable: $TARGET"
    cat "$TARGET" > "$TMP"
fi

# ─────────────────────────────────────────────────────────────────────────────
# validation
# ─────────────────────────────────────────────────────────────────────────────

[ -s "$TMP" ] || { printf "VOID" > "$TMP"; }

BYTES="$(wc -c < "$TMP" | tr -d ' ')"
MAX_BYTES=$((10 * 1024 * 1024))   # 10 MB
PAGER_LIMIT=$((900 * 1024))        # 900 KB — paged copy threshold

if (( BYTES > MAX_BYTES )); then
    die "payload too large: ${BYTES} bytes (limit: 10 MB)"
fi

info "payload: ${BYTES} bytes"

# ─────────────────────────────────────────────────────────────────────────────
# clipboard env detection — order matters
# ─────────────────────────────────────────────────────────────────────────────

detect_env() {
    # termux — no-root ARM64 Android; PREFIX set by Termux runtime
    if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
        if has_cmd termux-clipboard-set; then
            echo "termux"; return
        else
            warn "Termux detected but termux-api missing — fix: pkg install termux-api"
            echo "osc52"; return
        fi
    fi

    # wayland — check before X11; some sessions export both
    [ -n "${WAYLAND_DISPLAY:-}" ] && { echo "wayland"; return; }

    # x11
    [ -n "${DISPLAY:-}" ] && { echo "x11"; return; }

    # ssh / headless / tmux / screen — OSC52 escape sequence
    echo "osc52"
}

CLIP_ENV="$(detect_env)"
info "backend: $CLIP_ENV"

# ─────────────────────────────────────────────────────────────────────────────
# backends
# ─────────────────────────────────────────────────────────────────────────────

copy_termux() {
    require_cmd termux-clipboard-set
    # reads stdin directly — no probe write (that would corrupt clipboard on failure)
    if safe_timeout 5s termux-clipboard-set < "$TMP" 2>/dev/null; then
        CLIP_BACKEND="Android clipboard"
    else
        die "termux-clipboard-set failed — confirm Termux:API app is installed and running"
    fi
}

copy_wayland() {
    require_cmd wl-copy
    if safe_timeout 5s wl-copy < "$TMP" 2>/dev/null; then
        CLIP_BACKEND="Wayland clipboard"
    else
        warn "wl-copy failed — falling back to OSC52"
        copy_osc52
    fi
}

copy_x11() {
    require_cmd xclip
    if safe_timeout 5s xclip -selection clipboard < "$TMP" 2>/dev/null; then
        CLIP_BACKEND="X11 clipboard"
    else
        warn "xclip failed — falling back to OSC52"
        copy_osc52
    fi
}

copy_osc52() {
    # portable base64, no line wrapping: GNU uses -w0; BSD/macOS/toybox have no -w
    # (they emit a single line by default), so fall back to stripping newlines
    local encoded
    encoded="$(base64 -w0 < "$TMP" 2>/dev/null || base64 < "$TMP" | tr -d '\n')"

    if (( BYTES > 1000000 )); then
        warn "large OSC52 payload (${BYTES} bytes) — some terminals may truncate"
    fi

    if [ -n "${TMUX:-}" ]; then
        # tmux requires DCS passthrough wrapper
        printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded"
    elif [ -n "${STY:-}" ]; then
        # GNU screen DCS passthrough
        # NOTE: needs 'term xterm-256color' in ~/.screenrc — screen blocks OSC52 by default
        printf '\033P\033]52;c;%s\a\033\\' "$encoded"
    else
        printf '\033]52;c;%s\a' "$encoded"
    fi

    CLIP_BACKEND="OSC52"
}
# pbcopy-forward: write to a unix socket the client (Mac) exposes via SSH
# RemoteForward; the client listener pipes it into pbcopy. Robust when OSC52
# is unavailable (e.g. macOS Terminal.app). Socket path is a shared convention.
CLIP_SOCK="${CLIP_FORWARD_SOCK:-$HOME/.local/share/noemap/clip.sock}"
clip_forward_available() { [ -S "$CLIP_SOCK" ]; }
copy_pbcopy_forward() {
    if has_cmd nc; then
        if safe_timeout 5s nc -U "$CLIP_SOCK" < "$TMP" 2>/dev/null; then
            ok "mirrored to client clipboard (pbcopy-forward)"; return 0
        fi
    elif has_cmd socat; then
        if safe_timeout 5s socat - "UNIX-CONNECT:$CLIP_SOCK" < "$TMP" 2>/dev/null; then
            ok "mirrored to client clipboard (pbcopy-forward)"; return 0
        fi
    fi
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# dispatch
# ─────────────────────────────────────────────────────────────────────────────

do_copy() {
    case "$CLIP_ENV" in
        termux)  copy_termux  ;;
        wayland) copy_wayland ;;
        x11)     copy_x11     ;;
        osc52)   copy_osc52   ;;
        *)       die "unrecognized clipboard environment: $CLIP_ENV" ;;
    esac
    if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] && [ "$CLIP_ENV" != osc52 ]; then
        info "ssh session — mirroring to client clipboard"
        if clip_forward_available && copy_pbcopy_forward; then
            :
        else
            copy_osc52
        fi
    fi
    # cache for mesh clipboard paste-back (all nodes, all backends)
    _cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/clipso"
    mkdir -p "$_cache_dir"
    cp "$TMP" "$_cache_dir/last"
}

paginate() {
    local chunk_dir
    chunk_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipso-pages.XXXXXX")"
    trap 'rm -rf "$chunk_dir"; rm -f "$TMP" "$TMPERR"' EXIT INT TERM
    split -b "${PAGER_LIMIT}" "$TMP" "${chunk_dir}/page_"
    local pages=()
    mapfile -t pages < <(find "$chunk_dir" -name "page_*" | sort)
    local total="${#pages[@]}"
    local i=0
    for chunk in "${pages[@]}"; do
        i=$((i+1))
        cp "$chunk" "$TMP"
        BYTES="$(wc -c < "$TMP" | tr -d ' ')"
        do_copy
        if (( i < total )); then
            printf "${CYAN}[%d/%d]${RESET} %d bytes — any key: next  q: abort\n" "$i" "$total" "$BYTES" >&2
            local key
            read -n1 -s -r key < /dev/tty || true
            [[ "${key,,}" == "q" ]] && { warn "aborted at ${i}/${total}"; rm -rf "$chunk_dir"; exit 0; }
        else
            ok "[${i}/${total}] all chunks copied"
        fi
    done
    rm -rf "$chunk_dir"
}

if (( BYTES > PAGER_LIMIT )); then
    paginate
else
    do_copy
    printf "\n"
    if [ "${CLIPSO_NUMBERS:-1}" = "1" ]; then
        awk -v cyan="${CYAN}" -v reset="${RESET}" \
            'BEGIN{OFS=""} {printf "%s%4d%s  %s\n", cyan, NR, reset, $0}' "$TMP"
    else
        cat "$TMP"
    fi
    printf "\n"
    ok "copied to ${CLIP_BACKEND} — ${BYTES} bytes"
fi
