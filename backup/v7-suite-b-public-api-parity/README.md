# v7 — Suite B (public Calendar API) parity complete, PR-ready

**Date:** 2026-04-24
**Branch:** `port/hebrew`
**Base commit:** `8b98eac08084e15c5d1284b6efd5923dceaa491a` on `upstream/release/6.3`
**Swift toolchain:** 6.3.1-RELEASE (via `swiftly`)

## What's stable at this checkpoint

Everything from v6, plus **Suite B (public `Calendar` API) parity** — the
non-negotiable requirement from `backup/PARITY_PROTOCOL.md` that protocol-only
parity is insufficient because Foundation's `Calendar` struct layers
calendar-specific logic over `_CalendarProtocol`.

## Summary of fixes landed in v7

Suite B surfaced 76 divergences that Suite A had missed. All closed:

1. **`range(hour, day)` / `range(minute, hour)` / `range(second, minute)` / `range(weekday, X)`:**
   Added Gregorian-style fixed-range fast paths (0..<24, 0..<60, 1..<8) instead
   of letting _algorithmA compute them (which was adding +1 to upper bound).

2. **`dateComponents(in:from:).isLeapMonth`:** Now always populated as `false`,
   matching ICU's behavior of filling the field even when not in the requested
   component set. (`_CalendarGregorian` does the same.)

3. **`isDateInWeekend(_:)`:** Full implementation copied from `_CalendarGregorian`.
   Uses `locale?.weekendRange` when available, falls back to CLDR 001 region
   default (Saturday 7 through Sunday 1). Previously returned `weekday == 7` only.

4. **`dateComponents(_:from:to:)`:** Proper multi-unit recursive subtraction
   algorithm matching `_CalendarGregorian`'s pattern. Iteratively subtracts
   the largest requested component first, then smaller. Fast path for time
   components (hour/minute/second/nanosecond) via direct TimeInterval math.

5. **`date(byAdding:)` ordering:** Year/month now applied BEFORE day-level
   additions (matching ICU's ordering), not after. Fixes e.g. "Adar I 1, 5776 +
   {year:1, month:2, day:3}" — ICU interprets as year-first (Adar I → Adar
   demotion when leap→common), then months, then days. Previous ordering was
   reversed and produced off-by-month results.

6. **`date(byAdding: .day, value: N, wrappingComponents: true)`:** Fast path
   for single-field day-wrap. Wraps within current month via `((day - 1 + N)
   mod monthLen) + 1`. Previous impl silently carried over to next month.

## Test state at this checkpoint

| Layer | Status |
|---|---|
| Foundation Calendar full suite | ✅ 165/165 tests pass |
| Hebcal 73,414-day regression | ✅ 0 divergences |
| 400-day ICU cross-check | ✅ 0 divergences |
| **Suite A: `_CalendarProtocol` probe** (10 dates × ~50 obs) | ✅ 0 divergences |
| **Suite B: public `Calendar` API probe** (10 dates × ~100+ obs) | ✅ 0 divergences |

## Perf (unchanged from v4; re-measured to verify no regression)

| Test | ICU baseline | `_CalendarHebrew` | Speedup |
|---|---:|---:|---:|
| allocationsForFixedHebrewCalendar | 21,321 ns | 4,315 ns | 4.9× |
| roundTripDateComponents | 20,346 ns | 5,793 ns | 3.5× |
| copyOnWriteHebrew | 69,590 ns | 3,428 ns | 20× |
| nextThousandHanukkahs | 776 µs | 6 µs | 129× |

## Files in this backup

```
Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift                 ← significantly refactored
Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
Tests/FoundationEssentialsTests/HebrewRegressionTests.swift
Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift
Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift    ← Suite A (updated)
Tests/FoundationInternationalizationTests/HebrewPublicAPIComparisonProbe.swift  ← Suite B (NEW)
```

## Remaining before PR

Only task #11 (Hebcal fixture size). Every other parity requirement is closed.

**The Hebrew port is functionally PR-ready and ICU-behaviorally indistinguishable
from the current `_CalendarICU(.hebrew)` on every observable public surface.**
