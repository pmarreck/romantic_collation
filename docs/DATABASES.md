# SQLite and PostgreSQL

Both adapters expose `romantic_key_v2(text [, options])`. The result is a binary
key (SQLite BLOB, PostgreSQL bytea). Binary ordering matches the C comparator,
including natural numbers, structural-first ordering, and Latin letter rules.
NULL input or NULL options yield NULL. Options default to zero, the house order.
The option bits match `include/romantic_collation.h`: decimal = 8, scientific =
32, Roman = 64, and combined decimal/scientific = 40. Use integer constants in
indexed expressions. Code-point mode = 1; decimal comma adds 16.

These are sort-key functions, not a PostgreSQL collation provider or a SQLite
`COLLATE` callback. Use `ORDER BY romantic_key_v2(name)`. The SQLite comparison
callback has no error return, so allocation errors cannot safely become equality
or a different ordering. SQL scalar functions can fail the statement instead.

## SQLite

```sh
nix build .#sqlite-extension --out-link result-sqlite
sqlite3 example.db
```

```sql
.load ./result-sqlite/lib/romantic
CREATE TABLE items(name TEXT);
INSERT INTO items VALUES ('file10'), ('file2'), ('apple'), ('Apple');
SELECT name FROM items ORDER BY romantic_key_v2(name);
-- apple, Apple, file2, file10 (one value per row)
CREATE INDEX items_romantic_v2 ON items(romantic_key_v2(name));
EXPLAIN QUERY PLAN SELECT name FROM items ORDER BY romantic_key_v2(name);
```

Load the extension on each connection before reading or writing tables with its
expression indexes. Embedded NULs in TEXT are preserved because inputs use byte
lengths. Other SQLite input types must be explicitly cast to TEXT. Extension
loading must be permitted by the embedding application; the SQLite CLI supports
`.load`. The function is deterministic and innocuous, so it also works in schema
expressions with `trusted_schema=OFF`. Loading native code is privileged; load
only a module you trust.

## PostgreSQL

```sh
nix build .#postgres-extension --out-link result-postgres
```

The extension is compiled for the PostgreSQL major version in the locked Nix
package set. Build against the target server's headers; do not copy a module
between server majors. Use a UTF8 database. A server administrator can register
the built module using an absolute path visible to the server:

```sql
CREATE FUNCTION romantic_key_v2(text, integer DEFAULT 0)
RETURNS bytea AS '/absolute/path/result-postgres/lib/romantic_collation',
                'romantic_key_v2'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

SELECT name FROM items ORDER BY romantic_key_v2(name);
CREATE INDEX items_romantic_v2 ON items(romantic_key_v2(name));
```

The package also includes `romantic_collation.control` and its installation SQL
under `share/postgresql/extension/`. Install those in your server distribution's
extension directory and the shared module in its library directory to use
`CREATE EXTENSION romantic_collation`. On Nix, compose them into the PostgreSQL
package rather than modifying the immutable store. The absolute-path function
registration above is sufficient without modifying the server installation.

## Indexes, equality, and upgrades

`v2` identifies ordering revision 2, also reported by `rcol_ordering_version()`.
Library version and C ABI version are separate. Revision 2 fixes structural
ordering for every Unicode 17 `White_Space` character and `P*` punctuation.
Version 1 treated some of these as unknown characters after letters. Recompute
stored keys from the original text and rebuild indexes when adopting revision 2.
Code-point keys retain their bytes, but keep revision/options metadata explicit.

PostgreSQL extension 2.0 and the SQLite module expose `romantic_key_v2` only;
there is deliberately no silent rebinding of `romantic_key_v1` to new semantics.
There is no automatic SQL upgrade script from extension 1.0. Existing installations
must migrate their dependent objects explicitly. Keep the old module while any
index still depends on it, back up data, and coordinate connections before
recreating dependent functions/indexes against the new module. A future ordering
change likewise needs a new function revision and index/key rebuilds.

Equal keys can represent different strings: Romanian canonical spellings,
whitespace variants, and numeric equivalents in numeric modes can tie. A UNIQUE
expression index enforces collation equality. It is not a byte-identity check.
Keep ordinary text constraints if that is the intended rule. For deterministic
pagination add a unique row ID after the key in both ORDER BY and the index.
Do not use the key as a prefix-search representation; its three levels differ
from the source text.

Keys grow with input size. PostgreSQL B-tree entries have a page-dependent size
limit, so very long text can be sorted but may not fit an index entry. These
adapters do not alter the normal database handling of NULL, LIKE, or text `=`.
Compare returned keys explicitly when collation equality is wanted.

The complete `./test` runs disposable real SQLite and PostgreSQL databases. It
checks ordering, expression-index selection, canonical equality, malformed
options, NULLs, long values, and identical key bytes across the two engines.

API references: [SQLite expression indexes](https://sqlite.org/expridx.html),
[SQLite comparison callback contract](https://sqlite.org/c3ref/create_collation.html),
[PostgreSQL expression indexes](https://www.postgresql.org/docs/current/indexes-expressional.html),
and [PostgreSQL collation providers](https://www.postgresql.org/docs/current/sql-createcollation.html).
