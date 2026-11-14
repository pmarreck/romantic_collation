#!/usr/bin/env bash
# A rejected preparation must not turn into a cached/stale passing test run.
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d) || exit 1
trap 'command rm -rf "$work"' EXIT
printf '#!%s\nif [[ "$1" == eval ]]; then echo x86_64-linux; else exit 73; fi\n' "$(command -v bash)" > "$work/nix"
chmod +x "$work/nix"
output=$(env -u NIX_BUILD_TOP PATH="$work:$PATH" bash "$root/test" 2>&1)
rc=$?
if [[ $rc == 73 && "$output" != *'passed'* ]]; then
	echo 'build_failure: 1 passed, 0 failed'
else
	echo "build_failure: 0 passed, 1 failed (status $rc)"
	exit 1
fi
