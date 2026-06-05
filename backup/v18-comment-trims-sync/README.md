# `v18` — Sync from `port/hebrew-main`: comment trims + TODOs (PR #1953 review)

*2026-05-15*

**Status: tested + parity-verified, NOT committed.** Builds on v17.
Cherry-picks `origin/port/hebrew-main` commit `26c1377` "Address PR
#1953 review feedback: trim verbose comments, add TODO for shared
weekend logic" into our local Swift 6.3 working tree.

## What's in this snapshot

1 file affected: `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift`.

**No code changes. Comment-only.** -88 lines / +16 lines net.

### What was trimmed

12 sites in `Calendar_Hebrew.swift` had verbose explanatory comments
reduced to terse one-liners or replaced with `// TODO`:

1. `isDateInWeekend` — 3-line "Matches _CalendarGregorian.isDateInWeekend exactly..." comment → 1-line `// TODO: Factor out into shared utility; identical to _CalendarGregorian.isDateInWeekend.`. The TODO is reviewer-anchored on PR comment #7's de-duplication ask.
2. `utcDate(fromRataDie:...)` — 7-line doc with `skippedTimePolicy`/Bug-#7 explanation → 2-line summary.
3. `date(byAdding:)` — 8-line application-order comment → 4-line summary.
4. `nextWeekdayMatch` same-weekday branch — 4-line ICU-behavior explanation → 1 line.
5. `nextMonthWeekdayOrdinalMatch` doc — 4-line doc → 1-line "Fast path for `{month, weekday, weekdayOrdinal}` — \"Nth weekday of month\"".
6. `dateComponents(_:from:to:)` — 7-line multi-unit subtraction algorithm explanation removed entirely (the algorithm is the code).
7. `HebrewArithmetic` enum doc — 9-line provenance (biblical/civil ordering, RD convention, floor-div fixes) → 2-line summary.
8. `calendarElapsedDays` doc — 12-line dehiyot detail + ICU-divergence note → 2-line summary.
9. `calendarElapsedDays` inline "separate `if`" comment — 3 lines → 1 line.
10. `_yearDataCache` doc — 14-line cache-rationale + multi-slot-tried note → 1-line "Single-slot YearData cache."
11. `yearData(_:)` doc — 2-line "Cached `YearData(year:)`. Use for any call site..." → 1-line "Returns cached `YearData` if available, otherwise computes and caches it."
12. `hebrewFromFixed` approximate-year — 6-line floor-division rationale → 1-line "Approximate year using average Hebrew year length. Must err low."

### What's NOT in this commit (deliberately)

- **No code changes.** Every reviewer-flagged perf invariant
  (`skippedTimePolicy` not passed through to TZ at line ~614, separate-`if`
  for Betutakpat chaining at calendarElapsedDays, floor-div in
  hebrewFromFixed) is preserved by the code. The detailed rationale moves
  out of the comments and into either (a) the `SHAREABLE_APIS.md` plan
  for the eventual de-duplication PR, or (b) the bug-fix history in
  `HANDOFF.md` § "Bug-fix history" (bugs #4 and #7 are documented there).
- **Local-only research note removed**: The "A 4-slot version was
  tried (2026-05-04) and reverted" paragraph above `_yearDataCache`
  was deleted to match upstream's terse style. That history is
  preserved in `backup/BACKUPS.md` § task #35 and `SESSION_2026-05-04.md`.

## Parity

- 174/174 Calendar+RecurrenceRule tests pass (unchanged from v17).
- 58/58 Hebrew tests pass (unchanged from v17).
- Suite C `HebrewRecurrenceRuleParityProbe` 0 divergences.
- 73,414/73,414 Hebcal days still match.
- Build: clean, 31.5s (incremental).

## Drift vs `port/hebrew-main` after v18

`git diff origin/port/hebrew-main -- Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift`
shows 198 lines (was 202 at v17 — comment-trim removed 4 lines we
previously had at the c2668eb baseline). The remaining 198 lines are
**100% the v10/v11/v15 fast-path stack** (`nextMonthWeekdayWeekOfMonthMatch`,
`nextWeekdayOrdinalMatch`, `nextTimeOfDayMatch` + their gating
predicates). No comment drift.

## Performance

No expected change — comment-only edit. Not re-benchmarked.

## Reviewer context

PR #1953 round 2 comments (2026-05-13 → 2026-05-15):
- `@itingliu`: "these comments are so verbose" (on `Calendar_Hebrew.swift:617`).
- `@itingliu`: "Can we add a // TODO for these future refactoring opportunities?" (on `Calendar_Hebrew.swift:559`).

Round 2 also includes new comments on benchmark scope
(`BenchmarkCalendar.swift:562` and `:567` — measuring init vs measure
scope concerns) that are **not addressed in v18**. Those need to be
handled in a separate upstream commit on the Swift 6.4 machine, then
back-synced here as v19. Issue-level "@swift-ci please test" comment
suggests CI is being re-run on the updated branch.

## Restoration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
cp backup/v18-comment-trims-sync/Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift \
   Sources/FoundationEssentials/Calendar/
```

To roll back to v17 (pre-comment-trims) state, use
`backup/v17-frozen-pre-v18/`.
