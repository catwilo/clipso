#!/usr/bin/env bash
# history.sh -- recorded-run lookup and clipboard replay.
# Owns the pty-run history directory and the read/replay paths used by
# `clipso show` and `clipso send-payload`.

# history_dir -- path to the recorded-runs directory.
history_dir() {
    printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/pty-run/history"
}

# history_show <hash> -- print '$ <command>' followed by the recorded output.
history_show() {
    local hash="${1:-}"
    [ -n "$hash" ] || die "clipso show requires a hash"
    local dir; dir="$(history_dir)"
    local cmd="$dir/$hash.cmd" out="$dir/$hash.out"
    [ -f "$cmd" ] || die "no recorded command for hash: $hash"
    printf '$ %s\n' "$(cat "$cmd")"
    [ -f "$out" ] && cat "$out"
}

# history_send_payload <hash> -- copy a recorded payload back to the clipboard
# and play the repeat sound. Used by the repeat guard when the user answers no.
history_send_payload() {
    local hash="${1:-}"
    [ -n "$hash" ] || die "clipso send-payload requires a hash"
    local src; src="$(history_dir)/$hash.out"
    [ -f "$src" ] || die "no recorded payload for hash: $hash"
    TMP="$(mktemp "${TMPDIR:-/tmp}/clipso.XXXXXX")"
    trap 'rm -f "$TMP"' EXIT INT TERM
    cp "$src" "$TMP"
    CLIP_ENV="$(detect_env)"
    do_copy "$(wc -c < "$TMP" | tr -d ' ')"
    _play_special repeated
}
