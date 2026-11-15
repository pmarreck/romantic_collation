# PLAN

Completed work is preserved in [the log](docs/PLAN_LOG.md). Earlier design ideas are [deferred context](docs/plan_context/legacy-roadmap.md), not commitments for this polish pass.

## Library polish

- [ ] Push the polish commits and verify exact-commit Mechatron CI and the dynamic README badge before reporting shipped.
- [x] Keep collation equality as disclosed behavior without changing ordering revision 1; SQL and Elixir equality remain distinct from byte identity (done 2026-11-15 17:07 EST; commit f652b03).
- [x] Reduce CLI peak memory from 314368 to 173056 KiB on one million lines with identical output; stable-page resource and error regressions pass (done 2026-11-15 17:07 EST; commit 036b246).
- [x] Verify the latest stable Zig release. Answer: You confirmed keeping stable 0.17.1; it is already pinned and remains the oracle, not the 0.18 development compiler (done 2026-11-15 17:12 EST; commit f652b03).
- [x] Pin Rust 1.100.0, the current official stable release, and implement an independent core/checked ABI; 5102976 key cases match Zig, including Unicode Roman boundary contexts (done 2026-11-15 17:07 EST; commit f652b03).
- [x] Run the same CLI suites and separately packaged C ABI consumers against both backends, with export inventory and missing-export negative controls (done 2026-11-15 17:07 EST; commit f652b03).
- [x] Add Elixir key/keys/compare/equal?/stable-sort APIs through a Rust-backed dirty-CPU NIF; binary lengths, concurrency, option errors, and isolated tests pass (done 2026-11-15 17:07 EST; commit f652b03).
- [x] Document features and limits in README/all eight help catalogs; qualify 2732 checks, four foreign Zig cross-builds, native builds, and separate performance/complexity streams for both backends (done 2026-11-15 17:07 EST; commit f652b03).
