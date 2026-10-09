#!/usr/bin/env bats
# main_flow.bats -- clipso.sh primary interface: local file, stdin, paste, help.

load helpers

setup() { setup_env; }

@test "clipso <file>: copies file content and caches it for paste" {
    src="$BATS_TEST_TMPDIR/data.txt"
    printf 'local-file-line-1\nlocal-file-line-2\n' > "$src"
    run bash "$CLIPSO" "$src" </dev/null
    [ "$status" -eq 0 ]
    [ -s "$CLIPBOARD_FILE" ]
    [[ "$(cat "$CLIPBOARD_FILE")" == *'local-file-line-1'* ]]

    run bash "$CLIPSO" --paste
    [ "$status" -eq 0 ]
    [[ "$output" == *'local-file-line-2'* ]]
}

@test "clipso -: reads from stdin and caches the content" {
    printf 'stdin-payload-line\n' | bash "$CLIPSO" - >/dev/null
    [ -s "$CLIPBOARD_FILE" ]
    [[ "$(cat "$CLIPBOARD_FILE")" == *'stdin-payload-line'* ]]
}

@test "clipso --help: prints usage and exits 0" {
    run bash "$CLIPSO" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'clipso -- copy local files'* ]]
    [[ "$output" == *'clipso show <hash>'* ]]
}

@test "clipso --paste with no cache: dies with actionable message" {
    run bash "$CLIPSO" --paste
    [ "$status" -ne 0 ]
    [[ "$output" == *'no clipboard cache found'* ]]
}

@test "clipso <missing file>: dies with actionable message" {
    run bash "$CLIPSO" "$BATS_TEST_TMPDIR/nope.txt" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *'file not found'* ]]
}

@test "clipso --paste after a copy returns the cached payload" {
    src="$BATS_TEST_TMPDIR/one.txt"
    printf 'cached-line\n' > "$src"
    run bash "$CLIPSO" "$src" </dev/null
    [ "$status" -eq 0 ]
    run bash "$CLIPSO" --paste
    [ "$status" -eq 0 ]
    [[ "$output" == *'cached-line'* ]]
}

@test "clipso --to with missing alias arg dies with actionable message" {
    run bash "$CLIPSO" --to
    [ "$status" -ne 0 ]
    [[ "$output" == *'--to requires an alias'* ]]
}

@test "paginate: payload over PAGER_LIMIT enters the pager path" {
    # A single long line just past PAGER_LIMIT (900 KB). Few lines so the
    # test itself does not flood the terminal; the paginate path is taken
    # before privacy_display, so no display output is produced at all.
    big="$BATS_TEST_TMPDIR/big.txt"
    awk 'BEGIN { printf "%*s\n", 950000, "" }' > "$big"
    run bash "$CLIPSO" "$big" </dev/null
    [ "$status" -eq 0 ]
}

@test "clipso user@host:/path reads a remote file via ssh" {
    # Fake ssh: last arg is the remote command ("cat <path>"). Emit content.
    cat > "$BIN/ssh" <<'FAKE'
#!/usr/bin/env bash
for last; do :; done
case "$last" in
    "cat "*) printf 'remote-line-1\nremote-line-2\n'; exit 0 ;;
esac
exit 1
FAKE
    chmod +x "$BIN/ssh"

    run bash "$CLIPSO" "u@remote.invalid:/etc/hosts" </dev/null
    [ "$status" -eq 0 ]
    grep -q 'remote-line-1' "$CLIPBOARD_FILE"
    grep -q 'remote-line-2' "$CLIPBOARD_FILE"
}

@test "clipso user@host:/path ssh failure: dies with actionable message" {
    cat > "$BIN/ssh" <<'FAKE'
#!/usr/bin/env bash
printf 'fake ssh: permission denied\n' >&2
exit 255
FAKE
    chmod +x "$BIN/ssh"

    # warn() writes to /dev/tty (not captured by BATS run); die() writes to
    # stderr (captured). Assert only on what BATS can observe here: status
    # and the die() message.
    run bash "$CLIPSO" "u@remote.invalid:/etc/hosts" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *'failed to read remote file'* ]]
}

@test "clipso --to <alias> <file> sends the payload via nclip-send" {
    export NOEMAP_BASE="$BATS_TEST_TMPDIR/noemap"
    mkdir -p "$NOEMAP_BASE/bin" "$NOEMAP_BASE/state"
    cat > "$NOEMAP_BASE/bin/nclip-send" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$NCLIP_ALIASES_FILE"
cat >> "$NCLIP_PAYLOAD_FILE"
FAKE
    chmod +x "$NOEMAP_BASE/bin/nclip-send"
    export NCLIP_ALIASES_FILE="$BATS_TEST_TMPDIR/nclip-aliases"
    export NCLIP_PAYLOAD_FILE="$BATS_TEST_TMPDIR/nclip-payload"
    : > "$NCLIP_ALIASES_FILE"
    : > "$NCLIP_PAYLOAD_FILE"
    printf 'tx2|x\n' > "$NOEMAP_BASE/state/devices.db"

    src="$BATS_TEST_TMPDIR/to-src.txt"
    printf 'to-alias-payload-line\n' > "$src"

    run bash "$CLIPSO" --to tx2 "$src" </dev/null
    [ "$status" -eq 0 ]

    # send_to_remotes forks nclip-send in the background; poll briefly.
    i=0
    while [ $i -lt 30 ] && [ ! -s "$NCLIP_ALIASES_FILE" ]; do
        sleep 0.1
        i=$((i+1))
    done

    [ "$(cat "$NCLIP_ALIASES_FILE")" = "tx2" ]
    grep -q 'to-alias-payload-line' "$NCLIP_PAYLOAD_FILE"
}
