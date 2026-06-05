# Local backup log — port/hebrew work

**Repo:** `/Users/draganbesevic/Projects/claude/swift-foundation`.
**Remotes:** `origin` = `https://github.com/dra8an/swift-foundation.git` (user's fork),
`upstream` = `https://github.com/swiftlang/swift-foundation.git` (Apple). Push to fork; PRs fork → upstream.
**Active branch:** `port/hebrew`, based on `upstream/release/6.3`.

Since we cannot make incremental git commits during exploratory port work
(a single big commit is planned at the end), we snapshot stable milestones
to `backup/vN-<description>/` instead. Each snapshot preserves the directory
layout of the changed files so restoration is a plain `cp`.

This log is authoritative for what lives in `backup/`. When the final PR is
assembled, this file can be deleted along with the snapshots.

**Related:**
- **`backup/PARITY_PROTOCOL.md`** — **NON-NEGOTIABLE** protocol: every
  pure-Swift calendar port must match ICU behavior on every observable
  surface, verified by a side-by-side probe test. Applies to every calendar
  we port — Hebrew (first) through Chinese, Hindu, Islamic, etc.
- **`backup/PARITY.md`** — Hebrew's concrete parity requirements (current
  gaps + fix checklist).
- **`backup/SHARED_CODE_SAFETY.md`** — analysis of how the v8–v12 stack's
  shared-code changes (`Calendar_Enumerate.swift`, `Calendar_Recurrence.swift`)
  affect non-Hebrew calendars. Short answer: every gated by a protocol
  method whose default returns nil → other calendars fall through unchanged.
  Includes per-touchpoint inventory, residual-overhead quantification,
  and a reviewer checklist for upstream PR. Read this before reviewing
  any v8–v12 snapshot.
- `backup/OPEN_ISSUES.md` — pre-PR decisions that need to be resolved
  before the final commit (fixture sizing, release-mode benchmarking, etc.).
  Issue #0 defers to PARITY docs.

## Snapshots

### v1 — Hebrew core round-trip matches ICU
*2026-04-24*
- `_CalendarHebrew` class scaffold + full `HebrewArithmetic` (Reingold & Dershowitz).
- `date(from:)` and `dateComponents(_:from:in:)` implemented.
- Cross-check vs Foundation's ICU Hebrew: 0/400 daily divergences.
- Discovered + fixed stable-vs-dense month-numbering mismatch (Foundation uses stable ICU numbering; `civilToBiblical`/`biblicalToCivil` rewritten to match).
- Router NOT yet flipped; 10 of 14 protocol methods still stubbed with `fatalError`.
- See `v1-hebrew-core-roundtrip-matches-icu/README.md` for full details.

### v2 — Hebrew router flipped, all 164 tests pass
*2026-04-24*
- All 14 `_CalendarProtocol` methods implemented. `_calendarClass(.hebrew)` → `_CalendarHebrew.self`.
- `dateInterval` + `date(byAdding: .day)` are DST-aware (uses start-of-next-unit - start-of-this-unit in local time).
- **164 tests pass** (153 existing Foundation + 11 new Hebrew). 0 regressions.
- Speedups vs ICU baseline (debug): alloc 1.7×, round-trip 3.0×, CoW 5.4×, **Hanukkah enumerate 194×**.
- Known: task #10 — DST-aware day-add path is ~12 µs (should be sub-µs); fix sketched in task.
- See `v2-hebrew-router-flipped-all-tests-pass/README.md` for full details.

### v3 — Hebcal 73,414-day regression at 0/0 divergences
*2026-04-24*
- Added `HebrewRegressionTests.swift` — reads the 73,414-row Hebcal CSV, verifies every Gregorian → Hebrew conversion 1900-01-01 through 2100-12-31.
- **73,414 Hebcal days → 0 divergences.** 201 years of exact Hebrew-calendar agreement with the canonical reference.
- 165 tests in 10 suites pass. 0 regressions.
- Perf numbers unchanged from v2 (task #10 still pending).
- See `v3-hebcal-73k-regression-zero-divergences/README.md` for full details.

### v4 — date(byAdding: .day) offset-delta optimization (PR-READY)
*2026-04-24*
- Task #10 resolved: day-add hot path no longer round-trips through DateComponents. Uses O(1) offset-delta algorithm that handles DST correctness + non-DST zones.
- 165 tests still pass. Full Hebcal regression still 0/73,414.
- Final perf: alloc **4.9×**, round-trip **3.5×**, CoW **20×**, Hanukkah enumerate **129×** faster than ICU baseline.
- This is a PR-ready state for the Hebrew calendar port.
- See `v4-day-add-offset-delta-optimization/README.md` for full details.

### v5 — Parity work starting point
*2026-04-24*
- Added `HebrewICUComparisonProbe.swift`: side-by-side `_CalendarICU(.hebrew)` vs `_CalendarHebrew` comparison for every observable surface (queries, intervals, ordinality, range, add, bounds). Captures the canonical "what ICU does" reference.
- Added `backup/PARITY.md` (Hebrew concrete parity requirements) and `backup/PARITY_PROTOCOL.md` (generic protocol for all future calendar ports).
- No code change yet — v4's behavior is preserved. This snapshot records the exact gap set before parity work begins: nil fields in dateComponents for .weekdayOrdinal/.weekOfMonth/.weekOfYear/.yearForWeekOfYear/.quarter; 4 nil dateIntervals; 8 nil ordinality pairs; silent .yearForWeekOfYear add no-op; 5 bound mismatches.
- 165 tests still pass; 73,414 Hebcal days still match.
- Starting point for tasks #12–17.
- See `v5-parity-work-starting-point/README.md` for full details.

### v6 — ICU parity complete, zero divergences across 10 probe dates
*2026-04-24*
- **All ICU parity gaps closed.** Tasks #12–17 all completed.
- Multi-date probe sweep (10 dates × ~50 observations each = 500 checks): **0 divergences**.
- Key fixes: `.era=0` (ICU convention), `dateInterval(.era)` uses inf_ti duration, `dateInterval(.quarter)` always 3 real months, `.yearForWeekOfYear` uses weeks-in-year × 7 (not calendar year length), firstWeekday-aware ordinality for `.weekOfYear`/`.weekOfMonth`, simple 7-day chunking for `.weekday`/`.weekdayOrdinal`, `range(.month, .year) = 1..<14`, and ICU-matching bounds for all components.
- 165 tests pass, 73,414 Hebcal days match. Perf unchanged from v4.
- Note: v6 only covered Suite A (`_CalendarProtocol`). Suite B (public Calendar API) parity added in v7.
- See `v6-icu-parity-complete/README.md` for full details.

### v7 — Suite B (public Calendar API) parity complete, PR-ready
*2026-04-24*
- **Task #18 completed.** `HebrewPublicAPIComparisonProbe.swift` sweeps every public `Calendar` method across 10 probe dates: 0 divergences.
- Surfaced 76 divergences that Suite A had missed; all closed. Fixes:
  - Fixed-range fast paths for `range(hour/minute/second/weekday, X)`.
  - `dateComponents(in:from:)` always populates `.isLeapMonth`.
  - Full locale-aware `isDateInWeekend` (copied from _CalendarGregorian; Sat+Sun default for nil locale).
  - Proper multi-unit recursive `dateComponents(_:from:to:)` subtraction.
  - `date(byAdding:)` applies year/month BEFORE days (ICU ordering), fixing Adar I + 1 year + N days leap→common demotion case.
  - `date(byAdding: .day, wrapping: true)` wraps within month.
- Suites A + B both green; Hebcal 73,414 + 165 Calendar tests all pass.
- **Hebrew port is ICU-behaviorally indistinguishable from `_CalendarICU(.hebrew)` on every observable public surface. PR-ready.**
- See `v7-suite-b-public-api-parity/README.md` for full details.

### v8 — `_enumerateDatesStep` fast-path wiring (questionable, uncommitted)
*2026-05-03*
- **Status: tested + benchmarked, NOT committed.** Snapshotted before attempting a follow-up that may replace it.
- Adds a top-of-function fast-path check in `Calendar._enumerateDatesStep` that consults `_calendar.nextDate(after:matching:direction:)` and synthesizes a `SearchStepResult` on hit. Mirrors the wiring already in `Calendar.enumerateDates`.
- New internal proxy `Calendar._calendarNextDate` (since `_calendar` is `private` to `Calendar.swift` and the wiring lives in `Calendar_Enumerate.swift`).
- Headline wins (debug-mode, p50): `nextThousandThanksgivingsSequence` 1,096 µs → **4.25 µs** (258×). `RecurrenceRuleThanksgivings` 3,276 → **1,988 µs** (now 1.04× ICU). RecurrenceRule {LaborDay, ThanksgivingMeals, BikeParties} dropped 24–41%.
- Two patterns unaffected: `nextThousandThursdaysInTheFourthWeekOfNovember` (uses `weekOfMonth`, in our rejection guard) and `RecurrenceRuleDailyWithTimes` (multi-valued time-of-day combinations not in our fast path).
- Why "questionable": the Sequence API path is still ~7% slower than the block-based `enumerateDates` (4,248 ns vs 3,983 ns p50) due to per-call policy recheck + `SearchStepResult` build/destructure + iterator state mutation. Possible follow-up: hoist the probe-and-commit into `DatesByMatching.Iterator` itself, which would make this wiring redundant.
- Files: `Sources/FoundationEssentials/Calendar/{Calendar.swift, Calendar_Enumerate.swift}`.
- See `v8-enumeratedatesstep-fastpath/README.md` for full details + restoration instructions.

### v9 — `DatesByMatching.Iterator` fast-path hoist (questionable, uncommitted)
*2026-05-03*
- **Status: tested + benchmarked, NOT committed.** Builds on v8 (also uncommitted).
- `DatesByMatching.Iterator.init` probes `_calendarNextDate` once and stores `usesFastPath: Bool`. `Iterator.next()` takes a tight inner branch when set, bypassing `_enumerateDatesStep` entirely (skips per-call policy recheck + `SearchStepResult` synth/destructure).
- v8's `_enumerateDatesStep` wiring is preserved — still helps RecurrenceRule paths that route through `_enumerateDatesStep` rather than `DatesByMatching.Iterator`.
- Uniform 2–5% reduction across all framework benchmarks (debug-mode, p50). Sequence vs block gap on p0 closed from 7.7% → 3.6%; p50 gap (~6.7%) remained.
- `RecurrenceRuleThanksgivings` now beats ICU at 1.10× (was 1.04× at v8).
- Files: `Sources/FoundationEssentials/Calendar/{Calendar.swift unchanged, Calendar_Enumerate.swift updated}`.
- See `v9-iterator-fastpath-hoist/README.md` for full details + restoration instructions.

### v10 — `{month, weekday, weekOfMonth}` fast path
*2026-05-03*
- **Status: tested, NOT committed.** Builds on v8 + v9 (also uncommitted).
- Pure additive change in `Calendar_Hebrew.swift` only — no shared-code touch.
- Inverts the calendar-agnostic ICU week-numbering algorithm in O(1) per candidate year.
- Headline: `nextThousandThursdaysInTheFourthWeekOfNovember` 527 µs → **4,080 ns** (p50, 129× speedup, **109× ICU**), 646 mallocs → 0.
- All 5 new correctness probes pass (`{m:11,wd:5,wOM:4}`, `{m:1,wd:7,wOM:1}`, `{m:7,wd:6,wOM:5}`, `{m:6,wd:2,wOM:2}` Adar I leap-only, `{m:11,wd:5,wOM:4,h:14}` with time).
- 49/49 Hebrew tests, 165/165 Calendar tests, 73,414 Hebcal regression all clean.
- Files: `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift`, `Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift`.
- See `v10-weekofmonth-fastpath/README.md` for full details + restoration instructions.

### v11 — Helper-level fast-path hijacks (questionable, uncommitted)
*2026-05-03*
- **Status: tested + benchmarked, NOT committed.** Builds on v8/v9/v10.
- Two hijack injections in `Calendar_Enumerate.swift`: top of `dateAfterMatchingWeekdayOrdinal` (harmless but unused for current benchmarks); top of `dateAfterMatchingWeekOfMonth` (with month enrichment — routes through safe `{m, wd, weekOfMonth}` fast path).
- Added Hebrew `nextDate` support for `{weekday, weekdayOrdinal}` (no month) — `nextWeekdayOrdinalMatch` helper. Documented why `{wd, weekOfMonth}` no-month form is REJECTED (ICU parity break on rare patterns where target weekday isn't reachable in target week — e.g. Mon in week 1 of month starting Tue).
- 3 new correctness probes for `{wd, wdOrd}` no-month patterns.
- Modest perf wins: `RecurrenceRuleThanksgivings` 1,882 → **1,688 µs** (-10%, **1.23× ICU**); `RecurrenceRuleBikeParties` 1,638 → **1,430 µs** (-13%); other RecurrenceRule benchmarks 1–2%; mallocs 5–19% reduction. The user observed "still not the improvement I was looking for" — true; helper hijack only attacks the inner `dateAfterMatchingX` walk while ~1,400 ns/match remains in other framework machinery.
- Files: `Sources/FoundationEssentials/Calendar/{Calendar.swift unchanged, Calendar_Enumerate.swift, Calendar_Hebrew.swift}`, `Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift`.
- See `v11-helper-hijack/README.md` for full details + restoration instructions.

### v12 — RecurrenceRule single-combination short-circuit + Month/Weekday helper hijacks + Suite C parity probe (parity-verified, uncommitted)
*2026-05-04*
- **Status: tested + benchmarked + parity-verified, NOT committed.** Builds on v8/v9/v10/v11.
- **The home run**: short-circuit at top of `_unadjustedDates` (Calendar_Recurrence.swift). When every populated `_DateComponentCombinations` field has exactly one value AND policies are at default, translates to a `DateComponents` and calls `_calendarNextDate` directly, skipping the entire expansion-chain. New helper `_singleCombinationDateComponents`.
- Plus helper hijacks at `dateAfterMatchingMonth` (minimal `{month, isLeapMonth}` components) and `dateAfterMatchingWeekday` (minimal `{weekday}`) following the same `_calendarNextDate` pattern as v8/v9/v11.
- **Suite C added** (`HebrewRecurrenceRuleParityProbe`): 13 tests, 392 rule shapes × 2,088 date comparisons, **0 divergences** vs `_CalendarICU(.hebrew)`. Covers single-combination patterns (hits short-circuit), multi-combination patterns (BikeParties/Meals/DailyWithTimes shapes), negative ordinals, default matchingPolicy, interval > 1, Adar I leap-only, day-of-month, `.every(weekday)`. Test runtime ~1.6 s.
- Headline perf wins (debug-mode, p50): `RecurrenceRuleThanksgivings` 1,688 → **107 µs** (15.7× speedup, **19× ICU**); `RecurrenceRuleLaborDay` 1,637 → **106 µs** (15.4× speedup, **15× ICU**); `RecurrenceRuleThanksgivingMeals` -7%; mallocs on the two short-circuited benchmarks dropped 95% (2,400+ → ~100).
- Multi-combination patterns (BikeParties / DailyWithTimes) unchanged from v11 — fall through to existing path; their per-match cost is in framework machinery (flatMap allocation, `_adjustedDate`, filter passes), not in the helpers we hijacked.
- Files: `Sources/FoundationEssentials/Calendar/{Calendar_Enumerate.swift, Calendar_Recurrence.swift}`, `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift` (NEW).
- See `v12-recurrence-shortcircuit-and-parity-probe/README.md` for full details + restoration instructions.

### v13 — Multi-combination cartesian short-circuit in `_unadjustedDates` (parity-verified, uncommitted)
*2026-05-04*
- **Status: tested + benchmarked + parity-verified, NOT committed.** Builds on v12.
- Added `_expandedDateComponents` in `Calendar_Recurrence.swift` — produces cartesian product of populated `_DateComponentCombinations` fields when every shape is fast-path-eligible (positive ordinals only, no `.every` weekday, ≤64 combinations).
- Added second short-circuit in `_unadjustedDates` after the v12 single-combination one: if all expanded DCs fast-path successfully, sort chronologically and return; else fall through.
- **Headline win**: `RecurrenceRuleThanksgivingMeals` 1,469 µs → **89 µs** (16.5× speedup, **15× ICU**); 1,767 → **79 mallocs** (-96%).
- `RecurrenceRuleBikeParties` (negative ordinal in weekday) and `RecurrenceRuleDailyWithTimes` (`.every` weekday) are explicitly rejected by the cartesian helper and fall through to the existing path — unchanged behavior, parity preserved.
- Same gating mechanism as v12 (`_calendarNextDate` returns nil for non-Hebrew → fall through). Cross-calendar overhead: one extra cartesian-helper call + one extra protocol probe ≈ 10–50 ns.
- Suite C parity probe still passes (392 rule shapes × 2,088 comparisons, 0 divergences). The `yearly_multipleHours` test specifically exercises the new multi-combo path.
- Files: `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` (only).
- See `v13-multicombo-cartesian-shortcircuit/README.md` for full details + restoration instructions.

### v14 — Option B: BikeParties via runtime weekOfMonth translation for negative ordinals (parity-verified, uncommitted)
*2026-05-04*
- **Status: tested + benchmarked + parity-verified, NOT committed.** Builds on v13.
- Extended `_expandedDateComponents` to accept `anchor: Date?`. When supplied, `.nth(N<0, day)` weekday entries are translated at runtime to `{month, weekday, weekOfMonth}` via the anchor's month structure (target month = `c.months[0]` or anchor's month for monthly recurrence). Routes through the existing `{m, wd, weekOfMonth}` fast path — preserves Suite A/B raw-enumerate parity (which rejects negative `weekdayOrdinal` directly).
- New short-circuit branch (3) in `_unadjustedDates`, gated by a sentinel `_calendarNextDate(matching: {weekday: 1})` probe — non-Hebrew calendars bail before the expensive translation.
- **Headline win**: `RecurrenceRuleBikeParties` 1,463 → **115 µs** (12.7× speedup, **10.8× ICU**); 1,743 → **127 mallocs** (-93%).
- Same gating mechanism as v8–v13. Cross-calendar overhead per `_unadjustedDates` call when negative ordinals present: ~10 ns (sentinel probe).
- Suite C parity probe still passes — `monthly_multipleNthWeekdays` (BikeParties shape) verifies the new path matches ICU exactly.
- 7 of 9 calendar benchmarks now at 10–260× ICU. Remaining: `RecurrenceRuleDailyWithTimes` (.every weekday + multi-time, doesn't fit cartesian translation), `CurrentDateComponentsFromThanksgivings` (non-RecurrenceRule path, separate concern).
- Files: `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` (only).
- See `v14-optionb-negative-ordinal-translation/README.md` for full details + restoration instructions.

### v15 — Time-only fast path for Hebrew `nextDate` (parity-verified, uncommitted)
*2026-05-04*
- **Status: tested + benchmarked + parity-verified, NOT committed.** Builds on v14.
- Removed Hebrew's `!hasMonth && !hasDay && !hasWeekday → nil` rejection in `nextDate(after:matching:direction:)`. Added a time-only branch gated on `{hour, minute, second}` all set, plus a `nextTimeOfDayMatch` helper: if `targetSecsInDay > currentSecsInDay` return RD same-day, else RD+1 (RD-1 backward). `_adjustedDate` (called per result in `_dates`) handles DST as before.
- **Headline win**: `RecurrenceRuleDailyWithTimes` 3,024 → **191 µs** (15.8× speedup, **~8× ICU**); 3,742 → **151 mallocs** (-96%).
- Mechanism: for daily-frequency rules, `weekdayAction == .limit` → combinations contain no weekdays, only `{hours, minutes, seconds}`. v13's `_expandedDateComponents` already produces 4 valid time-only DCs; the only blocker was Hebrew's `nextDate` rejecting them. With v15, the existing v13 cartesian short-circuit fires.
- **Hebrew-only change.** No shared-code edits; non-Hebrew calendars unaffected. Gating (`hour && minute && second` all non-nil) deliberately matches only what `_unadjustedDates`'s short-circuits produce — partial time fields fall through to the generic enumerate framework, preserving ICU semantics where unspecified fields mean "any value".
- Suite A/B/C all pass; 178/178 Calendar+RecurrenceRule, 62/62 Hebrew, 73,414/73,414 Hebcal days, 0 divergences.
- 8 of 9 calendar benchmarks now ≥8× ICU. Other 8 within ±5% noise of v14. Only remaining: `CurrentDateComponentsFromThanksgivings` (non-RecurrenceRule path).
- Files: `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` (only).
- See `v15-time-only-fast-path/README.md` for full details + restoration instructions.

### v16 — Sync from `port/hebrew-main`: Mutex + comment cleanup (parity-verified, uncommitted)
*2026-05-07*
- **Status: tested + parity-verified, NOT committed.** Builds on v15.
- Cherry-picked source-only changes from upstream-bound `port/hebrew-main` (commits `46725dd` "Update Calendar_Hebrew for Swift 6.4: LockedState → Mutex, fix warning" and `04783dc` "Remove diagnostic probe files and icu4swift references") into our local Swift 6.3 working tree.
- Code changes (Calendar_Hebrew.swift only): added `internal import Synchronization`; `LockedState<YearData?>(initialState: nil)` → `Mutex<YearData?>(nil)`; `var newYear` → `let newYear` at line ~894 (warning fix; variable was never reassigned).
- Comment cleanup: removed icu4swift path/date provenance from 5 doc comments + fixed `eager-recalculation` hyphen typo. No code change.
- Strategy: local dev continues on `port/hebrew` (Swift 6.3); when v-stack is PR-ready, work flows to `port/hebrew-main` (Swift 6.4) on user's other machine. v16 is the first reverse-sync to keep code drift minimal.
- Mutex compatibility verified: 4 other files in this codebase already use `internal import Synchronization` + `Mutex<...>` with no availability guards (`NotificationCenter.swift:80` is the canonical example).
- Parity: 178/178 + 62/62 tests, 73,414 Hebcal days, Suite C 0 divergences. No perf impact (sync, not optimization).
- Files: `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` (only).
- See `v16-mutex-and-comment-sync/README.md` for full details + restoration instructions.

### v16-frozen — Safety snapshot pre-v17 (2026-05-13)
*2026-05-13*
- Comprehensive backup of working tree state at v16, captured before applying v17. Includes all 4 source files, 7 test files, 3 benchmark files (14 files total) — more than the per-vN minimal snapshots, so a full restore gives back v16 exactly.
- See `v16-frozen-pre-v17/README.md` for restoration.

### v17 — Sync from `port/hebrew-main` PR-feedback commit (parity-verified, uncommitted)
*2026-05-13*
- **Status: tested + parity-verified, NOT committed.** Builds on v16.
- Cherry-picks `origin/port/hebrew-main` commit `ef191c1` "Address PR #1953 review feedback: remove unused imports, fix DST tests, add benchmarks" into our local Swift 6.3 working tree.
- Source: removed 10 lines of unused libc imports from `Calendar_Hebrew.swift` (`Bionic`/`Glibc`/`Musl`/`CRT`/`WASILibc` — file doesn't use any libc symbols).
- Tests: replaced `HebrewDSTPolicyParityTests.swift` with upstream's parameterized version (`DSTProbe` + `CustomTestStringConvertible`, same test semantics).
- Tests: deleted `HebrewCalendarPerformanceTests.swift` (201 lines; functionality moved to `BenchmarkCalendar.swift`).
- Benchmarks: replaced `BenchmarkCalendar.swift` with upstream's version. Lost local research parameterization. Gained 5 new Hebrew-specific benchmarks: `HebrewCalendar-nextThousandHanukkahs`, `-allocationsForFixedCalendar`, `-copyOnWritePerformance`, `-dateComponents-yearMonthDay`, `-roundTripDateComponents`.
- Parity: 174/174 Calendar+RecurrenceRule tests, 58/58 Hebrew tests, Suite C 0 divergences, 73,414/73,414 Hebcal days. (Counts dropped 178→174 and 62→58 due to the 4 deleted-file tests.)
- Files: `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift`, `Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift`, `Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift` (3 files modified, 1 deleted).
- Doc correction: `MAIN_MERGE.md`'s "what does NOT go upstream" list previously included `HebrewDSTPolicyParityTests.swift` — that file IS upstream-shape (references `_CalendarGregorian` not `_CalendarICU`). Removed.
- See `v17-sync-from-port-hebrew-main/README.md` for full details + restoration instructions.

### v17-frozen — Safety snapshot pre-v18 (2026-05-15)
*2026-05-15*
- Single-file backup of `Calendar_Hebrew.swift` at v17 state, captured before applying v18 comment trims. See `v17-frozen-pre-v18/`.

### v18 — Sync from `port/hebrew-main` PR-round-2 commit (parity-verified, uncommitted)
*2026-05-15*
- **Status: tested + parity-verified, NOT committed.** Builds on v17.
- Cherry-picks `origin/port/hebrew-main` commit `26c1377` "Address PR #1953 review feedback: trim verbose comments, add TODO for shared weekend logic" into our local Swift 6.3 working tree.
- **Comment-only.** No code changes. -88 / +16 lines net. 12 sites in `Calendar_Hebrew.swift` trimmed (isDateInWeekend, utcDate, date(byAdding) header, nextWeekdayMatch same-weekday branch, nextMonthWeekdayOrdinalMatch doc, dateComponents subtraction header, HebrewArithmetic enum doc, calendarElapsedDays doc + inline note, _yearDataCache doc, yearData(_:) doc, hebrewFromFixed approx-year note).
- One `// TODO: Factor out into shared utility; identical to _CalendarGregorian.isDateInWeekend.` added, reviewer-anchored on PR comment #7 (de-duplication).
- Also removed our local-only "4-slot version was tried" research note (preserved in BACKUPS task #35 + SESSION_2026-05-04.md history).
- Reviewer context: PR #1953 round 2 comments — "these comments are so verbose" + "Can we add a // TODO for these future refactoring opportunities?". Benchmark-scope comments (separate, on `BenchmarkCalendar.swift:562/:567`) NOT addressed here — separate upstream commit needed.
- Parity: 174/174 + 58/58 tests unchanged. Suite C 0 divergences, 73,414 Hebcal days.
- Drift vs `port/hebrew-main` on `Calendar_Hebrew.swift`: 198 lines (was 202 at v17) — 100% v10/v11/v15 perf-stack drift, no comment drift.
- Files: `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` (only).
- See `v18-comment-trims-sync/README.md` for full details + restoration instructions.

### v18-frozen — Safety snapshot pre-v19 (2026-05-15)
*2026-05-15*
- Pre-v19 backup of `Calendar_Hebrew.swift` + `Calendar_Gregorian.swift` (both files will be modified for Tier 0 constants extraction). See `v18-frozen-pre-v19/`.

### v19 — SHAREABLE_APIS Tier 0: time-unit constants extracted (parity-verified, uncommitted)
*2026-05-18*
- **Status: tested + parity-verified, NOT committed.** First step of the post-PR-1953 follow-up refactor outlined in `backup/SHAREABLE_APIS.md`. Closes Tier 0 (reviewer comment #6).
- **NEW file**: `Sources/FoundationEssentials/Calendar/CalendarConstants.swift` — `internal enum _CalendarConstants` with 5 static lets (`kSecondsInWeek/Day/Hour/Minute` + `inf_ti`).
- `_CalendarHebrew`: removed 5 dead-code instance declarations (Hebrew never used `kSecondsIn*`; only `inf_ti` had 1 callsite). Updated 1 callsite + 1 doc-comment reference.
- `_CalendarGregorian`: removed 5 instance declarations. Updated 29 callsites: `kSecondsInWeek/Day/Hour/Minute` and `inf_ti` → `_CalendarConstants.X`.
- `Calendar_ICU.swift` deliberately untouched — different module (`FoundationInternationalization`), function-local `inf_ti` declarations only.
- The `k` prefix is preserved at the new constants (minimum-diff initial extraction). Modern-name rename can be a follow-up commit if reviewer asks.
- Parity: 174/174 + 58/58 tests, Suite C 0 divergences.
- **Important build lesson**: when removing stored properties from `internal` classes, SPM incremental compilation can leave stale `.swiftmodule` artifacts that cause runtime SIGSEGV in tests. Resolution: `rm -rf .build/<arch>/debug` for a clean rebuild. v19 verified after clean rebuild.
- Files: `Sources/FoundationEssentials/Calendar/{CalendarConstants.swift (new), Calendar_Hebrew.swift, Calendar_Gregorian.swift}`.
- See `v19-shareable-apis-tier0-constants/README.md` for full details + restoration instructions.

### v19-frozen — Safety snapshot pre-v20 (2026-05-18)
*2026-05-18*
- Pre-v20 backup of `Calendar_Hebrew.swift`, `Calendar_Gregorian.swift`, and `Calendar_Protocol.swift` (all three modified for Tier 1A hash default impl). See `v19-frozen-pre-v20/`.

### v20 — SHAREABLE_APIS Tier 1A: `hash(into:)` default impl (parity-verified, uncommitted)
*2026-05-18*
- **Status: tested + parity-verified, NOT committed.** Smallest Tier 1 step.
- Added `package func hash(into:)` default impl in `_CalendarProtocol` extension. Hashes the standard 7-field tuple (`identifier`, `timeZone`, `firstWeekday`, `minimumDaysInFirstWeek`, `localeIdentifier`, `preferredFirstWeekday`, `preferredMinimumDaysInFirstweek`) — all existing protocol requirements.
- Removed identical hash impls from `_CalendarHebrew` + `_CalendarGregorian`. Replaced with `// hash(into:) uses the _CalendarProtocol default impl.` marker.
- Three conformers keep their hash overrides: `_CalendarAutoupdating` (sentinel), `_CalendarICU` (locked accessors), `_CalendarBridged` (underlying NSCalendar). Different semantics, not de-duplicable here.
- PR #1953 reviewer comment #7 partially addressed (one of 4 duplicated pieces in the "duplicate of Gregorian up to line 142" area).
- Net diff: -32 / +18 ≈ -14 LOC across the three files. Modest, but proves the protocol-extension technique for Tier 1.
- **First real use of `./scripts/clean-test.sh`** — full clean rebuild (359s) + test (103s) = 464s, worked as designed.
- Parity: 174/174 + 58/58 tests, Suite C 0 divergences.
- Files: `Sources/FoundationEssentials/Calendar/{Calendar_Protocol.swift, Calendar_Hebrew.swift, Calendar_Gregorian.swift}`.
- See `v20-shareable-apis-tier1a-hash-default/README.md` for full details + restoration instructions.

### v20-frozen — Safety snapshot pre-v21 (2026-05-20)
*2026-05-20*
- Pre-v21 backup of Hebrew + Gregorian before extracting accessor / copy helpers. See `v20-frozen-pre-v21/`.

### v21 — Shared accessor helpers via `_CalendarUtility` (parity-verified, uncommitted)
*2026-05-20*
- **Status: tested + parity-verified, NOT committed.** Substantive de-duplication of Hebrew + Gregorian. Static helpers approach — no protocol changes, no composition struct, no class-layout changes.
- **NEW file**: `Sources/FoundationEssentials/Calendar/CalendarUtility.swift` — `internal enum _CalendarUtility` with 5 static helpers: `validatedFirstWeekday`, `resolveFirstWeekday`, `clampedMinimumDaysInFirstWeek`, `resolveMinimumDaysInFirstWeek`, `resolvedCopyArgs`.
- Hebrew + Gregorian: thinned `firstWeekday`/`minimumDaysInFirstWeek` getters/setters to one-line forwarders. Thinned `copy()` body from ~24 lines to ~8 lines.
- Duplicated logic (~74 lines in Hebrew + Gregorian combined) now lives in `_CalendarUtility` once (~79 lines). Net diff ~+5 LOC but the duplication is gone — future calendar ports (Coptic, Islamic, etc.) will save ~50 lines each by using the helpers.
- Why static helpers instead of protocol-default impls: the getters read `_firstWeekday`/`_minimumDaysInFirstWeek` (private storage not in protocol). A default impl would require either polluting the protocol or doing composition. Static helpers with explicit parameters bypass the whole dilemma. Same trick as v20's hash, but passing state explicitly.
- The 3 other conformers (`_CalendarAutoupdating`, `_CalendarICU`, `_CalendarBridged`) are completely unaffected — they keep their own implementations.
- Parity: 174/174 + 58/58 tests, Suite C 0 divergences. Verified on incremental build (no SPM cache footgun — no class-layout change).
- PR #1953 reviewer comment #7 substantially addressed (the bulk of the ~140-line "duplicate of Gregorian" surface area now de-duplicated).
- Files: `Sources/FoundationEssentials/Calendar/{CalendarUtility.swift (new), Calendar_Hebrew.swift, Calendar_Gregorian.swift}`.
- See `v21-shareable-apis-accessor-helpers/README.md` for full details + restoration instructions.

### v21-frozen — Safety snapshot pre-v22 (2026-05-21)
*2026-05-21*
- Pre-v22 backup of Hebrew + Gregorian + CalendarUtility before extracting isDateInWeekend. See `v21-frozen-pre-v22/`.

### v22 — `isDateInWeekend` extracted to `_CalendarUtility` (parity-verified, uncommitted)
*2026-05-21*
- **Status: tested + parity-verified, NOT committed.** Continues SHAREABLE_APIS work via static helpers in `_CalendarUtility`.
- Added `_CalendarUtility.isDateInWeekend(weekday:timeInDay:weekendRange:) -> Bool` (~22 lines) and `_CalendarUtility.defaultWeekendRange` (world-default region 001 weekend range).
- Hebrew's `isDateInWeekend(_:)` thinned from ~40 lines to ~10 lines. Also aligned its `timeInDay` computation to integer truncation (matches Gregorian's pattern via `dateComponents([.hour, .minute, .second], ...)`). **Resolves the previously-flagged fractional-second divergence with Gregorian.**
- Gregorian's `isDateInWeekend(_:weekendRange:)` thinned from ~30 to ~4 lines; `isDateInWeekend(_:)` thinned to ~3 lines. The `weekendRange`-taking internal overload is preserved as a thin wrapper for test compatibility (`GregorianCalendarTests.swift:753-761`).
- Resolves the `// TODO: Factor out into shared utility; identical to _CalendarGregorian.isDateInWeekend.` left in Hebrew by v18.
- Net LOC: -29 across all 3 files (the duplicated comparison logic now lives in one place).
- Parity: 174/174 + 58/58 tests, Suite C 0 divergences. Verified on incremental build (no class-layout change).
- Files: `Sources/FoundationEssentials/Calendar/{CalendarUtility.swift, Calendar_Hebrew.swift, Calendar_Gregorian.swift}`.
- See `v22-shareable-apis-isDateInWeekend/README.md` for full details + restoration instructions.

### v22-frozen — Safety snapshot pre-v23 (2026-06-04)
*2026-06-04*
- Pre-v23 backup of `Calendar_Hebrew.swift` + `Calendar_Cache.swift` before applying upstream `f94c6ac`. See `v22-frozen-pre-v23/`.

### v23 — Floor imports + Hebrew feature flag (back-sync from upstream `f94c6ac`, parity-verified, uncommitted)
*2026-06-04*
- **Status: tested + parity-verified, NOT committed.** Back-sync of pre-merge maintainer commit `f94c6ac` (Tina Liu, 2026-05-20) that landed in upstream as part of the squash-merge for PR #1953.
- `Calendar_Hebrew.swift` (+10): platform-specific libc imports for `floor()` (`Bionic` / `Glibc` / `Musl` / `CRT` / `WASILibc`). Fixes the non-Darwin build failure that was the root cause of upstream PR #2015 revert.
- `Calendar_Cache.swift` (+13/-1): adds `foundation_swift_hebrew_calendar_feature_enabled()` and gates the `.hebrew` router behind it. Flag returns `false` outside `FOUNDATION_FRAMEWORK`, so on this iMac's SPM build `Calendar(identifier: .hebrew)` routes to `_CalendarICU(.hebrew)`. Parity probes bypass via direct `_CalendarHebrew` construction so they continue to exercise our implementation.
- Parity (Hebrew filter, incremental): 58 tests in 7 suites passed in 47.6 s.
- See `v23-floor-and-feature-flag/README.md` for full details + restoration instructions.

### v23-frozen — Safety snapshot pre-v24 (2026-06-04)
*2026-06-04*
- Pre-v24 backup of `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift` before applying upstream `b1b8fdf`. See `v23-frozen-pre-v24/`.

### v24 — Move ICU-dependent Hebrew tests (back-sync from upstream `b1b8fdf`, parity-verified, uncommitted)
*2026-06-04*
- **Status: tested + parity-verified, NOT committed.** Back-sync of pre-merge maintainer commit `b1b8fdf` (Tina Liu, 2026-05-20).
- `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift` (-94): removed three tests that construct `Calendar(identifier: .hebrew)` (`debug_hanukkahEnumerateFires_systemTZ`, `debug_hanukkahEnumerateFires`, `crossCheck_againstICU`).
- `Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift` (NEW, +108): same three tests, in a new file under the Internationalization target where the ICU backing is available. After v23's feature-flag gate, these tests now exercise `_CalendarICU` (not `_CalendarHebrew`) — they live in the ICU file to reflect that.
- Parity (full Calendar+RecurrenceRule+Hebrew filter, clean rebuild): **211 tests in 15 suites passed in 52.1 s.** Build 440 s + test 164 s = 607 s. Matches the 2026-06-04 morning baseline; the additional suite is `HebrewCalendarICUTests`.
- See `v24-hebrew-test-split/README.md` for full details + restoration instructions.

### State after v24 (2026-06-04 evening)
- Local `port/hebrew` now contains everything in upstream's Hebrew implementation (`953cf80` → revert → `7808423` reapply), plus our 15-layer v8–v22 perf + SHAREABLE_APIS stack on top.
- Working tree dirty by design (11 modified + 9 untracked); HEAD still at `b6f4b59`.
- Next session: step 1 (force-push `origin/port/hebrew-main` to `upstream/main`). Then move to PR-branch creation on the Swift 6.4 machine.

### v24-frozen — Safety snapshot pre-v25 (2026-06-05)
*2026-06-05*
- Pre-v25 backup of `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift`. See `v24-frozen-pre-v25/`.

### v25 — Suite C upstream-ready (parity-verified, uncommitted)
*2026-06-05*
- **Status: tested + parity-verified, NOT committed.** Adapts `HebrewRecurrenceRuleParityProbe.swift` (Suite C) so it ships upstream as part of the combined v8–v22 PR (per `backup/PR_PLAN.md`).
- Drops the direct `_CalendarICU(...)` constructor reference. ICU side now uses `Calendar(identifier: .hebrew)` which routes to `_CalendarICU` automatically via the v23 feature-flag-off path in `_calendarClass(identifier:)`.
- Hebrew side continues to construct `_CalendarHebrew` directly via `@testable import` (bypasses the feature-flag gate to exercise our impl).
- Doc comment + 1 inline comment updated to describe the new routing. Two surviving `_CalendarICU` references are descriptive-only (in comments) — Swift doesn't care about names in comments, upstream-safe.
- Parity: **0 divergences across all 13 Suite C tests (392 rule shapes × 2,088 comparisons).** Probe runtime 1.8 s; incremental build 62 s.
- Files: `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift`.
- See `v25-suite-c-upstream-ready/README.md` for full details + restoration instructions.

### State after v25 (2026-06-05)
- Local `port/hebrew` ready to ship Suite C as part of the combined PR.
- Pre-PR tasks remaining (per `PR_PLAN.md`): audit `BenchmarkCalendar.swift` fast-path coverage (#61), generate three commit-shape patches (#62), cross-check no `LockedState` leaks (#63).
- Then PR-branch creation on Swift 6.4 machine (#64).
