# v8 — `_enumerateDatesStep` fast-path wiring

*2026-05-03*

**Status: tested + benchmarked, NOT yet committed.** Snapshotted before
attempting a follow-up optimization (hoisting the fast-path probe-and-loop
into `DatesByMatching.Iterator` to skip per-call `_enumerateDatesStep`
overhead). If the hoist works out cleanly, v8's wiring will probably be
removed in favor of the lower-overhead form.

## Files in this snapshot

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar.swift` | Added internal `_calendarNextDate(after:matching:direction:)` proxy on `Calendar`. Lets `_enumerateDatesStep` (in `Calendar_Enumerate.swift`) reach the protocol fast-path without exposing `private _calendar` storage across files. |
| `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` | Added top-of-function fast-path check in `_enumerateDatesStep`: when policies are at default and `_calendarNextDate(...)` returns non-nil, synthesize `SearchStepResult(result: (fast, true), newSearchDate: fast)` and return immediately. Mirrors the wiring in `Calendar.enumerateDates`. |

## What this enables

Sequence API (`cal.dates(byMatching:)`) and most `RecurrenceRule*` benchmarks
now consult the per-calendar fast-path. Hebrew sees big wins; other
calendars unaffected (their default `_CalendarProtocol.nextDate` returns
nil, so they fall through to the existing generic path).

## Verification at this snapshot

- `swift test --filter "Hebrew"` → 49/49 pass.
- `swift test --filter "Calendar"` → 165/165 pass.
- 73,414/73,414 Hebcal regression days unchanged.
- Package benchmark wins (debug-mode, p50, vs ICU prior baseline):
  - `nextThousandThanksgivingsSequence`: 1,096 µs → **4.25 µs** (258× speedup vs prior; ~232× ICU).
  - `RecurrenceRuleThanksgivings`: 3,276 µs → **1,988 µs** (now 1.04× ICU — slightly beats it).
  - `RecurrenceRuleLaborDay`: 2,952 µs → **1,733 µs** (-41%).
  - `RecurrenceRuleThanksgivingMeals`: 2,285 µs → **1,704 µs** (-25%).
  - `RecurrenceRuleBikeParties`: 2,226 µs → **1,684 µs** (-24%).
  - `RecurrenceRuleDailyWithTimes`: 2,979 µs → 3,089 µs (~ — pattern not in fast path).
  - `nextThousandThanksgivings` (already fast): 3,893 ns → 3,983 ns (noise).

## Why "questionable" — reasons the next iteration may replace this

- **Per-call policy recheck**: `_enumerateDatesStep` rechecks
  `matchingPolicy == .nextTime && repeatedTimePolicy == .first` on every
  call. `Calendar.enumerateDates` checks once and commits to a tight
  loop. Sequence API still pays this cost (~7% slower than block API at
  the same fast-path pattern: 4,248 ns vs 3,983 ns p50).
- **`SearchStepResult` build/destructure** per call.
- **Proxy hop** through `_calendarNextDate` (added to keep `_calendar`
  private). Cheap but non-zero.
- **Iterator state mutation** per call.

The follow-up plan: hoist the fast-path probe-and-commit into
`DatesByMatching.Iterator` itself, mirroring the structure of
`Calendar.enumerateDates`'s fast loop. If that matches the block-based
benchmark numbers, this v8 wiring becomes redundant.

## Restoration

```sh
cp backup/v8-enumeratedatesstep-fastpath/Sources/FoundationEssentials/Calendar/Calendar.swift \
   Sources/FoundationEssentials/Calendar/Calendar.swift
cp backup/v8-enumeratedatesstep-fastpath/Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift
```
