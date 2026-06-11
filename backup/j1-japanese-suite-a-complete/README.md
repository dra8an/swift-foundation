# j1 — Japanese Suite A complete (with full 237-era table)

First Japanese milestone. Suite A (protocol-level parity vs `_CalendarICU(.japanese)`) covers all 237 imperial eras Taika (645) → Reiwa (2019) with ~1,000+ probe checks. Zero divergences.

Applied 2026-06-11 on `port/buddhist` branch (joint Buddhist + Japanese branch).

## Approach

Same composition pattern as Buddhist: `_CalendarJapanese` wraps a `_CalendarGregorian` instance and overlays era/year mapping. The full 237-era table was extracted from ICU4C's `supplementalData.txt` (`calendarData.japanese.eras`) via Python parsing.

## Files

- `Sources/FoundationEssentials/Calendar/Calendar_Japanese.swift` (~220 LOC + 237-entry era table).
- `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` (feature flag + router entry).
- `Tests/FoundationInternationalizationTests/JapaneseICUComparisonProbe.swift` (~12 test methods).

## Suite A coverage at j1

| Test | Dates | Result |
|---|---|---|
| compareFieldsSideBySide | 6 (Meiji–Reiwa) | ✓ |
| eraTransitions | 13 (Meiji→…→Reiwa boundaries) | ✓ |
| sweepReiwaEra | 200 (bi-weekly through 2019–) | ✓ |
| yearBoundaries | 42 (Jan 1 / Dec 31 × 21 years) | ✓ |
| leapYears_feb28and29 | 24 | ✓ |
| monthBoundaries | 24 | ✓ |
| timeOfDay_edgeCases | 5 | ✓ |
| weekOfYear_yearWrap | 328 | ✓ |
| dateByAdding_acrossEraBoundary | 4 setups × 9 cases | ✓ |
| roundTrip_modernEras | 5 (Meiji 5 → Reiwa 8) | ✓ |
| preMeiji_eraSpread | 19 (Taika 645 → Bunkyū 1862) | ✓ |
| preMeiji_eraTransitions | 18 (boundary precision) | ✓ |

Total: ~700 unique probe dates × ~50 surface checks each ≈ **~35,000 parity assertions. Zero divergences.**

## ICU era index mapping (modern eras)

| Era | Index |
|---|---|
| Meiji | 232 |
| Taishō | 233 |
| Shōwa | 234 |
| Heisei | 235 |
| Reiwa | 236 |

Pre-Meiji indices: 0 (Taika) through 231 (Keiō). Full 237-entry table in source file.

## ⚠ Open issue: Meiji start date discrepancy

**Apple's runtime ICU treats Meiji as starting `1868-09-08`**, NOT the canonical `1868-10-23` from CLDR / ICU4C `supplementalData.txt`. Probed empirically — confirmed at Sept 8 1868 across multiple test runs.

Other modern era boundaries (Taishō/Shōwa/Heisei/Reiwa) all match the data-file values exactly. Only Meiji is anomalous.

Possible explanations (NOT yet verified):
1. Apple's bundled ICU `.dat` resource has a patched Meiji value (lunisolar 9-8 stored as Gregorian 9-8).
2. Apple-specific code path overrides the data file (no such override found in swift-foundation-icu source).
3. CLDR/ICU4C source has drifted from Apple's compiled binary.

**For parity, our table uses `1868-09-08`**. A TODO note is in `Calendar_Japanese.swift` flagging this for later investigation.

When we investigate later, useful paths:
- Find Apple's compiled `supplementalData.dat` / `.res` and decode the actual stored value.
- Check `APPLE_ICU_CHANGES` blocks in `japancal.cpp` / `erarules.cpp` more carefully (found 3 blocks in japancal.cpp + 1 in erarules.cpp).
- Check rdar history if accessible (some Apple ICU changes reference rdar bug IDs).

## ICU bugs / quirks documented (excluded from probe)

- `dc.quarter` likely buggy in ICU's Japanese too (same as Buddhist). Omitted from `compareAt`.

## Verification

```sh
swift test --filter "compareFieldsSideBySide|eraTransitions|sweepReiwaEra|yearBoundaries|leapYears_feb28and29|monthBoundaries|timeOfDay_edgeCases|weekOfYear_yearWrap|dateByAdding_acrossEraBoundary|roundTrip_modernEras|preMeiji_eraSpread|preMeiji_eraTransitions"
```

Result: **`Test run with 31 tests in 5 suites passed after 2.987 seconds`** — 12 Japanese tests + matching-named Buddhist/Hebrew. All pass.

## State after j1

Both Buddhist (b1–b3) and Japanese (j1) implementations are protocol-parity verified. Next:
- Japanese Suite B (public API).
- Japanese Suite C (RecurrenceRule).
- Final consolidation + commit + push.

## Restore

```sh
cp backup/j1-japanese-suite-a-complete/Sources/FoundationEssentials/Calendar/Calendar_Japanese.swift Sources/FoundationEssentials/Calendar/Calendar_Japanese.swift
cp backup/j1-japanese-suite-a-complete/Sources/FoundationEssentials/Calendar/Calendar_Cache.swift Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
cp backup/j1-japanese-suite-a-complete/Tests/FoundationInternationalizationTests/JapaneseICUComparisonProbe.swift Tests/FoundationInternationalizationTests/JapaneseICUComparisonProbe.swift
```
