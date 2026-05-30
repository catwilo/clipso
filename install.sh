#!/usr/bin/env bash
# clipso/install.sh — idempotent installer
#
# usage:
#   bash install.sh          install
#   bash install.sh verify   verify only (no changes)

set -Eeuo pipefail

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m' CYAN='\033[0;36m' RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi
ok()   { printf "${GREEN}[OK]${RESET}    %s\n" "$*" >&2; }
warn() { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*" >&2; }
die()  { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

_self="$0"
case "$_self" in */*) ;; *) _self="$(command -v "$_self")" ;; esac
if _real="$(readlink -f "$_self" 2>/dev/null)" && [ -n "$_real" ]; then
    _self="$_real"
else
    while [ -L "$_self" ]; do
        _link="$(readlink "$_self")"
        case "$_link" in /*) _self="$_link" ;; *) _self="$(dirname "$_self")/$_link" ;; esac
    done
fi
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd -P)"
CLIPSO_SH="$SCRIPT_DIR/clipso.sh"

[ -f "$CLIPSO_SH" ] || die "clipso.sh not found at $CLIPSO_SH"
[ -x "$CLIPSO_SH" ] || chmod +x "$CLIPSO_SH"

_do_verify() {
    local found target
    found="$(command -v clipso 2>/dev/null || true)"
    [ -n "$found" ] || { warn "clipso not in PATH — source your shell rc"; return 1; }
    target="$(readlink -f "$found" 2>/dev/null || echo "$found")"
    [ "$target" = "$CLIPSO_SH" ] || { warn "clipso → $target (expected $CLIPSO_SH)"; return 1; }
    ok "clipso → $found"
    echo "verify" | clipso - >/dev/null 2>&1 && ok "clipso runs OK" || { warn "clipso run failed"; return 1; }
}

if [ "${1:-}" = verify ]; then _do_verify; exit $?; fi

if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
    BINDIR="${PREFIX}/bin"
elif [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    BINDIR="$HOME/.local/bin"
else
    die "no writable bin dir found"
fi

ln -sf "$CLIPSO_SH" "$BINDIR/clipso"
ok "linked clipso → $BINDIR/clipso"
# also fix ~/.local/bin if it exists and differs from BINDIR (stale binary guard)
if [ "$BINDIR" != "$HOME/.local/bin" ] && [ -d "$HOME/.local/bin" ]; then
    ln -sf "$CLIPSO_SH" "$HOME/.local/bin/clipso"
    ok "linked clipso → $HOME/.local/bin/clipso (stale guard)"
fi

_BEG='# >>> clipso >>>'
_END='# <<< clipso <<<'

_wire_rc() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/clipso-rc.XXXXXX")"
    awk -v b="$_BEG" -v e="$_END" '
        $0==b {skip=1} skip && $0==e {skip=0; next} !skip {print}
    ' "$rc" > "$tmp"
    {
        cat "$tmp"
        printf '%s\n' "$_BEG"
        printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH";; esac\n' "$BINDIR" "$BINDIR"
        printf '%s\n' "$_END"
    } > "$rc"
    rm -f "$tmp"
    ok "wired $rc"
}

_wire_rc "$HOME/.zshrc"
[ -f "$HOME/.bashrc" ] && _wire_rc "$HOME/.bashrc"

ok "done — reload shell:"
printf '  source ~/.zshrc\n'
