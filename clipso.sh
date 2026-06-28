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

if (( BASH_VERSINFO[0] < 3 )) || { (( BASH_VERSINFO[0] == 3 )) && (( BASH_VERSINFO[1] < 2 )); }; then
    printf '[ERROR] bash 3.2+ required (found %s)\n' "$BASH_VERSION" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# colors
# ─────────────────────────────────────────────────────────────────────────────

# NO_COLOR: honor https://no-color.org — also strip colors when stderr is not a tty
if { true >/dev/tty; } 2>/dev/null && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m' CYAN='\033[0;36m' RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi


# ─────────────────────────────────────────────────────────────────────────────
# config
# ─────────────────────────────────────────────────────────────────────────────

CLIPSO_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/clipso/config"
[ -f "$CLIPSO_CFG" ] && source "$CLIPSO_CFG"
CLIPSO_NUMBERS="${CLIPSO_NUMBERS:-1}"
CLIPSO_ENABLED="${CLIPSO_ENABLED:-1}"
CLIP_SOCK="${HOME}/.noemap-clip.sock"   # canonical mesh socket path
_TTY_OUT() { { true >/dev/tty; } 2>/dev/null && printf "$@" >/dev/tty || printf "$@" >&2; }
ok()   { _TTY_OUT "${GREEN}[OK]${RESET}  ${*}\n"; }
warn() { _TTY_OUT "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }

# cfg_write KEY VALUE — atomic upsert into CLIPSO_CFG (same-dir tmp + mv)
cfg_write() {
    local key="$1" val="$2" tmp
    mkdir -p "$(dirname "$CLIPSO_CFG")"
    tmp="${CLIPSO_CFG}.tmp.$$"
    if [ -f "$CLIPSO_CFG" ]; then
        grep -v "^${key}=" "$CLIPSO_CFG" > "$tmp" 2>/dev/null || true
    fi
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$CLIPSO_CFG"
}
_fmt_size() {
    local b="$1"
    if   (( b < 1024 ));    then
        printf '%d B' "$b"
    elif (( b < 1048576 )); then
        printf '%d.%d KB' $(( b / 1024 )) $(( (b % 1024) * 10 / 1024 ))
    else
        printf '%d.%02d MB' $(( b / 1048576 )) $(( (b % 1048576) * 100 / 1048576 ))
    fi
}
die()  { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

# _play_confirm — play a short sound on successful copy (Termux only, background)
# Uses miau-dio WAV if present; falls back to a synthetic beep via sox.
_CONFIRM_WAV="${HOME}/.local/share/miau-dio/audio/a00287d0.wav"
_play_confirm() {
    [ "${CLIP_ENV:-}" = "termux" ] || return 0
    if [ -f "$_CONFIRM_WAV" ] && command -v play >/dev/null 2>&1; then
        play -q "$_CONFIRM_WAV" &>/dev/null &
    elif command -v play >/dev/null 2>&1; then
        play -q -n synth 0.08 sine 880 vol 0.6 &>/dev/null &
    fi
}


# ─────────────────────────────────────────────────────────────────────────────
# args
# ─────────────────────────────────────────────────────────────────────────────

SSH_PORT=22

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

# ── --to <alias[,alias...]> — one-shot: send to remote this invocation only
CLIPSO_TO="${CLIPSO_TO:-}"
CLIPSO_TO_EXPLICIT=0
if [ "${1:-}" = "--to" ]; then
    [ -n "${2:-}" ] || { printf '[ERROR] --to requires an alias\n' >&2; exit 1; }
    CLIPSO_TO="$2"
    CLIPSO_TO_EXPLICIT=1
    shift 2
fi

# ── target subcommand — manage persistent remote target ─────────────────────
if [ "${1:-}" = "target" ]; then
    subcmd="${2:-status}"
    case "$subcmd" in
        set)
            [ -n "${3:-}" ] || { printf '[ERROR] target set requires an alias\n' >&2; exit 1; }
            cfg_write CLIPSO_TO "$3"
            cfg_write CLIPSO_ENABLED 1
            ok "target set to: $3 (enabled)"; exit 0
            ;;
        off)
            cfg_write CLIPSO_ENABLED 0
            ok "remote send disabled — alias preserved (run: clipso target on to re-enable)"; exit 0
            ;;
        on)
            cfg_write CLIPSO_ENABLED 1
            _cur_to="${CLIPSO_TO:-}"
            [ -n "$_cur_to" ] && ok "remote send enabled — target: ${_cur_to}"                               || ok "remote send enabled — no target set (run: clipso target set <alias>)"
            exit 0
            ;;
        status)
            _cur_to="${CLIPSO_TO:-}"
            _cur_en="${CLIPSO_ENABLED:-1}"
            if [ -z "$_cur_to" ]; then
                ok "target: (none)"
            elif [ "$_cur_en" = "0" ]; then
                ok "target: ${_cur_to}  (disabled — run: clipso target on)"
            else
                ok "target: ${_cur_to}  (enabled)"
            fi
            exit 0
            ;;
        *)
            printf '[ERROR] unknown target subcommand: %s\n' "$subcmd" >&2
            printf 'usage: clipso target set <alias> | off | on | status\n' >&2
            exit 1
            ;;
    esac
fi

# ── --set-to: deprecated alias for target set ────────────────────────────────
if [ "${1:-}" = "--set-to" ]; then
    [ -n "${2:-}" ] || { printf '[ERROR] --set-to requires an alias\n' >&2; exit 1; }
    warn "--set-to is deprecated — use: clipso target set <alias>"
    cfg_write CLIPSO_TO "$2"
    cfg_write CLIPSO_ENABLED 1
    ok "target set to: $2"; exit 0
fi

#  run subcommand: clipso run <cmd...>  invoke pty-run, process log, clean up
if [ "${1:-}" = "run" ]; then
    shift
    [ $# -ge 1 ] || { printf '[ERROR] clipso run requires a command\n' >&2; exit 1; }
    _pty_log="${XDG_CACHE_HOME:-$HOME/.cache}/pty-run/last.log"
    if [ -f "$_pty_log" ] && ! pgrep -f "script .*${_pty_log}" >/dev/null 2>&1; then
        warn "stale pty-run lock found -- removing: $_pty_log"
        rm -f "$_pty_log"
    fi
    pty-run "$@"
    _run_rc=$?
    if [ -f "$_pty_log" ]; then
        "$0" "$_pty_log"
        rm -f "$_pty_log"
    fi
    exit "$_run_rc"
fi
# handle --toggle-numbers before getopts (long option)
if [ "${1:-}" = "--toggle-numbers" ]; then
    if [ "${CLIPSO_NUMBERS:-1}" = "1" ]; then
        CLIPSO_NUMBERS=0; msg="line numbers OFF"
    else
        CLIPSO_NUMBERS=1; msg="line numbers ON"
    fi
    cfg_write CLIPSO_NUMBERS "$CLIPSO_NUMBERS"
    ok "saved: $msg ($CLIPSO_CFG)"; exit 0
fi

while getopts ":p:h" opt; do
    case "$opt" in
        p) SSH_PORT="$OPTARG" ;;
        h)
            printf 'clipso — copy local files, remote files, or stdin to clipboard\n\n'
            printf 'usage:\n'
            printf '  clipso <file>                     copy a local file\n'
            printf '  clipso user@host:/path/file        copy a remote file over SSH\n'
            printf '  clipso -p <port> user@host:/file   remote with a custom SSH port\n'
            printf '  clipso -                           read stdin\n'
            printf '  echo hello | clipso               read piped stdin\n'
            printf '  clipso --paste / -P               paste from mesh clipboard cache\n'
            printf '  clipso --to <alias>               one-shot send to remote clipboard\n'
            printf '\nremote target management:\n'
            printf '  clipso target set <alias>          persist default remote target\n'
            printf '  clipso target off                  disable remote send (alias preserved)\n'
            printf '  clipso target on                   re-enable remote send\n'
            printf '  clipso target status               show current target config\n'
            printf '\nflags:\n'
            printf '  --toggle-numbers   toggle line numbers on/off  -p <port>  SSH port\n'
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
    cat > "$TMP"

elif [ "$IS_REMOTE" = true ]; then
    require_cmd ssh

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
    [ -f "$TARGET" ] || die "file not found: $TARGET"
    [ -r "$TARGET" ] || die "file not readable: $TARGET"
    cat "$TARGET" > "$TMP"
    _pty_log_path="${XDG_CACHE_HOME:-$HOME/.cache}/pty-run/last.log"
    [ "$TARGET" = "$_pty_log_path" ] && rm -f "$_pty_log_path"
fi

# ─────────────────────────────────────────────────────────────────────────────
# validation
# ─────────────────────────────────────────────────────────────────────────────

[ -s "$TMP" ] || { printf "VOID" > "$TMP"; }


# ─────────────────────────────────────────────────────────────────────────────
# privacy check — warn before copying sensitive content
# ─────────────────────────────────────────────────────────────────────────────

# privacy_check — single awk pass; zero per-line forks
# Globals: PRIVACY_HITS (int), PRIVACY_INFO_FILE (linenum TAB tag TAB masked)
PRIVACY_HITS=0
PRIVACY_INFO_FILE=""

privacy_check() {
    [ "${CLIPSO_PRIVACY:-1}" = "0" ] && return 0
    local PRIV_INFO
    PRIV_INFO="$(mktemp "${TMPDIR:-/tmp}/clipso-priv.XXXXXX")"
    awk '
    BEGIN{ NK=split("password passwd secret api_key apikey private_key auth_key bearer access_key token client_secret db_pass jwt credentials",KWS) }
    function valid_ip(s,  a,n,i) {
        n=split(s,a,"."); if(n!=4) return 0
        for(i=1;i<=4;i++) if(a[i]!~/^[0-9]+$/||a[i]+0>255) return 0
        return 1
    }
    function is_priv(s,  a) {
        split(s,a,"."); a[1]+=0; a[2]+=0
        return(a[1]==10||(a[1]==192&&a[2]==168)||(a[1]==172&&a[2]>=16&&a[2]<=31))
    }
    function is_safe(s) {
        return(s=="1.1.1.1"||s=="8.8.8.8"||s=="8.8.4.4"||s=="9.9.9.9"||s=="1.0.0.1")
    }
    function nontrivial(v,  lv) {
        lv=tolower(v)
        if(lv~/^(true|false|null|yes|no|none|todo|changeme|example|placeholder)$/) return 0
        if(lv~/^your_/||lv~/^<[^>]*>$/||lv~/^\**$/||lv~/^x+$/) return 0
        return (length(v)>=5)
    }
    function cred_hit(line,  lo,kws,nk,kw,i,p,bef,rest,val) {
        lo=tolower(line)
        for(i=1;i<=NK;i++) {
            kw=KWS[i]; if(!(p=index(lo,kw))) continue
            bef=(p>1)?substr(lo,p-1,1):""
            if(bef~/[a-z0-9_]/) continue
            rest=substr(line,p+length(kw))
            if(rest!~/^[^=:a-zA-Z0-9]*[=:]/) continue
            match(rest,/[=:][[:space:]]*/)
            val=substr(rest,RSTART+RLENGTH)
            gsub(/^[[:space:]"]+|[[:space:]",;]+$/,"",val)
            if(nontrivial(val)) return 1
        }
        return 0
    }
    {
        tag=""
        if(cred_hit($0)) tag="CRED"
        if(!tag) { s=$0
            while(match(s,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
                ip=substr(s,RSTART,RLENGTH); s=substr(s,RSTART+RLENGTH)
                if(valid_ip(ip)&&is_priv(ip)) { tag="PRIV-IP"; break }
            }
        }
        if(!tag&&match($0,/[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]/)) {
            mac=tolower(substr($0,RSTART,RLENGTH))
            if(mac!="00:00:00:00:00:00"&&mac!="ff:ff:ff:ff:ff:ff") tag="MAC"
        }
        if(!tag) { s=$0
            while(match(s,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
                pre=(RSTART>1)?substr(s,RSTART-1,1):""
                ip=substr(s,RSTART,RLENGTH); s=substr(s,RSTART+RLENGTH)
                if(!valid_ip(ip)||is_priv(ip)||is_safe(ip)) continue
                if(pre~/[a-zA-Z0-9.]/) continue
                split(ip,o,"."); if(o[1]+0==0||o[1]+0==127||o[1]+0==255) continue
                tag="PUB-IP"; break
            }
        }
        if(tag) print NR "\t" tag "\t" $0
    }
    ' "$TMP" > "$PRIV_INFO"
    if [ ! -s "$PRIV_INFO" ]; then rm -f "$PRIV_INFO"; return 0; fi
    PRIVACY_HITS=$(wc -l < "$PRIV_INFO" | tr -d ' ')
    PRIVACY_INFO_FILE="$PRIV_INFO"
}

display_with_privacy() {
    local nums="${CLIPSO_NUMBERS:-1}"
    local _tty; { true >/dev/tty; } 2>/dev/null && _tty=/dev/tty || _tty=/dev/stderr
    if [ "${PRIVACY_HITS:-0}" -gt 0 ] && [ -f "${PRIVACY_INFO_FILE:-}" ]; then
        local _src="$TMP"
        awk -v p="$PRIVACY_INFO_FILE" -v red="${RED}" -v cyan="${CYAN}" -v rst="${RESET}" -v nums="$nums" \
        'BEGIN{while((getline ln<p)>0){split(ln,a,"\t");fl[a[1]]=a[3]}}
         {if(NR in fl) { if(nums=="1") printf "%s%4d  %s%s\n",red,NR,$0,rst; else printf "%s%s%s\n",red,$0,rst }
          else          { if(nums=="1") printf "%s%4d%s  %s\n",cyan,NR,rst,$0; else print }}' "$_src" > "$_tty"
    else
        local _src="$TMP"
        if [ "$nums" = "1" ]; then
            awk -v c="${CYAN}" -v r="${RESET}" '{printf "%s%4d%s  %s\n",c,NR,r,$0}' "$_src" > "$_tty"
        else
            cat "$_src" > "$_tty"
        fi
    fi
}




BYTES="$(wc -c < "$TMP" | tr -d ' ')"
MAX_BYTES=$((10 * 1024 * 1024))   # 10 MB
PAGER_LIMIT=$((900 * 1024))        # 900 KB — paged copy threshold

if (( BYTES > MAX_BYTES )); then
    die "payload too large: ${BYTES} bytes (limit: 10 MB)"
fi


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

    # headless w/ live X11 socket (e.g. SSH into a box running Xorg) — use xclip
    if has_cmd xclip; then
        for _xs in /tmp/.X11-unix/X*; do
            [ -S "$_xs" ] || continue
            export DISPLAY=":${_xs##*/X}"
            echo "x11"; return
        done
    fi
    # macOS — pbcopy available (native, works headless/SSH)
    has_cmd pbcopy && { echo "pbcopy"; return; }
    # ssh / headless / tmux / screen — OSC52 escape sequence
    echo "osc52"
}

# headless: probe live X11 socket before detect_env runs (export must be in parent shell)
if [ -z "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
    for _xs in /tmp/.X11-unix/X*; do
        [ -S "$_xs" ] && export DISPLAY=":${_xs##*/X}" && break
    done
fi
CLIP_ENV="$(detect_env)"

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
        if [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
            warn "wl-copy failed — falling back to OSC52"
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
            warn "xclip failed — falling back to OSC52"
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
    # skip large payloads in SSH — terminal chain truncates/blobs
    if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] && (( BYTES > 20000 )); then
        CLIP_BACKEND="cache-only"; return 0
    fi
    # portable base64, no line wrapping: GNU uses -w0; BSD/macOS/toybox have no -w
    # (they emit a single line by default), so fall back to stripping newlines
    local encoded
    encoded="$(base64 -w0 < "$TMP" 2>/dev/null || base64 < "$TMP" | tr -d '\n')"

    if (( BYTES > 1000000 )); then
        warn "large OSC52 payload (${BYTES} bytes) — some terminals may truncate"
    fi

    local _tty; { true >/dev/tty; } 2>/dev/null && _tty=/dev/tty || _tty=/dev/stderr
    if [ -n "${TMUX:-}" ]; then
        # tmux requires DCS passthrough wrapper
        _pt="$(tmux show-options -gv allow-passthrough 2>/dev/null || true)"
        [ "$_pt" = "on" ] || { CLIP_BACKEND="OSC52-skipped"; return 0; }
        printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded" > "$_tty"
    elif [ -n "${STY:-}" ]; then
        # GNU screen DCS passthrough
        # NOTE: needs 'term xterm-256color' in ~/.screenrc — screen blocks OSC52 by default
        printf '\033P\033]52;c;%s\a\033\\' "$encoded" > "$_tty"
    else
        printf '\033]52;c;%s\a' "$encoded" > "$_tty"
    fi

    CLIP_BACKEND="OSC52"
}
CLIP_BACKEND="unknown"

# ─────────────────────────────────────────────────────────────────────────────
# dispatch
# ─────────────────────────────────────────────────────────────────────────────

do_copy() {
    # clipboard must receive the untouched original, never privacy-mangled content
    case "$CLIP_ENV" in
        termux)  copy_termux  ;;
        wayland) copy_wayland ;;
        x11)     copy_x11     ;;
        pbcopy)  copy_pbcopy ;;
        osc52)   copy_osc52 ;;
        *)       die "unrecognized clipboard environment: $CLIP_ENV" ;;
    esac
    # cache for mesh clipboard paste-back (all nodes, all backends)
    _cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/clipso"
    mkdir -p "$_cache_dir"
    cp "$TMP" "$_cache_dir/last"
}

# _should_send_remote — true if remote send is warranted this invocation
# --to explicit always bypasses CLIPSO_ENABLED; persistent target respects it.
_should_send_remote() {
    [ -n "${CLIPSO_TO:-}" ] || return 1
    [ "${CLIPSO_TO_EXPLICIT:-0}" = "1" ] && return 0
    [ "${CLIPSO_ENABLED:-1}" = "0" ] && return 1
    return 0
}

# send_to_remotes — push clipboard to remote aliases via nclip-send.
# Called ONCE at end of main, after local copy + display. Never inside do_copy.
send_to_remotes() {
    _should_send_remote || return 0
    [ -n "${CLIPSO_TO:-}" ] || return 0
    _nclip="${NOEMAP_BASE:-$HOME/unix-toolkit-tools/noemap}/bin/nclip-send"
    [ -x "$_nclip" ] || return 0
    for _to_alias in $(printf '%s' "$CLIPSO_TO" | tr ',' ' '); do
        _snap="$(mktemp "${TMPDIR:-/tmp}/clipso-snap.XXXXXX")"
        cp "$TMP" "$_snap"
        LC_ALL=C sed 's/[^[:print:]\t]//g' "$_snap" > "${_snap}.clean" && mv "${_snap}.clean" "$_snap" || true
        ( "$_nclip" "$_to_alias" < "$_snap" >/dev/null 2>&1; rm -f "$_snap" ) &
    done
    return 0
}
paginate() {
    local chunk_dir
    chunk_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipso-pages.XXXXXX")"
    trap 'rm -rf "$chunk_dir"; rm -f "$TMP" "$TMPERR"' EXIT INT TERM
    split -b "${PAGER_LIMIT}" "$TMP" "${chunk_dir}/page_"
    local pages=()
    while IFS= read -r _pg; do pages+=("$_pg"); done < <(find "$chunk_dir" -name "page_*" | sort)
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

# nesting guard: if called from within clipso (e.g. pty-run -> clipso -> clipso),
# act as pass-through -- copy only, no display, no remote send, no summary.
if [ "${CLIPSO_NESTED:-0}" = "1" ]; then
  export CLIPSO_NESTED=1
  cat > "$TMP"
  do_copy
  exit $?
fi
export CLIPSO_NESTED=1

privacy_check
[ "${PRIVACY_HITS:-0}" -gt 0 ] && BYTES="$(wc -c < "$TMP" | tr -d ' ')"

if (( BYTES > PAGER_LIMIT )); then
    paginate
else
    # preserve colored copy for tty display; strip ANSI only for clipboard
    printf "\n"
    display_with_privacy
    printf "\n"
    [ "${PRIVACY_HITS:-0}" -gt 0 ] && warn "privacy: ${PRIVACY_HITS} line(s) detected  see red above"
    _lines="$(wc -l < "$TMP" | tr -d ' ')"
    _size="$(_fmt_size "$BYTES")"
    if [ "${IS_STDIN:-false}" = "true" ] || [ -z "${TARGET:-}" ]; then
        _source="stdin"
    else
        _source="$(basename "${TARGET}")"
    fi
    case "$CLIP_ENV" in
        termux)  _platform="Termux" ;;
        wayland) _platform="Debian" ;;
        x11)     _platform="Debian" ;;
        pbcopy)  _platform="Mac"    ;;
        osc52)
            case "$(uname -s 2>/dev/null)" in
                Darwin) _platform="Mac"   ;;
                Linux)  _platform="Linux" ;;
                *)      _platform="local" ;;
            esac ;;
        *) _platform="local" ;;
    esac
    _BD=$'\033[1;2m' _D=$'\033[2m'
    if [ -n "${CLIPSO_TO:-}" ]; then
        _remotes_plain="$(printf '%s' "$CLIPSO_TO" | sed 's/,/ - /g')"
        _summary="[OK]  [${_platform}] > [${_remotes_plain}] -- ${_source} -- ${_lines} lines * ${_size}"
    else
        _summary="[OK]  [${_platform}] -- ${_source} -- ${_lines} lines * ${_size}"
    fi
    if [ -n "${CLIPSO_TO:-}" ]; then
        do_copy
        send_to_remotes
        if [ "${CLIPSO_NO_SUMMARY:-0}" = "1" ]; then
            : # remote handles its own copy
        fi
        _DB="${NOEMAP_BASE:-$HOME/unix-toolkit-tools/noemap}/state/devices.db"
        _remotes_str=""
        for _r in $(printf '%s' "$CLIPSO_TO" | tr ',' ' '); do
            if [ -f "$_DB" ] && awk -F'|' -v a="$_r" '$1==a{found=1}END{exit !found}' "$_DB" 2>/dev/null; then
                _remotes_str="${_remotes_str:+$_remotes_str - }${CYAN}${_r}${RESET}"
            else
                _remotes_str="${_remotes_str:+$_remotes_str - }${RED}✗${_r}${RESET}"
            fi
        done
        ok "${CYAN}[${_platform}]${RESET} ❯ [${_remotes_str}]  —  ${_BD}${_source}${RESET}  —  ${_D}${_lines} lines · ${_size}${RESET}"
        _play_confirm
    else
        sed 's/\x1b\[[0-9;]*m//g' "$TMP" > "$TMP.ansi" && mv "$TMP.ansi" "$TMP"
        do_copy
        ok "${CYAN}[${_platform}]${RESET}  —  ${_BD}${_source}${RESET}  —  ${_D}${_lines} lines · ${_size}${RESET}"
        _play_confirm
    fi
fi
