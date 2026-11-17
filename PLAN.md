# PLAN

Completed work is preserved in [the log](docs/PLAN_LOG.md). Earlier design ideas are [deferred context](docs/plan_context/legacy-roadmap.md), not commitments for this polish pass.

## Library polish

- [x] Fix Unicode whitespace/punctuation coverage in the Zig oracle and Rust backend using pinned Unicode 17 data; both public ABIs pass independent exhaustive scalar checks and the old backend fails the negative control (done 2026-11-17 09:30 EST; commit d712d90).
- [x] Publish ordering revision 2 and SQL v2 names; documentation, review findings, and NIF/CLI/database regressions pass without changing symbol or alphabet policy; full suite: 2760 passed, 0 failed (done 2026-11-17 09:30 EST; commit d712d90).
- [x] Preserve CLI input order for equal keys in both directions and retain the first input representative with unique filtering; Answer: you confirmed selected-field ties also retain input order; 22 new shared CLI cases and Elixir/SQL checks pass in the 2811-check suite (done 2026-11-17 09:40 EST; commit 0470ebb).
- [x] Verify pushed exact-commit CI and the README badge for Unicode structural ordering and stable sorting; Answer: origin/yolo equals 0470ebb, all seven Mechatron targets passed, and the endpoint and rendered README badge report PASSING; 2811 checks, parity, and four foreign Zig builds pass (done 2026-11-17 09:46 EST; commit 0470ebb).
- [x] Push the polish commits and verify exact-commit Mechatron CI and the dynamic README badge. Answer: origin/yolo equals 9fa299f; all six targets passed and both the badge endpoint and README image report PASSING (done 2026-11-15 17:19 EST; commit 9fa299f).
- [x] Verify the latest stable Zig release. Answer: You confirmed keeping stable 0.17.1; it is already pinned and remains the oracle, not the 0.18 development compiler (done 2026-11-15 17:12 EST; commit f652b03).
- [x] Pin Rust 1.100.0, the current official stable release, and implement an independent core/checked ABI; 5102976 key cases match Zig, including Unicode Roman boundary contexts (done 2026-11-15 17:07 EST; commit f652b03).
- [x] Run the same CLI suites and separately packaged C ABI consumers against both backends, with export inventory and missing-export negative controls (done 2026-11-15 17:07 EST; commit f652b03).
- [x] Add Elixir key/keys/compare/equal?/stable-sort APIs through a Rust-backed dirty-CPU NIF; binary lengths, concurrency, option errors, and isolated tests pass (done 2026-11-15 17:07 EST; commit f652b03).
- [x] Document features and limits in README/all eight help catalogs; qualify 2732 checks, four foreign Zig cross-builds, native builds, and separate performance/complexity streams for both backends (done 2026-11-15 17:07 EST; commit f652b03).
