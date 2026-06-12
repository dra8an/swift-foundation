# Package benchmarks (swift-benchmark target)

> **See also: [`BENCHMARK_TESTS.md`](BENCHMARK_TESTS.md)** — covers our
> *local* research-stage benchmarks living in `Tests/.../`, run via
> `swift test`, debug-mode timing only. This file covers the **official**
> upstream-committed benchmarks target.

## What this is

`Benchmarks/Benchmarks/Internationalization/BenchmarkCalendar.swift` is
swift-foundation's official Calendar benchmark file. It uses the
[`Benchmark`](https://github.com/ordo-one/package-benchmark) (Ordo One)
package — a separate target from the test runner, with proper metrics
collection (CPU time, malloc count, peak resident memory, throughput),
warm-up handling, and statistical reporting.

It runs via:

```sh
cd ~/Projects/claude/swift-foundation
swift package benchmark
# Or for one specific benchmark:
swift package benchmark --filter <name>
```

Unlike `swift test`-based timing, this target produces numbers fit for
upstream PR descriptions and tracking regressions over time.

## Existing Gregorian benchmarks (as of 2026-05-01, baseline)

All currently in the file use `Calendar(identifier: .gregorian)` or
`.current`. None exercise Hebrew, Buddhist, Japanese, or any other
non-Gregorian calendar.

| Benchmark | Pattern | Notes |
|---|---|---|
| `nextThousandThursdaysInTheFourthWeekOfNovember` | `{month: 11, weekday: 5, weekOfMonth: 4}` × 1000 | Originally named `nextThousandThanksgivings`; renamed because that wasn't actually computing Thanksgivings. |
| `nextThousandThanksgivings` | `{month: 11, weekday: 5, weekdayOrdinal: 4}` × 1000 | Real 4th-Thursday-of-November pattern. |
| `nextThousandThanksgivingsSequence` | Same, via `cal.dates(byMatching:)` | Swift 6+ only. |
| `RecurrenceRuleThanksgivings` | `Calendar.RecurrenceRule(frequency:.yearly)` × 1000 | Same Thanksgiving pattern via the higher-level RecurrenceRule API. |
| `RecurrenceRuleThanksgivingMeals` | `RecurrenceRule` with `hours = [14, 18]` | 1000 Thanksgiving meal slots (lunch + dinner). |
| `RecurrenceRuleLaborDay` | September, 1st Monday | 1000 occurrences. |
| `RecurrenceRuleBikeParties` | Monthly, 1st + last Friday | 1000 occurrences. |
| `RecurrenceRuleDailyWithTimes` | Mon-Wed at 9:00 and 10:00, :00 and :30 | Daily mixed-time recurrence. |
| `CurrentDateComponentsFromThanksgivings` | enumerate Thanksgivings + extract all components | Tests Thanksgiving find + decompose. |
| `allocationsForFixedCalendars` | `Calendar(identifier: .gregorian)` × 1M | Per-instance allocation cost. |
| `allocationsForCurrentCalendar` | `Calendar.current` × 1M | |
| `allocationsForAutoupdatingCurrentCalendar` | `Calendar.autoupdatingCurrent` × 1M | |
| `copyOnWritePerformance` | mutate `firstWeekday` × 1M | CoW with diff. |
| `copyOnWritePerformanceNoDiff` | mutate `timeZone` to same value × 1M | CoW with no-op set. |
| `allocationsForFixedLocale` | Locale construction × 1M | Not calendar, but in same file. |
| `allocationsForCurrentLocale` | Locale.current × 1M | |
| `allocationsForAutoupdatingCurrentLocale` | Locale.autoupdatingCurrent × 1M | |
| `identifierFromComponents` | Locale identifier construction × 1M | |

## Planned Hebrew additions — TBD

The Hebrew port lands a calendar that's competitive with (or faster than)
ICU on the patterns the public API exposes. We need parallel benchmarks
to back those claims under proper metric collection.

Comparison methodology: each Hebrew benchmark runs against **both**
`Calendar(inner: _CalendarICU(...))` (the ICU baseline as it existed
before the port) **and** `Calendar(identifier: .hebrew)` (which now
routes to `_CalendarHebrew` via the cache). Each benchmark is
parameterized and registered twice with `[ICU]` / `[Hebrew]` suffixes
so results show side-by-side.

### Proposed benchmarks

| Name | Pattern | Why |
|---|---|---|
| `hebrew_nextThousandHanukkahs` (×2: ICU, Hebrew) | `{month: 3, day: 25}` | Mirrors the canonical `{m, d}` annual recurrence. Exercises the wired fast path. |
| `hebrew_nextThousandHanukkahsAt1830` (×2) | `{month: 3, day: 25, hour: 18, minute: 30}` | Time-of-day preservation through the fast path. |
| `hebrew_nextThousandRoshChodesh` (×2) | `{day: 1}` | First of every Hebrew month — exercises `{day}`-only fast path. |
| `hebrew_nextThousandSaturdays` (×2) | `{weekday: 7}` | Weekday RD-modular fast path. |
| `hebrew_nextThousandTishriStarts` (×2) | `{month: 1}` | Month-only fast path. |
| `hebrew_RecurrenceRuleHanukkahs` (×2) | `RecurrenceRule` yearly, month=3, day=25 | High-level RecurrenceRule path (does it benefit from fast path?). |
| `hebrew_RecurrenceRulePassoverSeders` (×2) | `RecurrenceRule` with `hours = [19, 20]` | Mixed-time recurrence parallel to `RecurrenceRuleThanksgivingMeals`. |
| `hebrew_dateComponentsFromHanukkahs` (×2) | enumerate + extract all components | Mirrors `CurrentDateComponentsFromThanksgivings`. |
| `hebrew_allocationsForFixedCalendars` (×2) | Calendar construction × 1M | Allocation cost (already known to be ~35–43× ICU). |
| `hebrew_copyOnWritePerformance` (×2) | mutate `firstWeekday` × 1M | CoW (already known to be ~34–42× ICU). |
| `hebrew_dateAddByDay` (×2) | `date(byAdding: .day, value: 1)` × 1M | Pure arithmetic cost, no enumerate. |
| `hebrew_dateComponentsRoundTrip` (×2) | `dateComponents → date(from:)` × 1M | Round-trip cost. |

### Status

- [ ] Hebrew variants of the existing patterns added to `BenchmarkCalendar.swift`.
- [ ] First baseline run captured with `swift package benchmark`.
- [ ] Numbers documented below in "Results".
- [ ] (Optional) Same benchmarks added to a Gregorian-Hebrew comparison
      table for the PR description.

## Running

> **⚠ Read this before running anything.** This setup has known
> footguns; the working incantations below are the ones we've actually
> verified produce numbers.

### Working full run (this is what every v8–v15 baseline used)

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation/Benchmarks
export SWIFTCI_USE_LOCAL_DEPS=1
swift package benchmark run \
  --target InternationalizationBenchmarks \
  --benchmark-build-configuration debug
```

Wall time ~3–5 min. Three benchmarks crash unrelated to the port
(firstWeekday=0 / en_US asserts in `BenchmarkCalendar.swift` lines
~179, 205, 214) — ignore them; the 9 calendar benchmarks succeed.

### Working single-bench iteration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation/Benchmarks
export SWIFTCI_USE_LOCAL_DEPS=1
swift package benchmark run \
  --benchmark-build-configuration debug \
  --filter "^<EXACT_BENCHMARK_NAME>$"
```

Wall time ~30–90 s. Use this for "is my change directionally helping?"
iteration; only run the full target for the cross-benchmark picture or
when documenting results.

### The 9 calendar benchmarks (in `BenchmarkCalendar.swift`)

- `nextThousandThanksgivings`
- `nextThousandThanksgivingsSequence`
- `nextThousandThursdaysInTheFourthWeekOfNovember`
- `RecurrenceRuleThanksgivings`
- `RecurrenceRuleThanksgivingMeals`
- `RecurrenceRuleLaborDay`
- `RecurrenceRuleBikeParties`
- `RecurrenceRuleDailyWithTimes`
- `CurrentDateComponentsFromThanksgivings`

### Footguns (lessons from the v8–v15 work)

1. **Must `cd` into `Benchmarks/`.** It's a separate SwiftPM package
   from the main repo — running `swift package benchmark` from the repo
   root fails with `Unknown subcommand or plugin name 'benchmark'`.
2. **Debug mode is required.** Default is release; release-mode crashes
   with SIGBUS on Intel x86_64 + Swift 6.3.1 inside the BenchmarkTool
   subprocess. Pass `--benchmark-build-configuration debug`.
3. **Multi-keyword `--filter` is broken.** `--filter "Recurrence"` and
   `--filter "nextThousand|Recurrence|CurrentDate"` (with or without
   `^…$` anchors) silently match **zero** benchmarks on this setup. The
   only filter form we've gotten to work is `--filter "^<exact-name>$"`
   for a single benchmark. For multi-bench runs, use `--target` and let
   it run everything (filtering nothing).
4. **No `tee` / piping issues — output is reliable.** It just shows
   nothing if the filter matched nothing, which is easy to mistake for
   a hang.

### Comparing baselines (built-in)

```sh
swift package benchmark baseline update <name>     # save current numbers as baseline
# … make changes …
swift package benchmark baseline check <name>      # compare current to saved
```

Threshold/regression handling is part of the swift-benchmark package — see
the package's README for details. We haven't used this in the v8–v15 work
(captured raw output to `bench_*.txt` files instead and compared by hand).

## Results — Buddhist + Japanese (2026-06-11, debug mode, Intel iMac) — PR-READY

> **Use this section verbatim (minus local caveats) in the Buddhist/Japanese
> PR description.** Numbers accepted by user 2026-06-11.

### Benchmarks added (uncommitted → committed on `port/buddhist`)

`BenchmarkCalendar.swift` gained three mirrored 5-bench blocks so all
calendars run **identical bench bodies**:

| Shape | Gregorian | Buddhist | Japanese |
|---|---|---|---|
| enumerate `{m,d}` ×1000 | `GregorianCalendar-nextThousandChristmases` (12/25) | `BuddhistCalendar-nextThousandSongkrans` (4/13) | `JapaneseCalendar-nextThousandChildrensDays` (5/5) |
| construct + day-add | `*-allocationsForFixedCalendar` | same | same |
| CoW mutate firstWeekday | `*-copyOnWritePerformance` | same | same |
| dateComponents y/m/d | `*-dateComponents-yearMonthDay` | same | same |
| dc → date(from:) round-trip | `*-roundTripDateComponents` | same | same |

Also fixed the 3 pre-existing crashing benches (machine-independent now):
`copyOnWritePerformance` uses `(i % 2) + 1` (0 is invalid firstWeekday);
the two `allocationsFor*CurrentLocale` benches assert `!identifier.isEmpty`
instead of `== "en_US"`. And `InternationalizationBenchmark.swift`'s SPM
entry restored to `calendarBenchmarks()` (no-arg).

### Methodology

ICU side: flags as committed (`Calendar(identifier:)` routes to
`_CalendarICU` via the dynamic replacement). Ours side: SPM-branch feature
flags in `Calendar_Cache.swift` temporarily flipped to `true` (and for the
Gregorian control, the `.gregorian` branch temporarily routed to
`_calendarICUClass()`), then **restored**. Single-bench anchored filters,
debug build (release SIGBUSes on Intel x86_64 + Swift 6.3.1).

### The matrix (p50, ICU → ours, ratio >1× = ours slower)

| Shape | Gregorian | Buddhist | Japanese |
|---|---|---|---|
| enumerate {m,d} ×1000 | 676→3,581 µs (5.3×) | 355→1,639 µs (4.6×) | 201→887 µs (4.4×) |
| alloc + day-add | 3,810→20,705 ns (5.4×) | 3,933→20,837 ns (5.3×) | 3,956→19,743 ns (5.0×) |
| copyOnWrite | 21,689→566 ns (**38× faster**) | 20,448→783 ns (**26× faster**) | 21,001→782 ns (**27× faster**) |
| dateComponents ymd | 55→54 ns (par) | 54→59 ns (par) | 54→126 ns (2.3×) |
| roundTrip | 90→73 ns (1.2× faster) | 88→80 ns (par) | 87→163 ns (1.9×) |

Mallocs: enumerate ours 12 (Gregorian) / 5,355 (Buddhist) / 2,966 (Japanese)
vs ICU 333 / 162 / 96; CoW ours 1–2 vs ICU 24; dateComponents + roundTrip
0 on both sides.

### Conclusion (the PR narrative)

**The Buddhist/Japanese wrappers inherit `_CalendarGregorian`'s own
performance profile — composition adds essentially nothing.** The shipped
upstream pure-Swift Gregorian shows the same ~5× debug-mode ratios vs ICU
on the enumerate and alloc+add shapes; Buddhist/Japanese absolute values
match raw Gregorian within noise (e.g. 20.8 vs 20.7 µs alloc+add).

Measured composition overhead (the only cost that is *ours*):
- CoW: +217 ns (wrapper re-construction)
- Buddhist dateComponents: +5 ns; roundTrip: ~0
- Japanese dateComponents: +72 ns; roundTrip: +90 ns (era probe +
  era-table walk — fixable by folding era resolution into one pass)

Wins: CoW 26–38× faster (value-type advantage, consistent with Hebrew);
roundTrip/dateComponents par or better except Japanese era handling.

### Caveats

- **Debug-mode numbers.** Apple ships `_CalendarGregorian` as the
  production default, so the ~5× debug ratios vs ICU's release-compiled C
  are expected artifacts; they apply equally to the already-shipped
  Gregorian. Release verification blocked by the Intel SIGBUS — re-run on
  Apple Silicon before quoting absolute ratios upstream.
- No fast-path `nextDate` for Buddhist/Japanese yet (Hebrew-style fast
  paths are the obvious follow-up if enumerate performance matters).
- Raw logs: `/tmp/bench_icu_baseline.txt`, `/tmp/bench_ours_*.txt`,
  `/tmp/bench_greg_{ICU,OURS}_*.txt` (volatile — numbers preserved here).

## Results — first run (2026-05-03, debug mode, Intel iMac)

Methodology: parameterized `calendarBenchmarks(_ identifier:)` so the same
benchmark code runs against any calendar via the `cal` variable. To get the
ICU baseline for Hebrew workloads, `Calendar_Cache.swift` was temporarily
flipped so `.hebrew` returns `_CalendarICU` (then restored).

Three runs captured (raw output in `bench_*_baseline.txt` / `bench_*_results.txt`):

1. **Gregorian** — `calendarBenchmarks(.gregorian)` (control / context).
2. **Hebrew (ICU)** — `.hebrew` flipped to return `_CalendarICU` in cache.
3. **Hebrew (ours)** — `.hebrew` returns `_CalendarHebrew` (default after port).

### Calendar-using benchmarks (parameterized — different per run)

#### Snapshot labels — single canonical numbering

All benchmark columns and prose use the **backup snapshot labels** from
`BACKUPS.md` so the artifact and the perf number are always identifiable
together:

| Label | Snapshot directory | Commit / status | What's in it |
|---|---|---|---|
| baseline | (pre-port) | — | ICU-as-Hebrew (router temporarily flipped to `_CalendarICU` for measurement) |
| `c2668eb-pre` | (intermediate dev) | uncommitted dev step | `{m, d}`/`{m}`/`{d}`/`{wd}` fast paths only — adds `{m, wd, wdOrd}` extension but no YearData cache |
| `c2668eb` | (committed) | `c2668eb` | committed: `{m, wd, wdOrd}` extension + YearData cache |
| `v8` | `backup/v8-enumeratedatesstep-fastpath/` | uncommitted | + `_enumerateDatesStep` fast-path wiring (shared code) |
| `v9` | `backup/v9-iterator-fastpath-hoist/` | uncommitted | + `DatesByMatching.Iterator` probe-and-commit hoist |
| `v10` | `backup/v10-weekofmonth-fastpath/` | uncommitted | + Hebrew `{m, wd, weekOfMonth}` fast path |
| `v11` | `backup/v11-helper-hijack/` | uncommitted | + helper hijack at `dateAfterMatchingWeekOfMonth` / `dateAfterMatchingWeekdayOrdinal` |
| `v12` | `backup/v12-recurrence-shortcircuit-and-parity-probe/` | uncommitted | + `_unadjustedDates` single-combination short-circuit + `dateAfterMatchingMonth` / `dateAfterMatchingWeekday` hijacks + Suite C parity probe |
| `v13` | `backup/v13-multicombo-cartesian-shortcircuit/` | uncommitted | + `_unadjustedDates` multi-combination cartesian short-circuit (positive-ordinal patterns) |
| `v14` | `backup/v14-optionb-negative-ordinal-translation/` | uncommitted | + negative-ordinal patterns via runtime weekOfMonth translation (BikeParties shape) |
| `v15` | `backup/v15-time-only-fast-path/` | uncommitted | + time-only `{h, mi, s, ns?}` fast path in Hebrew `nextDate` (DailyWithTimes shape) |
| `v16` | `backup/v16-mutex-and-comment-sync/` | uncommitted | sync from `port/hebrew-main`: `LockedState` → `Mutex`, `var newYear` → `let`, icu4swift comment cleanup. No perf impact — code-shape sync only. |
| `v16-frozen` | `backup/v16-frozen-pre-v17/` | safety snapshot | pre-v17 comprehensive backup (4 source + 7 test + 3 bench files). |
| `v17` | `backup/v17-sync-from-port-hebrew-main/` | uncommitted | sync from `port/hebrew-main`'s `ef191c1` (PR #1953 review feedback): strip unused libc imports, parameterize DST tests, delete `HebrewCalendarPerformanceTests.swift`, replace `BenchmarkCalendar.swift` with upstream version (adds 5 Hebrew-specific benchmarks). No perf impact — code/test-shape sync only. |
| `v17-frozen` | `backup/v17-frozen-pre-v18/` | safety snapshot | pre-v18 single-file backup of `Calendar_Hebrew.swift`. |
| `v18` | `backup/v18-comment-trims-sync/` | uncommitted | sync from `port/hebrew-main`'s `26c1377` (PR #1953 round 2): trim verbose comments at 12 sites in `Calendar_Hebrew.swift`, add `// TODO` for shared weekend logic. Comment-only, -88/+16 lines net. No perf impact. |
| `v18-frozen` | `backup/v18-frozen-pre-v19/` | safety snapshot | pre-v19 backup of Calendar_Hebrew.swift + Calendar_Gregorian.swift. |
| `v19` | `backup/v19-shareable-apis-tier0-constants/` | uncommitted | SHAREABLE_APIS Tier 0: extracted 5 time-unit constants to new `_CalendarConstants` enum. Removed instance declarations from Hebrew + Gregorian; updated 29 Gregorian callsites + 1 Hebrew callsite. PR #1953 reviewer comment #6 addressed. No perf impact. |
| `v19-frozen` | `backup/v19-frozen-pre-v20/` | safety snapshot | pre-v20 backup of Hebrew + Gregorian + Calendar_Protocol. |
| `v20` | `backup/v20-shareable-apis-tier1a-hash-default/` | uncommitted | SHAREABLE_APIS Tier 1A: `hash(into:)` default impl in `_CalendarProtocol` extension. Removed duplicated impls from Hebrew + Gregorian. Three other conformers keep specialized overrides. PR #1953 reviewer comment #7 partially addressed. No perf impact. |
| `v20-frozen` | `backup/v20-frozen-pre-v21/` | safety snapshot | pre-v21 backup of Hebrew + Gregorian. |
| `v21` | `backup/v21-shareable-apis-accessor-helpers/` | uncommitted | Shared accessor helpers via new `_CalendarUtility` enum (5 static methods). Thinned `firstWeekday`/`minimumDaysInFirstWeek` getters/setters + `copy()` body in Hebrew + Gregorian. ~74-line duplication removed. PR #1953 comment #7 substantively addressed. No perf impact. |
| `v21-frozen` | `backup/v21-frozen-pre-v22/` | safety snapshot | pre-v22 backup of Hebrew + Gregorian + CalendarUtility. |
| `v22` | `backup/v22-shareable-apis-isDateInWeekend/` | uncommitted | `isDateInWeekend` body extracted to `_CalendarUtility.isDateInWeekend(weekday:timeInDay:weekendRange:)`. Hebrew + Gregorian thinned. Hebrew's `timeInDay` computation aligned to Gregorian's integer-truncation pattern (fixes earlier-flagged fractional-second divergence). Net -29 LOC. No perf impact. |

#### After `{m, wd, wdOrd}` fast-path extension — historical first cut (2026-05-03)

This was the original measurement after the `{m, wd, wdOrd}` fast-path
extension was added but before the YearData cache. Captured in
`bench_hebrew_results_v2.txt`. Kept here for historical context;
post-`c2668eb` numbers in the next table are the canonical reference.

| Benchmark | Gregorian | ICU-as-Hebrew | initial fast-path (`{m,d}` etc.) | `c2668eb-pre` (`{m,wd,wdOrd}` only) | vs ICU |
|---|---:|---:|---:|---:|---:|
| `nextThousandThanksgivings` | 4,805 μs | 995 μs | 1,155 μs | **4.5 μs** | **221×** |
| `nextThousandThanksgivingsSequence` | 4,840 μs | 986 μs | 1,167 μs | 1,237 μs | 0.80× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` | 1,977 μs | 445 μs | 541 μs | 559 μs | 0.80× |
| `RecurrenceRuleThanksgivings` | 3,837 μs | 2,069 μs | 3,467 μs | 3,430 μs | 0.60× |
| `RecurrenceRuleThanksgivingMeals` | 2,255 μs | 1,354 μs | 2,460 μs | 2,388 μs | 0.57× |
| `RecurrenceRuleLaborDay` | 2,854 μs | 1,637 μs | 3,138 μs | 3,069 μs | 0.53× |
| `RecurrenceRuleBikeParties` | 2,132 μs | 1,246 μs | 2,376 μs | 2,421 μs | 0.51× |
| `RecurrenceRuleDailyWithTimes` | 1,787 μs | 1,533 μs | 3,146 μs | 3,056 μs | 0.50× |

**Why the other framework benchmarks are unchanged:**

- `nextThousandThanksgivingsSequence` uses `cal.dates(byMatching:)` — the
  Swift `Sequence` API. It does NOT route through `Calendar.nextDate` /
  `Calendar.enumerateDates`, so our protocol-method fast-path isn't called.
- `nextThousandThursdaysInTheFourthWeekOfNovember` uses
  `{month, weekday, weekOfMonth}` — `weekOfMonth` is in our rejection guard
  (it'd require iso-week math), so it falls through to the generic framework.
- `RecurrenceRule*` benchmarks call `Calendar._dates(startingAfter:matching:)`
  internally, which goes directly to `_unadjustedDates` / `_adjustedDate` in
  `Calendar_Enumerate.swift` — completely bypassing `Calendar.nextDate` and
  thus our fast-path. Closing this gap requires either wiring the protocol
  method into `_dates(...)` (shared-code change) or per-calendar `YearData`
  caching to make the framework path itself faster.

**Mallocs (selected — `_CalendarHebrew` after extension vs ICU):**

| Benchmark | ICU mallocs | Hebrew mallocs (initial) | Hebrew mallocs (with ext) | Δ |
|---|---:|---:|---:|---:|
| `nextThousandThanksgivings` | 536 | 1,255 | **0** | **eliminated** |
| `nextThousandThursdaysInTheFourthWeekOfNovember` | — | 646 | 646 | unchanged |
| `RecurrenceRuleThanksgivings` | 378 | 4,056 | 4,056 | unchanged |
| `RecurrenceRuleDailyWithTimes` | 152 | 3,739 | 3,739 | unchanged |

#### Apples-to-apples through the v8–v12 stack

p50 across the canonical snapshot chain (debug-mode, Intel iMac,
Swift 6.3.1):

| Benchmark | `c2668eb-pre` | `c2668eb` | `v8` | `v9` | `v10` | `v11` | `v12` | `v13` | `v14` | `v15` | `v15` vs ICU |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `nextThousandThanksgivings` | 4,502 ns | 3,893 ns | 3,983 ns | 3,873 ns | (unchanged) | (unchanged) | 4,016 ns | 3,828 ns | 3,856 ns | 3,967 ns | ~250× |
| `nextThousandThanksgivingsSequence` | 1,237 µs | 1,096 µs | 4,248 ns | **4,133 ns** | (unchanged) | (unchanged) | 4,346 ns | 4,033 ns | 4,037 ns | 4,098 ns | ~240× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` | 553 µs | 514 µs | 537 µs | 527 µs | **4,080 ns** | (unchanged) | 4,184 ns | 4,000 ns | 4,018 ns | 4,174 ns | ~107× |
| **`RecurrenceRuleThanksgivings`** | 3,430 µs | 3,276 µs | 1,988 µs | 1,882 µs | (unchanged) | 1,688 µs | **107 µs** | 110 µs | 105 µs | 107 µs | **19× ICU** |
| **`RecurrenceRuleThanksgivingMeals`** | 2,388 µs | 2,285 µs | 1,704 µs | 1,625 µs | (unchanged) | 1,598 µs | 1,469 µs | **89 µs** | 87 µs | 88 µs | **15× ICU** |
| **`RecurrenceRuleLaborDay`** | 3,069 µs | 2,952 µs | 1,733 µs | 1,650 µs | (unchanged) | 1,637 µs | **106 µs** | 112 µs | 108 µs | 107 µs | **15× ICU** |
| **`RecurrenceRuleBikeParties`** | 2,421 µs | 2,226 µs | 1,684 µs | 1,638 µs | (unchanged) | 1,430 µs | 1,438 µs | 1,463 µs | **115 µs** | 118 µs | **10.5× ICU** |
| **`RecurrenceRuleDailyWithTimes`** | 3,056 µs | 2,979 µs | 3,089 µs | 3,028 µs | (unchanged) | 3,010 µs | 3,038 µs | 2,973 µs | 3,024 µs | **191 µs** | **~8× ICU** |
| `CurrentDateComponentsFromThanksgivings` | 5,639 µs | 5,579 µs | 6,101 µs | 5,773 µs | (unchanged) | 5,894 µs | 5,978 µs | 5,675 µs | 5,673 µs | 5,884 µs | — |

**Per-snapshot summaries** (each refers to the change adding the
described mechanism to the prior snapshot):

- **`c2668eb-pre`** (intermediate dev — `{m, wd, wdOrd}` extension only,
  before the YearData cache).
- **`c2668eb`** (committed): adds the YearData single-slot cache in
  `HebrewArithmetic`. Modest 3–8% win across the board.
- **`v8`**: wire `_calendar.nextDate` fast-path into
  `Calendar._enumerateDatesStep` (shared code). Closes the Sequence API
  gap (`nextThousandThanksgivingsSequence` 1,096 µs → 4.2 µs) and most
  of the RecurrenceRule gap.
- **`v9`**: hoist fast-path probe-and-commit into `DatesByMatching.Iterator`
  itself. Skips per-call `_enumerateDatesStep` overhead for fast-path-eligible
  patterns. Uniform 2–5% reduction across all framework benchmarks.
- **`v10`**: Hebrew `{m, wd, weekOfMonth}` fast path. The lone benchmark
  using this pattern (`nextThousandThursdaysInTheFourthWeekOfNovember`)
  collapsed from 527 µs → 4,080 ns (129× speedup; 106× ICU). Other
  benchmarks unaffected (different patterns).
- **`v11`**: helper-level hijacks at `dateAfterMatchingWeekOfMonth`
  (with month enrichment to route through the safe `{m, wd, weekOfMonth}`
  fast path) and `dateAfterMatchingWeekdayOrdinal` (harmless but unused
  for these benchmark shapes). Modest 10–13% wins on
  `RecurrenceRuleThanksgivings` and `RecurrenceRuleBikeParties`.
- **`v12`**: the home run. Single-combination short-circuit at the top
  of `_unadjustedDates` — when every populated `_DateComponentCombinations`
  field has exactly one value, translates to a `DateComponents` and calls
  `_calendarNextDate` directly, skipping the entire expansion-chain
  (months/weekdays/hours/minutes/seconds expansions + filter passes
  + DST adjustment per match). `RecurrenceRuleThanksgivings` collapsed
  from 1,688 µs → **107 µs** (15.7× speedup over v11, **19× ICU**);
  `RecurrenceRuleLaborDay` similarly to **106 µs** (15× ICU). Mallocs
  on these two dropped 95% (~2,400 → ~100). Plus helper hijacks at
  `dateAfterMatchingMonth` (minimal `{month, isLeapMonth}`) and
  `dateAfterMatchingWeekday` (minimal `{weekday}`) — these benefit
  `RecurrenceRuleThanksgivingMeals` (-7% because `dateAfterMatchingMonth`
  fires for `months=[11]`) but are no-ops on `BikeParties` (no months
  expansion) and `DailyWithTimes` (per-match cost is in framework
  machinery, not in helpers).

- **`v13`**: multi-combination cartesian short-circuit in
  `_unadjustedDates`. When the rule's combinations cartesian-product to
  N >= 2 fast-path-eligible `DateComponents` (positive ordinals only,
  no `.every` weekday, ≤64 combinations), generate them, probe each via
  `_calendarNextDate`, sort by date, return.
  `RecurrenceRuleThanksgivingMeals` (months=[11], weekdays=[.nth(4, thu)],
  hours=[14, 18]) collapsed from 1,469 µs → **89 µs** (16.5× speedup,
  **15× ICU**). Mallocs 1,767 → 79 (-96%). The other two multi-combination
  benchmarks (`BikeParties` with negative ordinal, `DailyWithTimes` with
  `.every`) remain on the slow path — `_expandedDateComponents` rejects
  those shapes to preserve raw-enumerate parity with ICU.

- **`v14`**: extended `_expandedDateComponents` to handle negative
  ordinals (`.nth(N<0, day)`) via runtime translation to
  `{month, weekday, weekOfMonth}` using the anchor's month structure.
  Routes through the existing `{m, wd, weekOfMonth}` fast path. New
  short-circuit branch (3) in `_unadjustedDates` is gated by a sentinel
  `_calendarNextDate(matching: {weekday: 1})` probe — non-Hebrew
  calendars bail before doing anchor-dependent calendar primitive calls.
  `RecurrenceRuleBikeParties` (months=nil, weekdays=[.nth(1, fri),
  .nth(-1, fri)]) collapsed from 1,463 µs → **115 µs** (12.7× speedup,
  **10.8× ICU**). Mallocs 1,743 → 127 (-93%).

- **`v15`**: time-only fast path in Hebrew `nextDate(after:matching:direction:)`.
  Removed the `!hasMonth && !hasDay && !hasWeekday → nil` rejection,
  added a branch gated on `{hour, minute, second}` all set, plus a
  `nextTimeOfDayMatch` helper (same-day if `targetSecsInDay > currentSecsInDay`,
  else next RD). For daily-frequency rules `weekdayAction == .limit`, so
  `_unadjustedDates`'s combinations contain no weekdays — only hours,
  minutes, seconds. v13's existing `_expandedDateComponents` already
  produces the 4 valid time-only DCs; the only blocker was Hebrew's
  `nextDate` rejecting them. With v15, v13's cartesian short-circuit
  fires. **Hebrew-only change** (no shared-code edits). The new gating
  deliberately matches only what `_unadjustedDates`'s short-circuits
  produce — partial time fields (e.g. `{hour: 9}` alone) still fall
  through to the generic enumerate framework, preserving ICU semantics
  where unspecified fields mean "any value".
  `RecurrenceRuleDailyWithTimes` (`.daily`, weekdays=[.every(.mon),
  .every(.tue), .every(.wed)], hours=[9,10], minutes=[0,30]) collapsed
  from 3,024 µs → **191 µs** (15.8× speedup, **~8× ICU**). Mallocs
  3,742 → 151 (-96%). Other 8 benchmarks within ±5% noise of `v14`.

**Parity verified at v15**: Suite C (`HebrewRecurrenceRuleParityProbe`)
— 13 tests, 392 rule shapes × 2,088 date comparisons against
`_CalendarICU(.hebrew)`, **0 divergences**. The `monthly_multipleNthWeekdays`
test specifically exercises the v14 negative-ordinal translation path
(BikeParties shape) and confirms the date stream matches ICU exactly.
Both fast-path-hits cases and fall-through cases match ICU. See
`backup/PARITY.md`.

**Headlines:**
- `nextThousandThanksgivingsSequence` collapsed `c2668eb-pre` → `v8` from
  1,237 µs → 4.2 µs (≈300× speedup) once `_enumerateDatesStep` was wired;
  `v9` trimmed it further to 4.1 µs via the Iterator hoist.
- `RecurrenceRuleThanksgivings` went from 1.10× ICU at `v9` to **19× ICU
  at `v12`** via the `_unadjustedDates` short-circuit.
- `v9` gave a uniform 2–5% reduction across all benchmarks (not just
  Sequence) — RecurrenceRule paths apparently also flow through
  `DatesByMatching`-style iterators in some places.

**Sequence vs block-API gap after `v9`:**
- p0 (best): block 3,746 ns vs Sequence 3,881 ns = **3.6%** (was 7.7%
  at `v8`).
- p50 (median): block 3,873 ns vs Sequence 4,133 ns = **6.7%** (unchanged
  from `v8` — fundamental Swift `IteratorProtocol` overhead).

**Mallocs at `v12`** (selected):

| Benchmark | ICU | `v12` Hebrew | Δ |
|---|---:|---:|---:|
| `nextThousandThanksgivings` | 536 | 0 | eliminated |
| `nextThousandThanksgivingsSequence` | — | 0 | eliminated |
| `RecurrenceRuleThanksgivings` | 378 | **102** | -96% from baseline (was 4,056 at `c2668eb-pre`) |
| `RecurrenceRuleLaborDay` | — | **92** | -95% from baseline |
| `RecurrenceRuleThanksgivingMeals` | — | 1,837 | -11% from baseline |
| `RecurrenceRuleBikeParties` | — | 1,757 | -12% from baseline |
| `RecurrenceRuleDailyWithTimes` | 152 | 3,739 | unchanged (no fast-path match) |

### Non-parameterized benchmarks (unchanged across runs — `.gregorian` hardcoded inside)

| Benchmark | All runs |
|---|---:|
| `allocationsForFixedCalendars` | ~20 μs |
| `allocationsForCurrentCalendar` | ~25 μs |
| `allocationsForAutoupdatingCurrentCalendar` | ~25 μs |
| `copyOnWritePerformanceNoDiff` | ~118 ns |

### Analysis

**State after `v12`:**

1. **Fast-path patterns** routed through `Calendar.nextDate` /
   `Calendar.enumerateDates` / `Calendar._enumerateDatesStep` /
   `DatesByMatching.Iterator`:
   - Shipped in `c2668eb`: `{m, d}`, `{m}`, `{d}`, `{wd}`, `{m, wd, wdOrd}`
     (+ time-of-day) — Nth-weekday-of-month.
   - Added in `v10`: `{m, wd, weekOfMonth}` (+ time-of-day).
   - Added in `v11`: `{wd, wdOrd}` (no month, uses date's current civil month).
   - These see **100–250× speedups** vs ICU. Zero mallocs.
   - The `v8` step-wiring + `v9` Iterator hoist mean the Swift `Sequence`
     API (`cal.dates(byMatching:)`) also benefits.

2. **RecurrenceRule single-combination patterns** — `RecurrenceRuleThanksgivings`,
   `RecurrenceRuleLaborDay`. The `v12` `_unadjustedDates` short-circuit
   detects these and routes through our `nextDate` fast path, skipping
   the entire expansion-chain. **15–19× ICU.**

3. **RecurrenceRule multi-combination patterns** — `RecurrenceRuleThanksgivingMeals`,
   `RecurrenceRuleBikeParties`, `RecurrenceRuleDailyWithTimes`. The
   short-circuit rejects these; the helper hijacks help only marginally.
   Still 0.50–0.92× ICU.

**Remaining cost contributors on multi-combination paths:**

- `_dateComponents(...)` decomposing the anchor (~200 ns/match)
- `dateInterval(of: .year/.month, for:)` computing search bounds (~200 ns)
- `_DateComponentCombinations` build (~100 ns)
- `_adjustedDate(...)` DST adjustment per match (~300 ns)
- `flatMap` array allocations in `_unadjustedDates` (per expansion step)
- `_limitMonths/Days/Weekdays/Time` filter passes
- `baseRecurrence.next()` advance per anchor

### What's left

- **Multi-combination RecurrenceRule patterns** — would require either
  (a) multi-stream interleaving in `_unadjustedDates` to handle
  multi-valued combinations, or (b) hoisting the entire fast-path into
  `DatesByRecurring.Iterator` (more invasive — see
  `backup/RECURRENCE_VS_NEXTDATE.md` for the analysis).
- **`RecurrenceRuleDailyWithTimes`** specifically would also benefit from
  fast-path extension to handle multi-valued time-of-day combinations
  (12 dates per day × 1000 days = 12,000 dates; currently ~250 ns/date).

## Why we want this in the upstream PR

The local `Tests/.../HebrewVsICUBenchmark.swift` numbers (see
`BENCHMARK_TESTS.md`) are debug-mode and machine-dependent — useful for
local iteration but not strong evidence for an upstream PR.

The package benchmark target:
- Runs in release mode by default (under the swift-benchmark harness).
- Captures CPU + malloc + RSS, not just wall-clock time.
- Has built-in baseline/regression tracking.
- Is what the swift-foundation maintainers use to gate performance
  claims in PR descriptions.

Hebrew benchmarks added here are the strongest possible support for the
"_CalendarHebrew is X× faster than ICU on workload Y" narrative. They
also serve as a regression net for future Hebrew port refactors.

## Caveats

- **Release-mode `swift package benchmark` may have its own crash issues**
  on Intel x86_64 + Swift 6.3.1 (parallel to the
  `swiftpm-testing-helper` SIGBUS in `swift test --release`).
  Verify before promising release-mode numbers; if blocked, document
  debug-mode numbers with the qualifier and revisit on Apple Silicon
  or a newer toolchain.
- **`Calendar(inner:)` is internal API** — using it from a benchmark target
  works (Benchmarks targets can `@testable import`) but creates a
  baseline-vs-impl comparison that's only meaningful while ICU and our
  port both exist. Once `_CalendarICU` is removed (or the router flip is
  permanent), the ICU side of the comparison will need to be revisited
  or removed.
- **`Calendar.current` semantics differ from `Calendar(identifier:)`** —
  the existing `allocationsForCurrentCalendar` benchmark uses
  `Calendar.current`. For Hebrew comparisons, prefer
  `Calendar(identifier: .hebrew)` to keep the comparison clean.
