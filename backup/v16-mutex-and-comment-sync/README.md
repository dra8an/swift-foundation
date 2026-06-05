# `v16` — Sync from `port/hebrew-main`: Mutex + comment cleanup

*2026-05-07*

**Status: tested + parity-verified, NOT committed.** Builds on v15.
Cherry-picks the source-only changes from upstream's `port/hebrew-main`
branch (commits `46725dd` Swift 6.4 update, `04783dc` icu4swift cleanup)
into our `port/hebrew` (Swift 6.3) working tree. No perf impact —
this is a sync, not an optimization.

## Strategy context

`port/hebrew-main` (on `origin`) is the upstream-bound clean shape
based on Foundation's `main` branch (Swift 6.4-targeted). `port/hebrew`
(local Swift 6.3 dev branch) is where v8–v15 perf work happens. When
the upstream PR is prepared, work flows local → main on the user's
Swift 6.4 machine. Periodic small syncs come back the other way. v16
is the first such sync.

## What's in this snapshot

Only `Calendar_Hebrew.swift` changed.

### Code changes (3)

1. **Added `internal import Synchronization`** after the platform
   imports (~line 26). Already used in 4 other files in this codebase
   (`PredicateExpression.swift`, `Locale_Notifications.swift`,
   `AttributedString+IndexValidity.swift`, `NotificationCenter.swift`).
   Module ships with our Swift 6.3.1 toolchain.

2. **`LockedState<YearData?>(initialState: nil)` → `Mutex<YearData?>(nil)`**
   (~line 1726). `Mutex` is the upstream-preferred primitive; same
   `.withLock { state in … }` API, so the two call sites in
   `HebrewArithmetic.yearData(_:)` (lines 1731, 1735 pre-edit) need
   no change. Works on Swift 6.3 — `NotificationCenter.swift:80` uses
   the same pattern with no availability guards.

3. **`var newYear` → `let newYear`** at line 894 (year+month
   `date(byAdding:)` path). Was an unused-mutability warning — the
   inner code reassigns `newCivilMonth`, not `newYear`. Line 926's
   separate `var newYear` is correct (its loop body genuinely mutates
   the variable).

### Comment cleanup (4 places)

Removed icu4swift provenance references from doc comments. Pure prose,
no code change:

- File header (line ~28): "via `icu4swift/Sources/CalendarComplex/HebrewArithmetic.swift`" removed.
- File header (line ~32): "(including Linux, which cannot compile ICU without significant effort)" removed.
- File header (line ~35): hyphen typo `eager-recalculation` → `eager recalculation`.
- `HebrewArithmetic` enum doc (line ~1593): "ported from icu4swift/..." removed.
- Floor-division fix comment (line ~1604): "(2026-04-22, from icu4swift's ±10,000-year round-trip stability test)" → just "are preserved:".
- `YearData` struct doc (line ~1740): "(This was the 2026-04-19 optimization in icu4swift: 2.9 µs → 96 ns.)" removed.

These are useful provenance for *us* but not for upstream readers, so
they were stripped on the way to the upstream-bound branch. We sync
the cleanup back here so future diffs against `port/hebrew-main` show
only meaningful code changes, not comment drift.

## Parity

- 178/178 Calendar+RecurrenceRule tests pass.
- 62/62 Hebrew tests pass.
- Suite C `HebrewRecurrenceRuleParityProbe` 0 divergences.
- 73,414/73,414 Hebcal days match.

## Performance

No change expected — `LockedState.withLock` and `Mutex.withLock` have
equivalent costs on this platform. Not benchmarked.

## Restoration

```sh
cp backup/v16-mutex-and-comment-sync/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
cp backup/v16-mutex-and-comment-sync/Tests/FoundationInternationalizationTests/*.swift \
   Tests/FoundationInternationalizationTests/
```

## What's still divergent from `port/hebrew-main`

- `port/hebrew-main` does NOT have v8–v15 (the perf stack lives only
  on `port/hebrew` until upstream PR time).
- `port/hebrew-main` does NOT have the Suite A / Suite B / Hebcal
  regression test files — those reference `_CalendarICU(.hebrew)` and
  external CSV, kept locally only.
- `port/hebrew-main` does NOT have the `backup/` directory.

The clean code-only delta (i.e. what would matter for an upstream PR)
is: v16 = `port/hebrew-main` + the v8–v15 stack.
