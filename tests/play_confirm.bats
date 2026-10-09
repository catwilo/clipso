#!/usr/bin/env bats
# play_confirm.bats -- dispatcher for play-confirm.sh:
#   (no arg)  -> rotation, advances .last
#   <N>       -> plays N.wav, does not touch .last
#   <name>    -> plays specials/<name>.wav, does not touch .last
#   CLIP_ENV != termux -> silent no-op

load helpers

setup() {
    setup_env

    # Fake audio: paplay appends the played file path to $PLAYED_FILE.
    # Fake setsid: executes its args directly (Termux may not ship setsid).
    cat > "$BIN/paplay" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$PLAYED_FILE"
FAKE
    chmod +x "$BIN/paplay"

    cat > "$BIN/setsid" << 'FAKE'
#!/usr/bin/env bash
"$@"
FAKE
    chmod +x "$BIN/setsid"

    export PLAYED_FILE="$BATS_TEST_TMPDIR/played"
    : > "$PLAYED_FILE"

    export CLIP_ENV=termux
    export SOUNDS="$XDG_CONFIG_HOME/clipso/sounds"
    mkdir -p "$SOUNDS/specials"
    : > "$SOUNDS/1.wav"
    : > "$SOUNDS/2.wav"
    : > "$SOUNDS/3.wav"
    : > "$SOUNDS/specials/repeated.wav"

    export PC="$REPO/play-confirm.sh"
}

_wait_played() {
    local i=0
    while [ $i -lt 25 ]; do
        [ -s "$PLAYED_FILE" ] && return 0
        sleep 0.1
        i=$((i+1))
    done
    return 0
}

@test "no args: rotation plays 1.wav then 2.wav, advancing .last" {
    run bash "$PC" </dev/null
    [ "$status" -eq 0 ]
    _wait_played
    [[ "$(tail -n1 "$PLAYED_FILE")" == */1.wav ]]
    [ "$(cat "$SOUNDS/.last")" = "1" ]

    run bash "$PC" </dev/null
    [ "$status" -eq 0 ]
    sleep 0.4
    [[ "$(tail -n1 "$PLAYED_FILE")" == */2.wav ]]
    [ "$(cat "$SOUNDS/.last")" = "2" ]
}

@test "numeric arg: plays exactly that WAV, .last untouched" {
    printf '9\n' > "$SOUNDS/.last"
    run bash "$PC" 3 </dev/null
    [ "$status" -eq 0 ]
    _wait_played
    [[ "$(tail -n1 "$PLAYED_FILE")" == */3.wav ]]
    [ "$(cat "$SOUNDS/.last")" = "9" ]
}

@test "named arg: plays specials/<name>.wav, .last untouched" {
    printf '2\n' > "$SOUNDS/.last"
    run bash "$PC" repeated </dev/null
    [ "$status" -eq 0 ]
    _wait_played
    [[ "$(tail -n1 "$PLAYED_FILE")" == */specials/repeated.wav ]]
    [ "$(cat "$SOUNDS/.last")" = "2" ]
}

@test "numeric arg not present as N.wav falls back to specials/<N>" {
    : > "$SOUNDS/specials/7.wav"
    rm -f "$SOUNDS/7.wav"
    run bash "$PC" 7 </dev/null
    [ "$status" -eq 0 ]
    _wait_played
    [[ "$(tail -n1 "$PLAYED_FILE")" == */specials/7.wav ]]
}

@test "specials/<name> forces the name route even for numeric names" {
    : > "$SOUNDS/2.wav"
    : > "$SOUNDS/specials/2.wav"
    run bash "$PC" specials/2 </dev/null
    [ "$status" -eq 0 ]
    _wait_played
    played="$(tail -n1 "$PLAYED_FILE")"
    [ "$played" = "$SOUNDS/specials/2.wav" ]
    [ "$played" != "$SOUNDS/2.wav" ]
}

@test "numeric arg with no matching WAV and no special warns, plays nothing" {
    run bash "$PC" 99 </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"no such sound: 99"* ]]
    [ ! -s "$PLAYED_FILE" ]
}

@test "unknown name: warns, exits 0, plays nothing" {
    run bash "$PC" nope </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"no such sound"* ]]
    [ ! -s "$PLAYED_FILE" ]
}

@test "CLIP_ENV != termux: silent no-op" {
    export CLIP_ENV=x11
    run bash "$PC" </dev/null
    [ "$status" -eq 0 ]
    [ ! -s "$PLAYED_FILE" ]
}

@test "rotation wraps: after last .wav the next is 1.wav" {
    printf '3\n' > "$SOUNDS/.last"
    run bash "$PC" </dev/null
    [ "$status" -eq 0 ]
    _wait_played
    [ "$(tail -n1 "$PLAYED_FILE")" = "$SOUNDS/1.wav" ]
    [ "$(cat "$SOUNDS/.last")" = "1" ]
}
