# PLAN

Completed work is preserved in [the log](docs/PLAN_LOG.md). Earlier design ideas are [deferred context](docs/plan_context/legacy-roadmap.md), not commitments for this polish pass.

## Library polish

- [x] Eliminate code-point key temporary allocations; retain key bytes for unaffected modes, reject the unproven house-style scratch candidate, and report timing uncertainty (done 2026-11-14 10:57 EST; commit c2f04f2).
- [x] Fix scientific exponent cutoff and equivalent mantissas; independent i128 normalization sweep and database regressions pass (done 2026-11-14 10:57 EST; commit c2f04f2).
- [x] Add loadable SQLite/PostgreSQL extensions; 30 real-engine checks and installed C ABI consumer pass (done 2026-11-14 10:57 EST; commit c2f04f2).
- [x] Document new features, SQL examples, limits, and index migration in README, database guide, C header, and all eight help catalogs (done 2026-11-14 10:57 EST; commit c2f04f2).
- [x] Qualify 443 tests, 200k fuzz iterations, the complexity gate, and five target builds; final push and CI evidence are recorded by Git and the CI service (done 2026-11-14 10:57 EST; commit c2f04f2).
