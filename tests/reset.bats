#!/usr/bin/env bats
# reset.bats -- guard disarm, history preservation, orphan sweep.

load helpers

setup() { setup_env; }

@test "reset removes last_cmd.sha256, last_cmd, last_output" {
    mkdir -p "$STATE"
    printf 'abc\n' > "$STATE/last_cmd.sha256"
    printf 'cmd\n' > "$STATE/last_cmd"
    printf 'out\n' > "$STATE/last_output"
    run bash "$CLIPSO" reset
    [ "$status" -eq 0 ]
    [ ! -f "$STATE/last_cmd.sha256" ]
    [ ! -f "$STATE/last_cmd" ]
    [ ! -f "$STATE/last_output" ]
}

@test "reset preserves history/ entries" {
    mkdir -p "$HIST"
    printf 'cmd\n' > "$HIST/deadbeef.cmd"
    printf 'out\n' > "$HIST/deadbeef.out"
    run bash "$CLIPSO" reset
    [ "$status" -eq 0 ]
    [ -f "$HIST/deadbeef.cmd" ]
    [ -f "$HIST/deadbeef.out" ]
}

@test "reset sweeps orphans older than 5 minutes" {
    old="$TMPDIR/clipso-run-log.OLD001"
    touch "$old"
    touch -d '10 minutes ago' "$old" 2>/dev/null || touch -t 202001010000 "$old"
    run bash "$CLIPSO" reset
    [ "$status" -eq 0 ]
    [ ! -f "$old" ]
}

@test "reset preserves orphans newer than 5 minutes" {
    fresh="$TMPDIR/clipso-run-log.NEW001"
    touch "$fresh"
    run bash "$CLIPSO" reset
    [ "$status" -eq 0 ]
    [ -f "$fresh" ]
}

@test "reset sweeps clipso-priv, clipso-rc, clipso-kb orphans" {
    for base in clipso-priv clipso-rc clipso-kb; do
        f="$TMPDIR/${base}.OLD001"
        touch "$f"
        touch -d '10 minutes ago' "$f" 2>/dev/null || touch -t 202001010000 "$f"
    done
    run bash "$CLIPSO" reset
    [ "$status" -eq 0 ]
    [ ! -f "$TMPDIR/clipso-priv.OLD001" ]
    [ ! -f "$TMPDIR/clipso-rc.OLD001" ]
    [ ! -f "$TMPDIR/clipso-kb.OLD001" ]
}

@test "reset clears the play-confirm rotation counter (.last)" {
    sounds="$XDG_CONFIG_HOME/clipso/sounds"
    mkdir -p "$sounds"
    printf '2\n' > "$sounds/.last"
    run bash "$CLIPSO" reset
    [ "$status" -eq 0 ]
    [ ! -f "$sounds/.last" ]
}

@test "reset only matches clipso mktemp patterns" {
    unrelated="$TMPDIR/some-other-tool.ABCDEF"
    touch "$unrelated"
    touch -d '10 minutes ago' "$unrelated" 2>/dev/null || touch -t 202001010000 "$unrelated"
    run bash "$CLIPSO" reset
    [ "$status" -eq 0 ]
    [ -f "$unrelated" ]
}
