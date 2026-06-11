# b2 — Buddhist Suite B complete

Second Buddhist milestone. Adds Suite B (public-API parity vs `_CalendarICU(.buddhist)` through the `Calendar` wrapper) on top of b1's Suite A coverage. Both PARITY_PROTOCOL suites now pass with zero divergences.

Applied 2026-06-11 on `port/buddhist`.

## Files

- `Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift` (unchanged from b1).
- `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` (unchanged from b1).
- `Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift` (unchanged from b1 — Suite A).
- `Tests/FoundationInternationalizationTests/BuddhistPublicAPIComparisonProbe.swift` (NEW — Suite B).

## Suite B coverage

8 tests, 133 unique probe dates, ~75 API surface checks per date ≈ **~10,000 individual parity checks**.

| Test | Dates | Notes |
|---|---|---|
| publicAPI_sweepAllMethods | 10 | Representative spread 1900–2050 |
| dstTimezones_americaLosAngeles | 8 | DST spring-forward + fall-back edges |
| localeVariations_firstWeekdayAndMinDays | 20 | 4 configs × 5 dates (US, ISO, Sat-start, custom) |
| yearBoundaries_commonAndLeap | 18 | Jan 1 / Dec 31 / Feb 28 across leap+common years |
| monthBoundaries_allMonths | 24 | First + last day of each month, 2025 |
| timeOfDay_edgeCases | 5 | Midnight, noon, 23:59:59 |
| farPastAndFarFuture | 6 | 1582–3000 |
| weekOfYear_yearWrap | 42 | 7 year-wraps × 6 day offsets |

## Surface methods covered (per date)

- `component()`, `dateComponents(_:from:)`, `dateComponents(in:from:)`
- `startOfDay()`, `dateInterval(of:for:)`, `range(of:in:for:)`, `ordinality(of:in:for:)`
- `date(from:)`, `date(byAdding:)` (4 forms incl. multi-field + wrapping), `date(bySetting:value:of:)`, `date(bySettingHour:minute:second:of:)`
- `compare(_:to:toGranularity:)`, `isDate(_:equalTo:toGranularity:)`, `isDate(_:inSameDayAs:)`, `date(_:matchesComponents:)`
- `isDateInWeekend()`, `dateIntervalOfWeekend()`, `nextWeekend()` (forward + backward)
- `enumerateDates()` with Christmas + Songkran patterns; `nextDate(after:matching:)`
- `dateComponents(_:from:to:)` multi-unit diff

## Same ICU quirks tracked at b1

- `dc.quarter` omitted from comparison (ICU's Buddhist returns 0 at year-wrap dates — bug).
- `dc.yearForWeekOfYear` returns unshifted Gregorian year (matches ICU's documented behavior).
- `dc.era` always 0 (single Buddhist era).

## Verification

```sh
swift test --filter "publicAPI_sweepAllMethods|dstTimezones_americaLosAngeles|localeVariations_firstWeekdayAndMinDays|yearBoundaries_commonAndLeap|monthBoundaries_allMonths|timeOfDay_edgeCases|farPastAndFarFuture|weekOfYear_yearWrap"
```

Result: **`Suite "Buddhist Calendar Public API Probe" passed after 4.244 seconds`** — 8/8 with all topics reporting "✓ zero divergences across the public Calendar API."

(The 21-test/4-suite total in the run output includes Hebrew tests with matching names — Hebrew suites also pass.)

## State after b2

Buddhist port is **functionally complete at the local research stage**. Both PARITY_PROTOCOL suites pass.

Pending (per `backup/BUDDHIST_JAPANESE_PLAN.md`):
- Wait for PR #2028 to merge.
- Create `port/buddhist-main` branch on Swift 6.4 machine off post-merge upstream/main.
- Cherry-pick the implementation + strip Suite A/B probes (which reference `_CalendarICU`).
- Open Buddhist PR upstream behind `foundation_swift_buddhist_calendar_feature_enabled()` flag.

## Restore

```sh
cp backup/b2-suite-b-complete/Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift
cp backup/b2-suite-b-complete/Sources/FoundationEssentials/Calendar/Calendar_Cache.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
cp backup/b2-suite-b-complete/Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift \
   Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift
cp backup/b2-suite-b-complete/Tests/FoundationInternationalizationTests/BuddhistPublicAPIComparisonProbe.swift \
   Tests/FoundationInternationalizationTests/BuddhistPublicAPIComparisonProbe.swift
```
