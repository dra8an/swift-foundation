# `v19` — SHAREABLE_APIS Tier 0: time-unit constants extracted

*2026-05-18*

**Status: tested + parity-verified, NOT committed.** First step of the
post-PR-1953 follow-up refactor outlined in `backup/SHAREABLE_APIS.md`.
Closes Tier 0 (time-unit constants overlap between `_CalendarHebrew`
and `_CalendarGregorian`, anchored on PR #1953 reviewer comment #6).

## What's in this snapshot

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/CalendarConstants.swift` (NEW) | New file. `internal enum _CalendarConstants` exposing the 5 shared time-unit constants as static lets. |
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Removed 5 dead-code instance declarations (Hebrew never used `kSecondsIn*`; only `inf_ti` had 1 callsite). Updated 1 callsite + 1 doc-comment reference to use `_CalendarConstants.inf_ti`. |
| `Sources/FoundationEssentials/Calendar/Calendar_Gregorian.swift` | Removed 5 instance declarations. Updated 29 callsites: `kSecondsInWeek/Day/Hour/Minute` and `inf_ti` → `_CalendarConstants.X`. |

`Calendar_ICU.swift` deliberately untouched — different module
(`FoundationInternationalization`), has its own function-local
`inf_ti` declarations. Out of scope for this Tier 0 extraction.

## What's shared now

```swift
internal enum _CalendarConstants {
    static let kSecondsInWeek = 604_800
    static let kSecondsInDay = 86400
    static let kSecondsInHour = 3600
    static let kSecondsInMinute = 60

    /// Sentinel used by unbounded-range loops in date arithmetic.
    static let inf_ti: TimeInterval = 4398046511104.0
}
```

The `k` prefix is preserved from the original Gregorian declarations
for minimum diff at callsites — a modern-name rename (drop `k` prefix
per Foundation convention) can be a follow-up commit if reviewer asks.

## Parity

- 174/174 Calendar+RecurrenceRule tests pass (unchanged from v18).
- 58/58 Hebrew tests pass (unchanged).
- Suite C 0 divergences.

## Important build note: SPM incremental-build cache invalidation needed

When v19 was first applied via incremental build, tests crashed with
SIGSEGV at runtime even though the build succeeded. The root cause was
SPM's incremental compilation reusing stale `.swiftmodule` artifacts
that referenced the *old* `_CalendarGregorian` class layout (before
removing the 5 stored properties). Test code linked against the new
binary but with stale module-info expectations → crash on first call
into Gregorian.

**Resolution**: `rm -rf .build/<arch>/debug` forces a full rebuild that
regenerates all module artifacts consistently. After that, all tests
pass cleanly.

**Lesson**: when extracting or removing stored properties from
`internal` classes that other modules import, force a clean rebuild
before testing. Add this to the workflow whenever a Tier 1+ refactor
removes/restructures stored properties.

## Performance

No expected change — pure constant extraction. Not re-benchmarked.

## Reviewer context

PR #1953 comment #6 (`itingliu` on `Calendar_Hebrew.swift:39`):
> "As we mentioned previously, these constants overlap with those in
> GregorianCalendar. We should extra these out so they can be shared"

Comment #7 + #13 + #14 agreed to defer the de-duplication into a
follow-up PR. v19 is the first commit of that follow-up.

Suite A/B/C remain untouched and stay local on `port/hebrew`. v19 will
need to be re-applied to `port/hebrew-main` on the Swift 6.4 machine
as the first commit of the follow-up PR.

## Restoration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
cp backup/v19-shareable-apis-tier0-constants/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
```

To roll back to v18 (no shared file, original instance constants):
- Delete `Sources/FoundationEssentials/Calendar/CalendarConstants.swift`.
- Restore `Calendar_Hebrew.swift` and `Calendar_Gregorian.swift` from
  `backup/v18-frozen-pre-v19/`.

## Next: Tier 1 (storage/init/copy/hash) or Tier 2 (arithmetic helpers)

Per `SHAREABLE_APIS.md`. Tier 1 is the more invasive ask (reviewer
comment #7 about line 142). Tier 2 has lower risk (pure functions on
already-decomposed values). Either order works; do whichever has
clearer review story first.
