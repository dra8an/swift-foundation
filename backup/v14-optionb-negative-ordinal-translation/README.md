# `v14` — Option B: BikeParties via runtime weekOfMonth translation for negative ordinals

*2026-05-04*

**Status: tested + benchmarked + parity-verified, NOT committed.** Builds
on `v13`. Closes the gap on `RecurrenceRuleBikeParties` (was 0.85× ICU,
now 10.8× ICU).

## Files in this snapshot

| File | Change since v13 |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` | (1) Added `_unadjustedDatesHasNegativeOrdinal` helper. (2) Extended `_expandedDateComponents` to accept an optional `anchor: Date?`. When supplied, `.nth(N<0, day)` weekday entries are translated at runtime to `{month, weekday, weekOfMonth}` using the anchor's month structure (target month = `c.months[0]` if single, else anchor's month). The translation routes through our existing `{m, wd, weekOfMonth}` fast path — preserving Suite A/B raw-enumerate parity (which rejects negative `weekdayOrdinal` directly). (3) Added new short-circuit branch (3) in `_unadjustedDates` for negative-ordinal patterns, gated by a sentinel `_calendarNextDate(matching: {weekday: 1})` probe (cross-calendar early-bail). |
| All other files | (unchanged from v13) |

## Why "questionable" was lifted (parity verified)

Suite C (`HebrewRecurrenceRuleParityProbe`) passes unchanged: 13 tests,
392 rule shapes × 2,088 date comparisons, **0 divergences** vs
`_CalendarICU(.hebrew)`. The `monthly_multipleNthWeekdays` test
specifically exercises the new negative-ordinal path (BikeParties shape
with `[.nth(1, fri), .nth(-1, fri)]`) and confirms the date stream
matches ICU exactly.

The parity was preserved because we route negative ordinals through the
**existing** `{m, wd, weekOfMonth}` fast path (which Suite A/B already
verified matches ICU), not through any new negative-ordinal-supporting
path that would diverge from ICU's raw `enumerateDates` behavior.

## Performance: full benchmark (`v13` → `v14`)

p50, debug-mode, Intel iMac, Swift 6.3.1:

| Benchmark | `v13` | **`v14`** | Δ | vs ICU |
|---|---:|---:|---:|---:|
| `nextThousandThanksgivings` (ns) | 3,828 | 3,856 | noise | ~258× |
| `nextThousandThanksgivingsSequence` (ns) | 4,033 | 4,037 | ~ | ~244× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` (ns) | 4,000 | 4,018 | ~ | ~111× |
| `RecurrenceRuleThanksgivings` (µs) | 110 | 105 | -5% | 19× |
| `RecurrenceRuleThanksgivingMeals` (µs) | 89 | 87 | ~ | 16× |
| `RecurrenceRuleLaborDay` (µs) | 112 | 108 | -4% | 15× |
| **`RecurrenceRuleBikeParties`** (µs) | 1,463 | **115** | **-92%** | **10.8× ICU** |
| `RecurrenceRuleDailyWithTimes` (µs) | 3,024 | 3,024 | unchanged | 0.51× |
| `CurrentDateComponentsFromThanksgivings` (µs) | 5,710 | 5,673 | ~ | — |

Mallocs on BikeParties: 1,743 → **127** (-93%).

## How the translation works (BikeParties as example)

For `RecurrenceRule(frequency: .monthly, weekdays: [.nth(1, fri), .nth(-1, fri)])`:

1. **Single-combo short-circuit (v12) fails** — multiple weekdays.
2. **v13 cartesian short-circuit fails** — negative ordinal rejected.
3. **v14 negative-ordinal path** activates:
   - `_unadjustedDatesHasNegativeOrdinal` → true (one negative).
   - Sentinel probe `_calendarNextDate(after: monthStart, matching: {weekday: 1}, .forward)` → returns next Sunday for Hebrew (non-nil) → calendar has fast path.
   - For non-Hebrew: returns nil → bail (no translation cost).
   - `_expandedDateComponents(combinations, anchor: monthStart)`:
     - `.nth(1, fri)` → DC₁ = `{weekday: 6, weekdayOrdinal: 1}` (positive — direct).
     - `.nth(-1, fri)` → translate runtime:
       - Compute month start, day1 weekday, days-in-month.
       - First Friday = day `1 + ((6 - day1Weekday + 7) % 7)`.
       - Total Fridays = `(daysInMonth - firstOcc) / 7 + 1`.
       - Last Friday day = `firstOcc + (totalOcc - 1) * 7`.
       - weekOfMonth(lastFriday) per ICU formula.
       - DC₂ = `{month: M, weekday: 6, weekOfMonth: K}`.
   - Probe DC₁ via `_calendarNextDate(matching: {wd:6, wdOrd:1})` → routes to `nextWeekdayOrdinalMatch` (no month).
   - Probe DC₂ via `_calendarNextDate(matching: {m, wd:6, wOM})` → routes to `nextMonthWeekdayWeekOfMonthMatch`.
   - Both succeed → sort by date, return `[(firstFri, DC₁), (lastFri, DC₂)]`.

Total per anchor: ~3 calendar primitive calls (year, month, dateInterval/range/weekday for translation) + ~2 fast-path calls. Vs the existing path's ~10 primitive calls + flatMap allocations.

## Cross-calendar safety

Same gating mechanism as v8–v13: every probe is a `_calendarNextDate(...)`
call. Non-Hebrew calendars hit the protocol-default nil on the sentinel
probe → bail before doing the translation. Aggregate added cost for
non-Hebrew calendars per `_unadjustedDates` call when negative ordinals
are present: ~10 ns (the sentinel probe).

For Hebrew with negative ordinals: ~3 calendar primitive calls per
`_unadjustedDates` invocation (target month structure) + 2 fast-path
probes. ~1 µs total per call vs the slow path's ~1.5 µs. Net win:
~500 ns/anchor + skipping ~7 helper invocations per anchor.

## What's still on the slow path

- **`RecurrenceRuleDailyWithTimes`**: `.every(day)` weekdays + multi-hour
  + multi-minute. The `.every` semantic doesn't fit our `{wd}` fast path
  (which advances a full week on weekday match). Closing this would
  require either a daily-frequency-aware fast path variant or hoisting
  fast-path into `DatesByRecurring.Iterator` — neither attempted in v14.

- **`CurrentDateComponentsFromThanksgivings`**: not a RecurrenceRule
  benchmark; not exercised by our short-circuits. Cost is in
  `dateComponents(_:from:)` + Thanksgiving enumerate.

## Restoration

```sh
cp backup/v14-optionb-negative-ordinal-translation/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v14-optionb-negative-ordinal-translation/Tests/FoundationInternationalizationTests/*.swift \
   Tests/FoundationInternationalizationTests/
```
