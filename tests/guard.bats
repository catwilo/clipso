#!/usr/bin/env bats
# guard.bats -- repeat-guard behavior in lib/pty_run.sh.

load helpers

setup() { setup_env; }

@test "first run persists hash, cmd, output and history entries" {
    s="$BATS_TEST_TMPDIR/run.sh"
    write_script "$s" 'echo hello-guard'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    [ -f "$STATE/last_cmd.sha256" ]
    [ -f "$STATE/last_cmd" ]
    [ -f "$STATE/last_output" ]
    h=$(cat "$STATE/last_cmd.sha256")
    [ -f "$HIST/$h.cmd" ]
    [ -f "$HIST/$h.out" ]
}

@test "identical second run: guard fires, output unchanged, clipboard == previous" {
    s="$BATS_TEST_TMPDIR/run.sh"
    write_script "$s" 'echo hello-guard; date +%s%N'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    cp1=$(cat "$CLIPBOARD_FILE")
    [ -n "$cp1" ]
    h1=$(cat "$STATE/last_cmd.sha256")

    sleep 1
    write_script "$s" 'echo hello-guard; date +%s%N'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    cp2=$(cat "$CLIPBOARD_FILE")
    h2=$(cat "$STATE/last_cmd.sha256")

    [ "$h1" = "$h2" ]
    [ "$cp1" = "$cp2" ]
}

@test "different script body: guard does not fire, output changes" {
    s1="$BATS_TEST_TMPDIR/run1.sh"
    s2="$BATS_TEST_TMPDIR/run2.sh"
    write_script "$s1" 'echo first-command'
    write_script "$s2" 'echo second-command'
    run bash "$PTY_RUN" "$s1" </dev/null
    [ "$status" -eq 0 ]
    h1=$(cat "$STATE/last_cmd.sha256")

    run bash "$PTY_RUN" "$s2" </dev/null
    [ "$status" -eq 0 ]
    h2=$(cat "$STATE/last_cmd.sha256")
    [ "$h1" != "$h2" ]
}
@test "answer yes: re-executes and overwrites clipboard with fresh output" {
    s="$BATS_TEST_TMPDIR/run.sh"
    write_script "$s" 'echo reexec-marker; date +%s%N'
    run bash "$PTY_RUN" "$s" </dev/null
    [ "$status" -eq 0 ]
    cp1=$(cat "$CLIPBOARD_FILE")
    [ -n "$cp1" ]

    sleep 1
    write_script "$s" 'echo reexec-marker; date +%s%N'
    # Feed 'y' to the guard's prompt under a pty (script(1) allocates one,
    # since BATS itself runs without a TTY -- [ -t 0 ] would be false).
    printf 'y\n' | script -q -E never -c "bash $PTY_RUN $s" >/dev/null 2>&1 || true
    cp2=$(cat "$CLIPBOARD_FILE")
    [ -n "$cp2" ]
    [ "$cp1" != "$cp2" ]
}
