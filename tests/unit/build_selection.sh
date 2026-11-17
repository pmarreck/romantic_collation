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
		ln -s collate "$work/packages/$package/bin/romantic-collate"
	done
done < build-targets.tsv
export PATH="$work/tools:$PATH"
cd "$project" || exit 1
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
valid_alias() {
	local dir=$1
	[[ -L $dir/romantic-collate && $(readlink "$dir/romantic-collate") == collate &&
	   $dir/romantic-collate -ef $dir/collate && -x $dir/romantic-collate ]]
}
alias_runs() {
	local dir=$1 input=$'file10\nfile2' expected=$'file2\nfile10' canonical alias
	canonical=$("$dir/collate" <<< "$input") || return 1
	alias=$("$dir/romantic-collate" <<< "$input") || return 1
	[[ $canonical == "$expected" && $alias == "$canonical" ]]
}
for cli in "$RCOL_DEFAULT_CLI" "$RCOL_ZIG_CLI" "$RCOL_RUST_CLI" "$RCOL_RUST_PRODUCT_CLI"; do
	check valid_alias "${cli%/*}"
	check alias_runs "${cli%/*}"
done
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
check valid_alias bin/linux-amd64
old=$(readlink result)
check success canonize rust
check test "$(readlink result)" = "$old"
check test "$(cat CANONICAL_IMPL)" = rust
ln CANONICAL_IMPL "$work/persisted-selection"
check success canonize rust
check test CANONICAL_IMPL -ef "$work/persisted-selection"
check success
check test "$(readlink result)" = rust-out/linux-amd64/gnu/release
check valid_alias bin/linux-amd64
check test bin/linux-amd64/romantic-collate -ef rust-out/linux-amd64/gnu/release/bin/collate
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
fixture_alias="$work/packages/linux-amd64/bin/romantic-collate"
mv "$fixture_alias" "$work/package-alias" || exit 1
check rejected
check test "$(readlink result)" = "$old"
check valid_alias bin/linux-amd64
mv "$work/package-alias" "$fixture_alias" || exit 1
mv bin/linux-amd64/romantic-collate "$work/saved-alias" || exit 1
ln -s not-collate bin/linux-amd64/romantic-collate || exit 1
check rejected
check test "$(readlink bin/linux-amd64/romantic-collate)" = not-collate
check test "$(readlink result)" = "$old"
mv bin/linux-amd64/romantic-collate "$work/foreign-alias" || exit 1
printf 'unmanaged\n' > bin/linux-amd64/romantic-collate
check rejected
check test "$(<bin/linux-amd64/romantic-collate)" = unmanaged
check test "$(readlink result)" = "$old"
mv bin/linux-amd64/romantic-collate "$work/foreign-file" || exit 1
mv "$work/saved-alias" bin/linux-amd64/romantic-collate || exit 1
for value in '' unknown ' zig' $'zig\nzig' $'zig\n\n' '$(touch escaped)'; do
	printf '%s' "$value" > CANONICAL_IMPL
	check rejected
done
check test ! -e escaped
printf zig > CANONICAL_IMPL
check success
ln CANONICAL_IMPL "$work/bare-selection"
check success canonize zig
check test CANONICAL_IMPL -ef "$work/bare-selection"
check rejected canonize rust --all
check rejected --impl invalid
check rejected --unknown
printf 'build_selection: %d passed, %d failed\n' "$pass" "$fail"
exit "$fail"
