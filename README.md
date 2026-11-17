# romantic_collation

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fromantic_collation.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

Read in: **English** · [Français](README.fr.md) · [Español](README.es.md) ·
[Italiano](README.it.md) · [Português (Brasil)](README.pt_br.md) · [Català](README.ca.md) ·
[Română](README.ro.md)

A small, **fast**, **opinionated**, cross-platform, **reproducible** string
collation / sorting library that ships its own versioned ordering and **ignores
the OS locale entirely**.

> Yes, it's a pun on the Romance languages. This is a house order, not every locale's order.

## Why

`sort`, `rg`, `fd`, and friends give you locale collation that is either
non-reproducible (glibc's tables change across versions), absent (musl falls
back to raw code points), or heavy (ICU). This library picks **one** opinionated,
documented order, compiles it in as versioned data, and produces **byte-for-byte
identical** results on glibc, musl, macOS, and Windows.

There is an escape hatch: `--code-point` gives you exact `LC_ALL=C sort` order.

SQLite and PostgreSQL extensions now expose indexable binary sort keys:
`ORDER BY romantic_key_v2(name)`. See [database setup and examples](docs/DATABASES.md).
Ordering revision 2 recognizes all Unicode 17.0.0 `White_Space` characters and
`P*` punctuation categories. For example, `a  < a— < aa`. All whitespace shares
the existing space weight; punctuation retains code-point order within its class.
Non-ASCII symbol ordering and language-specific alphabet choices are unchanged.
Stored keys/indexes from revision 1 must be recomputed; SQL now uses
`romantic_key_v2` (PostgreSQL extension 2.0). C ABI signatures are unchanged.
The compiler is pinned to Zig 0.17.1; correctness tests run with runtime safety enabled.
Zig remains the ordering oracle. An independent, dependency-free Rust core
(Rust 1.100.0) provides the same key bytes and checked C ABI, plus a Rust-backed
Elixir NIF. The same CLI acceptance tests run against both backends.
Scientific exponents now retain arbitrary precision, including normalization
carries and negative exponents. Code-point key generation writes directly to
the caller's buffer without a temporary allocation. Recompute any scientific-mode
keys stored by an older build when upgrading; exponent ordering and equivalent
mantissa spellings are now corrected.

## The opinionated house style (the default)

In priority order:

1. **Structural-first.** `whitespace < punctuation < digits < letters`.
   Whitespace and punctuation are significant and sort *before* alphanumerics
   (UCA/CLDR can also retain punctuation; this library fixes one house policy).
   So: `thing < "thing " < thing2 < thingthing`, and `"test with spaces" < test1`.
   *Spaces before letters. COME ON.*
2. **Natural numeric runs, arbitrary precision.** `file2 < file10` — digit runs
   compare as numbers, with **no cap on digit count**. Two 10,000-digit numbers
   order correctly. A leading `-` before digits is a **minus sign**
   (`-10 < -5 < 0`), but a `-` anywhere else stays a separator, so
   `peter-3 < peter-4` and ISO dates are unharmed. Dots are separators by default
   (`1.9 < 1.10`, version semantics); `-d`/`--decimal[=SEP]` declares decimal
   input, which absorbs digit-group separators between digits — so
   `999,999.00 < 1,000,000.00`, and **the same values sort into the same order
   whether written `1,000.00`, `1.000,00`, `1'000.00`, or `1 000.00`**.
   Absorption is group-size agnostic, so Indian 2-2-3 and Chinese 4-grouping work.
   Full detail and the complete list of caveats:
   **[docs/NUMERIC.md](docs/NUMERIC.md)**.
3. **Case-insensitive base letters.** `apple` and `Apple` are adjacent, not
   split into "all-uppercase-then-all-lowercase".
4. **Most diacritics as a secondary tie-break.** `café` sorts near `cafe`
   (base letter `e`), *not* dead-last like raw code points: `café < cafz`.
5. **Spanish and Romanian alphabet slots.** `n < ñ < o`; `a < ă < â < b`,
   `i < î < j`, `s < ș < t`, and `t < ț < u`. Romanian comma-below, legacy
   cedilla, and decomposed below-mark spellings compare equal.
6. **Case as the final tie-break.** lowercase before uppercase.

For mixed-language collections, apply one collation policy uniformly, chosen for
the intended audience. This library does not infer a locale per string, and its
house tailoring is not a substitute for every language's conventions. See
[Unicode's mixed-language collation guidance](https://www.unicode.org/faq/collation.html).
7. **Ligatures expand.** `ß`→`ss`, `œ`→`oe`, `æ`→`ae`, `ĳ`→`ij`, so `straße`
   lands next to `strasse` and `cœur` next to `coeur` instead of after every
   letter. The two stay distinguishable at the tertiary level, so the order
   remains total.
8. **NFC-aware for common precomposed Latin accents**, with a targeted
   Romanian below-mark canonicalization (v1 subset — see Limits).
9. **No OS locale, ever.** Reproducible everywhere.
10. **Code-point fallback** (`--code-point`) == pure UTF-8 byte order.

## Build & test

```sh
./build          # canonical Zig package; result/ and bin/<PF>/collate
./test           # both backends, ABI/parity, Elixir, CLI, real databases
./build --debug  # debug Nix package
./result/bin/collate --help
./build --all-impls  # both declared native routes, without changing the default
./build --impl rust # Rust product, without changing the published command
```

`CANONICAL_IMPL` selects the CLI backend; Zig remains the default and ordering
oracle. `./build canonize rust` records a selection without building or switching
the command; rerun `./build` to publish it. Use `canonize zig` to return. Native
products coexist under `<backend>-out/<PF>/[variant]/release/` (or `debug/`).
`--all-plats` builds the selected backend's declared platforms; `--all` combines
both scopes. `build-targets.tsv` is the declared matrix: five Zig targets and
currently Linux amd64 for Rust. A failed build preserves the prior publication.
The compatibility `result/` link follows the canonical host product, and
`bin/<PF>/collate` points to it. Direct `nix build` retains the historical Zig
default; use the explicit Rust outputs when bypassing the selector.

Zig Linux CLI builds are fully static (musl). Rust CLI builds currently use
the host GNU libc and Nix runtime closure; they are not portable static releases.
`--about` identifies the actual compiled `PF` and applicable libc `VARIANT`.

The package includes `lib/libromantic_collation.a` and
`include/romantic_collation.h`. Database modules use the server's native libc.
For embedding in a native C application, `nix build .#library --out-link
result-library` builds the archive against the host libc; compile with
`-Iresult-library/include` and link `result-library/lib/libromantic_collation.a`.

## Database ordering

```sh
nix build .#sqlite-extension --out-link result-sqlite
nix build .#postgres-extension --out-link result-postgres
```

After loading the matching extension:

```sql
SELECT name FROM items ORDER BY romantic_key_v2(name);
CREATE INDEX items_romantic_v2 ON items(romantic_key_v2(name));
```

Both engines return binary keys and support expression indexes. These functions
provide ordering through `ORDER BY`; they do not change text `=` or `LIKE`, or
install a native `COLLATE` provider. NULLs propagate. Optional integer options
match the C API, for example `romantic_key_v2(name, 64)` enables Roman numerals.
Equal keys can represent different strings, and a UNIQUE key index enforces
that equivalence. Keep ordering revisions/options fixed for each index; rebuild
stored keys and indexes when migrating them. PostgreSQL needs a UTF8 database
and a module compiled for its server major. Full setup and migration guidance:
[docs/DATABASES.md](docs/DATABASES.md).

For standard multilingual collation in a PostgreSQL build with ICU support,
an extension is not necessary: `CREATE COLLATION natural_root (provider = icu,
locale = 'und-u-kn-true');` supplies root numeric collation. Use this library's
extension when its custom house/numeric semantics or binary keys are wanted.
See [PostgreSQL's ICU collation documentation](https://www.postgresql.org/docs/current/collation.html).

## Rust and Elixir

The Rust crate lives in `rust/` and does not call Zig. Add it as a path dependency
when vendoring this repository:

```toml
[dependencies]
romantic-collation = { path = "vendor/romantic_collation/rust" }
```

```rust
use romantic_collation::{Collator, options};
let collator = Collator::new(options::ROMAN)?;
assert!(collator.compare(b"VII", b"IX")?.is_lt());
let key: Vec<u8> = collator.sort_key("café".as_bytes())?;
```

Allocation errors return `Result`; arbitrary bytes, including NUL and invalid
UTF-8, are accepted. The crate requires Rust 1.100. `nix build .#rust-library`
packages its Rust library and checked C ABI; `nix build .#rust-cli --out-link
result-rust` builds the existing C CLI over that ABI. Zig is still the default.
Native execution is qualified on Linux amd64. Rust/NIF macOS and Linux arm64
outputs are defined but are not yet runtime-qualified; Windows qualification
currently applies only to the Zig cross-builds.

For Elixir, add the repository as a Mix dependency (no Hex release yet):

```elixir
{:romantic_collation, git: "https://github.com/pmarreck/romantic_collation.git", branch: "yolo"}
```

Mix builds the Rust-backed NIF through the pinned Nix flake. Nix is required on
the build machine, not necessarily on the deployment machine: package the Mix
release and its native shared-library dependencies for the deployment target.
For a prebuilt NIF, set `ROMANTIC_COLLATION_NIF` to its absolute path **without**
the `.so` suffix while building/loading. `nix build .#elixir-nif` produces it.
Use the NIF built from the same revision as the Elixir module; older artifacts
do not provide the native sort entry point.
The packaged module declares NIF API 2.17 (ERTS 14.0 minimum); the runtime must
accept that ABI and the artifact's native dependencies. Runtime tests currently
use OTP 28.5.0.3. The pinned `nix develop` shell supplies the tested Elixir/OTP pair.

```elixir
RomanticCollation.sort(["file10", "file2"]) # ["file2", "file10"]
RomanticCollation.compare("VII", "IX", roman: true) # :lt
RomanticCollation.keys(["café", "cafe"]) # one batch native call
RomanticCollation.equal?("ș", "ş") # true, although "ș" != "ş"
```

Options are booleans named `code_point`, `decimal`, `decimal_comma`, `scientific`,
and `roman`, or the C API's integer mask. Sorting precomputes keys and sorts the
entire list in one native call. It returns the original binaries in a new list,
preserving input order for collation-equal values. Temporary sort keys do not
become BEAM terms. All native computation uses dirty CPU schedulers. This keeps
the sort off the ordinary schedulers, but large batches still occupy a dirty
scheduler and retain input plus keys. As with any NIF, a native memory-safety
defect can crash the VM; use a process boundary
for untrusted workloads requiring crash isolation. Restart the VM when replacing
the native module; hot NIF upgrades are not supported.

For fuller-featured, locale-aware **CLDR collation in Elixir**, consider
[Localize](https://github.com/elixir-localize/localize), which offers native
Elixir and ICU-backed collation. This library instead supplies one reproducible
house order with its own numeric and optional Roman-numeral rules.

## CLI

Sorting is stable: collation-equal lines retain their input order, including
with `--reverse` and when selecting a field with `-k`. `--unique` keeps the
first input line for each equal key in either direction. Case and other actual
key distinctions still affect ordering. This replaces the earlier raw-byte
tie-break; it changes CLI presentation, not the ordering revision or key bytes.

Sort keys are packed into stable pages instead of reserving a separate
overestimated allocation for every row. On a one-million-line workload this
reduced peak RSS from 307 MiB to 169 MiB (45%), with byte-identical output.
The CLI remains an in-memory sort: input, row metadata, and actual key bytes
still grow linearly with the dataset. These are whole-process RSS measurements,
not an assertion that the allocator returns every freed page to the OS.

```sh
collate [OPTIONS] [FILE]      # sorts lines from FILE (or stdin) to stdout

  -t, --field-separator <SEP>  Split each line on SEP (default: whole line)
  -k, --key <N>                Sort by the 1-based Nth field; ties keep input order
  -c, --code-point             Pure UTF-8 byte order (== LC_ALL=C sort)
  -d, --decimal[=SEP]          Declare DECIMAL input; SEP is the decimal mark,
                               '.' (default) or ','. Digit-group separators are
                               then absorbed (999,999.00 < 1,000,000.00)
  -s, --sci, --scientific[=SEP]  Order by value with exponents (2e5 < 1e10);
                               plain numbers normalize as exponent 0
  -n, --num, --numeric[=SEP]   Both -d and -s
      --roman                  Order whole-token Roman numerals by value
                               (VII < IX); canonical uniform-case tokens only
      --version-sort           Explicit form of the default dot handling
  -r, --reverse                Descending order; ties keep input order
  -u, --unique                 Keep the first input line per equal sort key
  -o, --output <FILE>          Write to FILE (-, @stdout, or @stderr)
  -h, --help                   Show help
      --about                  One-line version + platform
      --version                Library version
      --lang <code>            UI language for --help/--about (e.g. en, fr, es)
```

`FILE` may be `-` or `@stdin` for standard input (the default).

```sh
printf 'file10\nfile2\nApple\napple\n' | collate
# apple
# Apple
# file2
# file10
```

### Field sorting (`-t` / `-k`)

Sort by a chosen field, like `sort -t -k`. The separator may be multi-character;
a missing field sorts as empty. `COLLATE_FIELD_SEP` sets a default separator
(overridden by `-t`); a separator with no `-k` sorts by field 1.

```sh
printf 'a:3\nb:1\nc:2\n' | collate -t: -k2
# b:1
# c:2
# a:3
```

### Language (`--lang`, prepare-phase i18n)

`--help`/`--about` are localizable. Precedence: `--lang <code>` overrides
`ROMANTIC_COLLATION_LANG`, which overrides `LANG`/`LC_*`; English is the default and
fallback. The prepare-phase catalogs are `en`, `de`, `fr`, `es`, `it`, `pt_br`, `ca`,
and `ro`; full 50-locale coverage remains future work. Localized aliases are
`--hilfe`/`--sprache` (German), `--aide`/`--langue` (French),
`--ayuda`/`--idioma` (Spanish), `--aiuto`/`--lingua` (Italian),
`--ajuda`/`--linguagem` (Portuguese), `--ajut`/`--llengua` (Catalan), and
`--ajutor`/`--limba` (Romanian).

## C FFI (the real public API)

The C surface mirrors ICU4C's `ucol_*` collator API, but is UTF-8-native
(byte string + length, like `ucol_strcollUTF8`). See
[`include/romantic_collation.h`](include/romantic_collation.h).

```c
rcol_config config = RCOL_CONFIG_INIT(0); /* 0 = house style */
rcol_collator *c = NULL;
if (rcol_open(&config, &c) != RCOL_OK) { /* handle failure */ }

int32_t order;
if (rcol_compare_utf8(c, a, alen, b, blen, &order) != RCOL_OK) {
    /* equality is never confused with failure */
}

size_t required;
rcol_status status = rcol_sort_key_utf8(c, s, slen, out, cap, &required);
rcol_close(c);
```

Every fallible call returns `rcol_status`; useful values use out-parameters.
Length probes pass `out = NULL, out_cap = 0`. An undersized sort-key buffer
returns `RCOL_BUFFER_TOO_SMALL`, reports `required`, and remains untouched.
Rust panics are contained as `RCOL_INTERNAL_ERROR`; expected allocation failures
return `RCOL_OUT_OF_MEMORY`. Invalid pointers, stack exhaustion, and process
termination are outside that recovery contract. Handles and their freeing
functions must come from the same backend, never mixed between loaded libraries.

## Benchmarks

Run `./bm` (uses `hyperfine` from the dev shell). It records two deliberately
separate streams:

- `bench/<machine-id>.<backend>.performance.ndjson` contains non-blocking fixed-workload
  wall-clock and CPU-time telemetry for `collate` and independent competitors.
- `bench/<machine-id>.<backend>.complexity.ndjson` contains the blocking `N, 2N, 4N, 8N`
  growth control. Each doubling must stay in `[1.5, 3.0)`, and the smallest
  workload must take at least 5× empty-process startup time.

`BM_IMPL=zig ./bm` and `BM_IMPL=rust ./bm` select explicit backends; the default
is `CANONICAL_IMPL`. The original combined and backend-unqualified logs remain
historical data. Benchmark builds do not retarget the published CLI.

Measured — 50,000 realistic mixed lines, AMD Threadripper 3990X, hyperfine median:

| contestant | median | vs `collate` (house) |
|---|--:|--:|
| `sort` (`LC_ALL=C`, byte order) | 21.96 ms | **0.41×** (faster) |
| `collate --code-point` | 39.19 ms | 0.73× |
| `collate` (house style) | 53.46 ms | 1.00× |
| glibc `strcoll` (`en_US.UTF-8`) | 78.77 ms | 1.47× (collate faster) |
| `sort` (`en_US.UTF-8`) | 86.30 ms | 1.61× (collate faster) |
| ICU `ucol_getSortKey` (`en_US`) | *see `./bm`* | — |

**Honest verdict:** `collate` is **not** faster than coreutils' byte sort
(`LC_ALL=C sort`) — that's a mergesort doing trivial `memcmp`, and `collate`
does more work (multi-level keys). But `collate`'s opinionated house style is
**~1.5× faster than glibc locale collation** *and* reproducible across
glibc/musl/macOS/Windows, which locale collation is not. Use `--code-point` when
you want raw byte order and it's still within ~1.8× of `sort -C`.

**Scaling gate:** the sort path is `O(n log n)`; the gate runs it at N, 2N, 4N,
8N and fails on a super-linear (≥ 3×-per-doubling) regression. Measured ratios:
1.80 / 2.04 / 2.10 — clean `O(n log n)`.

## Fuzzing

```sh
./fuzz                  # 200k iterations, fixed seed (reproducible)
./fuzz 1000000          # longer run
./fuzz --random         # fresh seed, printed so any failure reproduces
```

Checks ORDERING laws, not crashes — a wrong order never crashes. Note that the
algebraic laws (reflexivity, antisymmetry, transitivity) are nearly vacuous for
a `memcmp`-based key, since `memcmp` is a total order over any bytes at all; the
properties that can actually fail are the structural `|L2| == |L3|` level-
alignment check and independent numeric / case-fold / expansion-adjacency
oracles. Each is verified to catch an injected bug.

## Architecture

Pure Zig core (no I/O) → C FFI (`rcol_*`) → C CLI that dogfoods the FFI.
See [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) and [RULES.md](RULES.md).

## Limits (v1)

**CJK is not covered — out of scope for now.** Chinese, Japanese, and Korean text
falls into `CLASS_OTHER` and sorts in **code-point order**: reproducible,
deterministic, and non-corrupting, but *not* linguistically ordered. This is a
deliberate boundary, not an oversight. Correct CJK collation needs **dictionaries**,
not tables:

- **Chinese** sorts by pronunciation (pinyin), which Han characters do not encode.
  A Han→reading map is ~40k entries, and it still is not enough because of
  polyphones (行 = *xíng* or *háng*), whose resolution needs word segmentation.
- **Japanese** sorts by reading (*yomi*), which is genuinely underdetermined —
  東 is *higashi* alone but *tō* in 東京, and surname readings are ambiguous even
  to humans. Even ICU punts, ordering kana properly and leaving kanji in a fixed
  Unihan order.
- **Korean** is the exception: hangul decomposes algorithmically and its
  code-point order already *is* dictionary order, so pure-hangul text is correct
  today by construction.

**The escape hatch, which needs no dictionary in this binary:** supply the reading
as a separate column and sort on it with `-t`/`-k`. That is what Japanese systems
actually do — it is why every Japanese form has a furigana field. Given
`東京<TAB>とうきょう`, `collate -t$'\t' -k2` yields correct Japanese order.

**One evolving global Latin order.** The house style is a single versioned,
compiled-in order, initially root-like but not frozen. It deliberately adopts
Spanish `ñ` and Romanian `ă â î ș ț` as primary letters, including Romanian
legacy and decomposed spellings. It remains non-native where one global order
would need a conflicting case pairing, contraction, or alphabet rearrangement:

| language | wants | we give |
|---|---|---|
| Swedish, Finnish | `å ä ö` as letters after `z` | folded to `a`/`o` |
| Danish, Norwegian | `æ ø å` as letters after `z` | `æ`→`ae`, `ø`→`o` |
| Czech, Slovak, Polish, Croatian | `č ř š ž` etc. as separate letters | folded to base |
| Hungarian | `cs dz dzs gy ly ny sz ty zs` as letters | not contracted |
| Estonian, Latvian, Lithuanian | reordered alphabets (`z` mid-alphabet in `et`) | base order |
| Turkish | dotless `ı` distinct from `i` | `ı` uncovered entirely |
| Canadian French (`fr-CA`) | accents compared *backwards* | forward |

This follows RULES.md #2 (never consult the OS locale). Future tailoring may
address genuine conflicts, especially Turkish case pairs and Hungarian ASCII
contractions. Note that broadening `æ`→`ae` in v1.1 *removed* an accidental
correctness for Danish/Norwegian, where `æ` previously landed after `z` by
virtue of being unrecognized.

- Latin coverage is complete for French, Spanish, Italian, Portuguese, Catalan,
  Romanian, German, and Dutch (verified as a set, both directions, by
  `tests/integration/latin_coverage.sh`). Icelandic `ð`/`þ` and the Nordic
  `ø`/`å`-as-letters are **not** covered. Unknown code points degrade gracefully
  to code-point order (sorted after known letters).
- NFC handling covers common **precomposed** Latin accents. The targeted
  exception is Romanian `s`/`t` plus combining comma-below or cedilla, which
  canonicalizes with precomposed `ș`/`ț` and legacy `ş`/`ţ`. Full Unicode
  normalization is deferred.
- Zig's `rcol_compare_utf8` builds temporary keys in an 8 KiB stack scratch buffer and falls
  back to the heap for oversize inputs. Precomputing sort keys still wins when
  each string is compared many times; SIMD/streaming compare is deferred.
  Rust currently uses fallible heap-backed keys for house-style comparisons.
  SIMD work is deferred: this pass targeted allocation capacity and pointer
  stability, not a measured scalar arithmetic bottleneck. Byte copies continue
  to use the platform/runtime's optimized copy routines.
- **Numeric caveats are enumerated in [docs/NUMERIC.md](docs/NUMERIC.md)** — in
  short: default text sort distinguishes leading zeroes, numeric modes collapse
  leading and fractional trailing zeroes, `--decimal` must not be used for
  version strings, and a sign is recognized only at the start of the collated
  string (use `-t`/`-k` to make a number a field). ASCII, fullwidth, and
  Mathematical Alphanumeric decimal digits are supported.
- Roman mode preserves the Zig oracle's greedy round-trip grammar and 15-byte
  token limit. It accepts repeated `M` above 3,999 (for example `MMMM`), not just
  the conventional 1..3,999 range. It is opt-in and never infers dataset context.

## Naming

The CLI binary is provisionally named **`collate`** — a single clean word. It can
be renamed without touching the library (the library symbols are
`rcol_*`).

## License

MIT — see [LICENSE](LICENSE).
