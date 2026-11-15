#!/usr/bin/env bash
# Deterministic boundary tests for the complexity-ratio gate. No timing occurs.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bench/policy.bash
source "$SCRIPT_DIR/../../bench/policy.bash"

passed=0
failed=0
for pair in 'zig default' 'rust rust-cli'; do
	read -r backend package <<< "$pair"
	if [[ $(benchmark_package "$backend") == "$package" ]]; then passed=$((passed+1)); else failed=$((failed+1)); fi
done
if benchmark_package invalid >/dev/null 2>&1; then failed=$((failed+1)); else passed=$((passed+1)); fi

ratios=(1.499 1.500 2.999 3.000)
expected=(fail pass pass fail)

for i in "${!ratios[@]}"; do
	actual=$(complexity_ratio_verdict "${ratios[$i]}")
	if [[ "$actual" == "${expected[$i]}" ]]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		printf 'ratio %s: expected %s, got %s\n' \
			"${ratios[$i]}" "${expected[$i]}" "$actual" >&2
	fi
done

startup_multiples=(4.999 5.000)
expected=(fail pass)
for i in "${!startup_multiples[@]}"; do
	actual=$(complexity_workload_verdict "${startup_multiples[$i]}")
	if [[ "$actual" == "${expected[$i]}" ]]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		printf 'startup multiple %s: expected %s, got %s\n' \
			"${startup_multiples[$i]}" "${expected[$i]}" "$actual" >&2
	fi
done

printf 'benchmark_policy: %d passed, %d failed\n' "$passed" "$failed"
exit "$failed"
