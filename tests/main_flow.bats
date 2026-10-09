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
