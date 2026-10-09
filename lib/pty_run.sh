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
    # Identical command to the previous run. Copy the previous payload
    # (hash + output) to the clipboard NOW -- so "no" leaves the clipboard
    # with what the user already had. If the user answers "yes", the run
    # proceeds and the new output overwrites the clipboard at the end.
    "$CLIPSO_DIR/clipso.sh" send-payload "$_run_hash" || die "clipso run: failed to copy previous payload to clipboard"

    if [ -t 0 ]; then
        # Ctrl+C at the prompt cancels the run (exit 130); Ctrl+D (EOF) is the
        # default answer ("no") and exits cleanly. Trap restored afterwards.
        trap 'printf "\n" >/dev/tty; exit 130' INT
        printf '\n  %brepeat detected%b  identical to previous run\n' "$YELLOW" "$RESET" >/dev/tty
        printf '  re-execute? %b[y/N]%b ' "$CYAN" "$RESET" >/dev/tty
        if ! read -r _ans; then
            printf '\n' >/dev/tty
            exit 0
        fi
        trap 'printf "\033[?1049l\033[?25h"' INT TERM HUP
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
    sed -i '1{/^Script started/d}; ${/^Script done/d}; s/\r//g' "$1"
    strip_display "$1"   # keep SGR (color); noise is stripped separately
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
# Drain late terminal replies (CPR, OSC color reports) that arrive after the
# pty exits: a short pause lets stragglers land in the log, then a second
# strip pass removes anything that slipped in during the pause. Two passes
# because the first strip can run before the last reply reaches the file.
sleep 0.1
_clean_run_log "$_run_log"
strip_display "$_run_log"
_run_lines="$(wc -l < "$_run_log" | tr -d ' ')"
_run_size="$(fmt_size "$(wc -c < "$_run_log" | tr -d ' ')")"
_dim=$'\033[2m'
_header="$(printf '%b[clipso]%b  %bhash=%b%s%b  %blines=%b%s%b  %bsize=%b%s%b' "$CYAN" "$RESET" "$_dim" "$CYAN" "$_run_hash" "$RESET" "$_dim" "$CYAN" "$_run_lines" "$RESET" "$_dim" "$CYAN" "$_run_size" "$RESET")"
_run_tmp="$(mktemp "${TMPDIR:-/tmp}/clipso-run-prepend.XXXXXX")"
{ printf '%s\n' "$_header"; cat "$_run_log"; } > "$_run_tmp"
mv "$_run_tmp" "$_run_log"
# Copy whatever the command produced -- normal output or an error message.
# Runs regardless of the command's exit code; cleanup handled by EXIT trap.
# Persist raw cmd + normalized output under the hash for `clipso show <hash>`.
# Persist history/last_output as STRIPPED text -- exactly what lands on the
# clipboard. Keeps `clipso show`, `send-payload` and the repeat guard byte
# identical with the live copy. The display above still got the colored log.
mkdir -p "$_persist_dir/history"
printf '%s\n' "$_run_cmd" > "$_persist_dir/history/${_run_hash}.cmd"
cp "$_run_log" "$_persist_dir/history/${_run_hash}.out" && strip_control "$_persist_dir/history/${_run_hash}.out"
printf '%s\n' "$_run_hash" > "$_prev_hash_file"
printf '%s\n' "$_run_cmd" > "$_persist_dir/last_cmd"
cp "$_persist_dir/history/${_run_hash}.out" "$_persist_dir/last_output"
"$CLIPSO_DIR/clipso.sh" "$_run_log"
exit "$_run_rc"
