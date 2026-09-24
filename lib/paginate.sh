#!/usr/bin/env bash
# paginate.sh -- chunked copy for payloads larger than PAGER_LIMIT.
# Depends on do_copy (clipboard.sh) and TMP/BYTES/PAGER_LIMIT globals.

paginate() {
    local chunk_dir
    chunk_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipso-pages.XXXXXX")"
    trap 'rm -rf "$chunk_dir"; rm -f "$TMP" "$TMPERR"' EXIT INT TERM
    split -b "$PAGER_LIMIT" "$TMP" "${chunk_dir}/page_"

    local pages=() pg
    while IFS= read -r pg; do pages+=("$pg"); done < <(find "$chunk_dir" -name "page_*" | sort)

    local total="${#pages[@]}"
    local i=0 chunk
    for chunk in "${pages[@]}"; do
        i=$((i+1))
        cp "$chunk" "$TMP"
        BYTES="$(wc -c < "$TMP" | tr -d ' ')"
        do_copy "$BYTES"
        if (( i < total )); then
            printf "${CYAN}[%d/%d]${RESET} %d bytes -- any key: next  q: abort\n" "$i" "$total" "$BYTES" >&2
            local key
            read -n1 -s -r key < /dev/tty || true
            [[ "${key,,}" == "q" ]] && { warn "aborted at ${i}/${total}"; rm -rf "$chunk_dir"; exit 0; }
        else
            ok "[${i}/${total}] all chunks copied"
        fi
    done
    rm -rf "$chunk_dir"
}
