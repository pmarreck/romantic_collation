# Library review

Reviewed 2026-11-14 by Codex at `a1eab7e`, initially clean, Zig 0.16.0.
Scope: key construction, C ABI, CLI ownership/errors, Nix builds, test entry points, and database integration. Baseline: 391 tests pass. Cross compilation alone does not qualify native execution.

## Strengths

- One pure key builder defines comparison, so the two cannot disagree through separate tokenization implementations.
- Checked status returns distinguish equality from allocation failure; output buffers remain untouched on insufficient capacity.
- Numeric magnitudes avoid floating point and fixed-width integer conversion. Roman interpretation is explicit and corpus independent.
- Versioned Unicode data, exhaustive finite-table expectations from independent data, malformed-byte tests, and semantic fuzz properties cover more than ordering-law tests alone.
- Small dependency-free core and explicit byte lengths make embedding practical.

## Findings

### DCR-001: Build/test wrappers can report success after a failed build

Medium severity, high confidence, source-established. `test` pipes build commands through `tail` without checking the producer's exit status. `build` also permits non-Nix compilation and copies binaries into a path integration tests prefer, allowing stale products to be tested. Remedy: canonical Nix checks, explicit artifact paths, no producer-status-masking pipeline or direct-build fallback. Regression criterion: a failed Nix preparation must make `./test` fail.

### DCR-002: The default correctness run disables runtime safety

Medium severity, high confidence, source-established. `build.zig` and `test` select ReleaseFast for unit tests as well as shipped binaries. Bounds/overflow failures can escape observation. Remedy: safety-enabled tests and independently optimized production artifacts.

### DCR-003: Persisted keys lack an explicit ordering revision

Medium severity for database adoption, high confidence, source-established. `rcol_version()` identifies the library but does not establish a separately versioned key-format/ordering contract. Silently changing ordering behind an existing index can invalidate index scans and uniqueness. Remedy: explicit ordering revision, versioned SQL function names, and documented rebuild/migration obligations.

### DCR-004: Scientific exponent cutoff reverses valid numeric order

Medium severity, high confidence, reproduced. `scanExponent` at the reviewed revision stops accumulating after a prefix reaches one billion. `1e10000000000` is then treated as exponent one billion, while `1e9999999999` is treated as 9,999,999,999. The regression observed `expected -1, found 1` for the correct ascending order. The cutoff also loses normalization carries for still wider exponents. Remedy: retain the original folded digits, keep a checked i64 fast path, and use linear decimal addition/subtraction for arbitrary-width normalization. Verify signs, carry/borrow, folded digits, and an independent i128 arithmetic sweep. Persisted scientific keys involving these large exponents need recomputation.

### DCR-005: Scientific mantissa spelling leaks into equality

Medium severity, high confidence, reproduced by the exponent normalization regression (`expected 0, found 1`). Trailing integer zeros survive the scientific mantissa builder, so `10e0` and `1e1` receive different keys despite representing the same value. Remedy: omit trailing mantissa zeros after computing the normalized exponent, retaining interior zeros and nonzero fractional digits. Verification includes a finite normalization sweep whose exponent oracle uses independent i128 arithmetic, plus database equality assertions. Previously stored scientific keys need recomputation after this correction.

## Gotchas and accepted limits

- House order is a linguistic policy, not a locale-neutral implementation of every alphabet. Turkish case pairs and Hungarian contractions require tailoring; CJK remains code-point ordered.
- Full Unicode normalization is absent. For example, decomposed acute accents do not generally equal precomposed accents. Romanian below-mark handling is a targeted exception.
- Equal keys do not imply byte-identical input. Whitespace variants, Romanian canonical forms, and numeric-mode spellings can tie. A unique key index enforces this equivalence, not ordinary text identity. SQL pagination needs an explicit tie-breaker; input stability specifically requires an arrival ordinal, not an arbitrary ID or byte order.
- Default version-style numbers, sign-at-offset-zero, optional grouping absorption, and Roman word collisions are deliberate policies. Choose fixed options for each indexed expression.
- Keys expand input size and PostgreSQL B-tree entries have size limits. Long strings may need bounded application fields or unindexed sorting.
- The CLI retains its complete input and all keys; it is not an external-memory sort.
- SQLite collation callbacks return only ordering, with no allocation-error channel. Returning byte order or equality on an allocation failure could corrupt index invariants. SQL key functions provide an error channel and expression-index support in both engines.
- Reserved `RCOL_NUMERIC` and `RCOL_CASE_SENSITIVE` bits are documented no-ops. Do not assume these change the order.

## Optimization direction

Reduce temporary allocation in the checked key API before duplicating the scanner as a streaming comparator. SIMD is a candidate for long ASCII runs, but token boundaries, numeric runs, and three-level emission introduce dependencies. Measure allocation removal first; retain portable compiler-generated memory comparison/copy paths.

## Resolutions and evidence

All five findings are addressed in this polish pass. `./test` now runs the Nix
check as its single build path and propagates failed preparation. Unit and ABI
tests run in Zig's safety-enabled profile. The installed header/archive are
tested by a separately compiled C consumer. SQL function names and the C API
identify ordering revision 1. Scientific exponents retain arbitrary precision,
and equivalent mantissas share keys; 246 normalization cases use an independent
i128 arithmetic oracle. Recompute older stored scientific-mode keys.

Verification: 443 tests pass, including 30 real-engine checks with SQLite and
PostgreSQL 18.4, installed SQL, expression indexes, and binary key agreement.
The final optimized fuzzer passed 200,000 iterations / 1,737,615 checks.
Linux amd64 ran natively; Linux arm64, Windows amd64/arm64, and macOS arm64
compiled successfully. Foreign runtime execution and editor/ZLS pairing were
not qualified here.

Code-point key generation now has zero temporary allocations for arbitrary
input lengths and length probes, witnessed with an allocator that fails every
request. Buffer failure and overlapping-input tests pass. A larger scratch
buffer for house-style keys was rejected after measurements showed no reliable
throughput improvement. The retained direct-write path removes an allocation
and copy, but latency measurements on the shared host were too variable for a
speedup claim: one-core baseline/candidate 33.2/37.0 ms; twelve-core-allowed
baseline/candidate 36.3/35.0 ms, 15 samples per case, 40,000 deterministic lines,
Zig 0.17.1 optimized artifacts. The CLI itself remains single-threaded.
SIMD was considered; no new intrinsics were justified for the token scanner.

The existing `./bm` gate passed at 25k/50k/100k/200k lines with ratios
1.893, 2.030, 2.118 and startup multiple 8.435. This bounds the measured CLI
row-scaling workload; it is not a proof of Big-O or a separate string-length
gate for the new wide-exponent path. Its decimal loops are linear by inspection.

## Verification limits

No production databases or user data are in scope. Database qualification must use disposable real-engine instances, indexed-versus-unindexed agreement, NULLs, embedded NULs where supported, option errors, and long inputs. Native foreign-platform runtime tests require suitable runners.

## Follow-up qualification, 2026-11-15

Commits `036b246` and `f652b03` retain Zig as the ordering oracle and default.
Zig 0.17.1 is already the latest stable release; the new independent Rust core
uses stable Rust 1.100.0. Both implement ordering revision 1. The full suite
passes 2,732 checks, including public consumers of both installed C ABIs and the
same CLI acceptance cases. A separate ABI-loaded differential consumer matches
5,102,976 key cases, including every code point in Roman boundary contexts,
all 128 option masks, malformed bytes, embedded NULs, and long numbers. Shared
Unicode tables are generated data, not shared tokenizer/encoder logic. This
does not replace the independent Unicode/arithmetic checks or prove all inputs.

CLI keys now occupy stable packed pages. A deterministic million-line corpus
reduced whole-process peak RSS from 314,368 to 173,056 KiB, about 45%, with
byte-identical output. Resource tests assert page capacity and pointer lifetime.
The sorter still retains the input, row records, and keys; it is not bounded
memory and does not spill to disk. No new SIMD claim is made.

Both existing row-scaling gates pass at 25k/50k/100k/200k lines: Zig ratios
1.872, 1.992, 2.023; Rust ratios 1.829, 1.931, 2.062. These are finite legacy
CLI-growth experiments on a shared host, not proofs, string-length gates, or
qualified one-core/twelve-core throughput comparisons. Fixed-workload timings
remain separate non-blocking telemetry.

Additional adoption limits:

- Rust house-style comparison currently allocates keys on the heap, while Zig
  has its small scratch fast path. Precompute keys for repeated comparisons.
- Rust brings its standard runtime and a larger native artifact. The current
  Rust CLI uses GNU libc/Nix dependencies; only Zig's Linux CLI is static musl.
- Elixir calls use dirty CPU schedulers and immutable handles. Large batches
  can occupy a dirty scheduler and use substantial memory. Native defects can
  still crash the VM; dirty scheduling is not a crash-isolation boundary.
- Rust panics become checked internal errors rather than unwinding across C.
  Stack exhaustion and invalid pointers remain outside the recovery contract.
- Zig's Roman parser accepts repeated `M` above 3,999 within its 15-byte token
  limit. An old source comment claims a stricter range than the implementation.
  Rust preserves the oracle's behavior. Tightening this needs a separate
  ordering-revision decision, not a silent port correction.
- Linux amd64 ran natively. The four other Zig targets compiled; Rust/NIF
  foreign runtime execution and hot NIF upgrades are not qualified.

## Localization review, 2026-11-17

Kip's [reproducible comparison](https://github.com/elixir-localize/collation_bench)
uses this project's `0cf9582` and Localize 1.8.0. Its reported timings are valid
end-to-end Elixir sorting measurements, not isolated core-comparator timings.
Localize's ICU NIF generates keys and sorts natively; this project's NIF batches
key generation but leaves sorting to Elixir. Allocation/copy reduction and native
batch sorting are candidates for measured follow-up, not established speedups.
The agreement sample contains 4,000 random pairs across four Latin-string lengths,
not all pairs in a 1,000-string set. Eleven differences do not establish accuracy
for other scripts or locales. The full throughput benchmark was not rerun here.

### DCR-006: Unicode structural coverage was incomplete (resolved)

Medium severity, high confidence, reproduced against the prior packaged CLI.
`a` followed by EN SPACE or EM DASH sorted after `aa`, contradicting the
structural-first contract. Revision 2 uses pinned Unicode 17 `White_Space` and
`P*` categories in both implementations. Existing ASCII symbol policy, alphabet
weights, numeric policy, and code-point mode remain unchanged. SQL v2 names and
PostgreSQL extension 2.0 make the ordering change explicit; rebuild old keys and
dependent indexes rather than rebinding v1 functions silently.

An independently compiled C consumer parses the original Unicode files, without
using generated production ranges. Against each public ABI it exhausts 1,112,064
Unicode scalars, verifies all 25 whitespace characters and all 856 punctuation
characters, rejects whitespace false positives, and checks unchanged code-point
keys. The old Rust backend fails this control at U+0085. Shared CLI regressions
also failed before the correction. The complete corrected suite passes 2,760
checks, including both backends, real database engines, and Elixir integration.

### DCR-007: CLI equal-key order was deterministic but not stable (resolved)

The prior CLI broke equal keys by raw line bytes and reversed completed
output for descending order. Neither retained input order for collation-equal
values. Elixir's existing sort is stable. The owner requested stable CLI sorting
and confirmed that selected-field ties must also retain input order. The CLI now
uses original input offsets only when keys tie and reverses only the key
comparison for descending mode. Those offsets come from the existing shared
input buffer, without increasing per-row storage. Unique filtering retains the
first input representative in either direction. Key bytes/revision do not change.

New acceptance cases failed 13 checks against the old CLI. Coverage includes
both input permutations, whitespace/canonical/numeric equivalences, missing
fields, field/raw modes, unique representatives, and independent integer-group
expectations for 5,000 shuffled records in four sort/unique combinations. SQL
documentation and real-engine tests distinguish deterministic IDs from explicit
arrival ordinals; database sorting itself does not promise stable equal-key order.
Elixir tests retain stability across both permutations of several equal-key sets.
The final complete suite passes 2,811 checks, including 22 new CLI cases per
backend, real-engine arrival-order tests, and the Rust-backed Elixir NIF.
All seven local CI targets pass; four foreign Zig targets compile successfully.
Native qualification remains Linux amd64, not foreign runtime execution.

### Policy distinctions, not automatic defects

- Root numeric CLDR is the closest standard comparison, but our signed decimal,
  arbitrary-width scientific, and optional Roman interpretation differ. ICU
  numeric collation does not parse signs, fractions, or exponents and limits a
  numeric unit to 254 significant digits. PostgreSQL can already use ICU root
  numeric collation without this extension when built with ICU support.
- Digits are not ASCII-only: fullwidth digits and five mathematical digit
  alphabets are supported. Arabic-Indic and other Unicode decimal sets are not.
- Spanish/Romanian primary letters are intentional house tailoring, not CLDR
  root behavior. Missing Latin folds, non-Latin case/script behavior, and absent
  full canonical normalization remain adoption limitations, not solved by the
  structural correction. Non-ASCII symbols still follow letters; ASCII symbols
  retain the legacy punctuation bucket.
- UCA does not inherently ignore punctuation. An ICU 76.1 functional probe with
  root numeric, non-ignorable settings reproduced the four structural examples
  in the README, as well as `a` + EN SPACE/EM DASH before `aa`. Earlier claims
  that these examples distinguish this library from UCA have been corrected.
- For mixed locales, Unicode recommends one ordering for the intended audience
  across the collection, not per-string locale guesses. No universal order can
  simultaneously give German and Swedish positions to the same letter. Root
  numeric is a sensible multilingual baseline; retaining the house tailoring is
  a separate owner policy choice. No CLDR-default migration was implemented.

Primary references: [Unicode mixed-language FAQ](https://www.unicode.org/faq/collation.html),
[ICU numeric attributes](https://unicode-org.github.io/icu-docs/apidoc/released/icu4c/ucol_8h.html),
and [PostgreSQL ICU collations](https://www.postgresql.org/docs/current/collation.html).

## Native Elixir batch sorting, 2026-11-17

`RomanticCollation.sort/2` now builds packed temporary keys through the existing
Rust C ABI and sorts entirely on a dirty CPU scheduler. Equal keys use the
original ordinal; the result is a new list of the original binary terms.
There is no change to the ordering revision or public C ABI. The adapter uses
libc `qsort` and `memcmp` (confirmed in the optimized artifact) rather than
adding a SIMD path. For bounded-length keys the sort is expected to scale as
O(n log n); key construction scales with input bytes and common prefixes
affect comparison cost.

The Elixir tests compare the native sorter with BEAM's stable key sort for all
128 option masks and both input permutations, checking embedded NUL and invalid
UTF-8 alongside valid text. The direct native test failed on the prior NIF as
expected. Additional cases cover allocation of keys larger than a page,
concurrent calls, and errors after accepting valid list elements.

Re-ran [Kip's harness](https://github.com/elixir-localize/collation_bench/tree/ba29e29fe889038721eb8c9734fad326f6f0978c)
with the same corpus and seed, Localize 1.8.0 and Benchee 1.5.1. Linux x86-64,
AMD Threadripper 3990X, ICU 76.1, Elixir 1.18.4, OTP 28.5.0.3, BEAM JIT on.
The candidate run added the previous `keys` + `Enum.zip` + `Enum.sort_by` +
`Enum.map` path as a fourth job, with identical input and Rust key engine.
Both paths returned exactly the same result on each of the four sort corpora.
The ICU NIF loaded and its direct sort returned a valid result for each corpus.
The agreement check still showed 11 disagreements with ICU across 4,000 pairs.

Median wall time in ms for sorting 1,000 strings, one CPU pinned, 2 s warmup
and 5 s sampling per job (not a CI timing gate):

| Code points | Previous sort | Native sort | Localize ICU | Localize Elixir |
| ---: | ---: | ---: | ---: | ---: |
| 5 | 0.708 | 0.587 | 0.606 | 6.94 |
| 10 | 1.05 | 0.86 | 0.96 | 11.28 |
| 20 | 1.90 | 1.55 | 1.57 | 29.45 |
| 50 | 3.33 | 3.05 | 3.31 | 50.47 |

With 12 CPUs available but still one Benchee job at a time, medians in the
same column order were 0.856/0.544/0.655/6.57, 1.36/0.87/1.01/11.41,
2.65/1.48/1.85/20.40, and 4.71/3.10/4.23/48.41 ms. Some jobs had far higher
variance than on one core; these numbers do not establish multicore speedup
or an ordering of general-purpose performance across libraries.

Whole-process peak RSS for one 200,000-row, 20-code-point sort, using the same
alphabet and seed and a fresh one-core BEAM for each sample: previous
344,748/337,884/336,024 KiB; native 199,352/199,352/199,352 KiB. This includes
BEAM startup, corpus generation, sorting and output hashing. All six outputs
had the same digest. These are workload-specific observations, not a leak
test or a general ranking against ICU.
