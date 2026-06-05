# v2 — Hebrew router flipped, all 164 tests pass

**Date:** 2026-04-24
**Branch:** `port/hebrew`
**Base commit:** `8b98eac08084e15c5d1284b6efd5923dceaa491a` ([6.3] Avoid corruption when downsizing Data via replaceSubrange) on `upstream/release/6.3`
**Swift toolchain:** 6.3.1-RELEASE (via `swiftly`)

## What's stable at this checkpoint

- All 14 `_CalendarProtocol` methods implemented (some with safe defaults for obscure `(smaller, larger)` combinations).
- `date(byAdding: .day)` is **DST-aware**: walks civil days by unpacking → incrementing → repacking (correct but slow — see task #10).
- `dateInterval(of:.year/.month/.day)` uses `start-of-next-unit minus start-of-this-unit` in local time (captures 23/25-hour DST transition days).
- **Router is flipped:** `_calendarClass(identifier: .hebrew)` returns `_CalendarHebrew.self`.
- **All 164 tests pass** across the full Calendar suite (153 existing Foundation + 11 new Hebrew).
- 0 divergences vs ICU across the 400-day cross-check sweep.

## Performance (debug mode, best of 5 runs)

| Test | ICU baseline | `_CalendarHebrew` | Speedup |
|---|---:|---:|---:|
| allocationsForFixedHebrewCalendar | 21,321 ns | 12,490 ns | 1.7× |
| roundTripDateComponents | 20,346 ns | 6,713 ns | 3.0× |
| copyOnWriteHebrew | 69,590 ns | 12,875 ns | 5.4× |
| **nextThousandHanukkahs** | **776 µs** | **4 µs** | **🚀 194×** |

## Known limitations

- **Task #10 (CRITICAL):** `date(byAdding: .day)` DST-aware path is ~12 µs (debug) — dominated by two `TimeZone.rawAndDaylightSavingTimeOffset` calls + `DateComponents` round-trip. Known fix: compute offsets at both endpoints, adjust by delta, skip unpack/repack. Expected to restore 30×+ on alloc/CoW benches.
- `ordinality` returns `nil` for some `(smaller, larger)` combinations (weekday-related, weekOfYear-related, quarter-related). None currently exercised by Foundation's existing tests.
- `dateInterval(of:)` returns `nil` for `.weekOfYear`, `.weekOfMonth`, `.quarter`, `.yearForWeekOfYear`, `.isLeapMonth`, `.isRepeatedDay`. Same — no tests exercise these for Hebrew.
- `dateComponents(_:from:to:)` is a crude second-based approximation (not a proper Foundation-style recursive multi-unit subtraction).
- `date(byAdding:wrappingComponents: true)` uses the same carry-over path as `false` (approximate).

## Files in this backup

```
Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
Sources/FoundationEssentials/Calendar/Calendar_Cache.swift   ← router flip
Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift
```

## How to restore

From `swift-foundation/` root:
```sh
cp backup/v2-hebrew-router-flipped-all-tests-pass/Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift Sources/FoundationEssentials/Calendar/
cp backup/v2-hebrew-router-flipped-all-tests-pass/Sources/FoundationEssentials/Calendar/Calendar_Cache.swift Sources/FoundationEssentials/Calendar/
cp backup/v2-hebrew-router-flipped-all-tests-pass/Tests/FoundationEssentialsTests/HebrewCalendarTests.swift Tests/FoundationEssentialsTests/
cp backup/v2-hebrew-router-flipped-all-tests-pass/Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift Tests/FoundationInternationalizationTests/
```

## Verification at time of snapshot

```
swift test --filter "Calendar"
→ 164 tests passed in 9 suites (153 Foundation + 11 Hebrew)
→ 0 regressions; 0 divergences vs ICU on cross-check
```
