#!/usr/bin/env bats
# display.bats -- payload header format and log normalization.

load helpers

setup() { setup_env; }

@test "payload starts with [clipso]  hash=...  lines=N  size=X" {
    s="$BATS_TEST_TMPDIR/run.sh"
    write_script "$s" 'echo display-header-test'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    first=$(head -n1 "$CLIPBOARD_FILE")
    [[ "$first" == '[clipso]  hash='* ]]
    [[ "$first" == *'  lines='* ]]
    [[ "$first" == *'  size='* ]]
}

@test "payload contains neither Script started nor Script done" {
    s="$BATS_TEST_TMPDIR/run.sh"
    write_script "$s" 'echo normalization-test'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q 'Script started' "$CLIPBOARD_FILE"
    ! grep -q 'Script done' "$CLIPBOARD_FILE"
}

@test "payload does not contain TERM= nor TTY= lines" {
    s="$BATS_TEST_TMPDIR/run.sh"
    write_script "$s" 'echo env-test'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q 'TERM=' "$CLIPBOARD_FILE"
    ! grep -q 'TTY=' "$CLIPBOARD_FILE"
}

@test "history/<hash>.out starts with the same [clipso] header (stripped)" {
    s="$BATS_TEST_TMPDIR/run.sh"
    write_script "$s" 'echo history-header-test'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    h=$(cat "$STATE/last_cmd.sha256")
    first=$(head -n1 "$HIST/$h.out")
    [[ "$first" == '[clipso]  hash='* ]]
}

@test "payload strips OSC replies and CPR reports (terminal query leftovers)" {
    s="$BATS_TEST_TMPDIR/run.sh"
    # Write a script that emits OSC 11 (background color, ST-terminated)
    # followed by a CPR cursor report -- both with real ESC bytes. This is
    # what a terminal sends back when the pty probes it during `clipso run`.
    cat > "$s" <<'SCRIPT'
#!/usr/bin/env bash
echo -n $'\x1b]11;rgb:0000/0000/0000\x1b\\\x1b[18;7R'
echo visible-marker
SCRIPT
    chmod +x "$s"

    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    ! grep -q $'\x1b]11;rgb' "$CLIPBOARD_FILE"
    ! grep -q $'\x1b[18;7R' "$CLIPBOARD_FILE"
    grep -q 'visible-marker' "$CLIPBOARD_FILE"
}
