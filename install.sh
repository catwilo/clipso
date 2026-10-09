#!/usr/bin/env bash
# clipso/install.sh — idempotent installer (symlink, never copy)
#
# usage:
#   bash install.sh          install
#   bash install.sh verify   verify only (no changes)
#
# PHILOSOPHY (toolkit standard): SYMLINK into the repo, never copy. The
# installed clipso is a symlink to clipso.sh; a `git pull` updates it with
# no reinstall. Verification asserts the symlink target is the repo file.
# Sounds (WAV) are generated into the clipso config dir by sounds/generate.sh;
# they are not part of the repo.

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
PLAY_CONFIRM="$SCRIPT_DIR/play-confirm.sh"

[ -f "$CLIPSO_SH" ] || die "clipso.sh not found at $CLIPSO_SH"
[ -f "$PLAY_CONFIRM" ] || die "play-confirm.sh not found at $PLAY_CONFIRM"
[ -x "$CLIPSO_SH" ] || chmod +x "$CLIPSO_SH"

# Dependency checks -- warn with an actionable command. Missing pieces never
# abort the install: clipso degrades gracefully (OSC52, silent guard).
if [ -n "${PREFIX:-}" ]; then
    if ! command -v termux-clipboard-set >/dev/null 2>&1; then
        warn "termux-clipboard-set missing -- clipboard will fall back to OSC52 only"
        warn "  install it with:  pkg install termux-api"
    fi
fi
if ! command -v miau-dio >/dev/null 2>&1; then
    warn "miau-dio missing -- confirmation sounds and the repeat-guard sound cannot render"
    warn "  install it from the unix-toolkit-tools registry:  ut install miau-dio"
fi
[ -x "$CLIPSO_SH" ] || chmod +x "$CLIPSO_SH"

if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
    BINDIR="${PREFIX}/bin"
elif [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    BINDIR="$HOME/.local/bin"
else
    die "no writable bin dir found"
fi

# _run_tests -- run the BATS regression suite; install BATS on first use.
_run_tests() {
    local bats_bin="$HOME/.local/bin/bats"
    [ -x "$bats_bin" ] || bats_bin="$(command -v bats 2>/dev/null || true)"
    if [ -z "$bats_bin" ] || [ ! -x "$bats_bin" ]; then
        local repo="$HOME/bats-core"
        [ -d "$repo" ] || git clone --depth 1 https://github.com/bats-core/bats-core.git "$repo" >&2 || die "failed to clone bats-core"
        bash "$repo/install.sh" "$HOME/.local" >&2 || die "failed to install bats"
        bats_bin="$HOME/.local/bin/bats"
    fi
    [ -x "$bats_bin" ] || die "bats not executable: $bats_bin"
    "$bats_bin" "$SCRIPT_DIR/tests/"
}

_do_verify() {
    local found target
    found="$(command -v clipso 2>/dev/null || true)"
    [ -n "$found" ] || { warn "clipso not in PATH — source your shell rc"; return 1; }
    target="$(readlink -f "$found" 2>/dev/null || echo "$found")"
    [ "$target" = "$CLIPSO_SH" ] || { warn "clipso -> $target (expected $CLIPSO_SH)"; return 1; }
    [ -L "$found" ] || { warn "clipso is not a symlink -> $found"; return 1; }
    ok "clipso -> $found"
    echo "verify" | clipso - >/dev/null 2>&1 && ok "clipso runs OK" || { warn "clipso run failed"; return 1; }

    local pc pc_target
    pc="$(command -v play-confirm 2>/dev/null || true)"
    if [ -z "$pc" ]; then
        warn "play-confirm not in PATH — run: bash install.sh"
        return 1
    fi
    pc_target="$(readlink -f "$pc" 2>/dev/null || echo "$pc")"
    [ "$pc_target" = "$PLAY_CONFIRM" ] || { warn "play-confirm -> $pc_target (expected $PLAY_CONFIRM)"; return 1; }
    [ -L "$pc" ] || { warn "play-confirm is not a symlink -> $pc"; return 1; }
    ok "play-confirm -> $pc"
}

if [ "${1:-}" = verify ]; then _do_verify;  exit $?; fi
if [ "${1:-}" = test ];   then _run_tests; exit $?; fi

_link() {
    local src="$1" dst="$2"
    ln -sfn "$src" "$dst"
    ok "linked $dst -> $src"
}

_link "$CLIPSO_SH" "$BINDIR/clipso"
_link "$PLAY_CONFIRM" "$BINDIR/play-confirm"
_link "$PLAY_CONFIRM" "$BINDIR/play-confirm.sh"

# Clear stale copies in ~/.local/bin when BINDIR is elsewhere; a copy there
# would shadow the link when ~/.local/bin precedes $PREFIX/bin in PATH.
if [ "$BINDIR" != "$HOME/.local/bin" ] && [ -d "$HOME/.local/bin" ]; then
    for _n in clipso play-confirm play-confirm.sh; do
        if [ -e "$HOME/.local/bin/$_n" ] && [ ! -L "$HOME/.local/bin/$_n" ]; then
            rm -f "$HOME/.local/bin/$_n"
            ok "removed stale copy $HOME/.local/bin/$_n"
        fi
    done
fi

# Generate confirmation sounds (idempotent; safe to re-run).
if [ -f "$SCRIPT_DIR/sounds/generate.sh" ]; then
    bash "$SCRIPT_DIR/sounds/generate.sh" || warn "sound generation reported issues"
fi

_BEG='# >>> clipso >>>'
_END='# <<< clipso <<<'

_wire_rc() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    [ -L "$rc" ] && warn "$(basename "$rc") is a symlink to versioned dotfile — skipping PATH inject" && return 0
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

_BEG_ZSH='# >>> clipso-keybinding >>>'
_END_ZSH='# <<< clipso-keybinding <<<'

_wire_keybinding() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    [ -L "$rc" ] && warn "$(basename "$rc") is a symlink — skipping keybinding inject" && return 0
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/clipso-kb.XXXXXX")"
    awk -v b="$_BEG_ZSH" -v e="$_END_ZSH" '
        $0==b {skip=1} skip && $0==e {skip=0; next} !skip {print}
    ' "$rc" > "$tmp"
    {
        cat "$tmp"
        printf '%s\n' "$_BEG_ZSH"
        printf '_wrap_clipso() {\n'
        printf '  [[ -z $BUFFER ]] && return\n'
        printf '  local _c=$BUFFER\n'
        printf '  local _tmp\n'
        printf '  _tmp=$(mktemp "${TMPDIR:-/tmp}/clipso-cmd.XXXXXX")\n'
        printf '  printf "#!/usr/bin/env bash\\n%%s\\n" "$_c" > "$_tmp"\n'
        printf '  print -s "$_c"\n'
        printf '  BUFFER="clipso run $_tmp"\n'
        printf '  zle accept-line\n'
        printf '}\n'
        printf '}\n'
        printf '_clipso_zshaddhistory() {\n'
        printf '  [[ "$1" == "clipso run /"* ]] && return 1\n'
        printf '  return 0\n'
        printf '}\n'
        printf 'autoload -Uz add-zsh-hook\n'
        printf 'add-zsh-hook zshaddhistory _clipso_zshaddhistory\n'
        printf 'zle -N _wrap_clipso\n'
        printf 'bindkey "^[g" _wrap_clipso\n'
        printf '%s\n' "$_END_ZSH"
    } > "$rc"
    rm -f "$tmp"
    ok "wired keybinding in $rc"
}

_wire_keybinding "$HOME/.zshrc"

# First-run bootstrap: if BATS is not present, install it once so the
# regression suite is usable from this node without manual setup. Failure
# here is non-fatal -- the tools are already installed by this point.
if [ ! -x "$HOME/.local/bin/bats" ] && ! command -v bats >/dev/null 2>&1; then
    _bats_repo="$HOME/bats-core"
    if [ ! -d "$_bats_repo" ]; then
        git clone --depth 1 https://github.com/bats-core/bats-core.git "$_bats_repo" >&2 \
            || warn "failed to clone bats-core (run tests later with: bash install.sh test)"
    fi
    if [ -d "$_bats_repo" ]; then
        bash "$_bats_repo/install.sh" "$HOME/.local" >&2 \
            || warn "failed to install bats (run tests later with: bash install.sh test)"
    fi
fi

ok "done — reload shell:"
printf '  source ~/.zshrc\n'
