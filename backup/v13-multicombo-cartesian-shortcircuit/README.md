# `v13` — Multi-combination cartesian short-circuit in `_unadjustedDates`

*2026-05-04*

**Status: tested + benchmarked + parity-verified, NOT committed.** Builds
on `v12`. Adds a second short-circuit at `_unadjustedDates` that handles
RecurrenceRule patterns where the cartesian product of populated
`_DateComponentCombinations` fields produces N >= 2 fast-path-eligible
`DateComponents` (e.g., `RecurrenceRuleThanksgivingMeals` with 2 hours).

## Files in this snapshot

| File | Change since v12 |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` | Added `_expandedDateComponents` cartesian helper + multi-combination short-circuit in `_unadjustedDates` (after the existing v12 single-combination short-circuit). The cartesian helper rejects `.every(day)` weekdays, `.nth(N <= 0, day)` negative ordinals, and pattern shapes whose cartesian product exceeds 64 combinations (defensive cap). |
| All other files | (unchanged from v12) |

## Why "questionable" was lifted (parity verified)

Suite C (`HebrewRecurrenceRuleParityProbe`) passes unchanged: 13 tests,
392 rule shapes × 2,088 date comparisons, **0 divergences** vs
`_CalendarICU(.hebrew)`. The `yearly_multipleHours` test specifically
exercises the new multi-combination path (ThanksgivingMeals shape with
hours=[14, 18]) and confirms the date stream matches ICU exactly.

The other multi-combination benchmark patterns (`BikeParties` with
negative ordinals, `DailyWithTimes` with `.every` weekdays) are
**explicitly rejected** by the cartesian helper, so they fall through
to the existing expansion-chain — no behavior change for those.

## Performance: full benchmark (`v12` → `v13`)

p50, debug-mode, Intel iMac, Swift 6.3.1:

| Benchmark | `v12` | **`v13`** | Δ | vs ICU |
|---|---:|---:|---:|---:|
| `nextThousandThanksgivings` (ns) | 4,016 | 3,828 | -5% (noise) | ~260× |
| `nextThousandThanksgivingsSequence` (ns) | 4,346 | 4,033 | -7% (noise) | ~244× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` (ns) | 4,184 | 4,000 | -4% | ~111× |
| `RecurrenceRuleThanksgivings` (µs) | 107 | 110 | noise | 19× |
| **`RecurrenceRuleThanksgivingMeals`** (µs) | 1,469 | **89** | **-94%** | **15× ICU** |
| `RecurrenceRuleLaborDay` (µs) | 106 | 112 | noise | 15× |
| `RecurrenceRuleBikeParties` (µs) | 1,438 | 1,463 | unchanged | 0.85× |
| `RecurrenceRuleDailyWithTimes` (µs) | 3,038 | 2,973 | unchanged | 0.52× |
| `CurrentDateComponentsFromThanksgivings` (µs) | 5,978 | 5,675 | -5% | — |

Mallocs on `ThanksgivingMeals`: 1,767 → **79** (-96%).

## Cartesian helper detection logic

`_expandedDateComponents(_:)` returns the cartesian product of populated
fields if every shape is fast-path-eligible. It returns nil (causing
fall-through to the existing path) when:

- Any `weekdays` entry is `.every(day)` (no ordinal — doesn't reduce to a
  single fast-path DateComponents).
- Any `weekdays` entry is `.nth(N, day)` with `N <= 0` (negative ordinals
  diverge from ICU's raw `enumerateDates` behavior; preserving Suite A/B
  parity requires not extending the fast-path to negatives via this
  route).
- Cartesian product exceeds 64 combinations (defensive cap against
  pathological inputs — also bounds per-anchor work).
- Total = 1 (single-combination case is handled by the existing v12
  short-circuit).

## Cross-calendar safety

Same gating mechanism as v12: every probe is a `_calendarNextDate(...)`
call. Non-Hebrew calendars hit the protocol default (returns nil) on the
first DC → break out → fall through to existing path. Aggregate per-call
overhead for non-Hebrew calendars: ~10-50 ns (one extra cartesian-helper
call + one extra protocol probe). See `backup/SHARED_CODE_SAFETY.md` for
the full per-touchpoint analysis.

## What's still on the slow path

- **`RecurrenceRuleBikeParties`** (multi-weekday with negative ordinal):
  `.nth(-1, day)` rejected. Would require either negative-ordinal
  support in our `nextWeekdayOrdinalMatch` (parity break with raw
  enumerate) OR runtime translation to `{m, wd, weekOfMonth}` (anchor-
  dependent calendar queries inside the cartesian helper).
- **`RecurrenceRuleDailyWithTimes`** (multi-`.every(day)` weekdays +
  multi-hour + multi-minute): `.every(day)` rejected. Daily-frequency
  same-day-time-of-day semantic doesn't fit our `{wd}` fast path
  (which always advances a full week on weekday match).

## Restoration

```sh
cp backup/v13-multicombo-cartesian-shortcircuit/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v13-multicombo-cartesian-shortcircuit/Tests/FoundationInternationalizationTests/*.swift \
   Tests/FoundationInternationalizationTests/
```
