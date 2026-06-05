# PR plan — single PR for v8–v22 (fast paths + SHAREABLE_APIS)

Last update: 2026-06-05.

This doc supersedes the relevant parts of `MAIN_MERGE.md` (which assumed
the v8–v15 perf stack and the v19–v22 SHAREABLE_APIS dedup would land as
two separate PRs). Decision 2026-06-05: **one combined PR**.

## Scope

One PR off `port/hebrew-main` (== `upstream/main`), containing:

- v8–v15: fast-path infrastructure + Hebrew implementation.
- v19–v22: SHAREABLE_APIS dedup (constants, hash default, accessor
  helpers, `isDateInWeekend`).

What this PR does NOT contain:

- v16–v18 sync layers (already in `upstream/main` via the squash of
  PR #1953 + reapply #2017).
- v23–v24 sync layers (likewise — they were already on
  `port/hebrew-main` pre-squash via `f94c6ac` + `b1b8fdf`).
- Hebcal regression CSV (stays local — task #11 resolved as "drop from
  PR", see below).
- Suite A/B parity probes (`HebrewICUComparisonProbe.swift`,
  `HebrewPublicAPIComparisonProbe.swift`) — stay local, reference
  `_CalendarICU`.
- Local research benches (`EnumerateMicroProfile.swift`, etc.).

## Branch + base

```
upstream/main ─── port/hebrew-main ─── port/hebrew-perf-and-dedup (NEW, PR base)
```

- `port/hebrew-main` was synced to `upstream/main` on 2026-06-04 (both
  at `5829fa1` as of session start 2026-06-05).
- `port/hebrew-perf-and-dedup` is the PR branch — created fresh from
  `port/hebrew-main` on the Swift 6.4 machine.
- Local `port/hebrew` (Swift 6.3) stays as the experimentation branch.

## Commit shape — three commits in this order

### Commit 1 — Shared-code fast-path infrastructure

**Files**:

- `Sources/FoundationEssentials/Calendar/Calendar.swift` — `_calendarNextDate` proxy (v8).
- `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` — `_enumerateDatesStep` fast-path wiring (v8) + `DatesByMatching.Iterator` hoist (v9) + helper hijacks (v11/v12).
- `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` — `_unadjustedDates` single-combination short-circuit (v12), multi-combination cartesian short-circuit (v13), negative-ordinal weekOfMonth translation (v14).
- `Sources/FoundationEssentials/Calendar/Calendar_Protocol.swift` — declare optional `nextDate(after:matching:direction:)` protocol method (default returns `nil`).

**Properties**:

- Hebrew-agnostic. No `_CalendarHebrew` references; the dispatch hook
  delegates to whichever conforming calendar implements the optional
  method.
- Every non-Hebrew calendar (Gregorian, ISO, ICU-backed everything else)
  falls through unchanged because the default impl returns nil.
- `backup/SHARED_CODE_SAFETY.md` is the cover note — per-touchpoint
  inventory + residual overhead quantification (<100 ns per
  guarded call) + reviewer checklist.

**Source snapshots**:

- `backup/v8-enumeratedatesstep-fastpath/` — Calendar.swift +
  Calendar_Enumerate.swift edits.
- `backup/v9-iterator-fastpath-hoist/` — Calendar_Enumerate.swift edits.
- `backup/v11-helper-hijack/` — Calendar_Enumerate.swift edits.
- `backup/v12-recurrence-shortcircuit-and-parity-probe/` —
  Calendar_Recurrence.swift edits.
- `backup/v13-multicombo-cartesian-shortcircuit/` —
  Calendar_Recurrence.swift edits.
- `backup/v14-optionb-negative-ordinal-translation/` —
  Calendar_Recurrence.swift edits.

**Suggested commit message**:

> Add fast-path protocol hook + shared-code wiring for recurrence
> short-circuits
>
> Adds `_CalendarProtocol.nextDate(after:matching:direction:)` as an
> optional fast-path hook (default returns nil). Calendars that
> implement it can short-circuit
> `Calendar.enumerateDates`/`Calendar.RecurrenceRule` expansion paths
> for specific component patterns. Non-implementing calendars are
> unchanged.
>
> See SHARED_CODE_SAFETY.md (in the project docs) for the
> per-touchpoint safety analysis.

### Commit 2 — Hebrew-specific fast paths

**Files**:

- `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` only.

**Content**:

- v10 — `{month, weekday, weekOfMonth}` fast path.
- v11 — helper-level hijacks for `dateAfterMatchingWeekOfMonth` /
  `dateAfterMatchingWeekdayOrdinal`.
- v12–v14 — RecurrenceRule short-circuit implementations.
- v15 — time-only `{h, mi, s}` fast path.

**Properties**:

- Implements the protocol method added by Commit 1.
- Hebrew-only — touches no shared code.
- 8 of 9 calendar benchmarks ≥8× ICU after this commit lands.

**Source snapshot**: `backup/v22-shareable-apis-isDateInWeekend/Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` minus the v19–v22 dedup deltas. (Practically: use the v18 snapshot's Calendar_Hebrew.swift, which captures the post-v15 state before dedup.)

Wait — the cleanest is: extract Calendar_Hebrew.swift from
`backup/v18-comment-trims-sync/Sources/.../Calendar_Hebrew.swift` and use
the v8–v15 deltas as a single diff from upstream's Hebrew. We need to
verify v18 minus v16+v17+v18 sync-layer comments = post-v15 state.
Confirm during pre-PR work.

**Suggested commit message**:

> Implement Hebrew fast paths for nextDate and RecurrenceRule
>
> Implements the `_CalendarProtocol.nextDate(after:matching:direction:)`
> hook (added previously) for `_CalendarHebrew`. Covers month-day,
> month-weekday-ordinal, month-weekday-weekOfMonth, and time-only
> patterns. Adds RecurrenceRule single-combination, multi-combination,
> and negative-ordinal short-circuits with weekOfMonth translation.
>
> Benchmarks (debug, vs ICU-backed Hebrew baseline):
> - nextThousandThanksgivings: ~250× faster
> - nextThousandThursdaysInTheFourthWeekOfNovember: ~107× faster
> - RecurrenceRuleThanksgivings: 19× faster
> - RecurrenceRuleDailyWithTimes: ~8× faster

### Commit 3 — SHAREABLE_APIS de-duplication

**Files**:

- `Sources/FoundationEssentials/Calendar/CalendarConstants.swift` (NEW).
- `Sources/FoundationEssentials/Calendar/CalendarUtility.swift` (NEW).
- `Sources/FoundationEssentials/Calendar/Calendar_Protocol.swift`
  (modified — `hash(into:)` default impl).
- `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift`
  (modified — thinned to use shared helpers).
- `Sources/FoundationEssentials/Calendar/Calendar_Gregorian.swift`
  (modified — thinned to use shared helpers).

**Content**:

- v19 — Time-unit constants extracted to `_CalendarConstants` enum.
- v20 — `hash(into:)` default impl in `_CalendarProtocol` extension.
- v21 — Accessor helpers via `_CalendarUtility`: `firstWeekday`,
  `minimumDaysInFirstWeek`, `copy()`.
- v22 — `isDateInWeekend` body extracted to `_CalendarUtility`. Side
  benefit: fixes Hebrew↔Gregorian fractional-second divergence.

**Properties**:

- Addresses PR #1953 review comments #6 (constants) and #7 (duplicate
  Hebrew↔Gregorian boilerplate).
- Net LOC: -29 across the touched files (v22 closeout).

**Source snapshots**:

- `backup/v19-shareable-apis-tier0-constants/`
- `backup/v20-shareable-apis-tier1a-hash-default/`
- `backup/v21-shareable-apis-accessor-helpers/`
- `backup/v22-shareable-apis-isDateInWeekend/`

**Suggested commit message**:

> Extract shared calendar helpers into _CalendarConstants + _CalendarUtility
>
> Addresses PR #1953 review feedback (comments #6 + #7). Pulls
> duplicated time-unit constants and `firstWeekday` /
> `minimumDaysInFirstWeek` / `copy()` / `isDateInWeekend` /
> `hash(into:)` patterns out of `_CalendarGregorian` and
> `_CalendarHebrew` and into shared static helpers.
>
> Net LOC across the touched files: ~-28 (basically a wash). The
> structural value comes from establishing a single source of truth
> for the shared logic. Future calendar ports (Islamic / Persian /
> Coptic / Japanese / etc.) will skip ~85 lines of boilerplate each
> by calling into the shared helpers — at 4+ future conformers that
> compounds to several hundred lines avoided, plus a real
> correctness benefit (no per-port divergence drift).
>
> Side effect: `_CalendarHebrew.isDateInWeekend` now matches
> `_CalendarGregorian.isDateInWeekend` exactly (resolves a
> fractional-second divergence the extraction surfaced).

**PR-description framing for Commit 3** (decided 2026-06-05): lead with
the future-ports angle — "foundation for upcoming calendar ports" — not
the immediate LOC. Reviewers will care about the duplication ergonomics
the original review comment flagged, and about the structural pattern
for future ports. The LOC number is a footnote.

## Test coverage going upstream

| Test file | Goes upstream? | Status |
|---|---|---|
| `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift` | Already there | Pre-existing (v24 trimmed to 13 tests) |
| `Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift` | Already there | v24, in upstream |
| `Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift` | Already there | v17 parameterized, in upstream |
| `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift` | **YES — adapted** | Suite C, needs `_CalendarICU(.hebrew)` ref replaced before sending |
| `Tests/FoundationEssentialsTests/HebrewRegressionTests.swift` | NO | Hebcal CSV — stays local |
| `Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift` | NO | Suite A — references `_CalendarICU` |
| `Tests/FoundationInternationalizationTests/HebrewPublicAPIComparisonProbe.swift` | NO | Suite B — references `_CalendarICU` |
| `Tests/FoundationInternationalizationTests/EnumerateMicroProfile.swift` + research benches | NO | Local research only |
| `Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift` | Already there | v17 — 5 Hebrew benchmarks. May add fast-path-specific benchmarks; assess during pre-PR |

### Suite C upstream adaptation

`HebrewRecurrenceRuleParityProbe.swift` line ~46 currently constructs
`_CalendarICU(.hebrew)` directly. To ship upstream:

1. Replace `_CalendarICU(.hebrew)` reference with
   `Calendar(identifier: .hebrew)`. With the v23 feature flag OFF (the
   default outside `FOUNDATION_FRAMEWORK`), `Calendar(identifier: .hebrew)`
   routes to `_calendarICUClass()` → `_CalendarICU(.hebrew)`. So no
   internal-class reference is needed in the test source.
2. Construct `_CalendarHebrew` directly via the `@testable import` path
   that's already in the file.
3. Compare the two — same parity logic as today.
4. Verify 0 divergences still hold after the adaptation.

Snapshot as v25 once done.

## Pre-PR blockers — resolution

| # | Blocker | Resolution in this plan |
|---|---|---|
| 11 | Hebcal 1.7 MB CSV fixture | **Drop from PR.** Suite C + DST parity in upstream is sufficient. Hebcal stays local belt-and-suspenders against an external reference. |
| 37 | Commit shape for v8–v22 | **Resolved**: 3 commits as above. |
| Suite C | References `_CalendarICU(.hebrew)` | **Adapt** to use `Calendar(identifier: .hebrew)` (routes to ICU via feature-flag-off). |
| 46 | Round-2 benchmark scope | Already moot per HANDOFF; resolved by upstream `f94c6ac`. |

## Pre-PR work (on this iMac, Swift 6.3)

These are safe local actions, no toolchain risk.

1. **Adapt Suite C** — edit `HebrewRecurrenceRuleParityProbe.swift` to drop the `_CalendarICU` reference per the section above. Verify 0 divergences. Snapshot as v25.
2. **Audit BenchmarkCalendar.swift** — does it already include the v8–v15 fast-path benchmarks (Thanksgivings, BikeParties, DailyWithTimes, etc.)? If not, decide whether to add them to the PR. The earlier benchmark scope debate (task #46) ended with the feature flag absorbing the concern — re-evaluate whether the perf benchmarks belong in the PR for evidence of the fast-path wins.
3. **Generate three commit-shape patches** — extract clean diffs for Commits 1, 2, 3 from the `backup/v*-*/` snapshots. Verify each applies cleanly atop upstream's `Calendar_Hebrew.swift` (which is `b1b8fdf`-state, = `port/hebrew-main`). Specifically:
   - Commit 1 patch — `Calendar.swift` + `Calendar_Enumerate.swift` + `Calendar_Recurrence.swift` + `Calendar_Protocol.swift` deltas.
   - Commit 2 patch — `Calendar_Hebrew.swift` v10/v11/v12/v13/v14/v15 deltas (fast-path implementations only, not the dedup thinning).
   - Commit 3 patch — `CalendarConstants.swift` + `CalendarUtility.swift` + `Calendar_Protocol.swift` (hash) + `Calendar_Hebrew.swift` + `Calendar_Gregorian.swift` dedup deltas.
4. **Cross-check Mutex/LockedState** — the PR builds against Swift 6.4 so all locks should be `Mutex`. Confirm none of our patches reintroduce `LockedState` (we use it locally on Swift 6.3 but upstream uses Mutex).
5. **Optional dry-run on the Swift 6.4 machine** — apply each patch, build + test, before opening the PR. This is the equivalent of CI but faster to iterate on.

## PR-branch creation (Swift 6.4 machine)

```sh
# Pull latest port/hebrew-main (== upstream/main)
git fetch origin
git fetch upstream

# Branch off
git checkout -b port/hebrew-perf-and-dedup port/hebrew-main

# Apply commit 1 patch (shared-code fast-path infra)
git apply /path/to/commit1-shared-fastpath.patch
swift test --filter "Calendar|RecurrenceRule"   # baseline still passes
git add -A
git commit -F /path/to/commit1-message.txt

# Apply commit 2 patch (Hebrew fast paths)
git apply /path/to/commit2-hebrew-fastpath.patch
swift test --filter "Hebrew|RecurrenceRule"
git add -A
git commit -F /path/to/commit2-message.txt

# Apply commit 3 patch (SHAREABLE_APIS dedup)
git apply /path/to/commit3-shareable-apis.patch
swift test --filter "Calendar|Hebrew"
git add -A
git commit -F /path/to/commit3-message.txt

# Push + open PR
git push -u origin port/hebrew-perf-and-dedup
gh pr create --base main --repo swiftlang/swift-foundation \
  --title "Hebrew calendar fast paths + shared helper extraction" \
  --body-file /path/to/pr-body.md
```

PR body should reference:

- `SHARED_CODE_SAFETY.md` as cover note for Commit 1.
- `SHAREABLE_APIS.md` as design context for Commit 3.
- Resolution of PR #1953 review comments #6 + #7 by Commit 3.
- Benchmarks from BenchmarkCalendar.swift (running `swift package benchmark run --filter "...Hebrew..."`).

## Anticipated review feedback

Per PR #1953 review experience:

- **Comment scope-creep risk** — three commits in one PR may attract
  "split this" feedback. Counter-argument: the three commits are
  logically related (the dedup is the same surface area the fast paths
  touch), and split PRs would have inter-PR dependencies. If reviewers
  push hard, we can split into two follow-up PRs as originally planned.
- **Public API audit** — Commit 1's protocol method may be flagged as a
  potential public API surface. It's declared on the internal
  `_CalendarProtocol` so it should be fine, but mention this in the PR
  body proactively.
- **Test coverage on non-Hebrew** — reviewers may ask whether `_CalendarGregorian`
  needs to implement the fast-path hook too. Answer: not in this PR;
  the protocol method's nil default leaves Gregorian unchanged. Future
  PR could add Gregorian fast paths.

## Ongoing maintenance after PR opens

- **Back-sync upstream changes that touch Hebrew/Calendar files.** Same
  pattern as v16–v24. Detect via `git log <last-sync>..upstream/main --
  Sources/FoundationEssentials/Calendar/`.
- **Address review feedback** as additional commits on
  `port/hebrew-perf-and-dedup`. After merge, back-sync the merged
  commits to local `port/hebrew` (the same way we did v17 and v18).
- **Continue local perf experimentation** on `port/hebrew` independently.
  v25+ slots remain available for new optimizations.

## Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-06-05 | One PR (vs the two PRs originally planned in `MAIN_MERGE.md`) | User preference. Reduces total PR overhead. Reviewers can still ask for a split if they want. |
| 2026-06-05 | Drop Hebcal regression test from PR | Suite C + DST parity coverage is sufficient. CSV-shipping size concern. |
| 2026-06-05 | Suite C ships, adapted | Critical regression-test coverage for the fast paths. Feature-flag-off makes the `_CalendarICU` reference replaceable. |
| 2026-06-05 | Branch name: `port/hebrew-perf-and-dedup` | Self-descriptive. Distinct from `port/hebrew` (Swift 6.3 research) and `port/hebrew-main` (mirror). |
| 2026-06-05 | Commit order: shared-code → Hebrew → SHAREABLE_APIS | Matches development order. Each commit testable in isolation. |

## Open questions for the user

1. **Branch name**: `port/hebrew-perf-and-dedup` OK, or different?
2. **Hebcal fixture**: confirm dropping from PR (local-only stays).
3. **Suite C adaptation**: confirm proceeding with the
   `Calendar(identifier: .hebrew)` route (vs `#if DEBUG_HEBREW_PARITY`
   alternative).
4. **Benchmarks**: do we want to add fast-path-specific benchmarks
   beyond what's already in `BenchmarkCalendar.swift` v17? E.g.
   `nextThousandThanksgivings` was already added at v17 — verify what
   else exists there.
