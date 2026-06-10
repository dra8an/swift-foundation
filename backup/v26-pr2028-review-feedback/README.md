# v26 — PR #2028 review feedback sync + partial-time fix + Option B probe

Back-sync of upstream PR #2028 commit `0127031` "Address PR #2028 review feedback" + two local-only corrections to handle the regressions it surfaced. Applied 2026-06-10.

## What the upstream commit changed

Five themes in `0127031`:

1. New `supportsNextDateFastPath: Bool` property on `_CalendarProtocol` (default false). Hebrew opts in. Replaces previous behavior of probing `nextDate(...)` per call.
2. `_CalendarConstants` enum moved to `Calendar` extension with `_kSecondsIn*` underscore-prefixed static lets.
3. `_expandedDateComponents` refactored from 8-deep nested loops to axis-based expansion via `WritableKeyPath`.
4. Fast-path entry conditions consolidated under one outer `if`.
5. Verbose doc comments trimmed.

## Two local corrections

### Partial-time fast path in Hebrew

The reviewer's opt-in design assumes "if you opt in, you handle every pattern." Pre-v26's per-call probe gave per-pattern fall-through; post-v26 doesn't. Hebrew's time-only fast path required all three of `{hour, minute, second}` — single-component patterns (`{hour: 18}`, `{minute: 30}`) returned nil and reached the user as nil.

Extended `nextDate` to allow partial time patterns. Added `nextTimeOfDayPeriodicMatch` for sub-day periods (period 86400 / 3600 / 60 depending on smallest specified field). `{hour}`-only → 1-day period (matches prior behavior with 0 minute / 0 second). `{minute}`-only → 1-hour period (any hour, M:00). `{second}`-only → 1-minute period (any minute, :S).

### Option B: per-call probe in framework (probe + fall-through)

The opt-in flag only resolves "does this calendar implement fast path AT ALL?" — not "does it handle THIS pattern?". For patterns Hebrew can't fast-path (year, era, weekOfYear, dayOfYear, various weekday combos), the post-v26 framework committed to the fast loop and emitted nil. Pre-v26 probed per call and fell through to the slow path.

Added a one-call probe in `Calendar.enumerateDates` and `DatesByMatching.Iterator.init`. Probe runs only when `_supportsNextDateFastPath == true`; non-opt-in calendars pay zero extra cost.

```swift
// Calendar.enumerateDates:
if matchingPolicy == .nextTime && repeatedTimePolicy == .first,
   _supportsNextDateFastPath,
   let firstMatch = _calendar.nextDate(after: start, matching: components, direction: direction) {
    // Fast loop seeded with firstMatch
}
// otherwise slow path

// DatesByMatching.Iterator.init:
self.usesFastPath = validates && matchingPolicy == .nextTime && repeatedTimePolicy == .first
    && calendar._supportsNextDateFastPath
    && calendar._calendarNextDate(after: start, matching: matchingComponents, direction: direction) != nil
```

This is a local-only divergence from PR #2028 — the shipped PR doesn't have the probe. Reintroduces ~1–5 µs per `enumerateDates` call on Hebrew. Negligible vs the work the loop does.

## Verification

`swift build && swift test --filter "Calendar|RecurrenceRule|Hebrew"`: **211/211 tests in 15 suites passed in 51.5 s.** Suite C parity probe: 0 divergences. All 14 Suite B `metonicCycle_nineteenYears` failures resolved.

## Files modified

- `Sources/FoundationEssentials/Calendar/Calendar.swift` — added probe in `enumerateDates`.
- `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` — added probe in `DatesByMatching.Iterator.init`.
- `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` — partial-time fast path + `nextTimeOfDayPeriodicMatch`.
- `Sources/FoundationEssentials/Calendar/Calendar_Protocol.swift` — `supportsNextDateFastPath` declaration + comment trims (from `0127031`).
- `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift` — axis-based expansion + entry-condition consolidation (from `0127031`).
- `Sources/FoundationEssentials/Calendar/CalendarConstants.swift` — moved to `Calendar` extension with `_kSecondsIn*` (from `0127031`).
- `Sources/FoundationEssentials/Calendar/Calendar_Gregorian.swift` — `_CalendarConstants.X` → `Calendar._kSecondsIn*` rename for the v19-v22 dedup call sites.

## Restore

```sh
for f in Calendar.swift Calendar_Enumerate.swift Calendar_Recurrence.swift Calendar_Hebrew.swift Calendar_Protocol.swift CalendarConstants.swift Calendar_Gregorian.swift; do
    cp backup/v26-pr2028-review-feedback/Sources/FoundationEssentials/Calendar/$f \
       Sources/FoundationEssentials/Calendar/$f
done
```

To revert to v25 (drop v26 entirely): `cp backup/v25-frozen-pre-v26/Sources/FoundationEssentials/Calendar/*.swift Sources/FoundationEssentials/Calendar/`.

## Upstream-vs-local diff

Two diffs from the upstream-shipped PR #2028 code:

1. `Calendar.swift` `enumerateDates`: probe condition `let firstMatch = _calendar.nextDate(...)`.
2. `Calendar_Enumerate.swift` `DatesByMatching.Iterator.init`: probe condition appended to `usesFastPath`.

If we ever want to feed these back upstream, the framing is: "opt-in flag is a necessary but not sufficient gate — per-pattern probe is the practical safety net for calendars whose fast path coverage doesn't span every component combination."

## Source

```
git show 0127031 -- Sources/FoundationEssentials/Calendar/    # upstream patch
# Local edits live only in this snapshot — see commits on port/hebrew once committed.
```
