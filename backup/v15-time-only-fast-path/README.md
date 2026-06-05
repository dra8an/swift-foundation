# `v15` — Time-only fast path for Hebrew `nextDate`

*2026-05-04*

**Status: tested + benchmarked + parity-verified, NOT committed.** Builds
on `v14`. Closes the gap on `RecurrenceRuleDailyWithTimes` (was 0.51× ICU,
now ~8.5× ICU).

## Files in this snapshot

| File | Change since v14 |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Replaced the `!hasMonth && !hasDay && !hasWeekday → nil` rejection in `nextDate(after:matching:direction:)` with a time-only branch gated on `{hour, minute, second}` all set. Added `nextTimeOfDayMatch` helper: if `targetSecsInDay > currentSecsInDay` return RD same-day, else RD+1 (RD-1 backward). `_adjustedDate` (called per result in `_dates`) handles DST as before. |
| All other files | (unchanged from v14) |

## Why the change is local to Hebrew

For `RecurrenceRule(frequency: .daily, weekdays: [.every(.mon), ...], hours: [9, 10], minutes: [0, 30])`:

- **`weekdayAction == .limit`** (RFC5545 BYDAY for FREQ=DAILY is a limit,
  not an expand). So `_unadjustedDates` is called with combinations
  containing **no weekdays** — only hours, minutes, and seconds (the
  anchor's second).
- v13's `_expandedDateComponents` already produces 4 valid DCs for this
  shape: `{hour: 9, minute: 0, second: X}`, `{hour: 9, minute: 30, ...}`,
  `{hour: 10, minute: 0, ...}`, `{hour: 10, minute: 30, ...}`.
- The blocker was Hebrew's `nextDate` rejecting time-only DCs. Removing
  that rejection (with appropriate gating) lets v13's existing cartesian
  short-circuit fire.
- `_limitWeekdays` runs in `nextGroup()` AFTER `_dates` returns, dropping
  the 4 DCs on non-Mon/Tue/Wed days. No expansion-chain change needed.

## Performance: full benchmark (`v14` → `v15`)

p50, debug-mode, Intel iMac, Swift 6.3.1:

| Benchmark | `v14` | **`v15`** | Δ | vs ICU |
|---|---:|---:|---:|---:|
| **`RecurrenceRuleDailyWithTimes`** (µs) | 3,024 | **181** | **-94%** | **~8.5× ICU** |
| (other 8 benchmarks unchanged — see `bench_hebrew_results_v15_time_only.txt`) | | | | |

Mallocs on DailyWithTimes: 3,742 → **151** (-96%).

Per-match cost: 181 µs / 1,000 matches ≈ 180 ns/match (debug).

## Parity

- Suite C (`HebrewRecurrenceRuleParityProbe`): 13 tests, 392 rule shapes
  × 2,088 date comparisons, **0 divergences** vs `_CalendarICU(.hebrew)`.
- Suite A + Suite B + DST + Hebcal regression (73,414 days): all pass.
- Total: 178/178 Calendar+Suite-C tests, 62/62 Hebrew tests.

## Cross-calendar safety

The change is entirely inside `Calendar_Hebrew.swift`. No shared-code
changes. Non-Hebrew calendars are unaffected.

The new gating (`hour && minute && second` all non-nil) deliberately
matches only the shape produced by `_unadjustedDates`'s cartesian /
single-combo short-circuits for daily-frequency rules. Partial time
fields (e.g. `{hour: 9}` alone) still fall through to the generic
enumerate framework, preserving ICU semantics where unspecified fields
mean "any value".

## What's still on the slow path

- **`CurrentDateComponentsFromThanksgivings`**: not a RecurrenceRule
  benchmark; not exercised by our short-circuits. Cost is in
  `dateComponents(_:from:)` + Thanksgiving enumerate.

## Restoration

```sh
cp backup/v15-time-only-fast-path/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v15-time-only-fast-path/Tests/FoundationInternationalizationTests/*.swift \
   Tests/FoundationInternationalizationTests/
```
