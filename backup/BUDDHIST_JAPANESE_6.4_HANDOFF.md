# Buddhist + Japanese — handoff for the 6.4 machine (PR-cutting)

**Purpose:** everything the 6.4 machine needs to cut the combined Buddhist +
Japanese PR against `swiftlang/swift-foundation` `main`, now that PR #2028
(Hebrew perf + dedup) is **MERGED** (2026-07-09, merge commit `91d1fb6d`).

This doc is committed to `port/buddhist` so it travels via `git fetch`. It
consolidates notes that previously lived only in the iMac's local agent
memory. Authoritative companions in this same `backup/`:
`BUDDHIST_JAPANESE_PLAN.md` (strategy), `BENCHMARKS_PACKAGE.md` (bench matrix
+ PR-ready results), `SESSION_2026-06-11.md` (full work log),
`BUDDHIST_JAPANESE_PR_DESCRIPTION.md` (draft PR body).

## Status

- Both calendars are code-complete and parity-verified on `port/buddhist`
  (tip `bb920e2`): Buddhist Suites A/B/C + Japanese Suites A/B/C, zero
  divergences vs the ICU-backed impls. Full suite green (1448 tests / 115
  suites) as of 2026-06-11.
- PR #2028 dependencies are now on `upstream/main`, verified 2026-07-10:
  `_CalendarUtility` + `_CalendarConstants` exist; the protocol member is
  `func supportsNextDateFastPath(for components: Calendar.ComponentSet) -> Bool`.

## The work (what got built)

- `_CalendarBuddhist` (~140 LOC): Gregorian + 543, single BE era. Composition
  over `_CalendarGregorian`.
- `_CalendarJapanese` (~450 LOC): 237-era table (Taika 645 → Reiwa 2019) from
  CLDR `supplementalData.txt`. Composition over `_CalendarGregorian`.
- Feature-flag gating in `Calendar_Cache.swift` (off by default), mirroring
  the Hebrew precedent.
- `bridgeToNSCalendar()` implemented for both, and for Hebrew (replacing its
  `fatalError` stub) — via `_NSSwiftCalendar(calendar: Calendar(inner: self))`.
- Two Japanese bugs found + fixed by Suite B: (1) `convertedToGregorian`
  now defaults a year-without-era to the latest era (Reiwa) — required
  because the generic enumeration slow-path round-trips year-in-era without
  era; (2) `dateComponents(_:from:to:)` dropped a bad raw year-delta override.
- Documented ICU quirks excluded from probes: `quarter=0` at year-wrap
  (both); Japanese `dateInterval(.era).duration` (ICU projects start m/d
  into the next era's start year); Meiji encoded as 1868-09-08 to match ICU
  runtime (CLDR canonical is 1868-10-23) — TODO.
- 15 mirrored benchmarks (Gregorian/Buddhist/Japanese × 5 shapes) + 3
  pre-existing bench crashers fixed. Matrix conclusion: composition adds
  ~nothing; Buddhist ≈ Gregorian, Japanese +70–90 ns on component/roundtrip
  (era-table walk). See `BENCHMARKS_PACKAGE.md`.

## Cherry-pick plan (fresh branch off post-merge `upstream/main`)

Create `port/buddhist-japanese-main` off current `upstream/main`. Bring over
these **3 code commits** from `origin/port/buddhist` — **SKIP the two backup
commits `d6d03da` and `bb920e2`** (backup/ never goes upstream):

| Commit | Files |
|---|---|
| `bd96a7a` | `Calendar_Buddhist.swift`, `Calendar_Japanese.swift`, `Calendar_Cache.swift` (flags), Buddhist A/B/C + Japanese A probes |
| `9ccf2f3` | Japanese B/C probes, era-inference fix, bridging (⚠ also edits `Calendar_Hebrew.swift`) |
| `2cf2086` | `BenchmarkCalendar.swift`, `InternationalizationBenchmark.swift` |

Expect this to be **file-take + manual fix**, not a clean `git cherry-pick`
(the branch was built on the Hebrew v-stack; `upstream/main` has diverged).

## Four required adaptations

1. **`supportsNextDateFastPath` signature (both calendars).** On
   `port/buddhist` these still use the OLD Bool form
   (`var supportsNextDateFastPath: Bool { gregorian.supportsNextDateFastPath }`,
   Buddhist ~L60, Japanese ~L308). Change BOTH to:
   ```swift
   func supportsNextDateFastPath(for components: Calendar.ComponentSet) -> Bool {
       gregorian.supportsNextDateFastPath(for: components)
   }
   ```
2. **`Calendar_Cache.swift` — reconcile, don't overwrite.** Upstream's cache
   file evolved through the Hebrew merge + #2028. Merge only the Buddhist/
   Japanese flag functions + the `_calendarClass` routing lines into the
   current upstream file. Do NOT drop the `port/buddhist` version on top.
3. **Hebrew edit in `9ccf2f3`** is our `bridgeToNSCalendar` fatalError→real
   fix. Hebrew is already upstream — check whether `main` still has the
   `fatalError("TODO: bridgeToNSCalendar")` stub. If so, decide: fold this
   one-line improvement into this PR, or split it into its own tiny PR.
   Don't let it silently conflict.
4. **Draft PR description + benches.** Update
   `BUDDHIST_JAPANESE_PR_DESCRIPTION.md` for the new signature, and (finally)
   capture **release-mode** bench numbers on the 6.4 box — the iMac's Intel
   SIGBUS blocked release runs, so the committed numbers are debug-mode.

## Verify before pushing

- `swift build` + full `swift test` (release) on the new branch.
- Buddhist A/B/C + Japanese A/B/C parity probes — zero divergences.
- `swift package benchmark run --target InternationalizationBenchmarks` runs clean.
- Feature flags OFF by default → `Calendar(identifier: .buddhist/.japanese)`
  unchanged until enabled.

## Open decisions (defer or include)

- Meiji 1868-09-08 vs canonical 1868-10-23 (TODO in source).
- No fast-path `nextDate` for Buddhist/Japanese (Hebrew-style fast paths are
  the follow-up if enumerate perf matters).
- Japanese era-walk micro-opt (+70–90 ns; fold era resolution into one pass).
