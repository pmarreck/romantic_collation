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
- Equal keys do not imply byte-identical input. Whitespace variants, Romanian canonical forms, and numeric-mode spellings can tie. A unique key index enforces this equivalence, not ordinary text identity. Add an ID or explicit binary text tie-breaker when stable row order matters.
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
