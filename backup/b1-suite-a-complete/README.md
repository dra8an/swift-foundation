# b1 — Buddhist Suite A complete

First Buddhist port milestone. Suite A (protocol-level parity vs `_CalendarICU(.buddhist)`) covers ~1,162 unique parity checks across 11 topics with zero divergences.

Branched off `port/hebrew` 2026-06-11. Branch: `port/buddhist`.

## Approach

Composition over `_CalendarGregorian`. Year offset +543 applied on extraction; -543 applied on construction. Single era (0). All other arithmetic delegated to the wrapped Gregorian.

## Files

- `Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift` (NEW, ~130 LOC).
- `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` (added feature flag + router entry).
- `Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift` (NEW, Suite A probe).

## Parity coverage at b1

| Test | Dates checked |
|---|---|
| compareFieldsSideBySide | 10 representative |
| sweepDecade_2020s | 520 weekly samples |
| yearBoundaries | 42 (Jan 1 + Dec 31 × 21 years) |
| leapYears_feb28and29 | 27 (Feb 28/last/Mar 1 × 9 years) |
| monthBoundaries | 24 (1st + last × 12 months) |
| timeOfDay_edgeCases | 6 (midnight, noon, EOD) |
| farPast | 10 (1582–1800) |
| farFuture | 10 (2150–3500) |
| weekOfYear_yearWrap | 328 (8 dates × 41 year wraps) |
| dateByAdding_largerUnits | 175 (5 dates × 5 units × 7 deltas) |
| dateComponentsFromTo | 10 (2 starts × 5 offsets) |

**Total: ~1,162 unique parity checks. Zero divergences.**

## Known ICU divergence (excluded from comparison)

`dc.quarter` — ICU's Buddhist returns 0 for dates within ±4 days of Jan 1 (year-wrap dates). Quarter is `ceil(month / 3)`, never zero — this is an ICU bug. Our implementation returns the correct quarter via Gregorian delegation. The comparison check is omitted in `compareAt` with a one-line comment noting the reason.

ICU returns the correct quarter for non-year-wrap dates. The bug surfaces only at year boundaries.

## ICU quirks our implementation matches

- `dc.era` always returns 0 (single Buddhist era).
- `dc.yearForWeekOfYear` returns the **unshifted Gregorian year** (not the BE year). Inconsistent with `dc.year` (which IS shifted), but it's ICU's documented behavior. Matched by not applying the +543 offset to `yearForWeekOfYear` in `adjustToBuddhist`.

## Verification

`swift test --filter "compareFieldsSideBySide|sweepDecade_2020s|yearBoundaries|leapYears_feb28and29|monthBoundaries|timeOfDay_edgeCases|farPast|farFuture|weekOfYear_yearWrap|dateByAdding_largerUnits|dateComponentsFromTo"`:

```
✔ Suite "Buddhist ICU Comparison Probe" passed after 2.837 seconds.
✔ Test run with 25 tests in 5 suites passed.
```

(25 tests = ~11 Buddhist tests + matching-named tests from Hebrew probe. All pass.)

## Restore

```sh
cp backup/b1-suite-a-complete/Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift
cp backup/b1-suite-a-complete/Sources/FoundationEssentials/Calendar/Calendar_Cache.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
cp backup/b1-suite-a-complete/Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift \
   Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift
```

## Versioning convention

Buddhist snapshots use prefix `b` (b1, b2, ...). Hebrew uses `v` (v1–v26). Japanese will use `j` (j1, j2, ...).

## Next

- Suite B: public-API probe via `Calendar(identifier: .buddhist)`. Requires either toggling the feature flag locally or building a Calendar(inner:) wrapper test pattern.
- Optionally expand Suite A: DST-aware time zones, locale variations, more boundary cases.
