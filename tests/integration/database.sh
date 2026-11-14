#!/usr/bin/env bash
# Runs only against private, disposable databases in the Nix check sandbox.
set -u
PASS=0
FAIL=0
check() {
	if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); else
		echo "FAIL: $1: expected '$3', got '$2'" >&2
		FAIL=$((FAIL+1))
	fi
}
work=$(mktemp -d) || exit 1
trap 'if [[ -f "$work/pg/postmaster.pid" ]]; then pg_ctl -D "$work/pg" -m immediate stop >/dev/null 2>&1; fi; command rm -rf "$work"' EXIT
sqlite_ext=${RCOL_SQLITE_EXTENSION:?Nix must supply the SQLite extension}
pg_ext=${RCOL_PG_EXTENSION:?Nix must supply the PostgreSQL extension}
sq() { printf '.load %s\n%s\n' "$sqlite_ext" "$1" | sqlite3 -bail :memory:; }
check 'SQLite natural numeric order' "$(sq "SELECT romantic_key_v1('file2') < romantic_key_v1('file10');")" 1
check 'SQLite NULL propagates' "$(sq "SELECT romantic_key_v1(NULL) IS NULL;")" 1
check 'SQLite NULL options propagate' "$(sq "SELECT romantic_key_v1('a',NULL) IS NULL;")" 1
check 'SQLite embedded NUL preserved' "$(sq "SELECT romantic_key_v1('a'||char(0)||'b') != romantic_key_v1('a');")" 1
check 'SQLite decimal option' "$(sq "SELECT romantic_key_v1('1.10',8) < romantic_key_v1('1.9',8);")" 1
check 'SQLite Roman option' "$(sq "SELECT romantic_key_v1('VII',64) < romantic_key_v1('IX',64);")" 1
check 'SQLite arbitrary exponent' "$(sq "SELECT romantic_key_v1('1e9999999999',32) < romantic_key_v1('1e10000000000',32);")" 1
check 'SQLite exponent normalization' "$(sq "SELECT romantic_key_v1('10e99999999999999999999',32) = romantic_key_v1('1e100000000000000000000',32);")" 1
check 'SQLite canonical equality' "$(sq "SELECT romantic_key_v1('ș') = romantic_key_v1('ş');")" 1
check 'SQLite long key' "$(sq "SELECT length(romantic_key_v1(printf('%10000s','a'))) > 10000;")" 1
for invalid in -1 128 4294967296 "'oops'"; do
	out=$(sq "SELECT romantic_key_v1('a',$invalid);" 2>&1); rc=$?
	check "SQLite rejects options $invalid" "$((rc != 0))" 1
done
out=$(sq "PRAGMA trusted_schema=OFF; CREATE TABLE t(v TEXT); INSERT INTO t VALUES('file10'),('file2'),('Apple'),('apple'); CREATE INDEX ix ON t(romantic_key_v1(v)); SELECT group_concat(v,',') FROM (SELECT v FROM t INDEXED BY ix ORDER BY romantic_key_v1(v)); SELECT group_concat(v,',') FROM (SELECT v FROM t NOT INDEXED ORDER BY romantic_key_v1(v));")
check 'SQLite indexed/unindexed order agrees' "$out" $'apple,Apple,file2,file10\napple,Apple,file2,file10'
out=$(sq "CREATE TABLE t(v TEXT); CREATE INDEX ix ON t(romantic_key_v1(v)); EXPLAIN QUERY PLAN SELECT v FROM t ORDER BY romantic_key_v1(v);")
check 'SQLite uses expression index' "$([[ "$out" == *'USING INDEX ix'* ]] && echo yes)" yes

# No network listeners, no existing cluster, unique Unix socket directory.
initdb -D "$work/pg" -A trust --no-locale -E UTF8 >"$work/init.log" 2>&1 || { cat "$work/init.log"; exit 1; }
pg_ctl -D "$work/pg" -l "$work/server.log" -o "-k $work -c listen_addresses='' -c fsync=off" -w start >"$work/start.log" 2>&1 || { cat "$work/server.log"; exit 1; }
psql_args=(-X -h "$work" -d postgres -v ON_ERROR_STOP=1 -Atq)
sed "s|MODULE_PATHNAME|$pg_ext|g" "${RCOL_PG_SQL:?Nix must supply installation SQL}" | psql "${psql_args[@]}" || exit 1
pg() { psql "${psql_args[@]}" -c "$1"; }
check 'PostgreSQL natural numeric order' "$(pg "SELECT romantic_key_v1('file2') < romantic_key_v1('file10');")" t
check 'PostgreSQL NULL propagates' "$(pg "SELECT romantic_key_v1(NULL) IS NULL;")" t
check 'PostgreSQL NULL options propagate' "$(pg "SELECT romantic_key_v1('a',NULL) IS NULL;")" t
check 'PostgreSQL decimal option' "$(pg "SELECT romantic_key_v1('1.10',8) < romantic_key_v1('1.9',8);")" t
check 'PostgreSQL Roman option' "$(pg "SELECT romantic_key_v1('VII',64) < romantic_key_v1('IX',64);")" t
check 'PostgreSQL arbitrary exponent' "$(pg "SELECT romantic_key_v1('1e9999999999',32) < romantic_key_v1('1e10000000000',32);")" t
check 'PostgreSQL exponent normalization' "$(pg "SELECT romantic_key_v1('10e99999999999999999999',32) = romantic_key_v1('1e100000000000000000000',32);")" t
check 'PostgreSQL canonical equality' "$(pg "SELECT romantic_key_v1('ș') = romantic_key_v1('ş');")" t
check 'PostgreSQL long key' "$(pg "SELECT octet_length(romantic_key_v1(repeat('a',10000))) > 10000;")" t
for invalid in -1 128; do
	out=$(pg "SELECT romantic_key_v1('a',$invalid);" 2>&1); rc=$?
	check "PostgreSQL rejects options $invalid" "$((rc != 0))" 1
done
out=$(pg "CREATE TABLE t(v text); INSERT INTO t VALUES('file10'),('file2'),('Apple'),('apple'); CREATE INDEX ix ON t(romantic_key_v1(v)); SET enable_seqscan=off; SELECT string_agg(v,',' ORDER BY romantic_key_v1(v)) FROM t;")
check 'PostgreSQL indexed order' "$out" 'apple,Apple,file2,file10'
out=$(pg 'SET enable_seqscan=off; EXPLAIN (COSTS OFF) SELECT v FROM t ORDER BY romantic_key_v1(v);')
check 'PostgreSQL uses expression index' "$([[ "$out" == *'Index Scan using ix'* ]] && echo yes)" yes
check 'SQLite/PostgreSQL exact binary key agreement' "$(sq "SELECT lower(hex(romantic_key_v1('café 10')));")" "$(pg "SELECT encode(romantic_key_v1('café 10'),'hex');")"
echo "database: $PASS passed, $FAIL failed"
exit "$FAIL"
