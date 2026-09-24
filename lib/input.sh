#!/usr/bin/env bash
# input.sh -- input detection and read (stdin | local file | remote ssh)

# Globals set by input_read: TMP, IS_REMOTE, IS_STDIN, REMOTE_USER/HOST/PATH, SSH_PORT
input_detect_remote() {
    [[ "${1:-}" =~ ^([^@]+)@([^:]+):(.+)$ ]] || return 1
    REMOTE_USER="${BASH_REMATCH[1]}"
    REMOTE_HOST="${BASH_REMATCH[2]}"
    REMOTE_PATH="${BASH_REMATCH[3]}"
    return 0
}

# input_read <target> <tmp_file>
#   target: '' (stdin via pipe), '-' (stdin explicit), file path, or user@host:/path
input_read() {
    local target="${1:-}" tmp="$2"
    local is_stdin=false is_remote=false

    if [ ! -t 0 ] && [ -z "$target" ]; then is_stdin=true; fi
    if [ "$target" = "-" ]; then is_stdin=true; fi

    if [ "$is_stdin" = false ] && input_detect_remote "$target"; then
        is_remote=true
    fi

    if [ "$is_stdin" = false ] && [ -z "$target" ]; then
        die "usage:
  clipso <file>
  clipso user@host:/path/file
  clipso -p <port> user@host:/file
  clipso -
  echo hello | clipso"
    fi

    IS_STDIN="$is_stdin"
    IS_REMOTE="$is_remote"

    if [ "$is_stdin" = true ]; then
        cat > "$tmp"
    elif [ "$is_remote" = true ]; then
        require_cmd ssh
        local safe_path err
        safe_path="$(printf '%s' "$REMOTE_PATH" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
        if ! ssh \
            -p "${SSH_PORT:-22}" \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            "${REMOTE_USER}@${REMOTE_HOST}" \
            "cat ${safe_path}" > "$tmp" 2>"${tmp}.err"
        then
            err="$(cat "${tmp}.err")"
            rm -f "${tmp}.err"
            [ -n "$err" ] && warn "ssh said: ${err}"
            die "failed to read remote file -- check host, port, key auth, and path"
        fi
        rm -f "${tmp}.err"
        ok "remote file streamed"
    else
        [ -f "$target" ] || die "file not found: $target"
        [ -r "$target" ] || die "file not readable: $target"
        cat "$target" > "$tmp"
    fi
}
