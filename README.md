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

Wraps the shell so its output lands in the clipboard. If the script
body is identical to the previous run (SHA256 match), the command is
NOT re-executed: a warning is printed, a dedicated repeat sound plays,
and the cached payload from the previous run is copied to the clipboard
again. State lives in `~/.cache/pty-run/`: `last_cmd` (last command),
`last_cmd.sha256` (its hash), `last_output` (last output). The special
sound is `~/.config/clipso/sounds/specials/repeated.wav`, rendered from
`sounds/specials/repeated.abc` by `sounds/generate.sh`.
