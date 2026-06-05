# Hebrew calendar port: ICU → pure Swift

Replaced `_CalendarICU(.hebrew)` with `_CalendarHebrew` in `swift-foundation`.
Reingold & Dershowitz arithmetic, ICU-behaviorally identical, substantially faster.

## Files added

| File | Purpose |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | `_CalendarHebrew` class + `HebrewArithmetic` algorithms. |
| `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift` | Direct unit tests: leap years, round-trip, ICU cross-check, **DST policy parity vs `_CalendarGregorian` (all 4 (.former/.latter)² combos)**. |
| `Tests/FoundationEssentialsTests/HebrewRegressionTests.swift` | 73,414-day Hebcal CSV regression. |
| `Tests/FoundationInternationalizationTests/HebrewCalendarPerformanceTests.swift` | Perf benchmarks vs ICU (Hanukkah enumerate, CoW, alloc, round-trip). |
| `Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift` | **Suite A** — `_CalendarProtocol`-level ICU parity probe. |
| `Tests/FoundationInternationalizationTests/HebrewPublicAPIComparisonProbe.swift` | **Suite B** — public `Calendar` API ICU parity probe. |
| `Tests/FoundationInternationalizationTests/HebrewDSTPolicyParityTests.swift` | DST policy parity tests vs `_CalendarGregorian` (moved from FoundationEssentialsTests — needs ICU-backed TimeZone). |

## Files modified

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` | Router flip: `_calendarClass(.hebrew)` returns `_CalendarHebrew.self`. |

## Parity — Suite A (`_CalendarProtocol`, internal)

Probe: ~300 dates across 13 topic-specific tests (Suite A) plus the
original 10 hand-picked edge cases × every observable protocol surface.
**0 divergences.**

Topics covered: year-length variants (all 6 regimes), Cheshvan/Kislev
length boundaries, full 19-year Metonic cycle, RH postponement (4
allowed weekdays), Adar I↔II transition, year boundaries, month
boundaries, major holidays, time-of-day edge cases (sub-second + DST
boundaries), far past/future (600–2300 CE), week-of-year wrap.


| Surface | Count | Result |
|---|---:|---|
| `dateComponents(_:from:in:)` fields | 15 | ICU == ours |
| `dateInterval(of:for:)` components | 9 | ICU == ours |
| `ordinality(of:in:for:)` pairs | 12 | ICU == ours |
| `range(of:in:for:)` pairs | 5 | ICU == ours |
| `date(byAdding: <c>, value: 1, to:)` | 9 | ICU == ours |
| `minimumRange(of:)` / `maximumRange(of:)` | 13 × 2 | ICU == ours |

## Parity — Suite B (public `Calendar` API)

Probe: ~300 dates across 11 topic-specific tests (matching Suite A's date sets
through the public Calendar API) + baseline 10-date probe + DST timezone sweep
(America/Los_Angeles spring-forward & fall-back, 17 wall-clocks) + locale-variations
sweep (6 firstWeekday/minDays configs × 10 dates). **0 divergences.**

| Method | Tested | Result |
|---|---:|---|
| `component(_:from:)` | ✅ all 15 components | ICU == ours |
| `dateComponents(_:from:)` (all fields) | ✅ | ICU == ours |
| `dateComponents(in:from:)` | ✅ | ICU == ours |
| `dateComponents(_:from:to:)` (Date args) | ✅ multi-unit | ICU == ours |
| `startOfDay(for:)` | ✅ | ICU == ours |
| `dateInterval(of:for:)` | ✅ all components | ICU == ours |
| `range(of:in:for:)` | ✅ 11 pairs | ICU == ours |
| `ordinality(of:in:for:)` | ✅ 14 pairs | ICU == ours |
| `date(from:)` | ✅ round-trip | ICU == ours |
| `date(byAdding: Component, value:)` | ✅ 20 (comp, value) combos | ICU == ours |
| `date(byAdding: DateComponents)` | ✅ multi-field | ICU == ours |
| `date(byAdding:, wrappingComponents: true)` | ✅ day-wrap within month | ICU == ours |
| `date(bySetting:value:of:)` | ✅ hour / minute / day | ICU == ours |
| `date(bySettingHour:minute:second:of:)` | ✅ | ICU == ours |
| `compare(_:to:toGranularity:)` | ✅ all 14 granularities × 2 date pairs | ICU == ours |
| `isDate(_:equalTo:toGranularity:)` | ✅ all granularities | ICU == ours |
| `isDate(_:inSameDayAs:)` | ✅ | ICU == ours |
| `date(_:matchesComponents:)` | ✅ match + mismatch | ICU == ours |
| `isDateInWeekend(_:)` | ✅ | ICU == ours |
| `dateIntervalOfWeekend(containing:)` | ✅ at probe date + at nearest Saturday | ICU == ours |
| `nextWeekend(startingAfter:direction:)` | ✅ both directions | ICU == ours |
| `enumerateDates(startingAfter:matching:)` | ✅ Hanukkah × 3, Passover × 3 | ICU == ours |
| `nextDate(after:matching:)` | ✅ Hanukkah | ICU == ours |

## Correctness

| Layer | Result |
|---|---|
| Full Foundation test suite (on main, 2026-04-28) | **1510/1510 pass** |
| Foundation `Calendar` test suite | **167/167 pass** |
| 73,414-day Hebcal regression (1900–2100) | **0 divergences** outside year 5806 (documented ICU/Hebcal disagreement; see PARITY.md) |
| Suite A protocol probe (13 topics, ~300 dates) | **0 divergences** |
| Suite B public-API probe (11 topics, ~300 dates + DST + locale sweeps) | **0 divergences** |
| DST policy parity (`utcDate` × 4 (.former/.latter)² combos × 16 wall-clocks) | **0 divergences vs `_CalendarGregorian`** |

## Performance (debug mode, best of 10 runs, Apple Silicon, Swift 6.4-dev)

### Core benchmarks (GMT timezone)

| Benchmark | ICU baseline | `_CalendarHebrew` | Speedup |
|---|---:|---:|---:|
| `allocationsForFixedHebrewCalendar` | 15,366 ns/iter | 440 ns/iter | **34.9×** |
| `copyOnWriteHebrew` | 15,621 ns/iter | 459 ns/iter | **34.0×** |
| `nextThousandHanukkahs` | 375 µs/match | 304 µs/match | **1.2×** |

### Core benchmarks (America/Los_Angeles timezone)

| Benchmark | ICU baseline | `_CalendarHebrew` | Speedup |
|---|---:|---:|---:|
| `allocationsForFixedHebrewCalendar` | 34,071 ns/iter | 783 ns/iter | **43.5×** |
| `copyOnWriteHebrew` | 32,996 ns/iter | 832 ns/iter | **39.7×** |
| `nextThousandHanukkahs` | 457 µs/match | 341 µs/match | **1.3×** |

### `nextThousandHanukkahs` breakdown (GMT timezone)

The enumerate benchmark uses Foundation's shared `Calendar_Enumerate.swift`
framework, which loops month-by-month through generic matching logic. This
buries the calendar-arithmetic speedup under framework overhead. Breaking
it into layers:

| Layer | What it measures | ICU | Hebrew | Speedup |
|---|---|---:|---:|---:|
| 1. Direct computation | decompose date + construct target (2 protocol calls) | 14 µs | 3 µs | **4.7×** |
| 1b. Pure arithmetic | Hebrew-only: `hebrewFromFixed` + `fixedFromHebrew` (no protocol dispatch) | — | 2 µs | — |
| 2. Manual month-loop | ~12 protocol calls per match (simulates enumerate's inner loop) | 135 µs | 98 µs | 1.4× |
| 3. Full `enumerateDates` | complete `Calendar_Enumerate.swift` framework | 380 µs | 300 µs | 1.3× |

The real calendar-arithmetic advantage is **4.7×** (Layer 1). The shared
enumerate framework adds ~245–280 µs of overhead per match regardless of
backend, diluting the ratio to 1.3×.

### Why `enumerateDates` can't see the speedup

`Calendar.enumerateDates(startingAfter:matching:matchingPolicy:...)` is
Foundation's public API for finding dates that match a pattern. Internally it
lives in `Calendar_Enumerate.swift` (~2500 lines of generic matching logic)
and works by looping month-by-month through the calendar, calling protocol
methods (`dateComponents`, `dateInterval`, `date(from:)`) at each step to
check if the target pattern matches. It doesn't know that Hebrew can jump
directly to "25 Kislev of year N" in one arithmetic step.

### Fast-path: `_CalendarHebrew.nextDate(after:matching:)`

A fast-path method on `_CalendarHebrew` handles simple `{month, day}`
patterns (like Hanukkah = 25 Kislev) by computing the target date directly
via `hebrewFromFixed` + `fixedFromHebrew` — O(1) per match instead of
O(12 months) iteration. Verified correct: 20/20 dates match `enumerateDates`
output exactly.

| Path | Time/match | vs ICU `enumerateDates` |
|---|---:|---:|
| ICU via `enumerateDates` | 380 µs | baseline |
| Hebrew via `enumerateDates` | 300 µs | 1.3× |
| Hebrew via `nextDate` fast-path | 513 ns | **741×** |

The fast-path currently lives on `_CalendarHebrew` only. To expose it
through `Calendar.enumerateDates`, Foundation would need one of:

1. **Protocol method**: add an optional `nextDate(after:matching:direction:)`
   to `_CalendarProtocol` with a default nil return. `Calendar.enumerateDates`
   checks it before entering the generic framework. Clean and extensible —
   every future calendar port can add its own fast-path — but changes the
   protocol interface.
2. **Calendar-level dispatch**: `Calendar.enumerateDates` checks the inner
   calendar type and calls the fast-path directly. Less invasive but doesn't
   scale to other calendars.

Either way, the implementation is ready in `_CalendarHebrew.nextDate` and
the 741× speedup is available to any code that calls it directly.

### `allocationsForFixedHebrewCalendar` breakdown

The allocations benchmark creates a new calendar + does one `date(byAdding:
.day)` per iteration. Breaking it into construction vs arithmetic:

**GMT timezone:**

| Layer | ICU | Hebrew | Speedup |
|---|---:|---:|---:|
| 1. Construction only | 6,735 ns | 118 ns | **57×** |
| 2. `date(byAdding:.day)` only | 2,219 ns | 245 ns | **9.1×** |
| 3. Both combined | 10,179 ns | 363 ns | **28×** |

**America/Los_Angeles timezone:**

| Layer | ICU | Hebrew | Speedup |
|---|---:|---:|---:|
| 1. Construction only | 8,428 ns | 118 ns | **71×** |
| 2. `date(byAdding:.day)` only | 3,174 ns | 628 ns | **5.1×** |
| 3. Both combined | 28,784 ns | 752 ns | **38×** |

Construction dominates. ICU allocates a C++ `icu::HebrewCalendar` on the
heap (~6.7 µs even with GMT; ~8.4 µs with LA due to ICU timezone setup).
Hebrew initializes a Swift class with 5 stored properties (~118 ns regardless
of timezone — it stores a reference to Foundation's `TimeZone`, not an ICU
timezone object). The 57–71× construction gap is the core of the 35–44×
headline number. Day-add arithmetic adds a secondary 5–9× advantage.

## Pre-PR blockers

| # | Item | Status |
|---|---|---|
| 11 | Decide final Hebcal regression fixture (1.7 MB vs sampled) | open |

Everything else closed. Port is ICU-behaviorally indistinguishable and PR-ready pending the fixture-size decision.
