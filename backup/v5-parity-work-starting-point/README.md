# v5 — Parity work starting point

**Date:** 2026-04-24
**Branch:** `port/hebrew`
**Base commit:** `8b98eac08084e15c5d1284b6efd5923dceaa491a` on `upstream/release/6.3`
**Swift toolchain:** 6.3.1-RELEASE (via `swiftly`)

## Purpose of this snapshot

Everything from v4, plus:
- The ICU comparison **probe test** (`HebrewICUComparisonProbe.swift`) — captures
  the full side-by-side behavior of `_CalendarICU(.hebrew)` vs `_CalendarHebrew`.
- The authoritative **`backup/PARITY.md`** with Hebrew's current gap checklist.
- The authoritative **`backup/PARITY_PROTOCOL.md`** — the generic contract every
  future calendar port will follow (Hebrew is the first instance).

## What this snapshot records: the starting point of parity work

This is the baseline **before** any parity-driven changes are made to
`_CalendarHebrew`. It's the state against which progress on tasks #12–17
should be measured. If later work introduces a regression, restoring from
this snapshot gives a clean "gap-identified but still-green" reference.

## Known gaps at this point (from PARITY.md)

- `dateComponents(_:from:in:)` returns `nil` for `.weekdayOrdinal`, `.weekOfMonth`,
  `.weekOfYear`, `.yearForWeekOfYear`, `.quarter`.
- `dateInterval(of:)` returns `nil` for `.quarter`, `.weekOfYear`,
  `.weekOfMonth`, `.yearForWeekOfYear`. `.era` returns a 1-year interval
  instead of the calendar-span interval.
- `ordinality(of:in:for:)` returns `nil` for 8 (smaller, larger) pairs.
- `range(of: .weekOfYear, in: .year, for:)` and
  `range(of: .weekOfMonth, in: .month, for:)` return `nil`.
- `date(byAdding: .yearForWeekOfYear, value: 1, to:)` is a silent no-op.
- `minimumRange` / `maximumRange` bounds diverge from ICU on `.year`,
  `.weekdayOrdinal`, `.weekOfMonth`, `.weekOfYear`, `.yearForWeekOfYear`.

None of these are hit by the 165 tests that currently pass (165 of which
includes our 11 new Hebrew tests + the 73,414-day Hebcal regression).
**They are visible via the probe**; they are real behavioral regressions
for any app that queries those fields.

## Test state at this checkpoint

- 165 tests pass.
- 73,414 Hebcal days match (0 divergences).
- 400-day ICU cross-check matches (0 divergences on the fields our
  `dateComponents` DOES populate).
- Probe test runs cleanly (diagnostic only — prints the gap table).
- Perf: alloc 4.9×, round-trip 3.5×, CoW 20×, Hanukkah 129× vs ICU baseline.

## Files in this backup

```
Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
Tests/FoundationEssentialsTests/HebrewRegressionTests.swift
Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift
Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift   ← new in v5
```

## How to restore

From `swift-foundation/` root:
```sh
cp backup/v5-parity-work-starting-point/Sources/FoundationEssentials/Calendar/*.swift Sources/FoundationEssentials/Calendar/
cp backup/v5-parity-work-starting-point/Tests/FoundationEssentialsTests/*.swift Tests/FoundationEssentialsTests/
cp backup/v5-parity-work-starting-point/Tests/FoundationInternationalizationTests/*.swift Tests/FoundationInternationalizationTests/
```

(The `PARITY.md` / `PARITY_PROTOCOL.md` live in `backup/` itself and don't
need restoration; they're not code.)
