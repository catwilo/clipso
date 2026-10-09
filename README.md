# clipso

Copy local files, remote files, or stdin to the clipboard. Detects the
environment and picks the right backend, with OSC52 as the universal
fallback for SSH and headless sessions.

Targets: Termux (ARM64, non-root), Debian, Arch Linux.
Backends: `termux-clipboard-set`, `wl-copy` (Wayland), `xclip` (X11),
OSC52 escape sequence (SSH/tmux/screen/headless).

## Usage

    clipso <file>                  copy a local file
    clipso user@host:/path/file    copy a remote file over SSH
    clipso -p 2222 user@host:/f    remote with a custom SSH port
    clipso -                       read stdin
    echo hello | clipso            read piped stdin

Output is printed to the terminal with numbered lines, followed by
`[OK]` confirming the backend and byte count.

To preserve native command output and still copy it:

    { some-cmd; } 2>&1 | tee /dev/tty | clipso

Payload limit is 10 MB. Payloads over 900 KB are split into chunks
and copied page by page — press any key to advance, `q` to abort.

## SSH dual-clipboard

When run inside an SSH session, clipso copies to the server local
clipboard (if a backend is available) and also mirrors to the client
terminal via OSC52, so the content lands wherever you are.
Headless servers use OSC52 only.

## Environment

- `NO_COLOR` — disable colored output (also auto-disabled when stderr
  is not a TTY).
- `TMUX` / `STY` — detected automatically for OSC52 passthrough.
- `CLIP_FORWARD_SOCK` — override the pbcopy-forward socket path
  (default: `~/.local/share/noemap/clip.sock`).

## Repeat guard

    clipso run <script>

Wraps the shell so its output lands in the clipboard. Each run is
identified by a SHA256 of its body (shebang excluded); the hash is
prepended to the clipboard payload as a one-line header:

    [clipso]  hash=<sha256>  lines=<N>  size=<X> B

If the script body is identical to the previous run, the command is NOT
re-executed. The previous payload (hash + output) is copied to the
clipboard, a dedicated repeat sound plays, and a short prompt appears:

    repeat detected  identical to previous run
    re-execute? [y/N]

Default is `no`, so the clipboard keeps the previous run's payload. Answer
`yes` to re-execute and overwrite the clipboard with the fresh output.
Ctrl+C cancels (exit 130); Ctrl+D is `no`. The prompt only appears when
stdin is a TTY -- scripts, cron and pipes keep the old behavior (replay
and exit).

### Recorded runs

    clipso show <hash>       print the command and its recorded output
    clipso send-payload <hash>  copy the recorded payload back to the clipboard

Every run persists `history/<hash>.{cmd,out}` under `~/.cache/pty-run/`.
`show` is how a very long command is identified after the fact: the hash
travels in the clipboard; the command body stays on disk.

### State

`~/.cache/pty-run/` holds the guard state and history:

- `last_cmd.sha256` -- hash of the last run
- `last_cmd` -- last command body
- `last_output` -- last normalized output (ANSI stripped, same bytes as clipboard)
- `history/<hash>.{cmd,out}` -- per-run record, never touched by `reset`

    clipso reset

Disarms the guard (drops last-run state), sweeps orphan temp files older
than 5 minutes from `$TMPDIR`, and preserves `history/`.

## Tests

The regression suite runs on BATS-core and lives in `tests/`:

    bash install.sh test

BATS is bootstrapped automatically on first use: the installer clones
`~/bats-core` and installs the binary under `~/.local`. The suite covers
the repeat guard, the hash identifier (`show` / `send-payload`), reset
behavior (state disarm, history preserved, orphan sweep) and display
normalization (no `Script started` / `TERM` / `TTY` lines; header format).

## Dependencies

Checked by `install.sh` with actionable warnings (missing pieces never
abort the install -- clipso degrades gracefully):

- `termux-clipboard-set` (Termux only) -- `pkg install termux-api`.
  Without it, clipboard falls back to OSC52.
- `miau-dio` -- renders confirmation sounds and the repeat-guard sound.
  Without it, the guard is silent (behavior unchanged, no audio feedback).
