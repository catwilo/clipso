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

# history_purge -- keep only the newest $CLIPSO_HISTORY_MAX entries.
# An "entry" is the pair <hash>.cmd + <hash>.out; .out is used as the
# anchor because every run writes exactly one of each. Called after each
# run so the history dir never grows without bound.
history_purge() {
    local dir max
    dir="$(history_dir)"
    [ -d "$dir" ] || return 0
    max="${CLIPSO_HISTORY_MAX:-200}"
    [ "$max" -gt 0 ] 2>/dev/null || return 0

    local victims
    victims="$(ls -t "$dir"/*.out 2>/dev/null | tail -n +$((max + 1)))" || true
    [ -n "$victims" ] || return 0

    local f hash
    for f in $victims; do
        hash="${f##*/}"; hash="${hash%.out}"
        rm -f "$f" "$dir/$hash.cmd"
    done
}

# history_list [N] -- print the N most recent entries (default 20), newest
# first, one line each: "<when>  <hash>  $ <first command line>".
history_list() {
    local n="${1:-20}"
    case "$n" in ''|*[!0-9]*) n=20 ;; esac
    [ "$n" -gt 0 ] 2>/dev/null || n=20

    local dir
    dir="$(history_dir)"
    if [ ! -d "$dir" ]; then
        printf '(no recorded runs)\n'
        return 0
    fi

    local found=0 out hash when first_line
    while IFS= read -r out; do
        [ -f "$out" ] || continue
        found=1
        hash="${out##*/}"; hash="${hash%.out}"
        when="$(date -r "$out" '+%Y-%m-%d %H:%M' 2>/dev/null \
              || date -d "@$(stat -c %Y "$out" 2>/dev/null || echo 0)" '+%Y-%m-%d %H:%M' 2>/dev/null \
              || printf '?')"
        first_line="$(head -n1 "$dir/$hash.cmd" 2>/dev/null || printf '')"
        if [ "${#first_line}" -gt 60 ]; then
            first_line="${first_line:0:57}..."
        fi
        printf '%s%s%s  %s%s%s  $ %s\n' "$DIM" "$when" "$RESET" "$CYAN" "$hash" "$RESET" "$first_line"
    done < <(ls -t "$dir"/*.out 2>/dev/null | head -n "$n")

    [ "$found" -eq 1 ] || printf '(no recorded runs)\n'
}
