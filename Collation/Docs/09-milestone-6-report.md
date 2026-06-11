# Milestone 6 Report: Conformance & Performance Baseline

> Completed 2026-06-11. Companion to the outcome note in `04-milestone-plan.md`.
> Previous report: `08-milestone-5-report.md`.

## What this milestone was for

Milestones 1–5 verified against corpora we authored. This milestone runs the
*official* specification-derived test suite, adds randomized coverage we did
not author, and establishes honest performance numbers — turning "agrees with
ICU on our tests" into "conformant, and we know where it stands".

## 1. Official UCA/CLDR conformance suite — green

`CollationTest_CLDR_SHIFTED_SHORT.txt` and
`CollationTest_CLDR_NON_IGNORABLE_SHORT.txt` (UCA/UCD 17.0.0, shipped with
ICU, ~433k lines total) list strings in root-collation order. Following ICU's
own `UCAConformanceTest`: strength=identical, normalization on (always, for
us), alternate per file; for every pair of consecutive lines,
`compare(prev, cur)` must not be "descending" **and** the sort keys must order
identically. Both files pass on both data variants
(`Tests/.../ConformanceTests.swift`).

One scope note: lines containing unpaired surrogates are skipped (under 200
per file) because Swift `String` cannot represent them — a property shared
with ICU4X, which sorts lone surrogates as U+FFFD. If Foundation integration
needs byte-level UTF-8 input handling later, this becomes that layer's
concern, not the collator's.

## 2. Fuzz harness — 52k keys byte-identical

`Tools/gen_fuzz_corpus.py` (seeded, reproducible) generates 2000 random
strings weighted toward trouble spots: combining-mark stacks, contraction
bases (Tibetan, kana voicing, l·), digit runs in three scripts, Hangul +
Jamo, Han OFFSET ranges, format controls and other ignorables, CJK
compatibility and musical decompositions, supplementary planes, unassigned
code points and noncharacters. `gen_golden --keys-only` records ICU's sort
keys; `FuzzTests` requires byte identity for all 13 option sets × 2 data
variants. All 52,000 keys match.

Byte-identical keys imply identical ordering for every pair, so this is a
complete order check without a quadratic matrix — the pattern to reuse for
future, larger fuzz rounds (new seed → regenerate corpus + keys).

## 3. Performance baseline

Benchmarks: `Sources/Bench` (Swift, release) vs `Tools/bench_icu.c` (ICU 79,
-O2, normalization on), 200-string corpora × 200 reps, tertiary strength,
this machine (x86_64 mac):

| corpus | Swift compare | ICU compare | Swift sortKey | ICU sortKey |
|---|---|---|---|---|
| ASCII words | 2.2 µs | 16 ns | 3.7 µs | 198 ns |
| accented Latin | 2.3 µs | 17 ns | 3.7 µs | 210 ns |
| CJK | 2.4 µs | 73 ns | 3.1 µs | 229 ns |

**Work done in this milestone:** the initial numbers showed compare at
4.5–7.4 µs because both strings' CEs were fully materialized before
comparing. CE generation is now lazy (`CEIterator.ce(at:)` /
`appendMore()`), so the primary level usually decides after a few
characters — a 3× improvement with zero behavioral change (all 23 test
suites, conformance included, unchanged).

**Why the remaining ~100× compare gap is unsurprising and where it lives:**
- ICU's 16 ns ASCII number is its identical-prefix skip + fast-Latin table —
  paths we deliberately don't have yet (fast-Latin we *chose* not to port,
  per the ICU4X model; an identical-prefix skip needs normalization-safety
  markers from the planned trie-value data format).
- Each compare allocates several small arrays (NFD unit/marks buffers,
  lookahead, CE buffer, ×2 strings). For short strings, allocation dominates.
  The fixes — buffer reuse across the two iterators, `Span`-based data
  access, the single-trie normalization format — are the planned M8
  hardening work and need no architectural change.
- sortKey at ~15× is closer because it's inherently O(n); the same
  allocation work applies.

The honest conclusion: correctness is fully proven; the performance
architecture (lazy CEs, one-pass levels) is now the same shape as ICU's; the
constant factor is Swift-implementation maturity, with known, bounded causes.

## Limitations carried forward

- Strings containing U+0000 are excluded from reference corpora (the C
  reference tools are NUL-terminated); U+0000 handling is unit-tested only.
- Fuzz corpus avoids lone surrogates by construction (Swift Strings).
- Deep optimization deferred to M8 as planned.
