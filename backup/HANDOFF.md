# Hebrew port — Session Handoff

**Cold-resume: read this file first.** Last update: 2026-06-04.

## ⚠ Current status: PR #1953 MERGED upstream (squash) → reverted → REAPPLIED on 2026-06-03

Hebrew is **live in `upstream/main`** as of 2026-06-03 via the squash + re-apply trio:

| Date | Commit | Action |
|---|---|---|
| late May | `953cf80` | **Merged**: "Add Swift Hebrew calendar implementation (#1953)" — squash of `port/hebrew-main` into `upstream/main`. |
| early June | `c15f44a` | **Reverted**: "Revert ... (#2015)". Root cause: missing `floor` import on non-Darwin + uncontrolled rollout — fixes shipped as `f94c6ac` (floor + feature flag) and `b1b8fdf` (test target split) on `port/hebrew-main`. |
| 2026-06-03 | `7808423` | **Reapplied**: "Reapply hebrew calendar feature (#2017)" — restored squash + added `CMakeLists.txt` entry. |

Hebrew is **gated behind `foundation_swift_hebrew_calendar_feature_enabled()`** — OFF by default — so production Apple-platform `Calendar(identifier: .hebrew)` callers still get `_CalendarICU` until the flag is enabled.

**CI status (initial push, 2026-05-08):** all three required checks passing — Linux ✓, macOS arm64 ✓, Windows (Swift `main` toolchain) ✓.

**Review activity** (now historic):
- Round 1 (2026-05-11) → upstream `ef191c1`, back-synced as v16+v17.
- Round 2 (2026-05-13 → 2026-05-15) → upstream `26c1377` (verbose-comment trims + TODOs), back-synced as v18. The open round-2 comments on `BenchmarkCalendar.swift:562/:567` (benchmark scope) were resolved by upstream maintainers via the pre-merge feature-flag patch `f94c6ac`; treat task #46 as **moot**.
- Pre-merge hardening (2026-05-20 by Tina Liu) → `f94c6ac` floor + feature flag, `b1b8fdf` ICU-dependent test move. These are NOT yet back-synced locally; planned as v23 + v24.

**Next action: step 1 of the Post-PR-merge action plan — sync `port/hebrew-main` with `upstream/main`.** Then back-sync `f94c6ac` + `b1b8fdf` to local `port/hebrew` as v23 + v24, then move to step 2 (SHAREABLE_APIS PR) and step 3 (v8–v15 perf-stack PR).

See `backup/SESSION_2026-05-21_to_06-04.md` for the full timeline + divergence analysis from this session.

Local development on `port/hebrew` (this branch, Swift 6.3) continues independently — perf experimentation, additional benchmarks, more parity tests — and v8–v22 stay applied locally throughout.

## Post-PR-merge action plan

PR #1953 has now MERGED (and was reapplied via #2017 on 2026-06-03). Steps 2 and 3 still happen on the **Swift 6.4 machine** for upstream-bound builds. Step 1 (a pure git operation) is safe on either machine. Local `port/hebrew` (Swift 6.3) continues to track changes by back-sync — v23 + v24 for the pre-merge hardening commits `f94c6ac` + `b1b8fdf`.

**Two-machine workflow**:

| Machine | Branch | Role |
|---|---|---|
| Swift 6.4 (user's other machine) | `port/hebrew-main` | Upstream-bound PRs originate here. Toolchain matches upstream `main`. |
| Swift 6.3 / Intel iMac (this one) | `port/hebrew` | Local dev / v-stack / perf experimentation / Suite A+B+C+regression nets. Back-sync upstream changes here as v-numbered snapshots. |

**Steps after PR #1953 merges**:

1. **Sync `port/hebrew-main` to post-merge `upstream/main`.** The branch's 11 per-commit history is now obsolete — the squash + reapply (`7808423`) made `Calendar_Hebrew.swift` / `Calendar_Cache.swift` / `Calendar.swift` / `Calendar_Protocol.swift` content-identical between `port/hebrew-main` and `upstream/main`. Choose:
   - **(A)** Hard-reset `port/hebrew-main` to `upstream/main` + `git push --force-with-lease origin port/hebrew-main`. Cleanest. Branch becomes a pure tracking/staging branch for follow-up PRs. Per-commit history is preserved in reflog + `backup/v*-*/` snapshots.
   - **(B)** Rebase `port/hebrew-main` onto `upstream/main`. Patch-id matching should drop the 11 commits as already applied; force-push afterward.
   - Either is **destructive on the published branch** — confirm with the user before running.
   - Pure git op (no build/test), so either Swift 6.3 or 6.4 machine is fine for this step.

2. **Open follow-up PR for the de-duplication refactor** per `backup/SHAREABLE_APIS.md`. Reviewer is already familiar with this scope from PR comments #6 + #7. Order:
   - Tier 0 — time-unit constants → `_CalendarConstants` enum.
   - Tier 1 — calendar property storage + init/copy/hash boilerplate → protocol-default impls.
   - Tier 2 — arithmetic helpers (`weekNumber`, `weekday(fromRataDie:)`, `utcDate(fromRataDie:)`, `isDateInWeekend`, etc.) → `_CalendarUtility` enum.
   - Tier 3 deferred.
   - Each tier optionally a separate commit or even separate PR depending on size + reviewer preference.

3. **Open second follow-up PR for the v8–v15 perf stack** per `backup/MAIN_MERGE.md`. Pre-PR checklist there has 8 items; the two open blockers are task #11 (Hebcal fixture handling) and task #37 (commit shape — split shared-code from Hebrew-specific is the recommended option). Suite C upstream handling also needs a call (`MAIN_MERGE.md § Suite C upstream handling`).

4. **Back-sync each landed upstream commit to `port/hebrew`** as v18, v19, ... — same fetch/diff/apply/snapshot pattern as v16 and v17. Keeps the local Suite A+B+C+regression nets verifying Hebrew parity stays clean as the upstream `_CalendarHebrew` evolves.

**Do NOT** start step 2 or 3 on the Swift 6.3 machine — toolchain mismatch risk. Local work here stays limited to: perf experimentation, additional Hebrew-only research benches, doc maintenance, back-syncs.

## Where we are

**Hebrew port is parity-complete + perf-optimized + parity-verified at v24; upstream is LIVE.** PR #1953 squash-merged, reverted, then reapplied 2026-06-03. Pre-merge maintainer hardening (`f94c6ac` floor+feature-flag + `b1b8fdf` Hebrew test split) back-synced as v23 + v24 on 2026-06-04. Three pre-PR blockers persist for the v8–v15 follow-up:
1. Hebcal fixture-size decision (task #11).
2. Commit strategy for v8–v24 uncommitted stack (task #37).
3. Suite C upstream handling (referenced in `MAIN_MERGE.md § Suite C upstream handling`).

Verified 2026-06-04 evening, local `port/hebrew`, debug, Swift 6.3.1:
- `swift test --filter "Hebrew"` (post-v24 incremental) → **58/58 in 8 suites in 46.4 s.**
- `swift test --filter "Calendar|RecurrenceRule|Hebrew"` (post-v24 incremental) → **211/211 in 15 suites in 51.4 s.**
- `./scripts/clean-test.sh "Calendar|RecurrenceRule|Hebrew"` (post-v24 full clean rebuild) → **211/211 in 15 suites; build 440 s + test 164 s = 607 s.**

Suite C parity probe: **0 divergences vs `_CalendarICU(.hebrew)`** across 392 rule shapes × 2,088 date comparisons.

Suite count grew from 14 → 15 vs the morning baseline because v24 added `HebrewCalendarICUTests` under `FoundationInternationalizationTests`.

### Code state

- **Last committed**: `c2668eb` "Extend Hebrew fast-path to {month, weekday, weekdayOrdinal} + cache YearData" (2026-05-03). Pushed to `origin/port/hebrew` (`https://github.com/dra8an/swift-foundation`).
- **Parallel branch**: `origin/port/hebrew-main` (based on upstream `main`, Swift 6.4) — clean upstream-bound shape. Has all of `port/hebrew`'s commits up through `c2668eb`, plus `46725dd` (Swift 6.4 Mutex), `04783dc` (probe/regression file removal + icu4swift comment cleanup), `ef191c1` (PR #1953 review feedback round 1: imports, DST tests, benchmarks), and `26c1377` (PR #1953 review feedback round 2: trim verbose comments + add TODO). v16 backports the first two; v17 backports `ef191c1`; v18 backports `26c1377`.
- **Uncommitted stack** (v8 → v22, all on top of `c2668eb`): 15 layers of perf+sync+refactor work, each backup-snapshotted in `backup/vN-*/` with its own README. **All parity-verified at v22**. See `BACKUPS.md` for the full chain.
- **v19 + v20 + v21 + v22 are SHAREABLE_APIS refactor commits** — started ahead of PR #1953 merging (user decided 2026-05-15 not to wait further). v19 = constants → `_CalendarConstants`. v20 = `hash(into:)` default impl in `_CalendarProtocol`. v21 = accessor helpers via new `_CalendarUtility` enum (firstWeekday/minimumDaysInFirstWeek + `copy()`). v22 = `isDateInWeekend` body extracted to `_CalendarUtility` (also fixed Hebrew↔Gregorian fractional-second divergence). Will be cherry-picked to a new branch from `port/hebrew-main` post-merge.
- **Working tree (modified files, all uncommitted)**:
  - `Sources/FoundationEssentials/Calendar/Calendar.swift` (proxy added in v8)
  - `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` (v8 + v9 + v11 + v12)
  - `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` (v10 + v11 + v15 + v16 + v17 + v18 + v19 + v20 + v21 + v22)
  - `Sources/FoundationEssentials/Calendar/Calendar_Gregorian.swift` (v19 + v20 + v21 + v22)
  - `Sources/FoundationEssentials/Calendar/Calendar_Protocol.swift` (v20 — hash default impl)
  - `Sources/FoundationEssentials/Calendar/CalendarConstants.swift` (v19 — NEW shared file)
  - `Sources/FoundationEssentials/Calendar/CalendarUtility.swift` (v21 — NEW shared file)
  - `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` (v12 + v13 + v14)
  - `Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift` (v17 — adopts upstream version with 5 new Hebrew benchmarks; lost local parameterization which was research-only anyway)
  - `Benchmarks/Benchmarks/Internationalization/{InternationalizationBenchmark.swift, BenchmarkTimeZone.swift}` (parameterized for `.hebrew`; revert to `.gregorian` before commit)
  - `Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift` (v17 — parameterized upstream version)
  - `Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift` (v10 + v11 + correctness probes — local research file, untracked)
  - `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift` (NEW Suite C parity probe — does NOT go upstream, references `_CalendarICU`)
- **Working tree (deleted, intentional v17)**: `Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift` (functionality moved to `BenchmarkCalendar.swift` upstream).
- **Working tree (untracked, intentional)**: `backup/`, `.swift-version`, local research bench files (`HebrewVsICUBenchmark.swift`, `AllocationsBreakdown.swift`, etc.).
- **Upstream PR open**: <https://github.com/swiftlang/swift-foundation/pull/1953> — review feedback addressed in `ef191c1` and back-synced here as v17.

### Headline performance at v24 (debug-mode, p50 vs ICU baseline)

Unchanged from v15 — v16 through v24 are code/comment-shape syncs, refactors, and upstream back-syncs, none perf-relevant.

| Benchmark | v24 | vs ICU |
|---|---:|---:|
| `nextThousandThanksgivings` | 3.97 µs | **~250× faster** |
| `nextThousandThanksgivingsSequence` | 4.10 µs | **~240× faster** |
| `nextThousandThursdaysInTheFourthWeekOfNovember` | 4.17 µs | **~107× faster** |
| `RecurrenceRuleThanksgivings` | 107 µs | **19× ICU** |
| `RecurrenceRuleThanksgivingMeals` | 88 µs | **15× ICU** |
| `RecurrenceRuleLaborDay` | 107 µs | **15× ICU** |
| `RecurrenceRuleBikeParties` | 118 µs | **10.5× ICU** |
| `RecurrenceRuleDailyWithTimes` | 191 µs | **~8× ICU** (was 0.51× at v14; v15 added time-only fast path) |

**8 of 9** calendar benchmarks now ≥8× ICU, with **0 divergences vs `_CalendarICU(.hebrew)`** across all parity probes (Suite A: ~300 dates, Suite B: ~300 dates, Suite C: 2,088 RecurrenceRule date comparisons).

## Quick-verify (confirms v24 state is still good)

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
git status                              # expect: b6f4b59 HEAD (test commit on top of c2668eb); modified Sources/ + Benchmarks/ + Tests/; deleted HebrewCalendarPerformanceTests.swift; untracked backup/, Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift (NEW from v24), Tests/.../EnumerateMicroProfile.swift, .swift-version
git log -1 --oneline                    # expect: "b6f4b59 test commit" (innocuous 1-line README change above c2668eb)
export SWIFTCI_USE_LOCAL_DEPS=1
swift test --filter "Calendar|RecurrenceRule|Hebrew"  # expect: 211 tests in 15 suites pass, 0 failures, Suite C 0 divergences. (211 = 174 Calendar+SuiteC + 58 Hebrew - shared overlap; 15 suites = 14 at v22 + 1 from v24's new HebrewCalendarICUTests.)
swift test --filter "Hebrew"            # expect: 58 tests in 8 suites pass (was 7 at v22 — v24 added HebrewCalendarICUTests).
```

If both pass, the v8–v24 stack is in the verified state. Pick up from "What's next".

**Light sanity check** (after editing source files): the v23 feature-flag gate means `Calendar(identifier: .hebrew)` on this iMac's SPM build routes to `_CalendarICU`, NOT `_CalendarHebrew`. Parity probes bypass via direct `_CalendarHebrew` construction, so they still exercise our impl. If a test that uses `Calendar(identifier: .hebrew)` ever starts failing in a way that looks "ICU-correct but Hebrew-wrong", that's the gate at work — and the test belongs in `HebrewCalendarICUTests.swift`, not `HebrewCalendarTests.swift`.

## ⚠ Build-cache protocol for stored-property refactors

When a refactor adds/removes/reorders stored properties on widely-imported `internal` classes (`_CalendarHebrew`, `_CalendarGregorian`, etc.), SPM's incremental compilation leaves stale module artifacts. Tests crash with **SIGSEGV (signal 11) in `swiftpm-testing-helper`** even though the build succeeds.

**Use these scripts. They will save you time.**

```sh
# Proactive: when you know your change touches storage
./scripts/clean-test.sh "Calendar|RecurrenceRule|Hebrew"

# Reactive: when a SIGSEGV crashes a test and you want to know if it's
# the cache footgun or a real regression
./scripts/diagnose-test-crash.sh "Calendar|RecurrenceRule|Hebrew"
```

`clean-test.sh` removes `.build/*/debug`, rebuilds fully (~5–7 min), and runs the filter. `diagnose-test-crash.sh` runs incrementally first; if it sees signal 11, force-cleans and retests, reporting `CACHE STALENESS CONFIRMED` vs `REAL REGRESSION`.

**Full rationale**: see `backup/BUILD_CACHE_PROTOCOL.md`. We lost ~30 minutes on v19 (2026-05-18) bisecting code that was actually fine before trying a clean rebuild. Don't repeat that.

## Timing discipline

Reference `backup/EXPECTED_TIMES.md` before running any build/test/benchmark. Every command has expected and hard-limit timings. **If a command runs >10% past its hard limit, STOP and investigate** — don't silently wait. Use `swift package benchmark run --filter "^<name>$"` for single-bench iteration (~90 s wall) instead of full bench (5+ min).

The memory `feedback_command_timing_discipline.md` (in `~/.claude/projects/.../memory/`) captures this rule across sessions.

## Environment

- **Machine:** Intel iMac 2019, macOS 15.7.3 (Darwin 24.6). Apple Silicon unavailable.
- **Swift toolchain:** 6.3.1-RELEASE via `swiftly` (not Xcode's 6.2.3).
- **Working repo:** `/Users/draganbesevic/Projects/claude/swift-foundation`.
- **Remotes:** `origin` = `https://github.com/dra8an/swift-foundation.git` (user's fork), `upstream` = `https://github.com/swiftlang/swift-foundation.git` (Apple). Push to origin; PRs fork → upstream.
- **Active branch:** `port/hebrew`, based on `upstream/release/6.3`.
- **Build needs `SWIFTCI_USE_LOCAL_DEPS=1`** and sibling clones at `../swift-collections` (checkout tag `1.1.6`), `../swift-foundation-icu` (main), `../swift-syntax` (main).
- **Release-mode `swift test` crashes** with SIGBUS on Intel x86_64 + Swift 6.3.1 inside `swiftpm-testing-helper`. All perf numbers are debug-mode; see OPEN_ISSUES #3.

## Files the cold session should read, in order

**Bigger picture first (the port effort as a whole):**

1. **`<icu4swift>/Docs/HANDOFF.md`** — icu4swift frozen-repo banner, broad port history, what the overall effort is (replace every ICU calendar with pure Swift). The mission context.
2. **`<icu4swift>/Docs-Foundation/PORT_DIRECTION.md`** — authoritative direction decision: all work moves to `swift-foundation`, icu4swift is frozen. (Path: `/Users/draganbesevic/Projects/claude/CalendarAPI/icu4swift/`.)
3. **`<icu4swift>/Docs-Foundation/MASTER.md`** — index of the design/reference docs that explain _CalendarProtocol, the 10 primitives, the staged rollout plan, etc.

**Current state (Hebrew port specifically):**

4. **`backup/HEBREW_PORT_SUMMARY.md`** (this repo) — one-page summary: files added, parity tables, test/perf results, pre-PR blockers.
5. **`backup/PARITY_PROTOCOL.md`** — **NON-NEGOTIABLE** contract for every calendar port. Suite A (protocol) + Suite B (public API) both required. This rule applies to every subsequent calendar port, not just Hebrew.
6. **`backup/PARITY.md`** — Hebrew's concrete parity status (all ✅).
7. **`backup/OPEN_ISSUES.md`** — pre-PR decisions. Issue #0 (PARITY) is closed. Issue #1 (fixture size) is the only blocker.
8. **`backup/BACKUPS.md`** — snapshot log + remote setup.
9. **`backup/MAIN_MERGE.md`** — what lands on `origin/port/hebrew-main` when v8–v15 is merged from local `port/hebrew`. Read before starting the merge on the Swift 6.4 machine — covers commit-shape options, Suite C upstream handling (it's NOT upstream-safe — `_CalendarICU` reference at line 46), Hebcal fixture decision, anticipated rebase conflicts, pre-merge checklist.
10. **`backup/SHAREABLE_APIS.md`** — planning doc for the post-PR-1953 follow-up that extracts `_CalendarHebrew`/`_CalendarGregorian` shared logic into a common base. Anchored on PR #1953 reviewer comments (#6 constants, #7 duplicate up to line 142). Acted on **after** PR #1953 merges. Tier 0 constants, Tier 1+ storage/init/copy/hash, Tier 2 arithmetic helpers; what NOT to extract; landing order recommendation. **Includes "Where shared code lives — the three homes" decision rule** for whether a piece goes in `_CalendarConstants`, `_CalendarProtocol` extension, `_CalendarUtility` static methods, or a composition struct.
10a. **`backup/PR_PLAN.md`** ⭐ NEW 2026-06-05 — concrete plan for the single combined PR (v8–v22 fast paths + SHAREABLE_APIS dedup). Branch `port/hebrew-perf-and-dedup` off `port/hebrew-main`. 3 commits in order: shared-code fast-path infra → Hebrew fast paths → SHAREABLE_APIS dedup. Includes pre-PR work list, Suite C adaptation plan, blocker resolutions, anticipated review feedback. **Supersedes the two-PR plan in `MAIN_MERGE.md` for current direction.**
11. **`backup/BUILD_CACHE_PROTOCOL.md`** — ⚠ READ BEFORE TIER 1+ REFACTORS. Documents the SPM incremental-build footgun on stored-property changes + the `scripts/clean-test.sh` + `scripts/diagnose-test-crash.sh` workflow. Cost us ~30 min on v19 by not having this protocol in place — don't repeat.

**Most recent session context (read before resuming work):**

12. **`backup/SESSION_2026-05-21_to_06-04.md`** — **most recent**: upstream PR #1953 squash-merged → reverted → reapplied (`7808423`, 2026-06-03). Pre-merge maintainer commits `f94c6ac` (floor + feature flag) and `b1b8fdf` (test target split) on `port/hebrew-main`. Divergence analysis. Step-1 sync options (reset vs rebase). v23 + v24 back-sync plan.
13. **`backup/SESSION_2026-05-04_to_13.md`** — v15 verification, v16 (Mutex + comment sync), v17 (PR-feedback back-sync), upstream PR #1953 opened + CI baseline + reviewer round 1, SHAREABLE_APIS planning, Claude Desktop worktree cleanup.
14. **`backup/SESSION_2026-05-04.md`** — v15-focused (earlier in the May-04-to-13 period, superseded by item 13).
15. **`backup/SESSION_2026-05-01_to_03.md`** — early session log covering v8–v12.
16. **`backup/SESSION_2026-04-27_to_29.md`** — earlier session: rebase onto main, port verification, bug fixes #8–9.

**v8–v14 backup snapshots (read in numerical order to understand the stack):**

- **`backup/v8-enumeratedatesstep-fastpath/README.md`** — `_enumerateDatesStep` fast-path wiring (shared code).
- **`backup/v9-iterator-fastpath-hoist/README.md`** — `DatesByMatching.Iterator` probe-and-commit hoist.
- **`backup/v10-weekofmonth-fastpath/README.md`** — Hebrew `{m, wd, weekOfMonth}` fast path.
- **`backup/v11-helper-hijack/README.md`** — `dateAfterMatchingWeekOfMonth` / `dateAfterMatchingWeekdayOrdinal` helper hijacks.
- **`backup/v12-recurrence-shortcircuit-and-parity-probe/README.md`** — `_unadjustedDates` single-combination short-circuit + Suite C parity probe.
- **`backup/v13-multicombo-cartesian-shortcircuit/README.md`** — `_unadjustedDates` multi-combination cartesian short-circuit (positive-ordinal patterns).
- **`backup/v14-optionb-negative-ordinal-translation/README.md`** — Negative-ordinal patterns via runtime weekOfMonth translation (BikeParties shape).
- **`backup/v15-time-only-fast-path/README.md`** — Time-only `{h, mi, s, ns?}` fast path in Hebrew `nextDate` (DailyWithTimes shape).
- **`backup/v16-mutex-and-comment-sync/README.md`** — Sync from `port/hebrew-main`: Mutex swap + comment cleanup. No perf change.
- **`backup/v16-frozen-pre-v17/README.md`** — Safety snapshot before v17 (full working-tree backup).
- **`backup/v17-sync-from-port-hebrew-main/README.md`** — Sync from `port/hebrew-main`'s PR-feedback commit `ef191c1`: strip libc imports, parameterize DST tests, delete `HebrewCalendarPerformanceTests.swift`, replace `BenchmarkCalendar.swift` with upstream version. No perf change.
- **`backup/v17-frozen-pre-v18/README.md`** — Safety snapshot before v18 (single file).
- **`backup/v18-comment-trims-sync/README.md`** — Sync from `port/hebrew-main`'s `26c1377`: 12 comment trims in `Calendar_Hebrew.swift` + one `// TODO`. Comment-only, no perf change.
- **`backup/v18-frozen-pre-v19/README.md`** — Safety snapshot pre-v19 (Hebrew + Gregorian).
- **`backup/v19-shareable-apis-tier0-constants/README.md`** — SHAREABLE_APIS Tier 0: extract 5 time-unit constants into `_CalendarConstants` enum. PR #1953 reviewer comment #6 addressed. **Note: requires `rm -rf .build/<arch>/debug` clean rebuild — incremental builds leave stale module artifacts after class-layout changes.**
- **`backup/v19-frozen-pre-v20/README.md`** — Safety snapshot pre-v20 (Hebrew + Gregorian + Calendar_Protocol).
- **`backup/v20-shareable-apis-tier1a-hash-default/README.md`** — SHAREABLE_APIS Tier 1A: `hash(into:)` default impl in `_CalendarProtocol` extension. Removes 2 duplicated impls (Hebrew + Gregorian). PR #1953 comment #7 partially addressed. Three other conformers (Autoupdating, ICU, Bridged) keep specialized overrides. **First real use of `./scripts/clean-test.sh`** — worked as designed.
- **`backup/v20-frozen-pre-v21/README.md`** — Safety snapshot pre-v21 (Hebrew + Gregorian).
- **`backup/v21-shareable-apis-accessor-helpers/README.md`** — Shared accessor helpers via NEW `_CalendarUtility` enum (5 static methods). Thinned `firstWeekday`/`minimumDaysInFirstWeek` getters/setters + `copy()` body in Hebrew + Gregorian. ~74-line duplication removed. PR #1953 comment #7 substantively addressed.
- **`backup/v21-frozen-pre-v22/README.md`** — Safety snapshot pre-v22 (Hebrew + Gregorian + CalendarUtility).
- **`backup/v22-shareable-apis-isDateInWeekend/README.md`** — `isDateInWeekend` body extracted to `_CalendarUtility`. Net -29 LOC. Side benefit: aligned Hebrew's `timeInDay` computation to Gregorian's pattern, fixing previously-flagged fractional-second divergence.

Each snapshot README has restoration instructions. `BACKUPS.md` is the canonical changelog.

**Performance research artifacts (cross-link from PARITY.md):**

17. **`backup/BENCHMARK_TESTS.md`** — local Tests/-based benchmarks (uncommitted), debug-mode timing.
18. **`backup/BENCHMARKS_PACKAGE.md`** — official package-benchmark target. Has the canonical snapshot-labeling convention + full perf table v8 → v19 + § Running with working bench command + 4 footguns.
19. **`backup/bench_*.txt`** — raw benchmark output files. Latest: `bench_hebrew_results_v15_time_only.txt`.
20. **`backup/RECURRENCE_VS_NEXTDATE.md`** — analysis of the per-match cost gap, plus resolution at v12/v13/v14/v15.
21. **`backup/EXPECTED_TIMES.md`** — build/test/benchmark timing bounds + 10% rule.

**Shared-code-change safety analysis (essential reading for upstream review):**

22. **`backup/SHARED_CODE_SAFETY.md`** — explains why the v8–v14 stack's shared-code edits in `Calendar_Enumerate.swift` and `Calendar_Recurrence.swift` are safe for non-Hebrew calendars. Every gated by a protocol method whose default returns nil; per-call gating overhead ≤100 ns; aggregate <1% of any practical workload's match cost. Includes a reviewer checklist.

## Files in the port

| File | Role |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Main implementation: `_CalendarHebrew` class + `HebrewArithmetic` (Reingold & Dershowitz). |
| `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` | Router flipped: `.hebrew` → `_CalendarHebrew.self`. |
| `Sources/FoundationEssentials/Calendar/Calendar.swift` | (uncommitted) `_calendarNextDate` proxy added in v8. |
| `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` | (uncommitted) `_enumerateDatesStep` fast-path wiring (v8) + `DatesByMatching.Iterator` hoist (v9) + helper hijacks (v11/v12). |
| `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` | (uncommitted) `_unadjustedDates` short-circuits: single-combo (v12), multi-combo positive (v13), negative-ordinal translation (v14). Plus `_singleCombinationDateComponents`, `_expandedDateComponents`, `_unadjustedDatesHasNegativeOrdinal` helpers. |
| `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift` | Direct unit tests. |
| `Tests/FoundationEssentialsTests/HebrewRegressionTests.swift` | 73,414-day Hebcal regression (local-only — references external CSV, doesn't go upstream). |
| `Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift` | Suite A — protocol probe (local-only — references `_CalendarICU`). |
| `Tests/FoundationInternationalizationTests/HebrewPublicAPIComparisonProbe.swift` | Suite B — public-API probe (local-only — references `_CalendarICU`). |
| `Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift` | DST policy parity vs `_CalendarGregorian` (upstream — was parameterized in v17 per PR feedback). |
| `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift` | (uncommitted, local-only) Suite C — RecurrenceRule parity probe. 13 tests, 392 rule shapes × 2,088 date comparisons, 0 divergences vs `_CalendarICU(.hebrew)`. References `_CalendarICU` so stays local. |
| `Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift` | (v17) Adopts upstream version with 5 Hebrew-specific package benchmarks added. Replaces the old `HebrewCalendarPerformanceTests.swift` which v17 deleted. |

Hebcal CSV reference lives outside the repo at `~/Projects/claude/CalendarAPI/icu4swift/Tests/CalendarComplexTests/hebrew_1900_2100_hebcal.csv` (1.7 MB). Moving/sampling it is task #11.

## Tasks

| # | Subject | Status |
|---|---|---|
| 1–10 | Core port (skeleton, arithmetic, router, day-add optimization) | ✅ done |
| 11 | Decide Hebcal fixture size (in-repo vs external vs sampled) | **open — sole PR blocker** |
| 12–17 | Suite A parity gaps | ✅ done |
| 18 | Suite B public-API probe | ✅ done |
| 19 | Expanded probe coverage (~300 dates × 13 topics) — Suite A & B | ✅ done (2026-04-27) |
| 20 | DST policy parity test — `_CalendarHebrew.utcDate` vs `_CalendarGregorian` across all 4 (.former/.latter)² combos | ✅ done (2026-04-27) |
| 21 | Expand Suite B to ~300 dates (match Suite A topic coverage through public API) | ✅ done (2026-04-28) |
| 22 | Move DST policy tests to FoundationInternationalizationTests (IANA TZ needs ICU link) | ✅ done (2026-04-28) |
| 23 | Fast-path infrastructure (`_CalendarProtocol.nextDate`, wiring in `Calendar.swift`, 4 patterns in Hebrew) | ✅ done (2026-04-30, committed `c2668eb`) |
| 24 | Package-benchmark Hebrew comparison (Gregorian / ICU-as-Hebrew / `_CalendarHebrew`) | ✅ done (2026-05-03) |
| 25 | Extend fast path to `{m, wd, wdOrd}` (Thanksgiving-style) | ✅ done (2026-05-03, committed `c2668eb`) |
| 26 | YearData single-slot cache | ✅ done (2026-05-03, committed `c2668eb`) |
| 27 | `_enumerateDatesStep` fast-path wiring + `DatesByMatching.Iterator` hoist (Sequence API + RecurrenceRule shared-code) | ✅ done (2026-05-03, **uncommitted** — `backup/v8-*/`, `v9-*/`) |
| 28 | `{m, wd, weekOfMonth}` fast path (`nextThousandThursdaysInTheFourthWeekOfNovember` 527 µs → 4 µs, 109× ICU) | ✅ done (2026-05-03, **uncommitted** — `backup/v10-*/`) |
| 29 | Helper-level hijacks at `dateAfterMatchingWeekOfMonth` / `dateAfterMatchingWeekdayOrdinal` | ✅ done (2026-05-03, **uncommitted** — `backup/v11-*/`) |
| 30 | `_unadjustedDates` single-combination short-circuit + `dateAfterMatchingMonth`/`dateAfterMatchingWeekday` hijacks (`RecurrenceRuleThanksgivings` 1,688 µs → 107 µs, **19× ICU**) | ✅ done (2026-05-04, **uncommitted** — `backup/v12-*/`) |
| 31 | Suite C `HebrewRecurrenceRuleParityProbe` — 392 rule shapes × 2,088 date comparisons, 0 divergences vs `_CalendarICU(.hebrew)` | ✅ done (2026-05-04, **uncommitted** — `backup/v12-*/`) |
| 32 | `_unadjustedDates` multi-combination cartesian short-circuit (`RecurrenceRuleThanksgivingMeals` 1,469 µs → 89 µs, **15× ICU**) | ✅ done (2026-05-04, **uncommitted** — `backup/v13-*/`) |
| 33 | `SHARED_CODE_SAFETY.md` — analysis of how every shared-code change is gated by protocol-method-returns-nil, ensuring non-Hebrew calendars fall through unchanged | ✅ done (2026-05-04) |
| 34 | `_unadjustedDates` negative-ordinal short-circuit via runtime weekOfMonth translation (`RecurrenceRuleBikeParties` 1,463 µs → 115 µs, **10.8× ICU**) | ✅ done (2026-05-04, **uncommitted** — `backup/v14-*/`) |
| 35 | Multi-slot YearData cache (4-slot LRU) | ✘ tried 2026-05-04, REVERTED — gave 2-5% wins on year-crossing benchmarks but 5-6% regressions on `nextThousand*`. Single-slot stays. |
| 36 | DailyWithTimes (`.every` weekday + multi-time) — time-only `{h, mi, s}` fast path in Hebrew `nextDate` (3,024 µs → 191 µs, **~8× ICU**) | ✅ done (2026-05-04, **uncommitted** — `backup/v15-*/`) |
| 37 | Decide commit strategy for v8–v17 stack (one PR or split into shared-code + per-calendar) | open — `MAIN_MERGE.md` recommends split (Commit A shared-code + Commit B Hebrew-specific). Resolve when PR #1953 merges. |
| 38 | v16 — sync `port/hebrew-main` grooming commits (`46725dd` Mutex + `04783dc` icu4swift cleanup) back to `port/hebrew` | ✅ done (2026-05-04, **uncommitted** — `backup/v16-*/`) |
| 39 | Author `MAIN_MERGE.md` — comprehensive merge-prep doc covering branch model, code delta, commit-shape options, Suite C handling, Hebcal fixture, rebase mechanics, pre-merge checklist | ✅ done (2026-05-07) |
| 40 | Open upstream PR #1953 at `swiftlang/swift-foundation` from `port/hebrew-main`. Initial-push CI: Linux ✓ macOS arm64 ✓ Windows ✓ | ✅ done (2026-05-08) |
| 41 | Address PR #1953 reviewer round 1 — performance tests → benchmarks, DST tests parameterized + `#expect` instead of `print`, remove unused libc imports. Landed as `ef191c1` on `port/hebrew-main`. | ✅ done (2026-05-11) |
| 42 | v17 — back-sync `ef191c1` to `port/hebrew` | ✅ done (2026-05-13, **uncommitted** — `backup/v17-*/`; comprehensive safety snap at `backup/v16-frozen-pre-v17/`) |
| 43 | Author `SHAREABLE_APIS.md` — planning doc for deferred de-duplication work (PR comments #6 + #7) | ✅ done (2026-05-13) |
| 44 | Address PR #1953 reviewer round 2 — verbose-comment trims + TODOs. Landed as `26c1377` on `port/hebrew-main`. | ✅ done partially (2026-05-14, code+comments). Two open comments on `BenchmarkCalendar.swift:562/:567` (benchmark scope) still need an upstream commit. |
| 45 | v18 — back-sync `26c1377` to `port/hebrew` | ✅ done (2026-05-15, **uncommitted** — `backup/v18-*/`; safety snap at `backup/v17-frozen-pre-v18/`) |
| 46 | Address PR #1953 reviewer round 2 remaining items (`BenchmarkCalendar.swift:562/:567` benchmark scope — measure init vs measure scope) | open — needs upstream commit on Swift 6.4 machine |
| 47 | SHAREABLE_APIS Tier 0 (time-unit constants extracted to `_CalendarConstants`) | ✅ done (2026-05-18, **uncommitted** — `backup/v19-*/`) — started ahead of PR #1953 merge per user direction |
| 48 | SHAREABLE_APIS — `hash(into:)` default impl in `_CalendarProtocol` extension — PR #1953 reviewer comment #7 partial | ✅ done (2026-05-18, **uncommitted** — `backup/v20-*/`) |
| 49 | SHAREABLE_APIS — accessor helpers via new `_CalendarUtility` enum (`firstWeekday`/`minimumDaysInFirstWeek` getters/setters + `copy()` body via static helpers). Substantive answer to comment #7. | ✅ done (2026-05-20, **uncommitted** — `backup/v21-*/`) |
| 50 | SHAREABLE_APIS — `isDateInWeekend` body extracted to `_CalendarUtility`. Side benefit: fixed Hebrew↔Gregorian fractional-second divergence. | ✅ done (2026-05-21, **uncommitted** — `backup/v22-*/`) |
| 51 | SHAREABLE_APIS — init body extraction (Hebrew + Gregorian still each have ~50 lines of init logic with calendar-specific defaults intermixed) | open — harder because ISO8601 defaults differ |
| 52 | SHAREABLE_APIS — composition struct (`_CalendarProperties`) for actual stored-property de-duplication | open — biggest layout-changing refactor; only needed if #51 isn't enough |
| 53 | Post-PR-merge: open v8–v15 perf-stack PR per `MAIN_MERGE.md` (split shared-code + Hebrew-specific) | open — PR #1953 has now merged; gated only on tasks #11/#37 + Suite C handling |
| 54 | Step 1 — sync `port/hebrew-main` to `upstream/main` | ✅ done (2026-06-05 on Swift 6.4 machine; both now at `5829fa1`) |
| 59 | Adopt single-PR direction (vs two PRs in `MAIN_MERGE.md`) — combine v8–v15 perf + v19–v22 dedup into one PR | ✅ done (2026-06-05; documented in `backup/PR_PLAN.md`) |
| 60 | Adapt Suite C (`HebrewRecurrenceRuleParityProbe.swift`) — replace `_CalendarICU` reference with `Calendar(identifier: .hebrew)` route. Snapshot as v25. | ✅ done (2026-06-05, **uncommitted** — `backup/v25-suite-c-upstream-ready/`; safety snap at `backup/v24-frozen-pre-v25/`; **0 divergences across 13 tests preserved**) |
| 61 | Audit `BenchmarkCalendar.swift` for fast-path benchmark coverage | ✅ done (2026-06-05; **decision: ship zero new benchmarks**, quote perf table in PR description) |
| 62 | Generate three commit-shape patches from `backup/v*-*/` snapshots | superseded by 2-commit shape; mega-commit on `port/hebrew` (`ccbe1fc`) + cherry-pick + selective staging used instead |
| 63 | Cross-check no `LockedState` leaks into outgoing patches | ✅ done (2026-06-05; `grep LockedState Sources/FoundationEssentials/Calendar/*.swift` returned nothing on PR branch) |
| 64 | Open PR `port/hebrew-perf-and-dedup` against `swiftlang/swift-foundation` `main` (Swift 6.4 machine) | open — gated on 6.4 build/test + Gregorian-dedup decision + 6.4-review-comments resolution |
| 65 | Mega-commit on `port/hebrew` (single commit of v8–v25 + local infrastructure) | ✅ done (2026-06-05, `ccbe1fc`, pushed to `origin`) |
| 66 | Create + push `port/hebrew-perf-and-dedup` PR branch with 2 commits (fast paths + SHAREABLE_APIS) | ✅ done (2026-06-05, pushed to `origin`) |
| 67 | Apply v19–v22 dedup operations to upstream's `Calendar_Gregorian.swift` (deferred from 6.3 — needs 6.4 build/test) | open — discuss tomorrow before acting |
| 68 | Address Swift 6.4 machine review comments on the PR branch | open — comments TBD; user will brief tomorrow |
| 69 | Write PR body (description, perf table, reviewer-facing cover notes) | open — gated on #67 outcome |
| 55 | Back-sync `f94c6ac` to local `port/hebrew` as v23 (floor + feature flag) | ✅ done (2026-06-04, **uncommitted** — `backup/v23-floor-and-feature-flag/`; safety snap at `backup/v22-frozen-pre-v23/`) |
| 56 | Back-sync `b1b8fdf` to local `port/hebrew` as v24 (Hebrew test split) | ✅ done (2026-06-04, **uncommitted** — `backup/v24-hebrew-test-split/`; safety snap at `backup/v23-frozen-pre-v24/`) |
| 57 | After v23 + v24: re-run `clean-test.sh "Calendar\|RecurrenceRule\|Hebrew"` and confirm 211/211 stays green | ✅ done (2026-06-04, **211/211 in 15 suites, build 440 s + test 164 s + incremental broader-filter pass 52 s**) |
| 58 | Update `BACKUPS.md` and `MAIN_MERGE.md` to reference post-merge reality (squash-merge cmt, reapply cmt, feature-flag gating) | open |
| 46 | Address PR #1953 reviewer round 2 remaining items (`BenchmarkCalendar.swift:562/:567` benchmark scope) | **moot** — resolved by maintainer feature-flag patch `f94c6ac` |

## What's next

### Status as of 2026-06-05 evening

**PR branch `port/hebrew-perf-and-dedup` is BUILT and PUSHED to `origin`.** Swift 6.4 machine has run validation — user reports "some comments, but in general it's fine." Specific comments TBD tomorrow morning.

Two commits on the PR branch (atop `port/hebrew-main` == `upstream/main`):
- `8342e1d` — Add Hebrew calendar fast paths + shared protocol method (Commit 1: shared-code wiring + Hebrew implementation + Suite C parity probe)
- `86515dd` — Extract shared calendar helpers into _CalendarConstants + _CalendarUtility (Commit 2: shared helpers + Hebrew adoption; **Gregorian deliberately reverted to upstream** — Gregorian dedup deferred)

Today's accomplishments in order:
1. Confirmed step 1 sync (`origin/port/hebrew-main` == `upstream/main` at `5829fa1`).
2. Task #60: Suite C adapted to drop `_CalendarICU` reference (v25, 0 divergences preserved).
3. Task #61: BenchmarkCalendar audit — decision: ship zero new benchmarks (quote perf numbers in PR description).
4. Mega-commit on `port/hebrew` (`ccbe1fc`): single commit of entire v8–v25 stack + local infrastructure → clean working tree.
5. Branch `port/hebrew-perf-and-dedup` created off `port/hebrew-main` + reshaped to 2 PR commits via cherry-pick + selective staging.
6. Pushed both branches to `origin`.
7. Handoff to Swift 6.4 machine for build + test + Gregorian-dedup decision + PR open.

User-driven decision today: **2-commit PR shape** instead of the 3-commit shape originally in `PR_PLAN.md` (fast paths + Hebrew impl bundled into Commit 1; SHAREABLE_APIS dedup as Commit 2).

See `backup/SESSION_2026-06-05.md` for the full session log.

### Next actions (tomorrow 2026-06-06)

1. **Address 6.4 review comments** — specific items TBD; user will brief on resume.
2. **Decide on Gregorian dedup** — apply as Commit 3 on the PR branch (using `patch --fuzz=3` from port/hebrew snapshots on the 6.4 machine) OR defer to follow-up PR. Discuss before acting.
3. **Write PR body** — use commit messages + `SHARED_CODE_SAFETY.md` (Commit 1 cover) + `SHAREABLE_APIS.md` (Commit 2 design) + benchmark numbers from local `HebrewVsICUBenchmark.swift`.
4. **Open PR** against `swiftlang/swift-foundation` `main` from the 6.4 machine.

### Gated on PR #1953 outcome

The two big PRs (de-duplication refactor + v8–v15 perf stack) need PR #1953 merged — **done as of 2026-06-03 via reapply commit `7808423`**. Pre-PR blockers still to resolve before either follow-up:

1. **Task #11 — Hebcal fixture handling.** `HebrewRegressionTests.swift` loads a 1.7 MB external CSV from a hardcoded path. Three options: (a) in-repo SwiftPM resource bundle (size concern), (b) sampled down (parity-coverage concern), (c) stays local-only (Suite-C-style tradeoff). Decision needed.

2. **Task #37 — Commit shape for v8–v15.** Per `MAIN_MERGE.md`, recommended split is *(A) shared-code* (`Calendar.swift` + `Calendar_Enumerate.swift` + `Calendar_Recurrence.swift`) + *(B) Hebrew-specific* (`Calendar_Hebrew.swift` only), as two commits or possibly two PRs. `SHARED_CODE_SAFETY.md` is the cover note for (A).

3. **Suite C upstream handling.** Suite C references `_CalendarICU(...)` (line 46) and can't go upstream as-is. Three options per `MAIN_MERGE.md § Suite C upstream handling`: adapt to `.gregorian` parity (recommended), external reference, or `#if DEBUG_HEBREW_PARITY`.

### Unblocked local work (no PR-merge dependency)

4. **Continue perf experimentation on `port/hebrew`.** Add v18+ layers if any new optimization opportunity surfaces. Anything Hebrew-only or in `port/hebrew`-only test files is safe.

5. **`CurrentDateComponentsFromThanksgivings` one-line fix candidate** — currently uses `currentCalendar` not the parameterized `cal`, so it doesn't measure Hebrew. Changing to `cal` would surface Hebrew's `dateComponents([16 fields])` perf. Optional v18 slot.

6. **Start the next calendar port** — PARITY_PROTOCOL defines the pattern. Candidates: Coptic, Ethiopian, Islamic Civil (all arithmetic, low-risk), Japanese (era table, medium). Each will inherit the v8–v15 shared-code infrastructure (whenever it lands) by implementing `_CalendarProtocol.nextDate(after:matching:direction:)`.

7. **`isDateInWeekend` 100% match fix** — see `SHAREABLE_APIS.md § Tier 2`. Two known divergences from `_CalendarGregorian.isDateInWeekend` (fractional-second time-in-day + DST instant offset). Worth fixing as part of the Tier 2 extraction; alternatively, fix locally first.

## Perf headline

See "Headline performance at v24" table at the top of this document. Plus
the `BENCHMARKS_PACKAGE.md` table for the full v8 → v24 progression.

Older Hebrew-specific benches (committed at `c2668eb`):
- alloc + day-add: **4.9×** faster
- round-trip dateComponents: **3.5×** faster
- copy-on-write mutation: **20×** faster
- `nextThousandHanukkahs` enumerate: **129×** faster

Release numbers TBD pending executable-target workaround for the Swift 6.3.1 test-helper crash.

## Correctness headline

- **1510/1510 full Foundation tests pass on main** (verified 2026-04-28 on Apple Silicon, Swift 6.4-dev main-snapshot-2026-04-27, macOS 26).
- **58/58 Hebrew tests pass at v24** (8 suites: direct units (in `HebrewCalendarTests.swift`), Hebrew Calendar ICU (in v24's new `HebrewCalendarICUTests.swift`), Suite A probe, Suite B probe, DST policy parity, Hebcal regression, vs-ICU benchmark, Suite C parity probe). Count dropped from 62 → 58 at v17 because `HebrewCalendarPerformanceTests.swift` was deleted; suite count grew from 7 → 8 at v24 because the ICU-dependent tests moved into their own file.
- **211/211 Calendar+RecurrenceRule+Hebrew tests pass at v24** (15 suites). Equivalent baseline as the v22 211/15 — v23/v24 didn't change the count, just moved 3 Hebrew tests into a new suite that the filter still catches.
- **73,414/73,414 Hebcal days match** over 1900–2100, with one documented 385-day window at Hebrew year 5806 (Gregorian 2045-11-10 → 2046-11-29) skipped — Hebcal/swift-foundation-icu disagree on year length there; PARITY mandates ICU.
- **Suite A** (`HebrewICUComparisonProbe`): 13 topic-specific tests covering ~300 dates. **0 divergences.**
- **Suite B** (`HebrewPublicAPIComparisonProbe`): 11 topic-specific tests covering ~300 dates (matching Suite A topics through the public Calendar API) + baseline 10-date probe + DST sweep (17 wall-clocks) + locale sweep (6 configs × 10 dates). **0 divergences.**
- **Suite C** (`HebrewRecurrenceRuleParityProbe`): 13 tests, 392 rule shapes × 2,088 date comparisons across 8 anchor dates. **0 divergences.** Required by the v8–v15 perf optimization stack to verify RecurrenceRule output matches `_CalendarICU(.hebrew)` exactly.
- **DST policy parity** (`HebrewDSTPolicyParityTests`): 16 wall-clocks × 4 policy combinations = 64 cases. **0 divergences vs `_CalendarGregorian`.**

## Bug-fix history

### 2026-04-27 expanded-probe session (bugs #1–7)

The probe expansion (~10 dates → ~300 dates across 13 topics) found seven distinct bug classes in the original `_CalendarHebrew`. All fixed. Full details in `PARITY.md` § "Bug-fix summary":

1. `ordinality(.weekday, in: .weekOfYear)` ignored `firstWeekday`.
2. `dateInterval(.yearForWeekOfYear).duration` used Hebrew calendar year, not yearForWeekOfYear.
3. R&D post-hoc `yearLengthCorrection` disagreed with ICU at year boundaries (e.g. Hebrew 5462 / Gregorian 1700) — Apple's swift-foundation-icu uses chained dehiyot (Lo ADU + Betutakpat as separate `if`, not else-if).
4. `dateComponents` extraction used `rawAndDaylightSavingTimeOffset(.former, .former)` where `secondsFromGMT(for:)` is the right API for UTC→local extraction.
5. `dateInterval(.hour/.minute/.second)` re-constructed via `date(from:)` with `.former` policy, landing in the wrong UTC half at DST repeats.
6. `dateComponents(_:from:to:)` iteration accumulated day-clamping (cumulative `start + n*step` is correct, not iterative `current + 1*step`).
7. `utcDate(fromRataDie:)` passed `skippedTimePolicy` through to TimeZone — `_CalendarGregorian` doesn't, and matching ICU requires dropping it. Caught by the new policy-parity test.

### 2026-04-28 Suite B expansion session (bugs #8–9)

Suite B expanded to ~300 dates (matching Suite A's topic coverage through the public Calendar API). Found two additional bugs:

8. Multi-field `date(byAdding:)` at Kislev 30: year+month were batched in a single decompose→adjust→clamp→reconstruct cycle, skipping intermediate day-clamping between year-add and month-add. Split into sequential operations matching `_CalendarGregorian`.
9. Nanosecond extraction used chained FP subtractions + `.rounded()` where `_CalendarGregorian` uses a single subtraction from the original value + truncation (`Int(...)`). Matched Gregorian's approach.
