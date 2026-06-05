# v11 — Helper-level fast-path hijacks

*2026-05-03*

**Status: tested + benchmarked, NOT committed.** Builds on v8 + v9 + v10
(also uncommitted). Single-match correctness preserved (49/49 Hebrew,
165/165 Calendar, 73,414 Hebcal regression all green).

## Files in this snapshot

| File | Change since v10 |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Extended `nextDate` rejection guard to allow `{weekday, weekdayOrdinal}` (no month). Added `nextWeekdayOrdinalMatch` helper. Documented `{weekday, weekOfMonth}` no-month rejection (parity break with ICU on rare patterns). |
| `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` | Two hijack injections: (a) top of `dateAfterMatchingWeekdayOrdinal` — calls `_calendarNextDate` after the early "no advancement" check (harmless but unused on the RecurrenceRule path); (b) top of `dateAfterMatchingWeekOfMonth` — enriches `components` with `date`'s current civil month before calling `_calendarNextDate`, routing through the safe `{m, wd, weekOfMonth}` fast path. |
| `Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift` | Added 3 `{wd, wdOrd}` no-month correctness probes. |
| `Sources/FoundationEssentials/Calendar/Calendar.swift` | (unchanged from v8 — keeps `_calendarNextDate` proxy) |

## Performance: full benchmark (v5 → v11)

p50, debug-mode, Intel iMac, Swift 6.3.1:

| Benchmark | v5 | v11 | Δ | vs ICU |
|---|---:|---:|---:|---:|
| `nextThousandThanksgivings` (ns) | 3,873 | 4,022 | noise | ~248× |
| `nextThousandThanksgivingsSequence` (ns) | 4,133 | 4,020 | -3% | ~245× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` (ns) | 4,080 | 4,073 | ~ | ~109× |
| `RecurrenceRuleThanksgivings` (µs) | 1,882 | **1,688** | **-10%** | **1.23× ICU** |
| `RecurrenceRuleThanksgivingMeals` (µs) | 1,625 | 1,598 | -2% | 0.85× |
| `RecurrenceRuleLaborDay` (µs) | 1,650 | 1,637 | -1% | 1.00× |
| `RecurrenceRuleBikeParties` (µs) | 1,638 | **1,430** | **-13%** | 0.87× |
| `RecurrenceRuleDailyWithTimes` (µs) | 3,028 | 3,010 | ~ | 0.51× |
| `CurrentDateComponentsFromThanksgivings` (µs) | 5,773 | 5,894 | ~ | (N/A) |

Mallocs (RecurrenceRule benchmarks):
- ThanksgivingMeals: 2,071 → **1,837** (-11%)
- BikeParties: 1,993 → **1,757** (-12%)
- Thanksgivings: 2,456 → **1,991** (-19%)
- LaborDay: 2,038 → **1,940** (-5%)

## Why "questionable" — and why the wins are smaller than hoped

The helper hijack only attacks **one** contributor (the inner
`dateAfterMatchingWeekOfMonth` walk). The remaining ~1,400 ns/match
lives in:

- `_dateComponents(...)` decomposing the anchor (~200 ns)
- `dateInterval(of: .year, for:)` computing search bounds (~200 ns)
- `_DateComponentCombinations` build (~100 ns)
- `_adjustedDate(...)` DST adjustment per match (~300 ns)
- `flatMap` array allocations in `_unadjustedDates` (~200 ns)
- `_limitMonths/Days/Weekdays/Time` filter passes (~200 ns)
- `baseRecurrence.next()` advance (~150 ns)

The user observed "still not the improvement I was looking for" — fair
critique. Closing more of the gap requires either restructuring
`_unadjustedDates` to short-circuit allocation/DST/filter work for
single-combination patterns, hijacking additional inner helpers
(`dateAfterMatchingMonth`, `dateAfterMatchingWeekday`, etc.), or hoisting
the entire fast-path into `DatesByRecurring.Iterator` (with the safety
caveats from `RECURRENCE_VS_NEXTDATE.md`).

## Correctness gotcha discovered while developing this

We initially tried fast-pathing `{weekday, weekOfMonth}` without month.
This produced a parity break vs ICU on rare patterns like `{wd:2, wOM:1}`
(Mon in week 1) — ICU's `enumerateDates` truncates after some
unsuccessful month-skips while ours keeps advancing month-by-month
indefinitely. ICU returned 31 matches over 100 requested; we returned 100.

**Fix**: rejected the no-month form in our fast-path guard. The helper
hijack at `dateAfterMatchingWeekOfMonth` enriches the components with
the date's current month BEFORE calling our fast path, so we always go
through the safe `{m, wd, weekOfMonth}` translation that's been verified
to match ICU exactly.

This pattern (enrich-and-reroute) is a useful safety primitive — keeps
the fast-path's parity guarantees while still benefiting the helper's
hot path.

## Restoration

```sh
cp backup/v11-helper-hijack/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v11-helper-hijack/Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift \
   Tests/FoundationInternationalizationTests/
```
