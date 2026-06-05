# `v17` — Sync from `port/hebrew-main`: PR #1953 review feedback

*2026-05-13*

**Status: tested + parity-verified, NOT committed.** Builds on v16.
Cherry-picks `origin/port/hebrew-main` commit `ef191c1` "Address PR
#1953 review feedback: remove unused imports, fix DST tests, add
benchmarks" into our local Swift 6.3 working tree.

## Background

Upstream PR <https://github.com/swiftlang/swift-foundation/pull/1953>
went through reviewer feedback on the Swift 6.4 machine. The feedback
was addressed there in commit `ef191c1` on `port/hebrew-main`. v17 is
the back-sync into our local `port/hebrew` so the two branches stay
near-mirrored on Hebrew-related source files. v17 = v16 + `ef191c1`.

## What's in this snapshot

4 files affected (3 changed/replaced, 1 deleted):

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Removed 10 lines of unused libc imports (`Bionic`/`Glibc`/`Musl`/`CRT`/`WASILibc`). File doesn't actually reference any libc symbols. Only `#if canImport(os) internal import os #endif` + `internal import Synchronization` remain. |
| `Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift` | Replaced with upstream's parameterized version. New `DSTProbe` struct + `CustomTestStringConvertible` for better failure output. Same test semantics — DST policy parity vs `_CalendarGregorian` across 4 (.former/.latter)² combos on repeat / skip / non-DST instants. |
| `Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift` | **Deleted.** Its functionality moved to `BenchmarkCalendar.swift` as proper package benchmarks (next row). Locally we had this from v1; deleted to match upstream and avoid drift. |
| `Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift` | **Replaced** with upstream's version. Lost local research parameterization (`calendarBenchmarks(_ identifier:...)` → `calendarBenchmarks()`). Gained 5 new Hebrew-specific benchmarks: `HebrewCalendar-nextThousandHanukkahs`, `-allocationsForFixedCalendar`, `-copyOnWritePerformance`, `-dateComponents-yearMonthDay`, `-roundTripDateComponents`. |

Not snapshotted here (no change at v17): `Calendar.swift`,
`Calendar_Enumerate.swift`, `Calendar_Recurrence.swift`. They're at
their v14 state, which is correct (the v8-v15 perf stack lives only
on `port/hebrew`).

## Parity

- 174/174 Calendar+RecurrenceRule tests pass (down from 178 at v16 —
  the 4-test drop is exactly the 4 tests from the deleted
  `HebrewCalendarPerformanceTests` file, all of which had "Hebrew
  Calendar" in their suite name and so previously matched the
  "Calendar" filter substring).
- 58/58 Hebrew tests pass (down from 62 — same 4 tests).
- Suite C `HebrewRecurrenceRuleParityProbe` still 0 divergences vs
  `_CalendarICU(.hebrew)`.
- 73,414/73,414 Hebcal days still match.

## Performance

No expected change — v17 doesn't touch the perf stack or any
production code path. Not re-benchmarked. The new `HebrewCalendar-*`
benchmarks added to `BenchmarkCalendar.swift` exercise the same code
paths as before, just under different names. If you re-run the full
benchmark, expect the same v15 numbers plus baseline numbers for the
5 new Hebrew benches.

## Restoration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
cp backup/v17-sync-from-port-hebrew-main/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v17-sync-from-port-hebrew-main/Tests/FoundationInternationalizationTests/*.swift \
   Tests/FoundationInternationalizationTests/
cp backup/v17-sync-from-port-hebrew-main/Benchmarks/Benchmarks/Internationalization/*.swift \
   Benchmarks/Benchmarks/Internationalization/
# Note: deleted file is NOT restored automatically — that requires
# recovering HebrewCalendarPerformanceTests.swift from backup/v16-frozen-pre-v17/.
```

If you want the full v16 state back (including the deleted test file),
see `backup/v16-frozen-pre-v17/README.md`.

## Doc corrections

`MAIN_MERGE.md`'s "What does NOT go upstream from local tree" list
incorrectly included `HebrewDSTPolicyParityTests.swift`. That file
IS on `port/hebrew-main` and goes upstream — it references
`_CalendarGregorian` (an internal Foundation type that exists on
both branches), not `_CalendarICU` (which is the actual upstream
incompatibility). v17's doc-update pass removes this entry.
