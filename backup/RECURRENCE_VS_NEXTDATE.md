# RecurrenceRule vs nextDate — per-match cost analysis

*2026-05-03 (analysis), 2026-05-04 (resolution: gap closed for single-combination patterns; see § "Resolution" below)*

After v10 (final fast-path additions), the Hebrew port lands these two
ICU-baseline-relative results on the same logical pattern:

| API | Benchmark | per-match cost | vs ICU |
|---|---|---:|---:|
| `Calendar.enumerateDates(...)` (block) | `nextThousandThanksgivings` | ~4 ns | **~250× faster** |
| `Calendar.dates(byMatching:)` (Sequence) | `nextThousandThanksgivingsSequence` | ~4 ns | **~239× faster** |
| `Calendar.dates(byRecurrenceRule:)` | `RecurrenceRuleThanksgivings` | ~1,882 ns | 1.10× ICU (barely beats) |

All three answer the same question — "find the 4th Thursday of every November."
The first two go through `_calendar.nextDate(after:matching:direction:)`
(our fast path) and run a single Hebrew arithmetic computation per match.
The RecurrenceRule path runs **~470× more work per match** because it goes
through the general-purpose recurrence machinery.

This doc explains what that machinery does, why it costs what it costs,
and where we'd need to wire a fast-path bypass.

## Per-match call graph: RecurrenceRule

For `RecurrenceRuleThanksgivings` — `RecurrenceRule(frequency: .yearly,
months: [11], weekdays: [.nth(4, .thursday)])`:

```
DatesByRecurring.Iterator.next()                       # Calendar_Recurrence.swift:507
└─ if currentGroup is empty: nextGroup()               # line 353
    ├─ baseRecurrence.next()                          # date arithmetic: advance anchor
    ├─ _dateComponents([.s, .mi, .h, .d, .m, .lm,     # 1 primitive (decompose anchor)
    │                   .doy, .wd], from: anchor)
    ├─ Build _DateComponentCombinations               # per-call setup
    │      months=[11] daysOfMonth=[?] weekdays=[.nth(4,.thursday)]
    │      hours=[anchorHour] minutes=[anchorMinute] seconds=[anchorSecond]
    ├─ dateInterval(of: .year, for: anchor)           # 1 primitive (search range)
    ├─ _dates(startingAfter: searchStart, matching:   # THE expensive call
    │         comboCombinations, in: searchRange,
    │         matchingPolicy: ..., repeatedTimePolicy: ...)
    │   ├─ _unadjustedDates(after: ...)               # Calendar_Recurrence.swift:820
    │   │   ├─ for weekdays expansion (line 871):
    │   │   │   ├─ _weekdayComponents(for: weekdays, ...)
    │   │   │   ├─ dateAfterMatchingWeekOfYear        # primitives inside
    │   │   │   ├─ dateAfterMatchingWeekOfMonth       # primitives inside
    │   │   │   ├─ dateAfterMatchingWeekdayOrdinal    # primitives inside
    │   │   │   └─ dateAfterMatchingWeekday           # primitives inside
    │   │   └─ for months expansion (line 859):
    │   │       └─ dateAfterMatchingMonth             # primitives inside
    │   └─ _adjustedDate × N (line 542)               # DST correction per result
    ├─ _limitMonths        (line 451)                 # filter pass over `dates` array
    ├─ _limitDaysOfTheYear (line 454)
    ├─ _limitDaysOfTheMonth (line 457)
    ├─ _limitWeekdays      (line 460)
    ├─ _limitTimeComponent × 3 (lines 463–469)
    └─ store result in currentGroup
└─ pop one date from currentGroup, return
```

**Inventory:** ~7–10 primitive Calendar calls per match (each ~200–250 ns
in debug mode), plus per-call array allocations for `_DateComponentCombinations`,
the `dates` working array, and the `_unadjustedDates` return tuple, plus
RFC5545-mandated filter passes.

**Result:** ~1,800–2,500 ns/match in debug. Matches benchmark observation
(1,882 ns/match for `RecurrenceRuleThanksgivings` on Intel iMac, Swift 6.3.1).

## Per-match call graph: nextDate fast path

For the same pattern as `DateComponents(month: 11, weekday: 5, weekdayOrdinal: 4)`
through `Calendar.enumerateDates` or `Calendar.dates(byMatching:)`:

```
Iterator.next()                                       # Calendar_Enumerate.swift:331
└─ usesFastPath branch:
    ├─ _calendarNextDate(after: searchingDate, ...)   # internal proxy
    │   └─ _CalendarHebrew.nextDate(...)              # Calendar_Hebrew.swift:1053
    │       └─ nextMonthWeekdayOrdinalMatch(...)      # Calendar_Hebrew.swift:1248
    │           └─ ONE pass through:
    │               ├─ HebrewArithmetic.fixedFromHebrew (with YearData cache)
    │               ├─ wd modular math
    │               └─ utcDate(fromRataDie:secondsInDay:in:...)
    └─ store searchingDate, return matchDate
```

**Inventory:** 1 Hebrew arithmetic op (RD → wd → day-of-month → RD → Date),
0 mallocs, no DST adjustment beyond what `utcDate` does internally.

**Result:** ~4 ns/match.

## The gap

`1882 ns / 4 ns ≈ 470×.` The gap is fundamentally about **work, not
overhead**. Even if we eliminated all framework overhead in the
RecurrenceRule path, the ~10 primitive calls would still cost
~2,000 ns/match in debug mode. The only way to close the gap is to
**bypass the per-match machinery entirely** when the rule reduces to a
single fast-pathable pattern.

## What "fast-pathable" means for RecurrenceRule

A `Calendar.RecurrenceRule` is fast-pathable when it can be expressed as
ONE `DateComponents` that our `nextDate(after:matching:direction:)`
handles. For the package benchmarks:

| Benchmark | Recurrence | Equivalent DateComponents | Fast-pathable? |
|---|---|---|---|
| `RecurrenceRuleThanksgivings` | yearly, months=[11], weekdays=[.nth(4,.thursday)] | `{m:11, wd:5, wdOrd:4, time-of-anchor}` | **Yes** (single combination) |
| `RecurrenceRuleLaborDay` | yearly, months=[9], weekdays=[.nth(1,.monday)] | `{m:9, wd:2, wdOrd:1, time-of-anchor}` | **Yes** (single combination) |
| `RecurrenceRuleBikeParties` | monthly, weekdays=[.nth(1,.friday), .nth(-1,.friday)] | TWO combinations: `{wd:6, wdOrd:1}` + `{wd:6, wdOrd:-1}` | **Closed at v14** via runtime weekOfMonth translation for the negative ordinal, routing through the existing `{m, wd, weekOfMonth}` fast path |
| `RecurrenceRuleThanksgivingMeals` | yearly, months=[11], weekdays=[.nth(4,.thursday)], hours=[14, 18] | TWO combinations: `{m:11, wd:5, wdOrd:4, h:14}` + same `h:18` | **Closed at v13** via cartesian short-circuit |
| `RecurrenceRuleDailyWithTimes` | daily, weekdays=[Mon, Tue, Wed], hours=[9, 10], minutes=[0, 30] | 4 time-only combinations: `{h:9..10, mi:0/30, s:<anchor>}` (weekday is a `.limit` for daily frequency, so it's NOT in `_unadjustedDates`'s combinations — it's filtered post-pass via `_limitWeekdays`) | **Closed at v15** by adding a time-only `{h, mi, s}` fast path to Hebrew's `nextDate` so v13's existing cartesian short-circuit fires |

**Single-combination cases are the slam-dunks.** Multi-combination cases
need either (a) interleaved fast-path enumeration of N streams in
chronological order, or (b) extending the fast path to handle multi-
valued time-of-day combinations.

## Where the wire-up would go

`DatesByRecurring.Iterator` in `Calendar_Recurrence.swift:281`+. Mirror
the v9 wiring on `DatesByMatching.Iterator`:

1. **In `init`**: detect "this rule reduces to a single fast-pathable
   `DateComponents`". Translate the rule into the equivalent `DateComponents`,
   probe `calendar._calendarNextDate(after: start, matching: dc,
   direction: .forward)`. If non-nil and we're confident the translation
   is exact (no expansions/limits/RFC5545 corner cases needed),
   set `usesFastPath = true` and store the translated `DateComponents`.

2. **In `next()`**: if `usesFastPath`, call `_calendarNextDate(after:
   searchingDate, matching: storedDC, direction: .forward)` directly.
   Apply lower/upper bound checks (already in the existing `next()`).
   Bypass `nextGroup()` entirely.

3. **Detection logic** for `RecurrenceRuleThanksgivings`-shape (single-
   combination yearly/monthly with one weekday-ordinal):
   - `recurrence.frequency` is `.yearly` or `.monthly`
   - `recurrence.months.count <= 1` and `recurrence.weekdays.count == 1`
     and the weekday is `.nth(N, .day)` for `N >= 1`
   - No `daysOfTheMonth`, `daysOfTheYear`, `weeksOfYear` set
   - `hours`, `minutes`, `seconds` each have at most 1 entry
   - `interval == 1` (every N years/months not yet handled)
   - matchingPolicy and repeatedTimePolicy are at default

When all of those are true, the rule maps cleanly to a single
`DateComponents`. Anything else falls through to the existing
`nextGroup()` path.

## Expected payoff

For `RecurrenceRuleThanksgivings`, the fast-path bypass should drop
per-match cost from ~1,882 ns to ~5–10 ns (the protocol-method call
overhead is slightly higher than the bare nextDate fast path because of
the `interval` check + bound check in the iterator). That's ~200–300×
speedup on the benchmark, putting it at **~250× faster than ICU**, in
the same league as the other fast-path patterns.

`RecurrenceRuleLaborDay` should see similar speedup — it has the same
shape (single yearly weekday-ordinal pattern).

The multi-combination cases (Meals, BikeParties, DailyWithTimes) won't
benefit from this single-combination optimization. They'd need separate
work: either multi-stream interleaving or fast-path extensions for
multi-valued time-of-day fields.

## Why this hasn't been done yet

1. **Pattern detection is more involved than for the Sequence API.**
   `DatesByMatching.Iterator` only had to check "is the calendar's
   `nextDate` non-nil" — the input was already a single `DateComponents`.
   `DatesByRecurring.Iterator` needs a translation step from a
   `Calendar.RecurrenceRule` to a `DateComponents`, with a precise
   inventory of "which RecurrenceRule shapes are losslessly convertible."

2. **RFC5545 conformance.** The full RecurrenceRule path implements the
   "expansion then limit" semantics from RFC5545 and an authoritative
   ordering. Any fast-path bypass needs to be provably equivalent in
   the supported subset, not just "correct on the benchmark."

3. **Cross-calendar correctness.** This wiring lives in shared code
   (`Calendar_Recurrence.swift`), so behavior must be exactly preserved
   for non-Hebrew calendars (which fall through to the existing path
   via the `_calendarNextDate` returning nil).

The same risk profile applies as v8/v9 — the fast-path probe gates
behavior change to calendars that have a non-default `nextDate`
implementation, so other calendars are unaffected.

## Decision pending

This is the highest-leverage remaining optimization (~470× per-match for
two benchmarks, plus partial wins for two others). It's also the most
invasive change so far — touches RecurrenceRule iterator, requires a
translation layer, and needs careful validation against the full
RecurrenceRule test suite.

If pursued, it'd benefit from being a separate commit on top of the
v8–v10 stack. Likely a separate PR upstream too, framed as
"RecurrenceRule single-combination fast-path bypass," with the
translation logic and detection guards as the bulk of the change.

## References

- `Sources/FoundationEssentials/Calendar/Calendar_Recurrence.swift`
  - `DatesByRecurring.Iterator` — the iterator we'd modify (line 281+)
  - `nextGroup()` — current per-call setup (line 353)
  - `_dates(startingAfter:)` — top-level `_DateComponentCombinations` engine (line 960)
  - `_unadjustedDates(after:)` — expansion engine (line 820)
- `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift`
  - `DatesByMatching.Iterator` — the v9 hoist we'd mirror (line 296+)
- `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift`
  - `nextDate(after:matching:direction:)` — fast-path entry point (line 1053)
  - `nextMonthWeekdayOrdinalMatch` — handles the Thanksgiving pattern (line 1248)
- `backup/v9-iterator-fastpath-hoist/README.md` — prior wiring of the same shape
- `backup/BENCHMARKS_PACKAGE.md` — current benchmark numbers

## Resolution (2026-05-04, v12 snapshot)

**Outcome: gap closed for single-combination patterns. ~16× speedup
delivered, parity-verified, but at a different layer than this analysis
originally proposed.**

The original analysis proposed translating the entire `RecurrenceRule`
to a `DateComponents` and short-circuiting at the
`DatesByRecurring.Iterator.next()` level. That approach has real
complexity: handling the off-by-one when start is itself a match,
translating `_DateComponentCombinations` consistently, dealing with
multi-stream interleaving for multi-valued cases.

The actually-shipped fix lives one level deeper, at the top of
`_unadjustedDates(after:matching:)` in `Calendar_Recurrence.swift`:

```swift
fileprivate func _unadjustedDates(after startDate: Date,
                                  matching combinationComponents: _DateComponentCombinations,
                                  ...) throws -> [(Date, DateComponents)]? {
    if matchingPolicy == .nextTime && repeatedTimePolicy == .first,
       let dc = _singleCombinationDateComponents(combinationComponents),
       let fast = _calendarNextDate(after: startDate, matching: dc, direction: .forward) {
        return [(fast, dc)]
    }
    // ... existing expansion chain ...
}
```

`_singleCombinationDateComponents` is a strict-allowlist translator:
returns nil if any populated combination field has > 1 value, if the
weekday entry is `.every` or `.nth(N<=0, day)`, etc. Otherwise builds a
`DateComponents` matching the rule.

Why this lives at `_unadjustedDates` rather than at the
`DatesByRecurring.Iterator`:

1. **Smaller blast radius.** The iterator itself is unchanged; only
   `_unadjustedDates`'s entry behavior differs. All the iterator's
   bound-checking, range-filtering, end-condition handling logic is
   preserved.
2. **No off-by-one to manage.** `_unadjustedDates(after: searchInterval.start)`
   uses strictly-after semantics — same as our `_calendarNextDate`. The
   "include start if it matches" semantic at the API level is handled
   by the iterator above us, unchanged.
3. **Fall-through is automatic.** Multi-combination patterns
   (`.afterOccurrences(N)` of `[multiple months]`, `[multiple weekdays]`,
   etc.) get nil from `_singleCombinationDateComponents` and run the
   existing expansion chain — no behavior change.
4. **Other calendars unaffected.** Same gating mechanism as v8/v9/v10
   — protocol default `nextDate` returns nil → `_calendarNextDate` returns
   nil → falls through to existing path.

### Performance delivered

| Benchmark | Pre-v12 | Post-v12 | Speedup | vs ICU |
|---|---:|---:|---:|---:|
| `RecurrenceRuleThanksgivings` | 1,688 µs | **107 µs** | **15.7×** | **19× ICU** |
| `RecurrenceRuleLaborDay` | 1,637 µs | **106 µs** | **15.4×** | **15× ICU** |

Mallocs on these two collapsed by 95% (2,400+ → ~100 per 1000-iteration
benchmark), confirming the entire allocation-heavy expansion chain is
being skipped.

### Multi-combination patterns: progress at v13–v15

| Benchmark | Pre-v12 | v12 | **v13** | **v14** | **v15** | Note |
|---|---:|---:|---:|---:|---:|---|
| **`RecurrenceRuleThanksgivingMeals`** | 1,598 µs | 1,469 µs | **89 µs** | 87 µs | 88 µs | hours=[14, 18] → cartesian = 2 DCs, both fast-pathable. **15× ICU** at v15. (Closed in v13.) |
| **`RecurrenceRuleBikeParties`** | 1,430 µs | 1,438 µs | 1,463 µs | **115 µs** | 118 µs | weekdays=[.nth(1, fri), .nth(-1, fri)] → v14 added runtime weekOfMonth translation for the negative ordinal, routing through the existing `{m, wd, weekOfMonth}` fast path. **10.5× ICU** at v15. |
| **`RecurrenceRuleDailyWithTimes`** | 3,010 µs | 3,038 µs | 2,973 µs | 3,024 µs | **191 µs** | weekdays=[.every(.mon/tue/wed)], hours=[9,10], minutes=[0,30] → daily frequency makes weekday a `.limit` (not in combinations); v15 added a time-only `{h, mi, s}` fast path in Hebrew's `nextDate` so v13's existing cartesian short-circuit fires for the 4 time-only DCs. Weekday filter still runs as `_limitWeekdays` post-pass. **~8× ICU** at v15. |

`v14` (2026-05-04) closed the BikeParties gap via "Approach (a)" from
the original analysis: anchor-dependent runtime translation. The key
insight that made it safe was preserving Suite A/B raw-enumerate parity
by routing through the **existing** `{m, wd, weekOfMonth}` fast path
(which already matches ICU), not introducing any new code path that
would diverge.

Sentinel-probe gating ensures non-Hebrew calendars don't pay the cost
of the anchor-dependent calendar primitive calls — they bail on the
sentinel returning nil. ~10 ns added per `_unadjustedDates` call for
non-Hebrew calendars when negative ordinals are present.

`v15` (2026-05-04) closed the DailyWithTimes gap via the third
approach the original analysis didn't consider: **the bottleneck wasn't
in `_unadjustedDates` at all**. For daily frequency, RFC5545 makes
weekday a `.limit` (applied as `_limitWeekdays` after `_dates` returns),
so the combinations passed to `_unadjustedDates` contain no weekdays
— only hours, minutes, and seconds. v13's `_expandedDateComponents`
already produced 4 valid time-only DCs; v13's cartesian short-circuit
was firing the probe; the only blocker was Hebrew's `nextDate`
rejecting time-only DateComponents at the gate
(`!hasMonth && !hasDay && !hasWeekday → nil`). Removing that
rejection (gated on `{hour, minute, second}` all set so partial-time
DCs still fall through) and adding a `nextTimeOfDayMatch` helper let
the existing v13 short-circuit close the gap entirely. **Hebrew-only
change** (~25 LOC); no shared-code edits.

The `{wd}` fast path's full-week-advance semantic that earlier analysis
flagged as a blocker turned out not to be on the critical path —
weekday filtering happens post-`_unadjustedDates` in this case, not
inside it.

### Correctness verification

Suite C added 2026-05-04: `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift`.
13 tests, 392 rule shapes × 2,088 date comparisons against
`_CalendarICU(.hebrew)` across 8 anchor dates (leap/common years, Adar I/II,
year boundaries, Hanukkah). **0 divergences.** Covers both fast-path-fires
cases AND fall-through cases. Also exercises:
- Negative ordinals (`.nth(-1, day)`, `.nth(-2, day)`) — fall through
- Default matchingPolicy (`.nextTimePreservingSmallerComponents`) — fall through
- `interval > 1` — fall through
- `.every(weekday)` — fall through
- Adar I leap-only edge case — fall through (single-combo but weekday
  not Nth)
- Multi-month, multi-hour, multi-weekday patterns — fall through

This satisfies the parity-protocol non-negotiable for the v8–v12
optimization stack.
