# `v22` — `isDateInWeekend` extracted to `_CalendarUtility`

*2026-05-21*

**Status: tested + parity-verified, NOT committed.** Continuing the
SHAREABLE_APIS work. Extracts the `isDateInWeekend` body into a static
helper on `_CalendarUtility`. Also fixes the small fractional-second
divergence between Hebrew and Gregorian (Hebrew now uses the same
integer-truncation pattern as Gregorian).

## What's in this snapshot

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/CalendarUtility.swift` | Added `static func isDateInWeekend(weekday:timeInDay:weekendRange:) -> Bool` — the comparison logic (~22 lines). Added `static let defaultWeekendRange` — the world-default (region 001) weekend range. |
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | `isDateInWeekend(_:)` thinned from ~40 lines to ~10 lines. Time-in-day computation aligned to integer-truncation (was preserving fractional seconds via inline math; now uses `dateComponents([.hour, .minute, .second], ...)` like Gregorian). |
| `Sources/FoundationEssentials/Calendar/Calendar_Gregorian.swift` | `isDateInWeekend(_:weekendRange:)` thinned from ~30 lines to ~4 lines (just gets weekday + timeInDay, calls utility). `isDateInWeekend(_:)` thinned from ~10 lines to ~3 (calls into the `weekendRange` overload). |

## Bug fixed as a side benefit

Earlier session (2026-05-07) flagged that Hebrew's `isDateInWeekend`
diverged from Gregorian on two edge cases:
1. **Fractional seconds in time-in-day** — Hebrew used `Double` preserving
   sub-second precision; Gregorian truncates to integer seconds.
2. **DST instant offset disambiguation** — Hebrew used
   `rawAndDaylightSavingTimeOffset(...,.former,.former)`; Gregorian uses
   `secondsFromGMT(for:)` (via `dateComponents` internals).

v22 aligns Hebrew to Gregorian's pattern for both. Hebrew now computes
`timeInDay` via `dateComponents([.hour, .minute, .second], from: date,
in: timeZone)` + `(h*3600 + m*60 + s)` integer math — same as Gregorian.

Suite C is unchanged after this fix (the divergent cases were rare
edge conditions not in our test suite), so behavior on common inputs
stays identical to before.

## Why this approach (recap)

Same pattern as v20 (`hash`) and v21 (accessors): a static helper on
`_CalendarUtility` that takes all the inputs it needs as parameters.
Each calendar produces those inputs from its own machinery, calls the
utility, returns the result. No protocol changes, no composition
struct, no class-layout changes.

Gregorian's `isDateInWeekend(_:weekendRange:)` internal overload is
preserved as a thin wrapper because tests at `GregorianCalendarTests.swift:753-761`
call it directly with custom `WeekendRange` values.

## Parity

- 174/174 Calendar+RecurrenceRule tests pass.
- 58/58 Hebrew tests pass.
- Suite C 0 divergences.
- Verified on incremental build (no class-layout change).

## Code reduction

Approximate LOC before vs after:

| Block | Before | After |
|---|---:|---:|
| Hebrew `isDateInWeekend(_:)` | 40 | 10 |
| Gregorian `isDateInWeekend(_:)` + `isDateInWeekend(_:weekendRange:)` | 42 | 8 |
| **Hebrew + Gregorian combined** | **82** | **18** |
| `_CalendarUtility` additions | 0 | 35 |
| **Net** | **82** | **53** |

29 LOC net reduction, plus the duplicated comparison logic now exists
in exactly one place.

## Reviewer context

PR #1953 comment #7 (cont'd). `isDateInWeekend` was tagged with a
`// TODO: Factor out into shared utility; identical to
_CalendarGregorian.isDateInWeekend.` in Hebrew (from v18's PR-feedback
sync). v22 resolves that TODO.

## Restoration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
cp backup/v22-shareable-apis-isDateInWeekend/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
```

To roll back to v21: restore from `backup/v21-frozen-pre-v22/`.
