#!/usr/bin/env bash
# remote.sh -- one-shot clipboard push to remote aliases (nclip-send).
# Uses env: CLIPSO_TO, CLIPSO_ENABLED, CLIPSO_TO_EXPLICIT, TMP.

_should_send_remote() {
    [ -n "${CLIPSO_TO:-}" ] || return 1
    [ "${CLIPSO_TO_EXPLICIT:-0}" = "1" ] && return 0
    [ "${CLIPSO_ENABLED:-1}" = "0" ] && return 1
    return 0
}

send_to_remotes() {
    _should_send_remote || return 0
    [ -n "${CLIPSO_TO:-}" ] || return 0
    local nclip="${NOEMAP_BASE:-$HOME/unix-toolkit-tools/noemap}/bin/nclip-send"
    [ -x "$nclip" ] || return 0
    local to_alias snap
    for to_alias in $(printf '%s' "$CLIPSO_TO" | tr ',' ' '); do
        snap="$(mktemp "${TMPDIR:-/tmp}/clipso-snap.XXXXXX")"
        cp "$TMP" "$snap"
        LC_ALL=C sed 's/[^[:print:]\t]//g' "$snap" > "${snap}.clean" && mv "${snap}.clean" "$snap" || true
        ( "$nclip" "$to_alias" < "$snap" >/dev/null 2>&1; rm -f "$snap" ) &
    done
    return 0
}

# remote_targets_rendered -- colored "a - b" list for the summary line
remote_targets_rendered() {
    local db="${NOEMAP_BASE:-$HOME/unix-toolkit-tools/noemap}/state/devices.db"
    local out="" r
    for r in $(printf '%s' "$CLIPSO_TO" | tr ',' ' '); do
        if [ -f "$db" ] && awk -F'|' -v a="$r" '$1==a{found=1}END{exit !found}' "$db" 2>/dev/null; then
            out="${out:+$out - }${CYAN}${r}${RESET}"
        else
            out="${out:+$out - }${RED}${r}${RESET}"
        fi
    done
    printf '%s' "$out"
}
