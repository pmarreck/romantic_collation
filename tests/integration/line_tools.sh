#!/usr/bin/env bash
# Integration test: line-oriented CLI tools that sit outside collation itself.
#   trailing CR is stripped when a line is split (CRLF input, LF output)
#   -r/--reverse sorts descending without reversing equal-key arrival order
#   -u/--unique keeps one row per equal sort key (not per raw line)
#   -o/--output writes to a file, stdout, or stderr
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="${COLLATE_CLI:-$REPO_ROOT/zig-out/bin/collate}"
if [[ -z "${COLLATE_CLI:-}" && ! -x "$CLI" ]]; then CLI="$REPO_ROOT/result/bin/collate"; fi
if [[ ! -x "$CLI" ]]; then echo "FAIL: CLI not built; run ./build" >&2; exit 1; fi

WORK="${TMPDIR:-/tmp}/collate_line_tools.$$"
mkdir -p "$WORK"
trap 'command rm -rf "$WORK" 2>/dev/null' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# ── CRLF: the CR is not part of the line, and output is LF ──
printf 'file10\r\nfile2\r\n' > "$WORK/crlf.txt"
out=$("$CLI" "$WORK/crlf.txt" 2>/dev/null)
if [[ "$out" == $'file2\nfile10' ]]; then
	pass "CRLF input sorts as LF and emits LF"
else
	fail "CRLF input got $(printf '%s' "$out" | od -An -tx1)"
fi

# A trailing CR must not change a last -t field.
printf 'a,10\r\nb,2\r\n' > "$WORK/crlf-fields.txt"
out=$("$CLI" -t, -k2 "$WORK/crlf-fields.txt" 2>/dev/null)
if [[ "$out" == $'b,2\na,10' ]]; then
	pass "CRLF does not stick to the last field"
else
	fail "CRLF field sort got '$out'"
fi

# ── reverse ──
out=$(printf 'b\na\nc\n' | "$CLI" -r 2>/dev/null)
if [[ "$out" == $'c\nb\na' ]]; then
	pass "-r reverses house order"
else
	fail "-r got '$out'"
fi
out=$(printf 'b\na\nc\n' | "$CLI" --reverse 2>/dev/null)
if [[ "$out" == $'c\nb\na' ]]; then
	pass "--reverse matches -r"
else
	fail "--reverse got '$out'"
fi

# ── unique by sort key, not by raw bytes ──
# A space and a tab are the same whitespace element. The kept line is the one
# encountered first in the input, independent of its byte spelling.
out=$(printf ' \n\t\nz\n' | "$CLI" -u 2>/dev/null)
if [[ "$out" == $' \nz' ]]; then
	pass "-u collapses equal whitespace keys and keeps the first"
else
	fail "-u whitespace got $(printf '%s' "$out" | od -An -tx1)"
fi
# Case is a real tertiary distinction, so both lines stay. A raw duplicate drops.
out=$(printf 'Apple\napple\napple\n' | "$CLI" --unique 2>/dev/null)
if [[ "$out" == $'apple\nApple' ]]; then
	pass "--unique keeps case-distinct keys and drops a raw duplicate"
else
	fail "--unique case got '$out'"
fi
# Default mode keeps the leading-zero distinction. Numeric mode does not:
# 01 and 1 are one key there, and stability keeps the first input, "1".
out=$(printf '1\n01\n2\n' | "$CLI" -u 2>/dev/null)
if [[ "$out" == $'01\n1\n2' ]]; then
	pass "-u keeps a default-mode leading-zero distinction"
else
	fail "-u default leading-zero got '$out'"
fi
out=$(printf '1\n01\n2\n' | "$CLI" -n -u 2>/dev/null)
if [[ "$out" == $'1\n2' ]]; then
	pass "-u collapses equal numeric keys"
else
	fail "-u numeric got '$out'"
fi
# Descending mode retains the same first-input representative.
out=$(printf ' \n\t\nz\n' | "$CLI" -u -r 2>/dev/null)
if [[ "$out" == $'z\n ' ]]; then
	pass "-u -r keeps the first input representative"
else
	fail "-u -r got $(printf '%s' "$out" | od -An -tx1)"
fi

# ── output path ──
printf 'b\na\n' > "$WORK/in.txt"
"$CLI" -o "$WORK/out.txt" "$WORK/in.txt" >/dev/null 2>&1
rc=$?
got=$(cat "$WORK/out.txt" 2>/dev/null || true)
if [[ $rc -eq 0 && "$got" == $'a\nb' ]]; then
	pass "-o writes the sorted lines"
else
	fail "-o rc=$rc got '$got'"
fi

# -o of the input path must not truncate before the read.
printf 'b\na\n' > "$WORK/inplace.txt"
"$CLI" -o "$WORK/inplace.txt" "$WORK/inplace.txt" >/dev/null 2>&1
rc=$?
got=$(cat "$WORK/inplace.txt")
if [[ $rc -eq 0 && "$got" == $'a\nb' ]]; then
	pass "-o of the input file sorts in place"
else
	fail "-o inplace rc=$rc got '$got'"
fi

out=$(printf 'b\na\n' | "$CLI" -o - 2>/dev/null)
if [[ "$out" == $'a\nb' ]]; then
	pass "-o - is stdout"
else
	fail "-o - got '$out'"
fi
out=$(printf 'b\na\n' | "$CLI" --output @stdout 2>/dev/null)
if [[ "$out" == $'a\nb' ]]; then
	pass "--output @stdout is stdout"
else
	fail "--output @stdout got '$out'"
fi

# @stderr: sorted lines on stderr, stdout empty.
stdout=$(printf 'b\na\n' | "$CLI" -o @stderr 2>"$WORK/err.txt")
err=$(cat "$WORK/err.txt")
if [[ -z "$stdout" && "$err" == $'a\nb' ]]; then
	pass "-o @stderr writes the sort and leaves stdout empty"
else
	fail "-o @stderr stdout='$stdout' stderr='$err'"
fi

stdout=$("$CLI" --output 2>"$WORK/missing-output.txt")
rc=$?
err=$(cat "$WORK/missing-output.txt")
if [[ $rc -eq 2 && -z "$stdout" && "$err" == *"requires"* ]]; then
	pass "--output without a path exits 2"
else
	fail "--output missing rc=$rc stdout='$stdout' stderr='$err'"
fi

stdout=$("$CLI" -o "$WORK/no/such/dir/out.txt" "$WORK/in.txt" 2>/dev/null)
rc=$?
if [[ $rc -eq 1 && -z "$stdout" ]]; then
	pass "unwritable -o exits 1 with clean stdout"
else
	fail "unwritable -o rc=$rc stdout='$stdout'"
fi

# A path with a space.
printf 'b\na\n' | "$CLI" -o "$WORK/out file.txt" >/dev/null 2>&1
got=$(cat "$WORK/out file.txt" 2>/dev/null || true)
if [[ "$got" == $'a\nb' ]]; then
	pass "-o accepts a path with spaces"
else
	fail "-o spaces got '$got'"
fi

echo ""
echo "line_tools: $PASS passed, $FAIL failed"
exit $FAIL
