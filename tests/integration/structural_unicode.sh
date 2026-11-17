#!/usr/bin/env bash
set -u
# Use UTF-8 byte escapes, not locale-dependent Bash \u expansion.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cli=${COLLATE_CLI:-$root/result/bin/collate}
[[ -x $cli ]] || { echo "missing CLI: $cli" >&2; exit 1; }
pass=0; fail=0
check() {
	local label=$1 expected=$2 input=$3
	shift 3
	local actual status
	actual=$(printf '%s' "$input" | "$cli" "$@" 2>&1); status=$?
	if [[ $status == 0 && $actual == "$expected" ]]; then pass=$((pass+1)); else
		printf 'FAIL: %s (status %s): got %q, expected %q\n' "$label" "$status" "$actual" "$expected" >&2
		fail=$((fail+1))
	fi
}
check 'EN SPACE and em dash precede letters' $'a\xE2\x80\x82\na—\naa' $'aa\na—\na\xE2\x80\x82\n'
check 'Unicode punctuation precedes numbers and letters' $'a.\na،\na—\na…\na、\na，\na0\naa' $'aa\na，\na0\na、\na…\na—\na،\na.\n'
check 'Unicode spaces retain whitespace equivalence' 'a ' $'a \na\xC2\x85\na\xE1\x9A\x80\na\xE2\x80\x82\na\xE2\x80\xA8\na\xE2\x81\x9F\na\xE3\x80\x80\n' -u
check 'format controls are not whitespace' $'aa\na\xE2\x80\x8B\na\xE2\x81\xA0\na\xEF\xBB\xBF' $'a\xEF\xBB\xBF\na\xE2\x81\xA0\na\xE2\x80\x8B\naa\n'
check 'non-ASCII symbols retain their existing class' $'a$\naa\na€\na😀' $'a😀\na€\naa\na$\n'
check 'code-point order is unchanged' $'aa\na\xE2\x80\x82\na—' $'a—\na\xE2\x80\x82\naa\n' --code-point
check 'reverse retains the corrected ordering' $'aa\na—\na\xE2\x80\x82' $'aa\na—\na\xE2\x80\x82\n' -r
check 'field sorting uses corrected structural order' $'3:a\xE2\x80\x82\n2:a—\n1:aa' $'1:aa\n2:a—\n3:a\xE2\x80\x82\n' -t: -k2
printf 'structural_unicode: %d passed, %d failed\n' "$pass" "$fail"
exit "$fail"
