# v6 — ICU parity complete, zero divergences across 10 probe dates

**Date:** 2026-04-24
**Branch:** `port/hebrew`
**Base commit:** `8b98eac08084e15c5d1284b6efd5923dceaa491a` on `upstream/release/6.3`
**Swift toolchain:** 6.3.1-RELEASE (via `swiftly`)

## What's stable at this checkpoint

Everything from v5, plus ALL ICU parity gaps closed:

- `dateComponents(_:from:in:)` returns **all 15 fields matching ICU** for all 10 probe dates.
- `dateInterval(of:for:)` matches ICU for all 9 components (`.era`, `.year`, `.month`, `.day`, `.hour`, `.quarter`, `.weekOfYear`, `.weekOfMonth`, `.yearForWeekOfYear`) across all 10 probe dates.
- `ordinality(of:in:for:)` matches ICU for all 12 `(smaller, larger)` pairs.
- `range(of:in:for:)` matches ICU for all 5 critical pairs.
- `date(byAdding:)` matches ICU for all 9 components.
- `minimumRange` / `maximumRange` match ICU for all 13 Calendar.Component values.

Key fixes landed in v6:
1. **`.era = 0`** (not 1) — matches ICU's 0-based era convention for Hebrew.
2. **`dateInterval(.era)`** returns `inf_ti` duration anchored at Hebrew epoch (-181,778,083,200 s).
3. **`dateInterval(.quarter)`** always spans 3 real civil months (in leap year civil-6/civil-7 slots are both real; in common year civil-6 is skipped transparently by `nextMonth()`).
4. **`dateInterval(.yearForWeekOfYear)` + `date(byAdding:.yearForWeekOfYear)`** use `numWeeksInYearForWeekOfYear(year) × 7 days` (50/51 weeks in common, 54-56 in leap), not calendar year length.
5. **`ordinality(.weekOfYear, .year)` / `(.weekOfMonth, .month)`** use firstWeekday-aware formula (unwrapped).
6. **`ordinality(.weekday, .year)` / `(.weekday, .month)` / `(.weekdayOrdinal, .month)`** use simple `(dayOfX - 1) / 7 + 1`.
7. **`ordinality(.month, .year)`** returns the civil month directly (not densified).
8. **`range(.month, .year)`** returns `1..<14` directly (matches ICU regardless of common/leap).
9. **`minimumRange` / `maximumRange`** bounds for `.year`, `.weekdayOrdinal`, `.weekOfMonth`, `.weekOfYear`, `.yearForWeekOfYear` match ICU.
10. **`HebrewICUComparisonProbe`** now sweeps 10 probe dates with every observable surface, catches regressions automatically.

## Test state at this checkpoint

- **165 tests pass** in the `Calendar` filter (9 existing Foundation suites + Hebrew + Hebrew Calendar Performance + Hebrew Calendar Regression).
- **73,414-day Hebcal regression:** 0 divergences.
- **ICU probe sweep, 10 dates × ~50 observations each = 500 checks:** 0 divergences.
- Perf: unchanged from v4 (alloc 4.9×, round-trip 3.5×, CoW 20×, Hanukkah enumerate 129×).

## Probe dates covered in v6

Multi-date probe exercises every known Hebrew edge case:
- Leap-year mid (Elul 20, 5776)
- Common-year mid (Adar 1, 5785)
- Leap year first day (Tishri 1, 5776)
- Common year first day (Tishri 1, 5786)
- Leap year Adar I (Adar I 1, 5776)
- Leap year Adar II (Adar II 1, 5776)
- Cheshvan 30, 5776 (long Marheshvan)
- Kislev 25, 5777 (Hanukkah common year)
- Passover 15 Nisan, 5776
- mid-5778 common year

## Files in this backup

```
Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
Tests/FoundationEssentialsTests/HebrewRegressionTests.swift
Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift
Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift   ← updated with sweepMultipleDates
```

## Remaining before PR

Only task #11 is still open: decide on Hebcal fixture size (1.7 MB). See `backup/OPEN_ISSUES.md` item 1.

The Hebrew port is functionally complete, ICU parity-verified, and ready for a PR.
