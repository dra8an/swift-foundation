# `v16-frozen` — pre-v17 safety snapshot

*2026-05-13*

Captured immediately before v17 sync from `origin/port/hebrew-main`'s
`ef191c1` ("Address PR #1953 review feedback: remove unused imports,
fix DST tests, add benchmarks"). This snapshot preserves the local
state at v16 so we can rollback if the v17 sync goes sideways.

## What's in this snapshot

| Layer | Files |
|---|---|
| Sources (4) | `Calendar.swift`, `Calendar_Enumerate.swift`, `Calendar_Hebrew.swift`, `Calendar_Recurrence.swift` |
| Tests (7) | `HebrewICUComparisonProbe.swift`, `HebrewPublicAPIComparisonProbe.swift`, `HebrewRecurrenceRuleParityProbe.swift`, `HebrewDSTPolicyParityTests.swift`, `HebrewCalendarPerformanceTests.swift`, `EnumerateMicroProfile.swift`, `HebrewRegressionTests.swift` |
| Benchmarks (3) | `BenchmarkCalendar.swift`, `BenchmarkTimeZone.swift`, `InternationalizationBenchmark.swift` |

This is more comprehensive than the per-vN snapshots that only
capture changed-by-that-layer files — here we capture **everything
v17 might touch** plus everything in the area, so a full restore
gives us back v16 exactly.

## What v17 will change

| File | Change | Source |
|---|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Remove 10 lines of unused libc imports (Bionic / Glibc / Musl / CRT / WASILibc). The file doesn't reference any libc symbols. | `ef191c1` |
| `Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift` | Refactor: parameterized `DSTProbe` struct + `CustomTestStringConvertible`. Same test semantics, better failure output. | `ef191c1` |
| `Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift` | Delete (201 lines). Functionality moved to `BenchmarkCalendar.swift` as proper package benchmarks. | `ef191c1` |
| `Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift` | Replace local research version (parameterized to `.hebrew`) with upstream version which adds 5 new Hebrew-specific benchmarks (`HebrewCalendar-nextThousandHanukkahs`, `-allocationsForFixedCalendar`, `-copyOnWritePerformance`, `-dateComponents-yearMonthDay`, `-roundTripDateComponents`). Loses local parameterization (which was research-only). | `ef191c1` |

## Restoration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
cp backup/v16-frozen-pre-v17/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v16-frozen-pre-v17/Tests/FoundationInternationalizationTests/*.swift \
   Tests/FoundationInternationalizationTests/
cp backup/v16-frozen-pre-v17/Tests/FoundationEssentialsTests/*.swift \
   Tests/FoundationEssentialsTests/
cp backup/v16-frozen-pre-v17/Benchmarks/Benchmarks/Internationalization/*.swift \
   Benchmarks/Benchmarks/Internationalization/
```

Note: if v17 deleted any file, you'll need to also restore that file
(this snapshot has `HebrewCalendarPerformanceTests.swift` even though
v17 removes it).
