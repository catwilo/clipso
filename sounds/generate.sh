#!/usr/bin/env bash
# sounds/generate.sh -- render clipso's confirmation sounds from .abc sources.
#
# Versioned in the repo; the WAV files it produces are NOT (see .gitignore).
# For every N.abc in this directory, renders N.wav into the clipso sounds
# dir using miau-dio. The file name IS the sequence number: play-confirm.sh
# plays them in numeric order, wrapping at the end.
#
# Idempotent: a WAV newer than its .abc is left as is. Use --force to
# re-render everything.
#
# Usage:
#   bash sounds/generate.sh [--force] [--dir <sounds-dir>]

set -Eeuo pipefail

_self="$0"
case "$_self" in */*) ;; *) _self="$(command -v "$_self")" ;; esac
SRC_DIR="$(cd "$(dirname "$_self")" && pwd -P)"
OUT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/clipso/sounds"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --dir)   OUT_DIR="$2"; shift 2 ;;
        *) printf 'usage: generate.sh [--force] [--dir <sounds-dir>]\n' >&2; exit 2 ;;
    esac
done

command -v miau-dio >/dev/null 2>&1 || {
    printf '[WARN] generate.sh: miau-dio not found -- cannot render sounds\n' >&2
    exit 1
}

mkdir -p "$OUT_DIR"

_abc_files=$(ls "$SRC_DIR"/[0-9]*.abc 2>/dev/null | sort -V) || true
if [ -z "$_abc_files" ]; then
    printf '[WARN] generate.sh: no N.abc sources in %s -- nothing to render\n' "$SRC_DIR" >&2
    exit 0
fi

for _abc in $_abc_files; do
    _n=$(basename "$_abc" .abc)
    _wav="$OUT_DIR/$_n.wav"
    if [ "$FORCE" -eq 0 ] && [ -f "$_wav" ] && [ "$_wav" -nt "$_abc" ]; then
        printf '[OK]    %s.wav up to date\n' "$_n" >&2
        continue
    fi
    if miau-dio play "$_abc" --out "$_wav" >/dev/null 2>&1; then
        printf '[OK]    rendered %s.wav\n' "$_n" >&2
    else
        printf '[WARN]  failed to render %s.wav from %s\n' "$_n" "$_abc" >&2
    fi
done
