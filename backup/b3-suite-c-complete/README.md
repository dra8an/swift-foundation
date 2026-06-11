# b3 — Buddhist Suite C complete

Third Buddhist milestone. Adds Suite C (RecurrenceRule parity vs `_CalendarICU(.buddhist)`) on top of b1's Suite A + b2's Suite B coverage.

Applied 2026-06-11 on `port/buddhist`.

## Files

- Source files unchanged from b2.
- `Tests/FoundationInternationalizationTests/BuddhistRecurrenceRuleParityProbe.swift` (NEW — Suite C, 5 patterns).

## Suite C coverage

5 RecurrenceRule patterns × 4 anchor dates × 5–12 forward occurrences each = **140 RecurrenceRule date comparisons. Zero divergences.**

| Pattern | Frequency | Components | Per-anchor occurrences | Total |
|---|---|---|---|---|
| yearly_christmas | yearly | month=12, day=25 | 5 | 20 |
| yearly_songkran | yearly | month=4, day=13 | 5 | 20 |
| monthly_firstOfMonth | monthly | day=1 | 12 | 48 |
| weekly_mondays | weekly | weekday=.every(.monday) | 8 | 32 |
| yearly_thanksgivingShape | yearly | month=11, weekday=.nth(4, .thursday) | 5 | 20 |

Anchor dates: 2020-01-01, 2024-06-15, 2025-09-23, 2026-06-11.

## Why Suite C for Buddhist (despite composition)

Buddhist uses composition over `_CalendarGregorian` and does NOT implement `supportsNextDateFastPath = true`. RecurrenceRule expansion goes through the generic enumerate framework, which calls back into our `dateComponents` / `date(byAdding:)` / `nextDate` (all parity-clean per Suite B).

So Suite C is a **regression net**, not a primary parity check. It catches drift if anyone later:
- Adds fast paths to Buddhist or to Gregorian that misbehave.
- Modifies the composition pattern.
- Touches the generic enumerate framework in a way that affects Buddhist.

For Japanese (next), Suite C will additionally cover era-transition recurrence patterns (e.g., a yearly recurrence spanning Heisei → Reiwa).

## Verification

```sh
swift test --filter "yearly_christmas|yearly_songkran|monthly_firstOfMonth|weekly_mondays|yearly_thanksgivingShape"
```

Result: **`Test run with 5 tests in 1 suite passed after 0.152 seconds`** — all 5 patterns match ICU exactly.

## State after b3

Buddhist is **triple-suite verified**:
- Suite A (`BuddhistICUComparisonProbe`): ~1,162 protocol-level checks. 0 divergences.
- Suite B (`BuddhistPublicAPIComparisonProbe`): ~10,000 public-API checks. 0 divergences.
- Suite C (`BuddhistRecurrenceRuleParityProbe`): 140 RecurrenceRule comparisons. 0 divergences.

Ready to start Japanese on the same branch.

## Restore

```sh
cp backup/b3-suite-c-complete/Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift
cp backup/b3-suite-c-complete/Sources/FoundationEssentials/Calendar/Calendar_Cache.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
cp backup/b3-suite-c-complete/Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift \
   Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift
cp backup/b3-suite-c-complete/Tests/FoundationInternationalizationTests/BuddhistPublicAPIComparisonProbe.swift \
   Tests/FoundationInternationalizationTests/BuddhistPublicAPIComparisonProbe.swift
cp backup/b3-suite-c-complete/Tests/FoundationInternationalizationTests/BuddhistRecurrenceRuleParityProbe.swift \
   Tests/FoundationInternationalizationTests/BuddhistRecurrenceRuleParityProbe.swift
```
