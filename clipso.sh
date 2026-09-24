#!/usr/bin/env bash
# clipso -- copy local files, remote files, or stdin to clipboard.
# Thin composition root: parse args, source modules, orchestrate.

set -Eeuo pipefail

CLIPSO_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# ── guard ────────────────────────────────────────────────────────────────────
if (( BASH_VERSINFO[0] < 3 )) || { (( BASH_VERSINFO[0] == 3 )) && (( BASH_VERSINFO[1] < 2 )); }; then
    printf '[ERROR] bash 3.2+ required (found %s)\n' "$BASH_VERSION" >&2
    exit 1
fi

# ── modules ──────────────────────────────────────────────────────────────────
source "$CLIPSO_DIR/lib/core.sh"
source "$CLIPSO_DIR/lib/config.sh"
source "$CLIPSO_DIR/lib/input.sh"
source "$CLIPSO_DIR/lib/privacy.sh"
source "$CLIPSO_DIR/lib/clipboard.sh"
source "$CLIPSO_DIR/lib/remote.sh"
source "$CLIPSO_DIR/lib/paginate.sh"

# play-confirm.sh — mandatory dependency (confirmation sound)
[ -f "$CLIPSO_DIR/play-confirm.sh" ] || die "missing dependency: play-confirm.sh"
source "$CLIPSO_DIR/play-confirm.sh"

# ── subcommands ──────────────────────────────────────────────────────────────
case "${1:-}" in
    --paste|-P)
        _cache="${XDG_CACHE_HOME:-$HOME/.cache}/clipso/last"
        [ -f "$_cache" ] || die "no clipboard cache found -- nothing copied yet via clipso"
        cat "$_cache"; exit 0 ;;

    target)
        sub="${2:-status}"
        case "$sub" in
            set)
                [ -n "${3:-}" ] || die "target set requires an alias"
                cfg_write CLIPSO_TO "$3"; cfg_write CLIPSO_ENABLED 1
                ok "target set to: $3 (enabled)"; exit 0 ;;
            off)  cfg_write CLIPSO_ENABLED 0; ok "remote send disabled (alias preserved)"; exit 0 ;;
            on)   cfg_write CLIPSO_ENABLED 1; ok "remote send enabled"; exit 0 ;;
            status)
                if [ -z "${CLIPSO_TO:-}" ]; then ok "target: (none)"
                elif [ "$CLIPSO_ENABLED" = "0" ]; then ok "target: ${CLIPSO_TO}  (disabled)"
                else ok "target: ${CLIPSO_TO}  (enabled)"; fi
                exit 0 ;;
            *) die "unknown target subcommand: $sub" ;;
        esac ;;

    --set-to)
        [ -n "${2:-}" ] || die "--set-to requires an alias"
        warn "--set-to is deprecated -- use: clipso target set <alias>"
        cfg_write CLIPSO_TO "$2"; cfg_write CLIPSO_ENABLED 1
        ok "target set to: $2"; exit 0 ;;

    reset)
        printf '\033[?1049l\033[?25h'
        stty sane 2>/dev/null || true
        command -v tput >/dev/null 2>&1 && tput rmcup 2>/dev/null || true
        rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/pty-run/last.log"
        exit 0 ;;

    run)  shift
        [ $# -eq 1 ] || die "clipso run requires exactly one script file"
        exec bash "$CLIPSO_DIR/lib/pty_run.sh" "$@" ;;

    --toggle-numbers)
        if [ "$CLIPSO_NUMBERS" = "1" ]; then CLIPSO_NUMBERS=0; msg="line numbers OFF"
        else CLIPSO_NUMBERS=1; msg="line numbers ON"; fi
        cfg_write CLIPSO_NUMBERS "$CLIPSO_NUMBERS"
        ok "saved: $msg ($CLIPSO_CFG)"; exit 0 ;;

    --help) set -- -h "${@:2}" ;;
esac

# ── flags ────────────────────────────────────────────────────────────────────
SSH_PORT=22
while getopts ":p:h" opt; do
    case "$opt" in
        p) SSH_PORT="$OPTARG" ;;
        h)
            cat <<'USAGE'
clipso -- copy local files, remote files, or stdin to clipboard

usage:
  clipso <file>                     copy a local file
  clipso user@host:/path/file        copy a remote file over SSH
  clipso -p <port> user@host:/file   remote with a custom SSH port
  clipso -                           read stdin
  echo hello | clipso               read piped stdin
  clipso --paste / -P               paste from mesh clipboard cache
  clipso --to <alias>               one-shot send to remote clipboard

remote target management:
  clipso target set <alias>          persist default remote target
  clipso target off                  disable remote send (alias preserved)
  clipso target on                   re-enable remote send
  clipso target status               show current target config

config (in ~/.config/clipso/config):
  CLIPSO_STRIP_ANSI=1   strip ANSI escape codes from clipboard payload (default 0)
  CLIPSO_NUMBERS=0      disable line numbers in tty display
  CLIPSO_PRIVACY=0      disable sensitive-content warnings

flags:
  --toggle-numbers   toggle line numbers on/off  -p <port>  SSH port
USAGE
            exit 0 ;;
        :) die "option -p requires a port number" ;;
        *) die "unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

# ── --to (one-shot remote) ──────────────────────────────────────────────────
CLIPSO_TO_EXPLICIT=0
if [ "${1:-}" = "--to" ]; then
    [ -n "${2:-}" ] || die "--to requires an alias"
    CLIPSO_TO="$2"
    CLIPSO_TO_EXPLICIT=1
    shift 2
fi

TARGET="${1:-}"

# ── nesting guard (pty-run -> clipso -> clipso) ─────────────────────────────
if [ "${CLIPSO_NESTED:-0}" = "1" ]; then
    TMP="$(mktemp "${TMPDIR:-/tmp}/clipso.XXXXXX")"
    trap 'rm -f "$TMP"' EXIT INT TERM
    input_read "" "$TMP" 2>/dev/null || { cat > "$TMP"; }
    CLIP_ENV="$(detect_env)"
    do_copy "$(wc -c < "$TMP" | tr -d ' ')"
    exit $?
fi
export CLIPSO_NESTED=1

# ── tmp files ────────────────────────────────────────────────────────────────
TMP="$(mktemp "${TMPDIR:-/tmp}/clipso.XXXXXX")"
TMPERR="$(mktemp "${TMPDIR:-/tmp}/clipso-err.XXXXXX")"
trap 'rm -f "$TMP" "$TMPERR"; [ -n "${PRIVACY_INFO_FILE:-}" ] && rm -f "$PRIVACY_INFO_FILE"' EXIT INT TERM

# ── main flow ───────────────────────────────────────────────────────────────
input_read "$TARGET" "$TMP"
[ -s "$TMP" ] || printf "VOID" > "$TMP"

privacy_scan "$TMP"

BYTES="$(wc -c < "$TMP" | tr -d ' ')"
MAX_BYTES=$((10 * 1024 * 1024))
PAGER_LIMIT=$((900 * 1024))
(( BYTES > MAX_BYTES )) && die "payload too large: ${BYTES} bytes (limit: 10 MB)"

CLIP_ENV="$(detect_env)"

# Optional ANSI strip (opt-in). Default preserves colors.
if [ "${CLIPSO_STRIP_ANSI:-0}" = "1" ]; then
    _stripped="$TMP.strip"
    sed 's/\x1b\[[0-9;]*m//g' "$TMP" > "$_stripped" && mv "$_stripped" "$TMP"
    BYTES="$(wc -c < "$TMP" | tr -d ' ')"
fi

if (( BYTES > PAGER_LIMIT )); then
    paginate
    exit 0
fi

# Display + summary
printf "\n"
privacy_display "$TMP" "$CLIPSO_NUMBERS"
printf "\n"
[ "${PRIVACY_HITS:-0}" -gt 0 ] && warn "privacy: ${PRIVACY_HITS} line(s) detected -- see red above"

lines="$(wc -l < "$TMP" | tr -d ' ')"
size="$(fmt_size "$BYTES")"
if [ "${IS_STDIN:-false}" = "true" ] || [ -z "${TARGET:-}" ]; then
    src_label="stdin"
else
    src_label="$(basename "$TARGET")"
fi
platform="$(platform_label)"

BD=$'\033[1;2m' DIM=$'\033[2m'

if [ -n "${CLIPSO_TO:-}" ]; then
    do_copy "$BYTES"
    send_to_remotes
    remotes_rendered="$(remote_targets_rendered)"
    ok "${CYAN}[${platform}]${RESET} > [${remotes_rendered}]  --  ${BD}${src_label}${RESET}  --  ${DIM}${lines} lines - ${size}${RESET}"
else
    do_copy "$BYTES"
    ok "${CYAN}[${platform}]${RESET}  --  ${BD}${src_label}${RESET}  --  ${DIM}${lines} lines - ${size}${RESET}"
fi
_play_confirm
