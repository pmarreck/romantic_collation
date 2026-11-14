---
purpose: Work plan and roadmap for romantic_collation
audience: agent
maintained_by: agent
---

# Earlier roadmap and deferred design context

## Done (v0.1.0 + follow-ups)













Current test count: 369 passed, 0 failed (95 Zig unit + 3 C unit + 6 benchmark-policy unit + 265 CLI integration).




## Open follow-ups

- [ ] **Evolve the global Latin house order deliberately.** The current root-like behavior is provisional while the product is being designed; evaluate regional preferences as candidates for the default whenever a single documented ordering can express them. Change the default carefully with full set-based language corpora and explicit examples of every affected existing ordering. Reserve explicit tailorings only for genuine contradictions, such as Turkish `I`/`ı` versus `i`/`İ` case pairing and Hungarian ASCII contractions.
- [ ] **Finish local rename cleanup.** The GitHub and Mechatron cutover is complete. If a local tmux session still has the old project name, rename it to `romantic_collation`.
- [ ] **Compatibility folding of LETTERS** (Peter's "what about other letter-like things?", 2026-07-31). Digits are done; the letter side remains. Fullwidth digits were one instance of a much larger, but BOUNDED and already-standardized, family: Unicode's compatibility decomposition (NFKD/NFKC, `UnicodeData.txt` field 5). It is a deterministic TABLE, not a dictionary, so it fits the project thesis — unlike CJK. The family, roughly in value order:
      - **Fullwidth/Halfwidth Forms** U+FF00–FFEF (~225): fullwidth ASCII → ASCII, halfwidth katakana → katakana. Cheapest, highest value.
      - **Mathematical Alphanumeric Symbols** U+1D400–1D7FF: bold/italic/script/ fraktur/double-struck/sans/monospace letters AND digits (𝟎-𝟿). ~1000 code points but ALGORITHMIC — contiguous 26/26/10 runs with a handful of holes (the letterlike-symbol borrowings), so it is arithmetic plus a small exception table, not a big table.
      - **Enclosed Alphanumerics** U+2460–24FF (①, Ⓐ), **Roman numerals** U+2160–217F (Ⅷ), **super/subscripts** U+2070–209F (², ₃), **Letterlike Symbols** U+2100–214F (ℂ, ℌ, №), vulgar fractions (½). Small tables each. Design notes when this is picked up: (a) fold at the PRIMARY level with a TERTIARY distinction, exactly like the existing ligature expansions, so Ⓐ sorts with A without being identical to it; (b) several are EXPANSIONS (½ → 1⁄2, ™ → TM, Ⅷ → VIII), so the existing `foldExpansion` mechanism must grow past 2 letters; (c) **the numeric scanner is the real work** — it currently tests raw bytes (`b >= '0' and b <= '9'`), so fullwidth digits would have to be folded BEFORE the digit-run scan to participate in natural-numeric ordering. That is a change to the hot loop, not just a new table. Recommend shipping the fullwidth block first behind the same opt-in-free default, and deferring the rest.
- [ ] Early-exit streaming comparator for strcoll8. The allocation is already gone; the remaining win is not building whole keys when the strings differ in the first element. Cost to weigh: it duplicates the key-building logic, demoting RULES.md #3 from true-by-construction to true-by-testing.

## Deferred (future, noted in README Limits)

Do not split `src/collation.zig`. About half of that file is tests, and the
length of `cli/main.c` is the help catalogs. A split would scatter one
algorithm without shrinking the part that changes. (2026-08-27 EDT)

- [ ] i18n ENFORCE phase: all 50 locales, compile/test enforcement, bilingual errors, RTL handling, alias-collision comptime guard. Flip when the CLI surface stabilizes (see the i18n skill checklist).
- [ ] Full Unicode normalization: fold DECOMPOSED combining-mark sequences to equal precomposed forms (v1 folds only precomposed Latin).
- [ ] Broaden diacritic coverage beyond Latin-1 + common Latin Extended-A.
- [ ] Wire the reserved option bits (`RCOL_NUMERIC`, `RCOL_CASE_SENSITIVE`) to actually toggle behavior.
- [ ] Optional locale tailoring: a real `rcol_open_locale`. (This is the architectural hook CJK would need — ICU calls it "tailoring"; it is a per-locale reordering layer, not more rows in `foldLetter`.)
- [ ] Optional table-only CJK tier behind a build flag (keeps the default binary small): hangul is algorithmic (jamo decomposition — zero data, and its code-point order is ALREADY correct dictionary order); kana is a ~200-entry gojūon table plus the JIS X 4061 tie-break levels (voicing/small-kana/ hiragana-vs-katakana); Han by Unihan `kTotalStrokes`/`kRSUnicode`. Stops short of pinyin/yomi — those need real dictionaries (polyphone and reading disambiguation is word-level, not character-level) and would blow the "small, no-ICU" thesis.
- [ ] SIMD sort-key generation for throughput.
