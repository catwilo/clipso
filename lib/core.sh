#!/usr/bin/env bash
# core.sh -- colors, logging, shared helpers

# NO_COLOR: honor https://no-color.org -- also strip colors when stderr is not a tty
if { true >/dev/tty; } 2>/dev/null && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m' CYAN='\033[0;36m' RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi

# _tty_path -- where display output goes: $CLIPSO_TTY_FILE when set
# (test runners), /dev/tty when writable, stderr otherwise. Single source
# of truth for every writer that needs to paint on the user's terminal.
_tty_path() {
    if [ -n "${CLIPSO_TTY_FILE:-}" ]; then
        printf '%s\n' "$CLIPSO_TTY_FILE"
    elif { true >/dev/tty; } 2>/dev/null; then
        printf '%s\n' /dev/tty
    else
        printf '%s\n' /dev/stderr
    fi
}

_TTY_OUT() {
    # Test runners and similar callers can redirect the display to a file
    # by exporting CLIPSO_TTY_FILE. Live behavior (write to /dev/tty, or
    # stderr when no tty) is unchanged when the variable is unset.
    if [ -n "${CLIPSO_TTY_FILE:-}" ]; then
        printf "$@" >> "$CLIPSO_TTY_FILE"
        return 0
    fi
    { true >/dev/tty; } 2>/dev/null && printf "$@" >/dev/tty || printf "$@" >&2
}
ok()   { _TTY_OUT "${GREEN}[OK]${RESET}  ${*}\n"; }
warn() { _TTY_OUT "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }
die()  { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1  ->  install it first"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

safe_timeout() {
    if has_cmd timeout; then
        timeout "$@"
    else
        shift; "$@"
    fi
}

fmt_size() {
    local b="$1"
    if   (( b < 1024 ));    then
        printf '%d B' "$b"
    elif (( b < 1048576 )); then
        printf '%d.%d KB' $(( b / 1024 )) $(( (b % 1024) * 10 / 1024 ))
    else
        printf '%d.%02d MB' $(( b / 1048576 )) $(( (b % 1048576) * 100 / 1048576 ))
    fi
}

# strip_display <file> -- strip terminal-noise sequences while PRESERVING
# SGR (color) escape codes. Used before painting the payload to the screen,
# so the display stays clean of pty leftovers but keeps its colors.
strip_display() {
    sed -i 's/\x1b\[[0-9;]*[GKHFABCDJsu]//g; s/\x1b\[?[0-9;]*[hl]//g; s/\x1b\][^\x07\x1b]*\x07//g; s/\x1b\][^\x07\x1b]*\x1b\\//g; s/\x1b\[[0-9;]*R//g' "$1"
}

# strip_control <file> -- strip terminal-noise sequences AND SGR color
# codes. Used on the payload that reaches the clipboard: no ANSI, no OSC,
# no CPR, nothing weird for the pasted text.
strip_control() {
    strip_display "$1"
    sed -i 's/\x1b\[[0-9;]*m//g' "$1"
}
