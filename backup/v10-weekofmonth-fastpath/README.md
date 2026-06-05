# v10 — `{month, weekday, weekOfMonth}` fast path

*2026-05-03*

**Status: tested, NOT yet committed.** Builds on v8 + v9 (also uncommitted).
Pure additive change in `Calendar_Hebrew.swift` only — no shared-code touch.

## Files in this snapshot

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | (1) Removed `weekOfMonth` from the immediate-reject in `nextDate`; added a specific guard requiring `{month, weekday, weekOfMonth}` shape (no day, no wdOrd). (2) Added dispatch branch in `nextDate`. (3) Added private helper `nextMonthWeekdayWeekOfMonthMatch` — inverts the calendar-agnostic ICU week-numbering algorithm to find the day-of-month directly in O(1) per candidate year. |
| `Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift` | Added 5 new probe rows to `extendedFastPath_correctnessVsICU`: `{m:11,wd:5,wOM:4}`, `{m:1,wd:7,wOM:1}`, `{m:7,wd:6,wOM:5}`, `{m:6,wd:2,wOM:2}` (Adar I leap-only), `{m:11,wd:5,wOM:4,h:14}` (with time). |

## Algorithm

For each candidate year:

```
firstDayWeekday = weekday-of(day-1 RD)                         # 1..7
periodStart     = (firstDayWeekday - firstWeekday + 7) % 7     # 0..6
correction      = (7 - periodStart) >= minDaysInFirstWeek ? 1 : 0
dayOffsetInWeek = (targetWeekday - firstWeekday + 7) % 7       # 0..6
day             = 7 * (targetWeekOfMonth - correction) + dayOffsetInWeek - periodStart + 1
```

Reject if `day < 1 || day > daysInMonth`, advance year, retry (max 6 iterations).

The formula inverts the same week-numbering rule used by
`weekNumber(...)` in this file (and matching the calendar-agnostic
algorithm shared with `_CalendarGregorian`).

## Verification

- 49/49 Hebrew tests pass.
- 165/165 Calendar tests pass.
- 73,414 Hebcal days clean.
- All 5 new probes pass: 0 divergences vs ICU's `enumerateDates`.

## Performance

| Benchmark | v9 | **v10** | Δ | vs ICU baseline |
|---|---:|---:|---:|---:|
| `nextThousandThursdaysInTheFourthWeekOfNovember` | 527 µs | **4,080 ns** (p50) | **129× faster** | **109× ICU** |
| Mallocs | 646 | **0** | eliminated | 0 |

The single benchmark that exercised this pattern in the package suite
collapses from a slight ICU regression (0.84×) to a 109× ICU win.

## Why "questionable" — reasons not yet committed

It's not really questionable per se — pure additive, all tests pass.
But it's bundled with v8/v9 in the working tree as part of the larger
"Hebrew port performance pass" and committing one without the others
would be a strange split.

## Restoration

```sh
cp backup/v10-weekofmonth-fastpath/Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
cp backup/v10-weekofmonth-fastpath/Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift \
   Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift
```
