#!/usr/bin/env bash
# All selector/publication mutation stays in a private, owned project tree.
set -u
root=$(pwd)
work=$(mktemp -d) || exit 1
trap 'cd "$root"; command rm -rf "$work"' EXIT
project="$work/project with spaces"
mkdir -p "$project" "$work/tools" "$work/packages/missing" || exit 1
cp build build-targets.tsv CANONICAL_IMPL "$project/" || exit 1
sed "1s|.*|#!$(command -v bash)|" tests/fixtures/build-nix > "$work/tools/nix"
sed "1s|.*|#!$(command -v bash)|" tests/fixtures/build-nix-store > "$work/tools/nix-store"
chmod +x "$work/tools/nix" "$work/tools/nix-store"
export FAKE_PACKAGE_ROOT="$work/packages"
ln -s "$RCOL_COREUTILS" "$work/packages/build-tools"
while read -r backend pf variant release debug; do
	[[ -n $backend && $backend != \#* ]] || continue
	for package in "$release" "$debug"; do
		mkdir -p "$work/packages/$package/bin"
		fixture=build-cli; [[ $backend != rust ]] || fixture=build-cli-rust
		sed "1s|.*|#!$(command -v bash)|" "$root/tests/fixtures/$fixture" > "$work/packages/$package/bin/collate"
		chmod +x "$work/packages/$package/bin/collate"
		ln -s collate "$work/packages/$package/bin/collate.exe"
	done
done < build-targets.tsv
export PATH="$work/tools:$PATH"
cd "$project" || exit 1
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
success() {
	bash ./build "$@" > "$work/log" 2>&1
	local status=$?
	[[ $status == 0 ]] || cat "$work/log" >&2
	return "$status"
}
rejected() { bash ./build "$@" > "$work/log" 2>&1; [[ $? != 0 ]]; }
check success
check test "$(readlink result)" = zig-out/linux-amd64/musl/release
check test -x bin/linux-amd64/collate
old=$(readlink result)
check success canonize rust
check test "$(readlink result)" = "$old"
check test "$(cat CANONICAL_IMPL)" = rust
check success
check test "$(readlink result)" = rust-out/linux-amd64/gnu/release
check test -x zig-out/linux-amd64/musl/release/bin/collate
check success --debug
check test "$(readlink result)" = rust-out/linux-amd64/gnu/debug
check success canonize zig
for flags in '--all' '--all-impls --all-plats' '--all-platforms --all-implementations' '--all-plats --all-impls --all-impls'; do
	: > "$FAKE_PACKAGE_ROOT/calls"
	read -r -a arguments <<< "$flags"
	check success "${arguments[@]}"
	count=$(sort -u "$FAKE_PACKAGE_ROOT/calls" | wc -l)
	check test "$count" = 7 # six products plus publication tools
done
for flags in '--all-impls' '--all-implementations'; do
	: > "$FAKE_PACKAGE_ROOT/calls"
	check success "$flags"
	check test "$(sort -u "$FAKE_PACKAGE_ROOT/calls" | wc -l)" = 3
done
for flags in '--all-plats' '--all-platforms'; do
	: > "$FAKE_PACKAGE_ROOT/calls"
	check success "$flags"
	check test "$(sort -u "$FAKE_PACKAGE_ROOT/calls" | wc -l)" = 6
done
old=$(readlink result)
old_product=$(readlink "$old")
export FAIL_PACKAGE=.#mswin-arm64
check rejected --all
unset FAIL_PACKAGE
check test "$(readlink result)" = "$old"
check test "$(readlink "$old")" = "$old_product"
export MISSING_COMMAND=.#linux-amd64
check rejected
unset MISSING_COMMAND
check test "$(readlink result)" = "$old"
for value in '' unknown ' zig' $'zig\nzig' $'zig\n\n' '$(touch escaped)'; do
	printf '%s' "$value" > CANONICAL_IMPL
	check rejected
done
check test ! -e escaped
printf zig > CANONICAL_IMPL
check success
check rejected canonize rust --all
check rejected --impl invalid
check rejected --unknown
printf 'build_selection: %d passed, %d failed\n' "$pass" "$fail"
exit "$fail"
