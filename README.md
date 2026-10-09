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

`clipso history [N]` lists the N most recent runs (default 20), newest
first:

    <when>  <hash>  $ <first line of the command>

### Retention

`history/` is bounded by `CLIPSO_HISTORY_MAX` (default 200 entries; one
entry = `<hash>.cmd` + `<hash>.out`). After every run the oldest entries
past the limit are dropped. Set a different cap in
`~/.config/clipso/config`:

    CLIPSO_HISTORY_MAX=500

Set it to `0` to disable pruning (unbounded history -- not recommended).

### State

`~/.cache/pty-run/` holds the guard state and history:

- `last_cmd.sha256` -- hash of the last run
- `last_cmd` -- last command body
- `last_output` -- last normalized output (ANSI stripped, same bytes as clipboard)
- `history/<hash>.{cmd,out}` -- per-run record, never touched by `reset`

    clipso reset

Disarms the guard (drops last-run state), sweeps orphan temp files older
than 5 minutes from `$TMPDIR`, and preserves `history/`.

## Confirmation sounds

`play-confirm` plays the confirmation WAVs. Installed as a command
(symlinked into `PATH`), it works with no arguments or with an explicit
selector:

    play-confirm             play the next WAV in the rotation (1, 2, 3, ...)
    play-confirm 2           play 2.wav directly, bypassing the rotation
    play-confirm repeated    play specials/repeated.wav

The rotation advances a counter stored in `.last` next to the WAVs. `N`
and `name` invocations leave the counter untouched. Unknown selectors
warn and exit 0 without playing anything. On non-Termux hosts it is a
silent no-op. Every call runs in the background and never blocks the
shell.

Resolution order for an argument `X`:

    1. `X` matches `specials/...`  -> play specials/<X-without-prefix>
    2. `X` exists as `X.wav`       -> play it (numeric path)
    3. `X` exists as `specials/X.wav` -> play it (name path)
    4. otherwise                   -> warn, exit 0, play nothing

So a special named `2` is reachable as `play-confirm specials/2`, and a
numerically-named selector without a matching WAV falls back to the
specials directory instead of erroring.

`CLIP_ENV` is autodetected when the command is invoked directly; the
symlink is resolved with `readlink -f` before locating the modules.

### Control-sequence stripping

The pty that carries a `clipso run` payload emits two kinds of control
bytes: SGR colors (that we want to keep for display) and terminal replies
(OSC background color, CPR cursor reports) that the shell's terminal
returns when probed. The two are handled separately:

- `strip_display <file>` -- removes cursor/erase CSI, OSC replies and CPR
  reports, but **keeps SGR colors**. Used on the log before painting the
  numbered payload to the screen, so the display stays readable.
- `strip_control <file>` -- calls `strip_display` and then removes SGR too.
  Used on the payload that reaches the clipboard (`history/<hash>.out`,
  `last_output`), so a paste has no ANSI bytes at all.

Any new strip of terminal noise must decide which of these two callers it
serves. Do not merge them -- a single function would either leave colors
in the clipboard or kill them on the screen.

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
