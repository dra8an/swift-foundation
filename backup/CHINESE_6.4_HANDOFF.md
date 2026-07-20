# Chinese calendar — 6.4 machine handoff (M5, 2026-07-19)

Mirror of BUDDHIST_JAPANESE_6.4_HANDOFF.md. Research branch: `port/chinese`
(6.3 iMac), head = c4 `b2d5d5f`. Master context: `backup/CHINESE_PLAN.md`
(§ 11 = findings/registry, § 12 = two-tier test strategy).

## Branch topology (PR branch is INDEPENDENT — not stacked on B/J)

```
Research side (6.3 iMac, fork):           PR side (this machine, fork -> upstream):
port/hebrew                               (merged: #1953/#2028)
  \- port/buddhist - ae2bc97              port/buddhist-japanese-main -- PR #2105 (open)
       \- port/chinese - 173a20a+         port/chinese-main ------------- NEW standalone PR
          (backup/ + probes + code)          \- cut fresh off upstream/main, 7 files only
```

Research branches stack (Chinese sits on Buddhist only to inherit probe
infrastructure). PR branches NEVER stack: `port/chinese-main` starts at the
top of `upstream/main`, contains only the seven Chinese files, zero B/J
code, and has NO dependency on #2105 merging in either direction. The one
shared touchpoint is `Calendar_Cache.swift` (both PRs add a flag + routing
line to the same region) — hence Step 2's "match whatever main has":
#2105-first -> chinese hunk slots after the B/J lines; both open -> the
second to land resolves a trivial one-hunk rebase conflict. You will own
two parallel unrelated PR branches: keep shepherding #2105, open
chinese-main standalone on the user's word.

## Cut the feature branch — exact operational script

Environment first: Apple Silicon → release mode WORKS here (it SIGBUSes on
the 6.3 Intel iMac; that is why all research numbers are debug).
`export TOOLCHAINS=swift SWIFTCI_USE_LOCAL_DEPS=1` for every build.

### Step 0 — sanity on the research branch

```
git fetch origin && git fetch upstream
git checkout port/chinese   # must be 8572c17 or later
swift test --filter "chinese|Chinese"   # expect ~48 tests, 0 failures
```

If this fails here but passed on the 6.3 machine → environment problem,
not code; check `swift --version` (toolchain memory) before touching code.

### Step 1 — branch + whole-file copies (new files, no upstream counterpart)

RECOMMENDED: create the branch as a git WORKTREE so #2105 work continues in
parallel and the two branches never share a .build (avoids the documented
SPM stale-artifact SIGSEGV trap — see BUILD_CACHE_PROTOCOL.md):

```
git fetch upstream
git worktree add -b port/chinese-main ../swift-foundation-chinese upstream/main
cd ../swift-foundation-chinese   # run ALL remaining steps here
```

(Each worktree has its own .build; refs/objects are shared; a branch can
only be checked out in one worktree at a time. Re-export TOOLCHAINS/
SWIFTCI_USE_LOCAL_DEPS per shell as usual.) Single-worktree alternative:

```
git checkout -b port/chinese-main upstream/main
git checkout origin/port/chinese -- \
  Sources/FoundationEssentials/Calendar/Calendar_Chinese.swift \
  Sources/FoundationEssentials/Calendar/Calendar_Astronomy.swift \
  Tests/FoundationEssentialsTests/ChineseCalendarTests.swift \
  Tests/FoundationInternationalizationTests/ChineseRecurrenceRuleParityProbe.swift
```

These four are self-contained: Chinese references `_CalendarAstronomy`
(they travel together), tests use @testable imports only, no external data.

### Step 2 — manual edits (files EXIST upstream; do NOT whole-file copy)

1. `Sources/FoundationEssentials/Calendar/CMakeLists.txt`: add
   `Calendar_Astronomy.swift` and `Calendar_Chinese.swift` to
   target_sources, alphabetical position.
2. `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift`, two hunks
   mirroring hebrew/B-J shape exactly:
   - both `#if` branches: `internal func
     foundation_swift_chinese_calendar_feature_enabled() -> Bool` hard
     `return false` (FOUNDATION_FRAMEWORK branch carries the
     "once Apple adds the underscored binding" comment style).
   - `_calendarClass(identifier:)`: `else if
     foundation_swift_chinese_calendar_feature_enabled() && identifier ==
     .chinese { return _CalendarChinese.self }` after the hebrew line.
   - RECONCILE: if #2105 merged, buddhist/japanese lines are already
     there — chinese slots after them; if not, chinese sits next to
     hebrew alone. Either is fine; match whatever main has.
3. `Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift`:
   append the `// MARK: - ChineseCalendar` 5-shape block — copy the block
   verbatim from `origin/port/chinese` (do not whole-file copy; upstream
   may have drifted).

### Step 3 — build + test gates (in order, stop on any failure)

```
swift build                                      # zero errors
swift test --filter "ChineseCalendarTests"       # 6 tests green
swift test --filter "chinese"                    # RecurrenceRule probe green
swift build -c release && swift test -c release --filter "ChineseCalendarTests"
```

### Step 4 — RELEASE benchmark re-measurement (only this machine can)

Research numbers are DEBUG (§ 11.11): 65/136/1352/554 ns + framework-bound
enumerate. Re-run BOTH sides in release and put THOSE numbers in the PR:

```
cd Benchmarks
swift package benchmark run --target InternationalizationBenchmarks \
  --benchmark-build-configuration release --filter "^ChineseCalendar-.*$"
# flip the SPM-branch chinese flag to true in Calendar_Cache.swift, re-run,
# RESTORE to false, verify with: grep "chinese_calendar_feature_enabled"
```

Expect the math-bound gaps to widen vs debug; if release shows anything
anomalous, § 11.10-11.12 has the framework-cap/scaling explanations —
check there before suspecting code. If a reviewer asks about table size,
also re-run the packing experiment in release (§ 11.19 — B's +24% is
debug-inflated; research-branch file `ChinesePackingExperiment.swift`).

### Step 5 — compliance gate (mechanical, run verbatim)

```
gh api repos/swiftlang/swift-foundation/contents/CONTRIBUTION_GUIDELINE.md --jq .content | base64 -d > /tmp/cg.md && diff /tmp/cg.md <(sed '$d' backup/CONTRIBUTION_GUIDELINE_upstream.md) || echo "GUIDELINE CHANGED — re-audit"
F="Sources/FoundationEssentials/Calendar/Calendar_Chinese.swift Sources/FoundationEssentials/Calendar/Calendar_Astronomy.swift Tests/FoundationEssentialsTests/ChineseCalendarTests.swift Tests/FoundationInternationalizationTests/ChineseRecurrenceRuleParityProbe.swift"
grep -ci "pure\|native" $F          # expect 0 per file
grep -c "print(" Tests/FoundationEssentialsTests/ChineseCalendarTests.swift Tests/FoundationInternationalizationTests/ChineseRecurrenceRuleParityProbe.swift   # expect 0
grep -cE "\)!|\]!" $F              # expect 0 (no force unwraps)
```

Also diff `_CalendarProtocol` vs the baseline memory
(reference_calendar_protocol_baseline) — if it drifted since #2028 head,
reconcile conformance before building.

### Step 6 — commit + PR

Single commit, no attribution lines (user rule), message shaped like:
`Add a Swift implementation of the Chinese calendar behind a feature flag`.
PR body: the draft below, with Step-4 release numbers substituted and the
verification narrative citing the § 11 registry (2057/2097 d0 artifact,
out-of-range intentional divergences, HKO/promulgated/Liu validation).
Standalone PR (§ 10 Q3; recommended and assumed — confirm with user only
if something forces bundling).

## ⚠ NEVER include (§ 12.2)

- `backup/` anything — esp. `duffett-smith-port/` (contingency, needs explicit
  user agreement) and `chncmp-harness/`
- `ChineseICUComparisonProbe`, `ChinesePublicAPIComparisonProbe`,
  `ChineseTableGeneratorProbe`, `ChineseInvariantProbe`,
  `ChineseQuarterParityProbe`,
  `ChineseDebugTraceProbe` (TracingCalendar + Hebrew leap-shape check —
  Hebrew fix is a PENDING USER DECISION, do not patch Calendar_Hebrew)
- `ChineseLiuReferenceProbe` — **GPL-3.0-derived data; cite results in PR
  text only**
- Chinese additions in shared CalendarDailySweep/StrictPolicy probes
- HKO CSV / any external data files

## Draft PR description (edit, don't expand)

**Add a Swift implementation of the Chinese calendar behind a feature flag**

Follows the Hebrew (#1953/#2028) and Buddhist/Japanese (#2105) pattern:
`_CalendarChinese` behind `foundation_swift_chinese_calendar_feature_enabled()`
(hard-false; zero behavior change until enabled).

Design: baked table for Chinese years 1901–2100 (200 × UInt32 = **800 B**,
packed month-length bits + leap index + new-year offset), generated from
`_CalendarICU(.chinese)` — parity by construction. Outside that range, ICU's
own chnsecal rules layer over Reingold/Dershowitz (Meeus) astronomy at UTC+8
(~400 LOC + ~3 KB coefficients). Total addition ~1,300 LOC, one file.

Verification (exhaustive suites on the research branch; distilled tests here):
- Daily parity vs ICU, 1899–2102 (74,510 days): zero divergence in the baked
  range outside two months where ICU emits impossible `day=0` fields
  (2057-09, 2097-08 — an ICU internal inconsistency, documented).
- Cross-checked against Hong Kong Observatory's official tables (1901–2100):
  matches except exactly ICU's 3 known HKO deviations (kept for parity).
- Out-of-range dates validated against the promulgated Qing record (4
  independent sources) and Yuk Tung Liu's DE441 computation for 2101–2200:
  97/100 years exact; the 3 diffs are within Liu's own stated uncertainty.
  Intentional divergences from ICU there (ICU's Duffett-Smith astronomy has
  no ΔT and errs 25–60 min; e.g. it invents leap months in 1794/1813/1889).
- Benchmarks (debug): dateComponents 3.2×, round-trip 3.9×, allocations
  18.6×, copy-on-write 37× vs ICU. `nextDate` fast path deliberately
  deferred to a follow-up PR (leap-month match semantics), as with #2105.
- REQUIRED, do not trim: the PR body must explain the week-year
  divergence, in this shape. chnsecal `handleGetExtendedYear` never
  reads YEAR_WOY, so the ICU-backed calendar computes a date's
  `yearForWeekOfYear` correctly but cannot use the field to construct
  or step dates: `dateInterval(.yearForWeekOfYear)` degenerates to nil
  and `date(byAdding:)` is a silent no-op. That asymmetry (readable,
  unusable) is a wiring gap, not a policy. We implement Foundation's
  documented week-year semantics instead: week 1 anchored by
  firstWeekday/minimumDaysInFirstWeek on the Chinese year start,
  intervals tile exactly, O(1) add. Same implementation shape as merged
  Hebrew; precedent for shipping correct semantics over an ICU quirk is
  the Japanese `.era` interval in #2105. Field values still match ICU
  exactly. Be explicit that this is the one place the flag flip changes
  observable behavior on valid input (nil to interval, no-op to
  advance), that the reversion path is two lines documented at both
  code sites, and that the weekYearSemantics guard test pins the
  chosen behavior.

## Review compliance (done — keep it that way)

Code is compliant with upstream `CONTRIBUTION_GUIDELINE.md` (mirror:
`backup/CONTRIBUTION_GUIDELINE_upstream.md`; verdict: CHINESE_PLAN § 11.15;
**re-fetch the guideline before opening the PR — upstream may have evolved
it**). Any edit you make during cherry-pick/review must preserve: unwrapped
why-only comments, no force unwraps (guard+fatalError), no prints in tests,
justified @unchecked Sendable. Prepared review responses in § 11.15:
exit-tests N/A rationale, probe parameterization offer, _CalendarUtility
consolidation as follow-up.

## Staged work gate — ✅ RESOLVED

A code review (CHINESE_PLAN § 11.21) fixed the easy findings and staged
S1-S5. **ALL RESOLVED (2026-07-19): S1 week-year (option B) DONE; S5
cleanup DONE; S3 quarter surfaces DECIDED match-ICU + IMPLEMENTED
(§ 11.23, 407-date gate green); S2 wrapping DECIDED keep Hebrew
day-only shape (§ 11.24, no code change).** S4 (month-add O(1)) remains
optional/deferred.

**Review round 2 (§ 11.25, 2026-07-19): 10 findings, zero behavioral
regressions. R1/R2/R3/R6 FIXED same day (incl. the PR-gating comment
unwrap) — the gate is clear again.** R4/R5/R7-R10 remain open as
quality/optional items per the § 11.25 table; none block the cut.

Review-question ammo: wrapping is day-only like the twice-reviewed
Calendar_Hebrew (full-contract wrapping = logged cross-calendar
follow-up); quarter surfaces mirror the ICU wrapper exactly, incl. the
leap-month containment quirk merged Hebrew also carries (Adar II).

## After opening

Watch reviews from this machine; size questions → argue absolute costs +
packing density (never "ICU already ships bigger"); update HANDOFF.md.
