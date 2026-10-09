#!/usr/bin/env bats
# hash.bats -- hash identifier, clipso show, clipso send-payload.

load helpers

setup() { setup_env; }

@test "clipso show <hash> prints the recorded command with '$ ' prefix" {
    mkdir -p "$HIST"
    printf 'echo demo\n' > "$HIST/deadbeef.cmd"
    printf 'demo\n' > "$HIST/deadbeef.out"
    run bash "$CLIPSO" show deadbeef
    [ "$status" -eq 0 ]
    [[ "$output" == *'$ echo demo'* ]]
    [[ "$output" == *'demo'* ]]
}

@test "clipso show unknown hash: die with actionable error" {
    run bash "$CLIPSO" show nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"no recorded command for hash: nope"* ]]
}

@test "clipso send-payload <hash> copies the recorded payload to clipboard" {
    mkdir -p "$HIST"
    printf 'payload-body-line1\npayload-body-line2\n' > "$HIST/cafebabe.out"
    run bash "$CLIPSO" send-payload cafebabe
    [ "$status" -eq 0 ]
    got=$(cat "$CLIPBOARD_FILE")
    [[ "$got" == *'payload-body-line1'* ]]
    [[ "$got" == *'payload-body-line2'* ]]
}

@test "clipso send-payload with missing history: die" {
    run bash "$CLIPSO" send-payload deadbeef
    [ "$status" -ne 0 ]
    [[ "$output" == *"no recorded payload for hash: deadbeef"* ]]
}
