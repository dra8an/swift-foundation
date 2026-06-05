---
name: Main-merge recap (port/hebrew → port/hebrew-main)
description: What lands on `origin/port/hebrew-main` when the v8–v15 stack is merged from local `port/hebrew`. File-by-file delta, perf delta, commit-shape options, what stays local. Read before starting the merge on the Swift 6.4 machine.
type: reference
---

# Main-merge recap: `port/hebrew` → `port/hebrew-main`

**Audience**: future-you on the Swift 6.4 machine, when v8–v15 is ready
to land upstream. **Status of this document**: prepared at v16 sync,
2026-05-07.

## ⚠ Current status (2026-05-08): upstream PR in review — merge blocked

An upstream PR is open at
<https://github.com/swiftlang/swift-foundation/pull/1953>. Branch
`port/hebrew-main` was pushed and is the basis for that PR.

**CI status (initial push, 2026-05-08):** all three required checks
passing — Linux ✓, macOS arm64 ✓, Windows (Swift `main` toolchain) ✓.
This is the baseline CI signal for the Hebrew port at the
`port/hebrew-main` snapshot (`c2668eb` + `46725dd` + `04783dc`).

**PR feedback addressed (2026-05-11):** commit `ef191c1` "Address PR
#1953 review feedback: remove unused imports, fix DST tests, add
benchmarks" pushed to `origin/port/hebrew-main`. v17 back-syncs those
source-only changes into `port/hebrew` (2026-05-13).

**Do NOT start the v8–v15 merge yet.** Reviewer feedback on the
current PR may change the shape of `_CalendarHebrew` itself
(API, internal helpers, file layout, parity contract) — anything that
affects the lines v8–v15 modify. Wait for one of:

- The PR merges and `port/hebrew-main` is rebased onto post-merge
  upstream `main`. Then start the v8–v15 merge.
- Reviewer requests substantive changes. Apply them on
  `port/hebrew-main` first, then sync back to `port/hebrew` (similar
  to how v16 was synced from the `46725dd` + `04783dc` commits), then
  start the v8–v15 merge.
- The PR is closed without merging. Different conversation.

Local work on `port/hebrew` (perf experiments, additional benchmarks,
extra parity tests) is unblocked — only the upstream merge is gated.

## Branch model

- **`port/hebrew`** (this repo, Swift 6.3.1) — active development. Has
  `c2668eb` committed + 9 uncommitted layers (v8–v16). Carries Suite A,
  Suite B, Suite C, Hebcal regression, DST policy parity tests, research
  benchmarks, `backup/` directory.
- **`port/hebrew-main`** (Swift 6.4 machine) — upstream-bound clean
  shape, based on Foundation's `main`. Has `c2668eb` + `46725dd`
  (LockedState → Mutex) + `04783dc` (icu4swift comment cleanup +
  removal of probe / regression test files). No probes, no `backup/`,
  no research benches.
- **v16** is what we backported here from `port/hebrew-main`'s two
  grooming commits, so future syncs in either direction have minimum
  drift in `Calendar_Hebrew.swift`.

## What's already on `port/hebrew-main`

`c2668eb` "Extend Hebrew fast-path to {month, weekday, weekdayOrdinal}
+ cache YearData" + 2 grooming commits. Hebrew currently fast-paths:

- `{m, d}` annual, `{m}` month-only, `{d}` month-walking, `{wd}`
  weekday-RD-modular
- `{m, wd, wdOrd}` Nth weekday of month, `{wd, wdOrd}` Nth weekday
  no-month
- Single-slot `YearData` cache via `Mutex<YearData?>`

## Code delta on merge (v8–v15)

Four source files change. **No new test files** go upstream (Suite C
also constructs `_CalendarICU(...)` directly, so it stays local — see
"What does NOT go upstream" below).

| File | What v8–v15 add | Layers |
|---|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar.swift` | `_calendarNextDate(after:matching:direction:)` proxy on `Calendar` that consults the protocol method. ~30 LOC. | v8 |
| `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` | Fast-path wiring inside `_enumerateDatesStep`. Probe-and-commit hoist in `DatesByMatching.Iterator`. Helper hijacks at `dateAfterMatchingWeekOfMonth` / `dateAfterMatchingWeekdayOrdinal` / `dateAfterMatchingMonth` / `dateAfterMatchingWeekday` (each enriches the components and routes through the protocol fast path before falling back). | v8 + v9 + v11 + v12 |
| `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` | Three short-circuit branches inside `_unadjustedDates`: (1) single-combination, (2) multi-combination cartesian (positive ordinals), (3) negative-ordinal cartesian via runtime weekOfMonth translation. Plus helpers `_singleCombinationDateComponents`, `_expandedDateComponents(_:anchor:maxCombinations:)`, `_unadjustedDatesHasNegativeOrdinal`. | v12 + v13 + v14 |
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Three new fast-path shapes: `{m, wd, weekOfMonth}`, `{wd, wdOrd}` no-month, time-only `{h, mi, s, ns?}`. Plus helper methods: `nextMonthWeekdayWeekOfMonthMatch`, `nextWeekdayOrdinalMatch`, `nextTimeOfDayMatch`. Updates the gating predicate accordingly. | v10 + v11 + v15 |

## Performance delta

Eight of nine `InternationalizationBenchmarks` calendar benchmarks
move from "ICU-equivalent or slower" to "8–250× ICU." Numbers below
are debug-mode p50, at v15 (current local state) vs the committed
`c2668eb` baseline:

| Benchmark | At `c2668eb` | After v8–v15 | Speedup | vs ICU |
|---|---:|---:|---:|---:|
| `nextThousandThanksgivings` | 3,893 ns | 3,967 ns | (already fast at `c2668eb`) | ~250× |
| `nextThousandThanksgivingsSequence` | 1,096 µs | 4,098 ns | ~270× | ~240× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` | 514 µs | 4,174 ns | ~123× | ~107× |
| `RecurrenceRuleThanksgivings` | 3,276 µs | 107 µs | ~31× | 19× |
| `RecurrenceRuleThanksgivingMeals` | 2,285 µs | 88 µs | ~26× | 15× |
| `RecurrenceRuleLaborDay` | 2,952 µs | 107 µs | ~28× | 15× |
| `RecurrenceRuleBikeParties` | 2,226 µs | 118 µs | ~19× | 10.5× |
| `RecurrenceRuleDailyWithTimes` | 2,979 µs | 191 µs | ~16× | ~8× |
| `CurrentDateComponentsFromThanksgivings` | 5,579 µs | 5,884 µs | (uses `Calendar.current` not `cal` — not exercising Hebrew) | — |

Allocations: the four RecurrenceRule benchmarks drop ~95% of mallocs
each (e.g. ThanksgivingMeals 1,837 → 0; DailyWithTimes 3,742 → 151).

## Cross-calendar safety

Every shared-code change is gated by a protocol-method-returns-nil
pattern. Non-Hebrew calendars (Gregorian, Islamic Civil/Tabular/UQ,
Chinese, etc.) hit the default `nil` and fall through to the existing
path unchanged. Aggregate added cost per `_unadjustedDates` call for
non-Hebrew calendars: ≤100 ns (a sentinel probe). Reviewer-oriented
analysis lives in `backup/SHARED_CODE_SAFETY.md`.

## Commit-shape options (open task #37)

**A. One commit.** "Hebrew calendar fast-path optimizations." Easy for
us, hard for upstream review — reviewers must mentally separate
shared-code edits from Hebrew-specific ones.

**B. Two commits, possibly two PRs** (more likely what upstream wants):

- *Commit A — shared-code fast-path infrastructure*: `Calendar.swift`
  + `Calendar_Enumerate.swift` + `Calendar_Recurrence.swift`. Net
  change for any non-Hebrew calendar: zero behavior, ≤100 ns overhead
  per `_unadjustedDates` call. `SHARED_CODE_SAFETY.md` is the cover
  note.
- *Commit B — Hebrew-specific fast paths*: `Calendar_Hebrew.swift`
  only.

Reviewers will likely insist on this split because Commit A touches
code paths that affect every calendar. The two PRs can land in either
order — they're independent.

## Suite C upstream handling

Suite C (`HebrewRecurrenceRuleParityProbe.swift`) constructs
`_CalendarICU(...)` at line 46 the same way Suite A and B do, so
**Suite C does NOT go upstream**. This creates a problem for the
shared-code commit's review story: reviewers can't see a parity test
demonstrating that the `_unadjustedDates` modifications are
behaviorally identical to the pre-change path.

Three options when prepping the upstream PR:

1. **Adapt Suite C for upstream** — rewrite the comparator to use
   `Calendar(identifier: .gregorian)` (or another well-established
   calendar) instead of `_CalendarICU(.hebrew)`. Loses Hebrew-specific
   verification but proves the shared-code paths still match the
   framework's existing behavior on a calendar reviewers can reason
   about. **Recommended** — `.gregorian` parity is what reviewers
   actually care about, since `_CalendarGregorian` is what 99% of
   users have in production.
2. **Reference Suite C as "verified locally"** — link the local fork
   or attach the test file as a non-committed PR artifact. Reviewers
   trust the report or ask to see it.
3. **Land Suite C as `#if DEBUG_HEBREW_PARITY` block** — keeps the
   test in-tree as a runnable check for anyone with
   `_CalendarICU(.hebrew)` available, but doesn't run by default.

## Hebcal regression (open task #11, sole pre-PR blocker)

`HebrewRegressionTests.swift` currently loads the 1.7 MB Hebcal CSV
from `~/Projects/claude/CalendarAPI/icu4swift/Tests/CalendarComplexTests/hebrew_1900_2100_hebcal.csv`
(hardcoded external path). For upstream this needs:

- (a) **Move into the repo as a SwiftPM resource bundle.** Size
  concern (1.7 MB checked-in CSV).
- (b) **Sample the CSV down** to a manageable size (e.g. 1,000 spread-
  sampled days). Parity-coverage concern — the current 73,414-day
  sweep is exhaustive and has caught real bugs.
- (c) **Stay external; test stays local-only.** Suite C-style
  tradeoff.

Decision needed before either commit shape lands upstream.

## Rebase mechanics (when you do the merge)

The local working tree has v8–v16. v16 is already on `port/hebrew-main`
as commits `46725dd` + `04783dc`, so you only need to rebase v8–v15.

Anticipated conflicts in `Calendar_Hebrew.swift`:

- `internal import Synchronization` — already present on
  `port/hebrew-main`. Skip our v16 add of it during rebase (keep
  upstream's).
- `LockedState<YearData?>(initialState: nil)` → `Mutex<YearData?>(nil)`
  — already done on `port/hebrew-main`. Skip our swap during rebase.
- `var newYear` → `let newYear` (~line 894) — already done on
  `port/hebrew-main`. Skip our change during rebase.
- icu4swift comment cleanup at 5 sites — already done on
  `port/hebrew-main`. Skip during rebase.

For the other three source files (`Calendar.swift`,
`Calendar_Enumerate.swift`, `Calendar_Recurrence.swift`), check for
upstream-`main` evolution. The diff `c2668eb` → `origin/port/hebrew-main`
already showed 875 lines of non-Hebrew Foundation evolution
(`Calendar_Gregorian.swift`, `RecurrenceRule.swift`,
`Date+FormatStyle.swift`, etc.). Most of that is in files we don't
touch with v8–v15, but watch for:

- `Calendar.swift` — has touched APIs in our v8 proxy area? Check
  upstream's diff to `Calendar.swift` first.
- `Calendar_Recurrence.swift` — `_unadjustedDates` is the function we
  modify most heavily. Confirm upstream hasn't touched it.

## What does NOT go upstream from local tree

- `backup/` directory (snapshots, raw bench output, READMEs, session
  logs, FAST_PATHS_OVERVIEW.md, this MAIN_MERGE.md, etc.)
- `Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift` (Suite A — references `_CalendarICU`)
- `Tests/FoundationInternationalizationTests/HebrewPublicAPIComparisonProbe.swift` (Suite B — references `_CalendarICU`)
- `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift` (Suite C — references `_CalendarICU` at line 46)
- Research benchmark / probe files: `HebrewVsICUBenchmark.swift`, `EnumerateMicroProfile.swift`, `AllocationsBreakdown.swift`, `EnumerateBreakdown.swift` (untracked)
- `Tests/FoundationEssentialsTests/HebrewRegressionTests.swift` (depends on task #11)
- `.swift-version` (pinned to 6.3.1)
- Benchmark file parameterizations to `.hebrew` in `BenchmarkCalendar.swift` / `BenchmarkTimeZone.swift` / `InternationalizationBenchmark.swift` (revert to `.gregorian` default before commit, per `SESSION_2026-05-01_to_03.md:204`)

## Reading order on the Swift 6.4 machine

1. **`backup/HANDOFF.md`** — cold-resume entrypoint, current state, file inventory.
2. **`backup/MAIN_MERGE.md`** — this file. The merge plan.
3. **`backup/FAST_PATHS_OVERVIEW.md`** — one-page summary of every layer with cross-references.
4. **`backup/SHARED_CODE_SAFETY.md`** — reviewer cover note for the shared-code part of the upstream PR.
5. **`backup/BACKUPS.md`** — chronological log; each `vN-*/` directory has a restoration-instructions README.
6. **`backup/PARITY.md`** + `backup/PARITY_PROTOCOL.md` — parity contract.
7. **`backup/RECURRENCE_VS_NEXTDATE.md`** — the analysis that drove v12–v15.

## Pre-merge checklist

- [ ] Decide commit shape (one commit vs two — task #37).
- [ ] Decide Suite C upstream handling (adapt to `.gregorian`,
      external reference, or `#if DEBUG_HEBREW_PARITY` — see § "Suite
      C upstream handling").
- [ ] Decide Hebcal fixture handling (in-repo, sampled, or external —
      task #11).
- [ ] Revert `BenchmarkCalendar.swift` / `BenchmarkTimeZone.swift` /
      `InternationalizationBenchmark.swift` parameterizations to
      `.gregorian` default.
- [ ] Confirm no upstream-`main` conflicts in `Calendar.swift` /
      `Calendar_Enumerate.swift` / `Calendar_Recurrence.swift`
      touch points.
- [ ] Run quick-verify on `port/hebrew-main` after rebase: `swift test
      --filter "Calendar|RecurrenceRule"` (expect 178/178 — Suite C
      may be missing from the upstream branch, in which case expect
      165/165) + `swift test --filter "Hebrew"` (expect smaller
      count since Suites A/B/C/regression aren't there).
- [ ] Re-run full benchmark target on Swift 6.4 to capture release-mode
      numbers (Swift 6.4 may not have the SIGBUS issue we hit on Swift
      6.3.1 + Intel — verify before publishing PR numbers).
- [ ] Capture v15 release-mode bench output for the PR description if
      available.
