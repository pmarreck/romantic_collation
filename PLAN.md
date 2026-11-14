# PLAN

Completed work is preserved in [the log](docs/PLAN_LOG.md). Earlier design ideas are [deferred context](docs/plan_context/legacy-roadmap.md), not commitments for this polish pass.

## Library polish

- [x] Critique current contracts, implementation, tests, and database suitability; five verified findings, fixes, and adoption gotchas recorded in CODE_REVIEW.md (done 2026-11-14 10:57 EST; baseline a1eab7e).
- [ ] Upgrade the Nix-pinned compiler from Zig 0.16.0 to latest stable 0.17.1 and qualify safe tests and optimized builds.
- [ ] Measure the hot path, retain demonstrated optimizations, and verify key bytes for unaffected modes and intentional numeric corrections.
- [ ] Fix the reproduced scientific-exponent cutoff, including signed huge exponents, normalization carry/borrow, and database regressions.
- [ ] Add loadable SQLite and PostgreSQL sort-key extensions with isolated real-engine ordering and index tests.
- [ ] Explain new features, SQL examples, limits, and index migration requirements in the README and CLI help.
- [ ] Run the complete suite, bounded fuzzing, benchmarks, and supported target builds; push and verify CI for the final commit.
