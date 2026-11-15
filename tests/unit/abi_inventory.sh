#!/usr/bin/env bash
# Fail closed when a public declaration is not loaded by the external consumer.
set -u
work=$(mktemp -d) || exit 1
trap 'command rm -rf "$work"' EXIT
rg -o '\brcol_[a-z_]+\(' include/romantic_collation.h | sed 's/(//' | sort -u > "$work/public"
rg -o '"rcol_[a-z_]+"' tests/unit/backend_parity.c | tr -d '"' | sort -u > "$work/loaded"
if ! cmp "$work/public" "$work/loaded"; then exit 1; fi
if ! cc -shared -fPIC tests/unit/missing_export.c -o "$work/missing.so"; then exit 1; fi
"$RCOL_PARITY" "$work/missing.so" "$RCOL_RUST_SHARED" > "$work/log" 2>&1
status=$?
if [[ $status != 1 ]] || ! rg -q 'missing ABI symbol: rcol_open' "$work/log"; then
	cat "$work/log"
	echo 'ABI missing-export negative control failed' >&2
	exit 1
fi
echo 'abi_inventory: 2 passed, 0 failed'
