#!/usr/bin/env bash
# pty_run.sh -- execute a script under a pty, normalize the log, copy to clipboard.
# Invoked as: clipso run <script>
# Uses clipso.sh itself for clipboard copy; preserves and returns the inner exit code.

set -Eeuo pipefail
CLIPSO_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"

source "$CLIPSO_DIR/lib/core.sh"

[ $# -eq 1 ] || die "clipso run requires exactly one argument: a script file"
_run_script="$1"
[ -f "$_run_script" ] || die "clipso run: file not found: $_run_script"
[ -r "$_run_script" ] || die "clipso run: file not readable: $_run_script"

_run_log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/pty-run"
mkdir -p "$_run_log_dir"
# Transient log for THIS run: never the shared last.log path, so a nested
# clipso run cannot delete the file a parent invocation is still reading.
_run_log="$(mktemp "${TMPDIR:-/tmp}/clipso-run-log.XXXXXX")"

# EXIT (always): drop temp files so a subsequent run is never blocked.
# INT/TERM/HUP (interruption only): restore the terminal -- avoids being stuck in alt-screen.
trap 'rm -f "$_run_log" "$_run_script" 2>/dev/null || true' EXIT
trap 'printf "\033[?1049l\033[?25h"' INT TERM HUP
# ── repeat guard ─────────────────────────────────────────────────────────────
# Same command as the previous run (SHA256 of the script body, shebang
# excluded): do NOT re-execute. Warn, play the special sound, copy the
# cached payload (~/.cache/clipso/last) to the clipboard.
_run_cmd="$(tail -n +2 "$_run_script")"
_run_hash="$(printf '%s' "$_run_cmd" | sha256sum)"
_run_hash="${_run_hash%% *}"
_persist_dir="${XDG_CACHE_HOME:-$HOME/.cache}/pty-run"
mkdir -p "$_persist_dir"
_prev_hash_file="$_persist_dir/last_cmd.sha256"

if [ -f "$_prev_hash_file" ] && [ "$(cat "$_prev_hash_file")" = "$_run_hash" ]; then
    _prev_payload="${XDG_CACHE_HOME:-$HOME/.cache}/clipso/last"
    [ -f "$_prev_payload" ] || die "clipso run: repeat detected but clipboard cache missing"
    warn "repeat detected: identical command to previous run -- not executing"
    "$CLIPSO_DIR/clipso.sh" --repeat "$_prev_payload"

    # Interactive re-execute prompt (default: no). Only offered when stdin is
    # a TTY, so scripts/cron/pipes keep the old behavior -- replay and exit.
    if [ -t 0 ]; then
        printf 're-execute? [y/N] ' >&2
        read -r _ans || _ans=""
        case "$_ans" in
            y|Y) : ;;
            *)   exit 0 ;;
        esac
    else
        exit 0
    fi
fi


_run_shell="$(command -v bash || echo /bin/sh)"
_run_inner="$_run_shell $_run_script"

_clean_run_log() {
    sed -i '1{/^Script started/d}; ${/^Script done/d}; s/\x1b\[[0-9;]*[GKHFABCDJsu]//g; s/\x1b\[?[0-9;]*[hl]//g; s/\r//g' "$1"
}

printf '\033[?1049h\033[2J\033[H'
# set -e is intentionally bypassed here via if/else: the inner command may fail
# and we must still reach the alt-screen close below.
if COLUMNS=$(tput cols 2>/dev/null || echo 80) LINES=$(tput lines 2>/dev/null || echo 24) \
    script -q -e -O "$_run_log" -c "$_run_inner"; then
    _run_rc=0
else
    _run_rc=$?
fi

# Leave alt-screen BEFORE rendering, so the normalized output, line numbers and
# [OK] line are painted on the normal screen and stay visible.
printf '\033[?1049l\033[?25h'

_run_tmp="$(mktemp "${TMPDIR:-/tmp}/clipso-run-prepend.XXXXXX")"
{ printf '%s\n' "$_run_cmd" | sed 's/^/$ /'; cat "$_run_log"; } > "$_run_tmp"
mv "$_run_tmp" "$_run_log"

# Copy whatever the command produced -- normal output or an error message.
# Runs regardless of the command's exit code; cleanup handled by EXIT trap.
printf '%s\n' "$_run_hash" > "$_prev_hash_file"
printf '%s\n' "$_run_cmd" > "$_persist_dir/last_cmd"
cp "$_run_log" "$_persist_dir/last_output"
"$CLIPSO_DIR/clipso.sh" "$_run_log"
exit "$_run_rc"
