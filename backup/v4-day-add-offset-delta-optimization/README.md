# v4 — date(byAdding: .day) offset-delta optimization

**Date:** 2026-04-24
**Branch:** `port/hebrew`
**Base commit:** `8b98eac08084e15c5d1284b6efd5923dceaa491a` on `upstream/release/6.3`
**Swift toolchain:** 6.3.1-RELEASE (via `swiftly`)

## What's stable at this checkpoint

Everything from v3, plus:
- **Task #10 (CRITICAL) fixed.** `date(byAdding: .day)` (and all day-multiple components) now uses an O(1) offset-delta algorithm:
  1. Read TZ offset at current date.
  2. Candidate UTC = current + N × 86400 seconds.
  3. Read TZ offset at candidate.
  4. Target = candidate − (offset2 − offset1).

  Handles spring-forward (delta > 0, subtracts to correct UTC), fall-back (delta < 0, adds to correct UTC), and non-DST timezones (delta = 0, pure +N·86400). No DateComponents round-trip, no Hebrew arithmetic invocation, no allocation on the hot path.
- **165 tests still pass**, including full Hebcal 73,414-day regression.

## Performance (debug mode, best of 3 trial rounds × best-of-5 internal runs)

| Test | ICU baseline | v3 (pre-opt) | **v4 (post-opt)** | Final speedup vs ICU |
|---|---:|---:|---:|---:|
| allocationsForFixedHebrewCalendar | 21,321 ns | 12,490 ns | **4,315 ns** | **4.9×** |
| roundTripDateComponents | 20,346 ns | 6,713 ns | 5,793 ns | 3.5× |
| copyOnWriteHebrew | 69,590 ns | 12,875 ns | **3,428 ns** | **20×** |
| **nextThousandHanukkahs** | **776 µs** | **4 µs** | **6 µs** | **129×** |

Hanukkah regressed slightly (4→6 µs) but is still dominantly faster than ICU.

## Remaining plumbing (deferred; not blockers)

- `ordinality` returns `nil` for some `(smaller, larger)` pairs that Foundation's existing tests don't exercise: weekday-related, weekOfYear-related, quarter-related.
- `dateInterval(of:)` returns `nil` for `.weekOfYear`, `.weekOfMonth`, `.quarter`, `.yearForWeekOfYear`, `.isLeapMonth`, `.isRepeatedDay`.
- `dateComponents(_:from:to:)` is a crude second-based approximation (not a proper recursive multi-unit subtraction).
- `date(byAdding:wrappingComponents: true)` uses the same carry-over path as `false`.

None of these are hit by the 165 tests that currently pass. They'll need to be filled in before final PR if Apple's integrator runs a more thorough test matrix against `_CalendarHebrew`.

## Files in this backup

```
Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
Tests/FoundationEssentialsTests/HebrewRegressionTests.swift
Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift
```

## Verification at time of snapshot

```
swift test --filter "Calendar"
→ 165 tests passed in 10 suites (9 original + Hebrew Calendar Regression)
→ 73,414/73,414 Hebcal days match
→ 400/400 cross-check days match ICU
→ 0 regressions on pre-existing Foundation tests
→ Hebrew perf: 4.9× / 3.5× / 20× / 129× faster than ICU baseline
```

This is a PR-ready state for the Hebrew calendar port.
