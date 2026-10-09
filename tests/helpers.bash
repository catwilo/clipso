# helpers.bash -- shared setup for clipso BATS tests.
# Each test runs in an isolated HOME/XDG/TMPDIR; the repo under test is a
# copy inside BATS_TEST_TMPDIR so no real state is ever touched.
# A fake termux-clipboard-set captures the payload to a plain file.

setup_env() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_CONFIG_HOME="$HOME/.config"
    export TMPDIR="$BATS_TEST_TMPDIR/tmp"
    export PREFIX="$BATS_TEST_TMPDIR/prefix"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$TMPDIR" "$PREFIX/bin"

    export BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN"
    cat > "$BIN/termux-clipboard-set" << 'FAKE_EOF'
#!/usr/bin/env bash
cat > "$CLIPBOARD_FILE"
FAKE_EOF
    chmod +x "$BIN/termux-clipboard-set"
    export CLIPBOARD_FILE="$BATS_TEST_TMPDIR/clipboard"
    export PATH="$BIN:$PATH"

    export REPO="$BATS_TEST_TMPDIR/repo"
    cp -a "$BATS_TEST_DIRNAME/.." "$REPO"
    rm -rf "$REPO/.git"
    export CLIPSO="$REPO/clipso.sh"
    export PTY_RUN="$REPO/lib/pty_run.sh"
    export STATE="$XDG_CACHE_HOME/pty-run"
    export HIST="$STATE/history"
}

write_script() {
    local path="$1"
    shift
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "$*"
    } > "$path"
    chmod +x "$path"
}
