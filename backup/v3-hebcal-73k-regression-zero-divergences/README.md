# v3 — Hebcal 73,414-day regression at 0/0 divergences

**Date:** 2026-04-24
**Branch:** `port/hebrew`
**Base commit:** `8b98eac08084e15c5d1284b6efd5923dceaa491a` on `upstream/release/6.3`
**Swift toolchain:** 6.3.1-RELEASE (via `swiftly`)

## What's stable at this checkpoint

Everything from v2, plus:
- **Full Hebcal regression ported.** `HebrewRegressionTests.swift` reads the 73,414-row CSV and verifies every single Gregorian → Hebrew conversion. **0 failures.**
- **Struct named `HebrewCalendarRegressionTests`** so Swift Testing's `--filter "Calendar"` picks it up automatically.
- `165 tests in 10 suites pass` across the entire Calendar surface.

## Test coverage summary

| Suite | Tests | Purpose |
|---|---:|---|
| Gregorian Calendar (Internationalization) | various | existing Foundation Gregorian tests |
| Gregorian Calendar | 20+ | existing Foundation Gregorian tests (Essentials) |
| GregorianCalendar RecurrenceRule | 1 | recurrence rules, Gregorian |
| Calendar RecurrenceRule | 1 | recurrence rules, ICU-backed (non-Hebrew) |
| Calendar | 1 | `Calendar`-level behavior tests |
| Locale | 1 | locale-dependent calendar tests |
| Hebrew Calendar | 7 | round-trip, leap-year, cross-check, debug |
| Hebrew Calendar Performance | 4 | bench suite + A/B vs ICU |
| Hebrew Calendar Regression | 1 | 73,414-day vs Hebcal |
| — | — | — |
| **Total** | **165** | **0 failures, 0 divergences** |

## Performance (unchanged from v2)

| Test | ICU baseline | `_CalendarHebrew` | Speedup |
|---|---:|---:|---:|
| allocationsForFixedHebrewCalendar | 21,321 ns | 12,490 ns | 1.7× |
| roundTripDateComponents | 20,346 ns | 6,713 ns | 3.0× |
| copyOnWriteHebrew | 69,590 ns | 12,875 ns | 5.4× |
| **nextThousandHanukkahs** | **776 µs** | **4 µs** | **🚀 194×** |

## Files in this backup

```
Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
Tests/FoundationEssentialsTests/HebrewRegressionTests.swift          ← new
Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift
```

## Known open item

- **Task #10 (CRITICAL):** `date(byAdding: .day)` DST-aware path still takes ~12 µs (debug); fix plan documented in task description. Target: sub-µs via offset-delta approach (compute TZ offsets at both endpoints, adjust by delta).

## Verification at time of snapshot

```
swift test --filter "Calendar"
→ 165 tests passed in 10 suites (9 original + Hebrew Calendar Regression)
→ 73,414/73,414 Hebcal days match
→ 400/400 cross-check days match ICU
→ 0 regressions on pre-existing Foundation tests
```
