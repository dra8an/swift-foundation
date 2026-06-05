# v12 — RecurrenceRule single-combination short-circuit + Month/Weekday helper hijacks + parity probe

*2026-05-04*

**Status: tested + benchmarked + parity-verified, NOT committed.** Builds
on v8/v9/v10/v11 (also uncommitted). This is the largest single perf gain
in the entire stack: `RecurrenceRuleThanksgivings` and
`RecurrenceRuleLaborDay` collapsed by ~16× from v11.

## Files in this snapshot

| File | Change since v11 |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` | **NEW**: single-combination short-circuit at top of `_unadjustedDates`. When every populated `_DateComponentCombinations` field has exactly one value (and policies at default), translates to a `DateComponents` and calls `_calendarNextDate` directly, returning `[(fast, dc)]` and skipping the entire expansion-chain. New helper `_singleCombinationDateComponents` for the translation. |
| `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` | **NEW**: helper hijack at `dateAfterMatchingMonth` (calls `_calendarNextDate` with minimal `{month, isLeapMonth}` components after the early "no advancement" check) and `dateAfterMatchingWeekday` (with minimal `{weekday}` components). Existing v8/v9/v11 wirings preserved. |
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | (unchanged from v11) |
| `Sources/FoundationEssentials/Calendar/Calendar.swift` | (unchanged from v8 — keeps `_calendarNextDate` proxy) |
| `Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift` | (unchanged from v11) |
| `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift` | **NEW** Suite C parity probe: 13 tests, 392 rule shapes × 2,088 date comparisons, **0 divergences** vs `_CalendarICU(.hebrew)`. |

## Why "questionable" was lifted

v8–v11 were all marked "questionable" because we lacked an ICU↔Hebrew
parity probe for `RecurrenceRule`. The user's existing parity protocol
(`backup/PARITY_PROTOCOL.md`) is non-negotiable — every observable
calendar surface must match ICU exactly.

v12 adds Suite C (`HebrewRecurrenceRuleParityProbe`) covering:
- Single-combination patterns that hit the short-circuit fast path
- Multi-combination patterns that fall through (multi-hour, multi-weekday,
  multi-month, daily-with-times)
- Negative ordinals (`.nth(-1)`, `.nth(-2)`)
- Edge cases (Adar I leap-only, default matchingPolicy, interval > 1,
  day-of-month, `.every(weekday)`)
- 8 anchor dates spanning leap/common years and Adar transitions

**2,088 date comparisons, 0 divergences.** This is the strongest
correctness evidence we have for the Hebrew port at the RecurrenceRule
level.

## Performance: full benchmark (`v9` → `v12`)

p50, debug-mode, Intel iMac, Swift 6.3.1. Snapshot labels match
`backup/BACKUPS.md` and `backup/BENCHMARKS_PACKAGE.md`.

| Benchmark | `v9` (Iterator hoist) | `v11` (helper hijack) | **`v12`** | vs ICU |
|---|---:|---:|---:|---:|
| `nextThousandThanksgivings` (ns) | 3,873 | 4,022 | 4,016 | ~248× |
| `nextThousandThanksgivingsSequence` (ns) | 4,133 | 4,020 | 4,346 | ~227× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` (ns) | 4,080 | 4,073 | 4,184 | ~106× |
| **`RecurrenceRuleThanksgivings`** (µs) | 1,882 | 1,688 | **107** | **19× ICU** |
| **`RecurrenceRuleLaborDay`** (µs) | 1,650 | 1,637 | **106** | **15× ICU** |
| `RecurrenceRuleThanksgivingMeals` (µs) | 1,625 | 1,598 | **1,469** | 0.92× |
| `RecurrenceRuleBikeParties` (µs) | 1,638 | 1,430 | 1,438 | 0.87× |
| `RecurrenceRuleDailyWithTimes` (µs) | 3,028 | 3,010 | 3,038 | 0.50× |
| `CurrentDateComponentsFromThanksgivings` (µs) | 5,773 | 5,894 | 5,978 | (N/A) |

Mallocs (RecurrenceRule): Thanksgivings 2,456 → **102** (-96%); LaborDay
2,038 → **92** (-95%); other RecurrenceRule benchmarks 5–15% reduction.

## What helped vs what didn't

The v12 stack has TWO mechanisms; per-benchmark attribution:

- **Single-combination short-circuit (the home run)** — fires when every
  populated `_DateComponentCombinations` field has exactly one value.
  Skips the entire expansion-chain in `_unadjustedDates`. **All the
  big win on `RecurrenceRuleThanksgivings` and `RecurrenceRuleLaborDay`
  came from this** (15.5× and 15.4× speedups respectively).
- **Helper hijacks (base hits at best)** — `dateAfterMatchingMonth`,
  `dateAfterMatchingWeekday`, plus existing v11 hijacks at
  `dateAfterMatchingWeekOfMonth` and `dateAfterMatchingWeekdayOrdinal`.
  Smaller wins:
  - `RecurrenceRuleThanksgivingMeals` saw -7% from `dateAfterMatchingMonth`
    fire (single-combination short-circuit doesn't fire because hours
    has 2 values).
  - `RecurrenceRuleBikeParties` saw 0% benefit from v12 — has no `months`
    field, and `dateAfterMatchingWeekday` is a no-op (the v11
    `dateAfterMatchingWeekOfMonth` hijack already lands the date on the
    right weekday). The 13% v11 win on this benchmark was the
    `dateAfterMatchingWeekOfMonth` hijack from earlier.
  - `RecurrenceRuleDailyWithTimes` saw 0% benefit — `dateAfterMatchingMonth`
    never invoked (no `months`), and the existing helper walks are bounded
    short enough that hijacking saves only a few ns/call against ~3 µs
    of total per-match cost dominated by `_adjustedDate` + filter passes
    + 12-combination flatMap allocation.

The remaining cost on multi-combination benchmarks lives in machinery
surrounding the helpers (12-way flatMap chain, `_adjustedDate` DST
adjustment, `_limitX` filter passes), not in the helpers themselves.
Closing that gap would require either:
1. Multi-combination interleaving in `_unadjustedDates` (interleave N
   fast-path streams in chronological order — significant complexity
   for RFC5545 ordering).
2. Hoisting the entire fast-path into `DatesByRecurring.Iterator` (with
   the safety caveats from `RECURRENCE_VS_NEXTDATE.md`).

Neither attempted in v12.

## Restoration

```sh
cp backup/v12-recurrence-shortcircuit-and-parity-probe/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v12-recurrence-shortcircuit-and-parity-probe/Tests/FoundationInternationalizationTests/*.swift \
   Tests/FoundationInternationalizationTests/
```
