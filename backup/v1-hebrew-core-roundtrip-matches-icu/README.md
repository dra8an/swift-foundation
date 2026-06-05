# v1 — Hebrew core round-trip matches ICU

**Date:** 2026-04-24
**Branch:** `port/hebrew`
**Base commit:** `8b98eac08084e15c5d1284b6efd5923dceaa491a` ([6.3] Avoid corruption when downsizing Data via replaceSubrange) on `upstream/release/6.3`
**Swift toolchain:** 6.3.1-RELEASE (via `swiftly`)

## What's stable at this checkpoint

- `_CalendarHebrew` class (class body only — 10 of 14 protocol methods still stubbed with `fatalError`).
- Full `HebrewArithmetic` enum ported from `icu4swift/Sources/CalendarComplex/HebrewArithmetic.swift`, including the three 2026-04-22 floor-division fixes:
  1. `hebrewFromFixed` year approximation uses `floorDiv`.
  2. `calendarElapsedDays` returns `Int64` (avoids Int32 overflow at year ≈ ±5.88 M).
  3. `calendarElapsedDays` internal divisions use `floorDiv`.
- `date(from:)` + `dateComponents(_:from:in:)` work correctly for {era, year, month, day, hour, minute, second, nanosecond, weekday, dayOfYear, timeZone, isLeapMonth}.
- Cross-check against Foundation's ICU-backed Hebrew passes for **400 consecutive days** (0 divergences).
- Discovered and fixed the stable-vs-dense month-numbering convention: Foundation uses stable (Adar always = 7 in common years, 7 in leap; Adar I = 6 only in leap; month 6 skipped in common years).

## What's still stubbed (crashes if called via router)

- `minimumRange`, `maximumRange`, `range(of:in:for:)`
- `ordinality(of:in:for:)`, `dateInterval(of:for:)`, `isDateInWeekend`
- `date(byAdding:to:wrappingComponents:)`
- `dateComponents(_:from:to:)`
- `bridgeToNSCalendar()` (framework-only)

Router in `Calendar_Cache.swift` has NOT been flipped yet — `.hebrew` still goes through `_CalendarICU`.

## Files in this backup

```
Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift
```

## How to restore

From `swift-foundation/` root:
```sh
cp backup/v1-hebrew-core-roundtrip-matches-icu/Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift Sources/FoundationEssentials/Calendar/
cp backup/v1-hebrew-core-roundtrip-matches-icu/Tests/FoundationEssentialsTests/HebrewCalendarTests.swift Tests/FoundationEssentialsTests/
cp backup/v1-hebrew-core-roundtrip-matches-icu/Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift Tests/FoundationInternationalizationTests/
```

## Verification at time of snapshot

```
swift test --filter "Hebrew"
→ 9 tests passed in 2 suites (5 correctness + 4 perf)
→ crossCheck_againstICU: 0/400 divergences
```
