# Hebrew calendar: ICU parity requirements — NON-NEGOTIABLE

**Status:** Authoritative. Any behavior difference between `_CalendarHebrew`
and `_CalendarICU(.hebrew)` that is NOT explicitly marked "accepted
divergence" in this file is a **bug** and must be fixed before the port can
be considered complete.

**Reason:** Foundation's `.hebrew` calendar has years of production exposure
through `_CalendarICU`. Apps written against its observable behavior must
continue working unchanged. Any regression — even on obscure components like
`.yearForWeekOfYear` — is a user-facing behavior change and unacceptable
for a drop-in replacement.

**Probe protocol:** The reference behavior below is captured by running
`Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift`.
Re-run this probe any time `_CalendarHebrew` changes to verify no parity
regression has crept in. The probe instantiates both classes directly and
is pass-only (diagnostic — inspect stdout for the comparison table).

Reference probe date: **2016-09-23 21:35:55 UTC** (= 20 Elul 5776 AM, a leap year).
All probes use `timeZone: .gmt` unless otherwise noted.

## Parity status at 2026-04-28 — 🎉 **ALL TASKS COMPLETE (tasks #12–20)**

**Suite A (protocol probe):** ~300 dates across 13 edge-case topics = **0 divergences**.
**Suite B (public-API probe):** 10 hand-picked dates + DST sweep (17 wall-clocks) + locale sweep (6 configs × 10 dates) = **0 divergences**.
**Suite C (RecurrenceRule parity probe — 2026-05-04, last verified at v15):** 13 tests, 392 rule shapes × 2,088 date comparisons across 8 anchor dates = **0 divergences**. Required after the v8–v15 perf optimization stack introduced fast-path short-circuits and helper hijacks in `_unadjustedDates` / `dateAfterMatchingX` (Calendar_Recurrence.swift / Calendar_Enumerate.swift), plus the v14 negative-ordinal runtime weekOfMonth translation and the v15 time-only `{h, mi, s}` fast path in Hebrew's `nextDate` (DailyWithTimes shape). The `yearly_multipleHours` test verifies the v13 multi-combination cartesian short-circuit (ThanksgivingMeals shape); the `monthly_multipleNthWeekdays` test verifies the v14 negative-ordinal translation (BikeParties shape); daily-frequency rules with `.every(weekday)` filters and multi-time expansions exercise the v15 time-only fast path through the same probe. Covers: single-combination patterns, multi-combination patterns, negative ordinals (now translated rather than rejected), default matchingPolicy, interval > 1, Adar I leap-only, day-of-month, `.every(weekday)`. See `Tests/FoundationInternationalizationTests/HebrewRecurrenceRuleParityProbe.swift`.
**DST policy parity:** 16 wall-clocks × 4 policy combos = 64 cases vs `_CalendarGregorian` = **0 divergences**.
**Full Foundation test suite on main:** 1510 tests, 123 suites = **0 failures** (verified 2026-04-28 on Apple Silicon, Swift 6.4-dev main-snapshot).

Suite A topics (13):
- Year-length variants (all 6 regimes × 3 sample points = 18 dates)
- Cheshvan/Kislev length boundaries (30 dates)
- Full 19-year Metonic cycle (19 dates)
- Rosh Hashanah postponement — all 4 allowed weekdays (12 dates)
- Adar I↔II transition (3 leap years × 7 boundary days = 21 dates)
- Year boundaries — common and leap (10 transitions × 4 days = 40 dates)
- Month boundaries — unusual lengths (4 years × valid 29/30 days = 75 dates)
- Major holidays — common and leap (3+3 years × ~9 holidays = 48 dates)
- Time-of-day edge cases (13 dates)
- DST timezones — America/Los_Angeles spring-forward & fall-back (17 dates)
- Far past and far future — 600–2300 CE (9 dates)
- Locale variations — 6 firstWeekday/minDays configs × 10 dates (60 dates)
- Week-of-year wrap (6 transitions × 15 days = 90 dates)

Original 10 hand-picked edge dates (still exercised in `sweepMultipleDates` and `publicAPI_sweepAllMethods`):
- Leap-year mid (Elul 20, 5776) — reference date below
- Common-year mid (Adar 1, 5785)
- Leap year first day (Tishri 1, 5776)
- Common year first day (Tishri 1, 5786)
- Leap year Adar I (Adar I 1, 5776)
- Leap year Adar II (Adar II 1, 5776)
- Cheshvan 30, 5776 (long Marheshvan)
- Kislev 25, 5777 (Hanukkah common year)
- Passover 15 Nisan, 5776
- mid-5778 common year

### `dateComponents([.all], from: d)` query — ✅ **TASK #12 COMPLETE**

| Field | ICU | Current ours | Status |
|---|---:|---:|---:|
| `.era` | 0 | 0 | ✅ matches (note: ICU uses 0-based; was ours=1, fixed) |
| `.year` | 5776 | 5776 | ✅ matches |
| `.month` | 13 | 13 | ✅ matches |
| `.day` | 20 | 20 | ✅ matches |
| `.hour / .minute / .second` | 21 / 35 / 55 | 21 / 35 / 55 | ✅ matches |
| `.weekday` | 6 | 6 | ✅ matches |
| `.weekdayOrdinal` | 3 | 3 | ✅ matches |
| `.quarter` | 0 | 0 | ✅ matches (ICU sentinel) |
| `.weekOfMonth` | 3 | 3 | ✅ matches |
| `.weekOfYear` | 54 | 54 | ✅ matches |
| `.yearForWeekOfYear` | 5776 | 5776 | ✅ matches |
| `.dayOfYear` | 376 | 376 | ✅ matches |
| `.isLeapMonth` | false | false | ✅ matches |

### `dateInterval(of: X, for: d)` — duration in seconds — ✅ **TASK #13 COMPLETE**

| Component | ICU | Current ours | Status |
|---|---:|---:|---:|
| `.era` | 4,398,046,511,104 | 4,398,046,511,104 | ✅ matches (inf_ti anchored at Hebrew epoch) |
| `.year` | 33,264,000 | 33,264,000 | ✅ matches |
| `.month` | 2,505,600 | 2,505,600 | ✅ matches |
| `.day` | 86,400 | 86,400 | ✅ matches |
| `.hour` | 3,600 | 3,600 | ✅ matches |
| `.quarter` | 7,603,200 | 7,603,200 | ✅ matches (3 real civil months) |
| `.weekOfYear` | 604,800 | 604,800 | ✅ matches |
| `.weekOfMonth` | 604,800 | 604,800 | ✅ matches |
| `.yearForWeekOfYear` | 33,264,000 | 33,264,000 | ✅ matches (55 weeks × 7 for this leap year) |

### `ordinality(of: smaller, in: larger, for: d)` — ✅ **TASK #14 COMPLETE**

| Pair | ICU | Current ours | Status |
|---|---:|---:|---:|
| (.day, .year) | 376 | 376 | ✅ matches |
| (.day, .month) | 20 | 20 | ✅ matches |
| (.month, .year) | 13 | 13 | ✅ matches (returns civil month directly, not densified) |
| (.hour, .day) | 22 | 22 | ✅ matches |
| (.month, .quarter) | 3 | 3 | ✅ matches (mcount table) |
| (.weekOfYear, .year) | 54 | 54 | ✅ matches (firstWeekday-aware, unwrapped) |
| (.weekOfMonth, .month) | 3 | 3 | ✅ matches (firstWeekday-aware) |
| (.weekday, .year) | 54 | 54 | ✅ matches (simple (dayOfYear-1)/7+1) |
| (.weekday, .month) | 3 | 3 | ✅ matches (simple (day-1)/7+1) |
| (.weekday, .weekOfYear) | 6 | 6 | ✅ matches |
| (.weekdayOrdinal, .month) | 3 | 3 | ✅ matches |
| (.quarter, .year) | 2 | 2 | ✅ matches (mquarter table) |

### `range(of: smaller, in: larger, for: d)`

| Pair | ICU | Current ours | Status |
|---|---|---|---|
| (.day, .year) | 1..<386 | 1..<386 | ✅ matches |
| (.day, .month) | 1..<30 | 1..<30 | ✅ matches |
| (.month, .year) | 1..<14 | 1..<14 | ✅ matches (constant; bypasses _algorithmA) |
| (.weekOfYear, .year) | 1..<57 | 1..<57 | ✅ matches (leap year max week count) |
| (.weekOfMonth, .month) | 1..<6 | 1..<6 | ✅ matches |

### `date(byAdding: <c>, value: 1, to: d)` — result date — ✅ **TASK #15 COMPLETE**

| Component | ICU | Current ours | Status |
|---|---|---|---|
| `.day` | 2016-09-24 | 2016-09-24 | ✅ matches |
| `.weekOfYear` | 2016-09-30 | 2016-09-30 | ✅ matches |
| `.weekOfMonth` | 2016-09-30 | 2016-09-30 | ✅ matches |
| `.weekdayOrdinal` | 2016-09-30 | 2016-09-30 | ✅ matches |
| `.month` | 2016-10-22 | 2016-10-22 | ✅ matches |
| `.year` | 2017-09-11 | 2017-09-11 | ✅ matches |
| `.hour` | 2016-09-23 22:35 | 2016-09-23 22:35 | ✅ matches |
| `.quarter` | unchanged | unchanged | ✅ matches (ICU no-ops this for Hebrew) |
| `.yearForWeekOfYear` | 2017-10-13 | 2017-10-13 | ✅ matches (55 weeks × 7 days for 5776) |

### `minimumRange` / `maximumRange` — ✅ **TASK #16 COMPLETE**

| Component | ICU min | Ours min | ICU max | Ours max | Status |
|---|---|---|---|---|---|
| `.era` | 0..<1 | 0..<1 | 0..<1 | 0..<1 | ✅ matches |
| `.year` | -5M..<5M+1 | -5M..<5M+1 | -5M..<5M+1 | -5M..<5M+1 | ✅ matches |
| `.month` | 1..<14 | 1..<14 | 1..<14 | 1..<14 | ✅ matches |
| `.day` | 1..<30 | 1..<30 | 1..<31 | 1..<31 | ✅ matches |
| `.hour` | 0..<24 | 0..<24 | 0..<24 | 0..<24 | ✅ matches |
| `.weekday` | 1..<8 | 1..<8 | 1..<8 | 1..<8 | ✅ matches |
| `.weekdayOrdinal` | -1..<6 | -1..<6 | -1..<6 | -1..<6 | ✅ matches |
| `.quarter` | 1..<5 | 1..<5 | 1..<5 | 1..<5 | ✅ matches |
| `.weekOfMonth` | 1..<6 | 1..<6 | 1..<7 | 1..<7 | ✅ matches |
| `.weekOfYear` | 1..<52 | 1..<52 | 1..<57 | 1..<57 | ✅ matches |
| `.yearForWeekOfYear` | -5M..<5M+1 | -5M..<5M+1 | -5M..<5M+1 | -5M..<5M+1 | ✅ matches |
| `.dayOfYear` | 1..<354 | 1..<354 | 1..<386 | 1..<386 | ✅ matches |
| `.isLeapMonth` | 0..<1 | 0..<1 | 0..<1 | 0..<1 | ✅ matches |

## Required before PR — checklist

- [x] Populate `.weekdayOrdinal`, `.weekOfMonth`, `.weekOfYear`, `.yearForWeekOfYear`, `.quarter` in `dateComponents(_:from:in:)`. — **Task #12**
- [x] Implement `dateInterval(of: .quarter / .weekOfYear / .weekOfMonth / .yearForWeekOfYear)`. — **Task #13**
- [x] Fix `dateInterval(of: .era)` to return the calendar-span interval (~inf_ti duration), not a single year. — **Task #13**
- [x] Implement the remaining ordinality pairs: `(.month, .quarter)`, `(.weekOfYear, .year)`, `(.weekOfMonth, .month)`, `(.weekday, .year)`, `(.weekday, .month)`, `(.weekday, .weekOfYear)`, `(.weekdayOrdinal, .month)`, `(.quarter, .year)`. — **Task #14**
- [x] Implement `date(byAdding: .yearForWeekOfYear)` (currently a silent no-op). — **Task #15**
- [x] Match ICU bounds for `minimumRange` / `maximumRange` on `.year`, `.weekdayOrdinal`, `.weekOfMonth`, `.weekOfYear`, `.yearForWeekOfYear`. — **Task #16**
- [x] Re-run the probe after every change; the diagnostic output must show zero `nil` → value transitions that weren't accounted for. — **ongoing discipline**
- [x] Extend the probe to test multiple dates (common year, leap year, year boundary, Adar I vs Adar II). — **Task #17**

## Accepted divergences

None on the ICU axis. The expanded probe sweep (~300 dates × 13 topic areas
in Suite A and Suite B, plus DST and locale variations in Suite B) produces
zero divergences from `_CalendarICU(.hebrew)` on every observable surface.

**Hebcal axis (separate authority):** at Hebrew year 5806 only, Hebcal
disagrees with swift-foundation-icu's chained-dehiyot algorithm, producing
a 385-day window of mismatched dates from Gregorian 2045-11-10 through
2046-11-29. Hebcal follows the standard Reingold & Dershowitz formulation
(year 5806 = 384d regular leap), while swift-foundation-icu's `hebrwcal.cpp`
applies Lo ADU + Betutakpat as separate `if` blocks (Lo ADU's wd-shift can
chain into Betutakpat), giving year 5806 = 385d complete leap. The PARITY
protocol mandates ICU as authoritative; the Hebcal regression test
(`HebrewRegressionTests.hebrewDailyRegression`) skips this Gregorian window
with a documented comment.

## Bug-fix summary (2026-04-27 expanded-probe session)

The probe expansion (~10 dates → ~300 dates across 13 topics) plus the
follow-up DST policy parity test found **seven** distinct bug classes in
the original `_CalendarHebrew`. All fixed:

1. **`ordinality(.weekday, in: .weekOfYear)` ignored `firstWeekday`.**
   Returned raw `comps.weekday`; now `((weekday - firstWeekday + 7) % 7) + 1`.
   (40 div in Suite B Topic 12.)

2. **`dateInterval(.yearForWeekOfYear).duration` used Hebrew calendar year, not yearForWeekOfYear.**
   Now queries `dateComponents([.yearForWeekOfYear], …)` and uses that.
   (~70 div across Suite A Topics 1, 4, 6, 7, 13.)

3. **R&D post-hoc `yearLengthCorrection` disagreed with ICU at certain year boundaries.**
   Ported swift-foundation-icu's inline dehiyot algorithm — including the
   Apple-specific separate-`if` chain (not else-if) where Lo ADU's wd-shift
   can subsequently trigger Betutakpat. Verified at Hebrew year 5462 / Gregorian 1700.
   (Topic 11 + revealed the Hebcal disagreement at year 5806.)

4. **DST-aware `dateComponents` extraction used `rawAndDaylightSavingTimeOffset(.former,.former)`.**
   Switched to `secondsFromGMT(for:)` matching `_CalendarGregorian`. The former
   API can resolve ambiguously at DST transitions. (Most of the 99 div in Topic 10.)

5. **`dateInterval(.hour/.minute/.second)` re-constructed via `date(from:)` with `.former`.**
   Now uses local-floor approach matching `_CalendarGregorian` directly.
   This was causing intervals to land in the wrong half of repeated wall-clock
   windows during DST fall-back, which cascaded into `enumerateDates` failing
   to find matches and `date(bySettingHour:)` returning nil.

6. **`dateComponents(_:from:to:)` iteration accumulated day-clamping.**
   Iterative form (`current + 1*step`) clamps day at every month boundary;
   ICU uses cumulative form (`start + n*step`) which clamps from the
   *original* day each iteration. Fixed by changing the inner loop to use
   cumulative addition. Fixes 1-day drift in cross-month diff at e.g.
   AdarI 30 + 2 months → Nisan 30 (instead of Nisan 29 via clamp accumulation).

7. **`utcDate(fromRataDie:)` passed `skippedTimePolicy` through to TimeZone.**
   `_CalendarGregorian.date(from:inTimeZone:dstRepeatedTimePolicy:dstSkippedTimePolicy:)`
   accepts the skipped-policy parameter but **does not pass it** to
   `TimeZone.rawAndDaylightSavingTimeOffset(...)` — only the repeated
   policy. Our Hebrew utcDate was passing both, causing 1-hour
   divergences at spring-forward windows when callers specified
   `skippedTimePolicy: .latter`. Fixed by matching Gregorian's call shape
   (drop skipped at the TZ-offset boundary). Caught by the new
   `utcDate_allPolicyCombinations_matchGregorian` test which sweeps all
   four (.former/.latter)² combinations.

### 2026-04-28 Suite B expansion session (bugs #8–9)

Suite B expanded to ~300 dates (matching Suite A's 13 topic date sets through
the public Calendar API). Found two additional bugs:

8. **Multi-field `date(byAdding:)` batched year+month, skipping intermediate day-clamping.**
   At Kislev 30 in a complete year, adding year=1 landing in a deficient year
   (Kislev 29) must clamp day to 29 before the month-add runs. The batched
   approach did a single decompose→year+month→clamp→reconstruct, missing the
   year→clamp step. Fixed by splitting into sequential operations (year first,
   clamp, reconstruct, then month separately) matching `_CalendarGregorian`'s
   `date(byAddingAndCarryingOverComponents)` pattern.
   (Suite B Topics 2 and 7: Kislev 30 at years 5752 and 5780.)

9. **Nanosecond extraction used chained FP subtractions + `.rounded()`.**
   Hebrew computed fractional seconds by chaining: secondsInDay → subtract
   hours → subtract minutes → subtract seconds → fractional, then
   `Int((fractional * 1e9).rounded())`. `_CalendarGregorian` computes
   `Int((timeInterval - timeInterval.rounded(.down)) * 1_000_000_000)` — a
   single subtraction from the original value, truncated (not rounded).
   The chained subtractions accumulated FP error, and rounding vs truncation
   diverged by ±1 ns at sub-millisecond timestamps. Fixed by matching
   Gregorian's single-subtraction + truncation approach.
   (Suite B Topic 9: 0.001s-offset timestamps.)

## Test inventory

- **Suite A** (`Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift`):
  13 topic-specific tests + 2 baseline (`compareFieldsSideBySide`, `sweepMultipleDates`).
  ~300 dates across year-length regimes, Cheshvan/Kislev boundaries, the full
  19-year Metonic cycle, RH postponement, Adar I↔II transition, year/month
  boundaries, holidays, time-of-day, far past/future (600–2300 CE), week-of-year wrap.

- **Suite B** (`Tests/FoundationInternationalizationTests/HebrewPublicAPIComparisonProbe.swift`):
  11 topic-specific tests (matching Suite A's date sets through the public Calendar
  API) + baseline 10-date probe (`publicAPI_sweepAllMethods`) + DST sweep
  (`dstTimezones_americaLosAngeles` — 17 wall-clocks) + locale sweep
  (`localeVariations_firstWeekdayAndMinDays` — 6 configs × 10 dates).
  Suite B topics: yearLengthVariants, cheshvanKislev, metonicCycle, roshHashanah
  Postponement, adarTransition, yearBoundaries, monthBoundaries, majorHolidays,
  timeOfDay, farPastAndFarFuture, weekOfYear_yearWrap — each exercising every
  public `Calendar` method at every date (component, dateComponents, startOfDay,
  dateInterval, range, ordinality, date(from:), date(byAdding:), compare,
  isDate(equalTo:), weekend queries, enumerateDates, nextDate, dateComponents
  from:to:). ~300 dates total.

- **DST policy parity** (`Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift`):
  - `utcDate_allPolicyCombinations_matchGregorian` — 16 wall-clocks × 4 policy
    combinations = 64 cases comparing our `_CalendarHebrew.utcDate` directly
    against `_CalendarGregorian.date(from:inTimeZone:dstRepeated:dstSkipped:)`.
  - `date_from_hebrewVsGregorian_atDSTBoundaries` — end-to-end check that
    `Calendar(.hebrew).date(from:)` agrees with `Calendar(.gregorian).date(from:)`
    at every DST boundary going through the public API (default policies).

## Local-only tests (not committed to PR)

See [`BENCHMARK_TESTS.md`](BENCHMARK_TESTS.md) for the local research
benchmarks (run via `swift test`, debug-mode timing, kept in `Tests/`).
See [`BENCHMARKS_PACKAGE.md`](BENCHMARKS_PACKAGE.md) for the upstream
Calendar benchmarks target (`Benchmarks/`, run via `swift package
benchmark`, real CPU/malloc/RSS metrics) — Hebrew additions planned
there for the PR's perf narrative. These live
in `Tests/FoundationInternationalizationTests/` but are deliberately
excluded from the Hebrew port commit:

- **`HebrewVsICUBenchmark.swift`** — ICU vs `_CalendarHebrew` benchmarks
  (8 `@Test`s including 5 `nextThousand…` enumerate patterns covering
  `{m,d}`, `{m,d,h,m,s}`, `{day:1}`, `{month:1}`, `{weekday:7}`).
- **`AllocationsBreakdown.swift`** — splits the 35–44× alloc speedup into
  construction-cost (58–77×) and arithmetic-cost (7–9×) layers.
- **`EnumerateBreakdown.swift`** — 3-layer cost decomposition of
  `nextThousandHanukkahs` (direct call → manual month-loop → full
  framework).
- **`EnumerateMicroProfile.swift`** — protocol-dispatch cost,
  fast-path-vs-framework ratio, and **`extendedFastPath_correctnessVsICU`**:
  9 component patterns × 50–100 matches each, compared to ICU's
  `enumerateDates` ground truth. **0 divergences** verified 2026-05-01.

The fast-path infrastructure (`Calendar_Protocol.swift` + `Calendar.swift`
wiring + `_CalendarHebrew.nextDate` extensions) is a separate
research-stage change. When ready to upstream, the fast-path correctness
test should be promoted into a real test file.

If a future probe date reveals a divergence, either fix it or move it here
with explicit justification.
