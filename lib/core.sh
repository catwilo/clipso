#!/usr/bin/env bash
# core.sh -- colors, logging, shared helpers

# NO_COLOR: honor https://no-color.org -- also strip colors when stderr is not a tty
if { true >/dev/tty; } 2>/dev/null && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m' CYAN='\033[0;36m' RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi

_TTY_OUT() { { true >/dev/tty; } 2>/dev/null && printf "$@" >/dev/tty || printf "$@" >&2; }
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

# strip_control <file> -- remove terminal control sequences in place.
# Covers CSI cursor/erase, CSI SGR colors, OSC replies (BEL or ST
# terminated) and CPR cursor-position reports. The last three are the
# bytes a terminal sends back when probed via the pty (e.g. background
# color query, cursor position); without this they leak into the
# clipboard payload as "weird characters".
strip_control() {
    sed -i 's/\x1b\[[0-9;]*[GKHFABCDJsu]//g; s/\x1b\[?[0-9;]*[hl]//g; s/\x1b\][^\x07\x1b]*\x07//g; s/\x1b\][^\x07\x1b]*\x1b\\//g; s/\x1b\[[0-9;]*R//g; s/\x1b\[[0-9;]*m//g' "$1"
}
