---
purpose: Ultimate goals and terminology for romantic_collation
audience: both
maintained_by: agent
---

# romantic_collation — Project Overview

## The one-sentence goal

A small, FAST, OPINIONATED, cross-platform, REPRODUCIBLE string-collation /
sorting library that ships its own versioned ordering data and **ignores the OS
locale entirely** — because that is the only way to get byte-for-byte identical
sort results on glibc, musl, macOS, and Windows.

## Why this exists

- **glibc `strcoll` is not reproducible.** Its locale collation tables change
  across glibc versions, so the "same" sort produces different output on
  different distros/years.
- **musl has no locale collation at all** — it falls back to code-point order.
- **ICU is correct but heavy** — a large dependency to vendor for "sort these
  lines the way a human expects."
- **`rg` / `fd` / `eza` punt to code-point order**, which puts `Z` before `a`
  and every accented letter after `z`.

This library picks a single, opinionated, documented order, ships it as
versioned data compiled into the binary, and guarantees the same result
everywhere. If you want the raw escape hatch, `--code-point` gives you exact
`LC_ALL=C sort` order.

## Architecture (hexagonal / ports-and-adapters)

```
any consumer ──► C FFI (rcol_*) ──► pure Zig core (no I/O)
                     ▲
              C CLI `collate` dogfoods the same FFI
```

- **Pure Zig core** (`src/collation.zig`): all logic, no I/O. Builds sort keys.
- **C FFI** (`src/lib.zig` + `include/romantic_collation.h`): the real
  public API, modeled on ICU4C's `ucol_*` surface but UTF-8-native.
- **C CLI** (`cli/main.c`): the `collate` command, which calls *through* the FFI
  (not the Zig core directly) so the FFI boundary is exercised.

The Zig implementation is the ordering oracle, by explicit owner decision.
An independent Rust core (`rust/`) exposes the same checked C ABI and a native
Rust API. Parity failures require investigating Rust, not redefining Zig to fit
the port. The C CLI is separately packaged over either backend and runs the same
acceptance suite. `CANONICAL_IMPL` retains Zig as the default.

Elixir uses the Rust core through a small dirty-CPU NIF adapter, with precomputed
batch keys and stable sorting. Database extensions retain the Zig core and
versioned key functions. Equal keys can represent different byte strings;
disclosing that equivalence, not removing it, is the accepted contract.
See [README.md](README.md) for build, deployment, and qualification limits.

## Terminology

- **Sort key** (a.k.a. collation key / weight string): a binary string derived
  from an input such that plain `memcmp` of two sort keys reproduces the desired
  comparison order. Computed once, compared many. Mirrors ICU `ucol_getSortKey`.
- **House style**: the default opinionated order (structural-first, natural
  numeric, case-insensitive base, most diacritics secondary, selected global
  Spanish/Romanian primary letters, case tertiary).
- **Structural-first**: Unicode whitespace and punctuation sort BEFORE alphanumerics
  and are NOT ignored (a fixed policy; UCA also supports non-ignorable punctuation).
  Yields "space before letters"
  and "shorter-prefix-before-longer".
- **Code-point mode**: the escape hatch (`RCOL_CODE_POINT`) = pure UTF-8
  byte order = `LC_ALL=C sort`.
- **Collation element**: one unit of comparison — a folded letter, a digit run,
  a whitespace char, a punctuation char, or an "other" code point.
- **Level (primary/secondary/tertiary)**: L1 = structural class + base letter
  or selected alphabet slot; L2 = remaining diacritic distinction; L3 = case.
  Compared in that priority order.

## Naming conventions

- Zig package/module/static-lib: `romantic_collation`
- C FFI symbol prefix: `rcol_`
- C header: `include/romantic_collation.h`
- CLI binary: `collate`; Linux/macOS alias: `romantic-collate`
- Default git branch: `yolo`
