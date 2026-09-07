#!/usr/bin/env bash
# play-confirm.sh — play a short sound on successful clipboard copy (Termux only)
# Extracted from clipso.sh so it can be reused by other tools (e.g. noemap's
# nclip-listen) without sourcing all of clipso.sh.
#
# Usage:
#   source play-confirm.sh   # defines _play_confirm; caller invokes it
#   ./play-confirm.sh        # runs _play_confirm immediately (CLIP_ENV must be set by caller)

_CONFIRM_WAV="${HOME}/.local/share/miau-dio/audio/a00287d0.wav"

_play_confirm() {
    [ "${CLIP_ENV:-}" = "termux" ] || return 0

    if ! command -v play >/dev/null 2>&1; then
        printf '[WARN] play-confirm: play (sox) not found -- no confirmation sound available\n' >&2
        return 1
    fi

    if [ -f "$_CONFIRM_WAV" ]; then
        if play -q "$_CONFIRM_WAV" >/dev/null 2>&1; then
            return 0
        fi
        printf '[WARN] play-confirm: %s found but playback failed\n' "$_CONFIRM_WAV" >&2
        return 1
    fi

    printf '[WARN] play-confirm: sound file missing at %s\n' "$_CONFIRM_WAV" >&2
    printf '[WARN] play-confirm: regenerate it with: miau-dio play-saved a00287d0\n' >&2

    if play -q -n synth 0.08 sine 880 vol 0.6 >/dev/null 2>&1; then
        return 0
    fi
    printf '[WARN] play-confirm: fallback tone also failed\n' >&2
    return 1
}

# If executed directly (not sourced), run it now.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    _play_confirm
fi
