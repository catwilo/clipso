#!/usr/bin/env bash
# config.sh -- config file load + atomic upsert

CLIPSO_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/clipso/config"
[ -f "$CLIPSO_CFG" ] && source "$CLIPSO_CFG"

CLIPSO_NUMBERS="${CLIPSO_NUMBERS:-1}"
CLIPSO_ENABLED="${CLIPSO_ENABLED:-1}"
CLIPSO_STRIP_ANSI="${CLIPSO_STRIP_ANSI:-0}"
CLIPSO_PRIVACY="${CLIPSO_PRIVACY:-1}"
CLIPSO_TO="${CLIPSO_TO:-}"

# cfg_write KEY VALUE -- atomic upsert into CLIPSO_CFG (same-dir tmp + mv)
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
