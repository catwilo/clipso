#!/usr/bin/env bash
# tests/run.sh -- pretty BATS runner.
# One line per test: [N/total] PASS|FAIL file :: title. No carriage
# returns, no in-place counter updates -- a paste of the whole output is
# complete and ordered. Failure details are printed under the line as
# indented comment lines.
#
# Usage: bash tests/run.sh

set -u

# Colors: honor NO_COLOR and non-tty stdout (definitions must exist before
# the first printf that references them, since `set -u` is active).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    GREEN=$'\033[32m' RED=$'\033[31m' DIM=$'\033[2m' RESET=$'\033[0m'
else
    GREEN='' RED='' DIM='' RESET=''
fi

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BATS="${BATS:-$(command -v bats 2>/dev/null || true)}"
[ -n "$BATS" ] && [ -x "$BATS" ] || {
    printf '[ERROR] bats not found in PATH (run: bash install.sh test)\n' >&2
    exit 1
}

shopt -s nullglob
FILES=("$TESTS_DIR"/*.bats)
shopt -u nullglob
[ "${#FILES[@]}" -gt 0 ] || { printf '[WARN] no .bats files in %s\n' "$TESTS_DIR" >&2; exit 0; }

TOTAL=0
for f in "${FILES[@]}"; do
    n="$("$BATS" --count "$f" 2>/dev/null || echo 0)"
    TOTAL=$((TOTAL + n))
done
[ "$TOTAL" -gt 0 ] || { printf '[WARN] bats counted 0 tests\n' >&2; exit 0; }

printf '[INFO] running %d test(s) across %d file(s)\n' "$TOTAL" "${#FILES[@]}"

IDX=0
PASS=0
FAIL=0
for f in "${FILES[@]}"; do
    fname="$(basename "$f")"
    # Silence the display that would otherwise print on /dev/tty and interleave
    # with the per-test lines. Content is kept per file; it is shown only if
    # that file had a failure, as a "details" block under the failing line.
    _tty_file="$(mktemp "${TMPDIR:-/tmp}/clipso-tty.XXXXXX")"
    export CLIPSO_TTY_FILE="$_tty_file"
    _file_failed=0
    while IFS= read -r line; do
        case "$line" in
            ok\ *)
                IDX=$((IDX + 1))
                title="${line#ok *}"; title="${title#* }"
                printf '[%3d/%d] %sPASS%s %s :: %s\n' "$IDX" "$TOTAL" "$GREEN" "$RESET" "$fname" "$title"
                PASS=$((PASS + 1))
                ;;
            not\ ok\ *)
                IDX=$((IDX + 1))
                title="${line#not ok *}"; title="${title#* }"
                printf '[%3d/%d] %sFAIL%s %s :: %s\n' "$IDX" "$TOTAL" "$RED" "$RESET" "$fname" "$title"
                FAIL=$((FAIL + 1))
                _file_failed=1
                ;;
            '# '\ *)
                printf '           %s%s%s\n' "$DIM" "${line#\# }" "$RESET"
                ;;
        esac
    done < <("$BATS" --tap "$f" 2>&1)

    if [ "$_file_failed" -eq 1 ] && [ -s "$_tty_file" ]; then
        printf '           %s--- tty output (%s) ---%s\n' "$DIM" "$fname" "$RESET"
        sed 's/^/           /' "$_tty_file"
    fi
    rm -f "$_tty_file"
    unset CLIPSO_TTY_FILE
done

printf '\n[INFO] %d passed, %d failed, %d total\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
