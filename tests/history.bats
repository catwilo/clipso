#!/usr/bin/env bats
# history.bats -- recorded-run listing, purge policy, and clipso history CLI.

load helpers

setup() { setup_env; }

@test "clipso history: empty history prints a clear message" {
    run bash "$CLIPSO" history
    [ "$status" -eq 0 ]
    [[ "$output" == *'no recorded runs'* ]]
}

@test "clipso history: lists entries with hash and first command line" {
    mkdir -p "$HIST"
    printf 'echo list-me\n' > "$HIST/aaaa1111.cmd"
    printf 'list-me\n'      > "$HIST/aaaa1111.out"
    run bash "$CLIPSO" history
    [ "$status" -eq 0 ]
    [[ "$output" == *'aaaa1111'* ]]
    [[ "$output" == *'$ echo list-me'* ]]
}

@test "clipso history <N> limits the number of lines" {
    mkdir -p "$HIST"
    for i in 1 2 3 4 5; do
        printf 'echo %s\n' "$i" > "$HIST/h${i}.cmd"
        printf '%s\n' "$i" > "$HIST/h${i}.out"
        sleep 0.02
    done
    run bash "$CLIPSO" history 2
    [ "$status" -eq 0 ]
    ! [[ "$output" == *'no recorded runs'* ]]
    # Each entry line ends with "$ <cmd>". Count is robust to the ANSI
    # codes that history_list paints around date and hash.
    count=$(printf '%s\n' "$output" | grep -c '  \$ ')
    [ "$count" -eq 2 ]
}

@test "history_purge: keeps only the newest CLIPSO_HISTORY_MAX entries" {
    mkdir -p "$HIST"
    for i in 1 2 3 4 5; do
        printf 'echo %s\n' "$i" > "$HIST/h${i}.cmd"
        printf '%s\n' "$i" > "$HIST/h${i}.out"
        sleep 0.02
    done
    # Source the library and purge with max=2.
    run bash -c ". '$REPO/lib/core.sh'; . '$REPO/lib/history.sh'; CLIPSO_HISTORY_MAX=2; XDG_CACHE_HOME='$XDG_CACHE_HOME' history_purge; ls '$HIST' | wc -l | tr -d ' '"
    [ "$status" -eq 0 ]
    # 2 entries x 2 files = 4 remaining.
    [ "$output" = "4" ]
}

@test "clipso run: purges old entries automatically after each run" {
    export CLIPSO_HISTORY_MAX=1
    s1="$BATS_TEST_TMPDIR/r1.sh"
    s2="$BATS_TEST_TMPDIR/r2.sh"
    write_script "$s1" 'echo first-run'
    write_script "$s2" 'echo second-run'
    run bash "$PTY_RUN" "$s1" </dev/null
    [ "$status" -eq 0 ]
    sleep 0.05
    run bash "$PTY_RUN" "$s2" </dev/null
    [ "$status" -eq 0 ]
    # Only the newest entry survives: 2 files in history/.
    count=$(ls "$HIST" | wc -l | tr -d ' ')
    [ "$count" = "2" ]
}
