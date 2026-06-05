# v25 — Suite C upstream-ready (drop `_CalendarICU` direct reference)

Adapts `HebrewRecurrenceRuleParityProbe.swift` (Suite C, the
`Calendar.RecurrenceRule` parity probe) so it can ship upstream as part of
the combined v8–v22 PR per `backup/PR_PLAN.md`. Applied 2026-06-05 on
local `port/hebrew` (Swift 6.3) atop v24.

## What it does

**Before (v24):** Suite C constructed both calendars by directly
instantiating their internal classes:

```swift
let icuInner = _CalendarICU(
    identifier: .hebrew, timeZone: timeZone, locale: nil,
    firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
)
let oursInner = _CalendarHebrew(
    identifier: .hebrew, timeZone: timeZone, locale: nil,
    firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
)
return (Calendar(inner: icuInner), Calendar(inner: oursInner))
```

The `_CalendarICU(...)` reference made the file local-only — that internal
class is the ICU bridge and the probe was a parity oracle against it.

**After (v25):** ICU side now goes through the public Calendar API:

```swift
var icu = Calendar(identifier: .hebrew)
icu.timeZone = timeZone
let oursInner = _CalendarHebrew(
    identifier: .hebrew, timeZone: timeZone, locale: nil,
    firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
)
return (icu, Calendar(inner: oursInner))
```

This works because `Calendar(identifier: .hebrew)` routes via
`_calendarClass(identifier:)` (`Calendar_Cache.swift`):

```swift
} else if foundation_swift_hebrew_calendar_feature_enabled() && identifier == .hebrew {
    return _CalendarHebrew.self
} else {
    return _calendarICUClass()
}
```

The `foundation_swift_hebrew_calendar_feature_enabled()` flag returns
`false` outside `FOUNDATION_FRAMEWORK`, so on the SPM build the public
`Calendar(identifier: .hebrew)` resolves to `_CalendarICU`. The probe gets
its ICU oracle without any direct `_CalendarICU(...)` reference. Suite C
becomes upstream-safe.

Hebrew side continues to construct `_CalendarHebrew` directly via the
`@testable import` path — that's still required because the feature flag
also gates the public `Calendar(identifier: .hebrew)` path on Apple
platforms, so we need to bypass it to verify our implementation.

## Comment updates

The doc comment at the top of the file was updated to reflect the new
construction (mentions feature-flag-off routing). Two remaining
references to `_CalendarICU` survive in code comments — those are
descriptive references to the routing mechanism, not compilation
dependencies, so they're upstream-safe.

## Verification (2026-06-05, this iMac, Swift 6.3.1, debug)

13 Suite C tests, run via `swift test --filter
"yearly_singleMonth_nthWeekday|monthly_nthWeekday|yearly_multipleHours|monthly_multipleNthWeekdays|daily_withTimes|negativeOrdinals|multipleMonths|adarI_leapOnly|timeOfDay|defaultMatchingPolicy|intervalGreaterThanOne|dayOfMonth|everyWeekday"`:

- All 13 tests pass.
- Headline counts (sample): 288 rules × 1,440 comparisons in
  `yearly_singleMonth_nthWeekday`; 36 × 180 in `monthly_nthWeekday`;
  16 × 80 in `negativeOrdinals`; 12 × 60 in `timeOfDay`. **0 divergences
  across all 13 tests.**
- Probe suite runtime: 1.8 s (incremental build 62 s, test 1.8 s).

## Why the API switch preserves parity

The previous construction path was:

```swift
_CalendarICU(identifier: .hebrew, timeZone: tz, locale: nil, firstWeekday: nil, ...)
  → Calendar(inner: icuInner)
```

The new path is:

```swift
Calendar(identifier: .hebrew)
  → CalendarCache.fixed[.hebrew] → _calendarClass(.hebrew) → _calendarICUClass()
  → _CalendarICU.self → _CalendarICU(identifier: .hebrew, timeZone: TimeZone.default, ...)
  → then `.timeZone = tz` overrides
```

Both wind up at a `_CalendarICU` with `identifier: .hebrew` and the
specified `timeZone`. The remaining init parameters (locale, firstWeekday,
minimumDaysInFirstWeek, gregorianStartDate) default to `nil` in both
paths (the public `Calendar(identifier:)` initializer fills these with
the same nil defaults). So the underlying calendar instances are
configuration-equivalent — confirmed by the 0-divergence result across
2,088 comparisons.

## Files modified

- `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift`:
  - Doc comment at lines 22–25 updated to describe the new routing.
  - `makePair` static method (lines ~45–58) refactored.

## Files captured

- `HebrewRecurrenceRuleParityProbe.swift` (after-v25 state)

## Restore

```sh
cp backup/v25-suite-c-upstream-ready/Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift \
   Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift
```

To revert to v24 (drop v25 entirely):

```sh
cp backup/v24-frozen-pre-v25/Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift \
   Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift
```

## Source

This is local-authored — no upstream equivalent. The Hebrew port has
always carried Suite C as a local-only test on `port/hebrew`. v25 just
prepares it to ship upstream as part of the combined PR.

## What v25 unblocks

Per `backup/PR_PLAN.md`, Suite C now ships in the combined PR as a
regression-test cover for the fast-path optimizations (Commit 2 in the
3-commit shape). Without v25, the PR would have to either drop Suite C
(losing critical regression coverage) or gate it behind a Foundation
internal debug flag.
