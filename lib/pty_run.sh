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
_run_log="$_run_log_dir/last.log"
[ ! -f "$_run_log" ] || die "clipso run: stale pty log exists -- remove manually: $_run_log"

# EXIT (always): drop temp files so a subsequent run is never blocked.
# INT/TERM/HUP (interruption only): restore the terminal -- avoids being stuck in alt-screen.
trap 'rm -f "$_run_log" "$_run_script" 2>/dev/null || true' EXIT
trap 'printf "\033[?1049l\033[?25h"' INT TERM HUP

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

_clean_run_log "$_run_log"
_run_cmd="$(tail -n +2 "$_run_script")"
_run_tmp="$(mktemp "${TMPDIR:-/tmp}/clipso-run-prepend.XXXXXX")"
{ printf '%s\n' "$_run_cmd" | sed 's/^/$ /'; cat "$_run_log"; } > "$_run_tmp"
mv "$_run_tmp" "$_run_log"

# Copy whatever the command produced -- normal output or an error message.
# Runs regardless of the command's exit code; cleanup handled by EXIT trap.
"$CLIPSO_DIR/clipso.sh" "$_run_log"
exit "$_run_rc"
