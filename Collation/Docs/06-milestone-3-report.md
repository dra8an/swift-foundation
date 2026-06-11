# Milestone 3 Report: Full Level Loop + Settings

> Completed 2026-06-11 (commit `42b55f1`). Companion to the outcome note in
> `04-milestone-plan.md`. Previous report: `05-milestone-2-report.md`.

## What this milestone was for

Milestones 1–2 compared at primary strength only. This milestone graduates the
collator to the complete UCA comparison: secondary (accents), case, tertiary,
quaternary levels, plus the settings that configure them. After this, the
remaining gaps to full root-collation conformance are context matching (M4)
and sort keys (M5) — the *comparison semantics* are now complete.

## What was built

- **`CollationOptions`** (`CollationOptions.swift`): public options struct —
  strength (primary/secondary/tertiary/quaternary/identical), alternate
  (non-ignorable/shifted), maxVariable (space/punct/symbol/currency),
  case-first (off/lower/upper), case-level, backwards-secondary ("French"),
  numeric. Internally it produces the exact `CollationSettings` options word
  from ICU4C, so the ported comparison code uses the same bit tests as the
  original (`tertiaryMask`, `sortsTertiaryUpperCaseFirst`, …).
- **`CEIterator`** (`CollationElements.swift`): produces the full 64-bit CEs
  of a string through the NFD front end, terminated by `NO_CE`. Includes the
  CODAN numeric path: digit runs are collected (with a one-scalar pushback
  into the normalized stream) and encoded as length-graded primaries — the
  dense ≤7-digit encodings and the digit-pair encoding for long runs, ported
  from `appendNumericCEs`/`appendNumericSegmentCEs`.
- **`CollationCompare`** (`CollationCompare.swift`): faithful port of
  `CollationCompare::compareUpToQuaternary` over materialized CE arrays —
  primary loop with variable-CE shifting (rewrites variable CEs to
  primary-only and zeroes trailing primary-ignorables, in place), forward and
  backward (French, merge-separator-segmented) secondary, the case level with
  its primary-strength and upper-first subtleties, tertiary with case-first
  weight transforms (`^= 0xc000` / `+= 0x4000`), and the quaternary loop with
  the `| 0xffffff3f` regular-CE saturation. Script reordering hooks omitted
  (M7).
- **`RootCollator.compare(_:_:options:)`**: derives variableTop from the
  newly-parsed scripts data (`lastPrimaryForGroup`, present in both bundled
  data variants), runs the level loop, and for identical strength breaks ties
  by NFD code-point order via the existing `NFDIterator`.

## Verification

`gen_golden.c` now emits one matrix per configuration; the corpus grew to 239
strings (shifted classics like "di Silva"/"diSilva"/"di-Silva", numeric runs
incl. a 32-digit value, French accent pairs, ignorables, currency/symbol
variables). 13 configurations:

| Config | Strength | Setting |
|---|---|---|
| primary…identical | each | defaults |
| shifted / shifted3 | quaternary / tertiary | alternate=shifted |
| case1 / caselevel | primary / tertiary | caseLevel=on |
| upperfirst / lowerfirst | tertiary | caseFirst |
| french | tertiary | backwards secondary |
| numeric | tertiary | CODAN |

13 configs × 2 data variants (regular + NFD-only ICU4X) × 239² pairs =
**1.49M comparisons, 100% agreement with ICU 79.**

## Two findings worth remembering

1. **ICU's root collator defaults to normalization OFF.** Our implementation
   (like ICU4X) always normalizes. For input whose combining marks are not in
   canonical order, the two genuinely differ at secondary strength and the
   difference showed up immediately in the matrix. The oracle now sets
   `UCOL_NORMALIZATION_MODE=UCOL_ON` everywhere. Implication for Foundation
   integration: our comparisons match "ICU with normalization on", which is
   the CLDR-recommended and canonically-correct behavior — but not bit-for-bit
   ICU's *default* on non-FCD input.
2. **Transcribed constants are a liability.** A garbled
   `CASE_AND_TERTIARY_MASK` (0xc03f instead of `CASE_MASK |
   ONLY_TERTIARY_MASK` = 0xff3f) zeroed the NO_CE terminator's masked
   tertiary and ran the case-first tertiary loop out of bounds. The
   caseFirst differential configs caught it within seconds — exactly the kind
   of bug the per-setting matrices exist for. Masks are now written as
   derivations of their component constants, not as literals.

## Limitations carried forward

- Contexts still resolve to default CE32s (M4).
- No script reordering (M7); `[reorder]`-dependent settings untested.
- No sort keys (M5).
- CE arrays are materialized per compare; fine for correctness, revisit
  in the perf pass (M6).
