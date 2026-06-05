# Fast paths: what's where, and what each layer bought us

One-page reference. For deep details on any layer, follow the cross-reference column.

## Currently committed on `port/hebrew` (HEAD = `c2668eb`)

Two commits introduce the fast-path infrastructure:

| Commit | Adds |
|---|---|
| `8663837` | `_CalendarProtocol.nextDate(after:matching:direction:) -> Date?` (default `nil`). `Calendar.nextDate` / `Calendar.enumerateDates` consult it before falling through to the generic enumerate framework. Hebrew `nextDate` handles `{m, d}`, `{m}`, `{d}`, `{wd}` + optional time-of-day. |
| `c2668eb` | Hebrew `nextDate` extended with `{m, wd, wdOrd}` and `{wd, wdOrd}` (no-month). Single-slot `YearData` cache in `HebrewArithmetic`. |

A parallel branch `origin/port/hebrew-main` is the upstream-bound clean shape (based on Foundation's `main` branch, Swift 6.4-targeted). It has all of `port/hebrew`'s commits up through `c2668eb`, plus two grooming commits: `46725dd` (LockedState → Mutex for Swift 6.4) and `04783dc` (icu4swift provenance comment cleanup + removal of probe/regression test files that reference `_CalendarICU`). The v16 layer below backports those source-only changes into `port/hebrew`.

Committed Hebrew `nextDate` accepts these `DateComponents` shapes (each with optional `{h, mi, s, ns}`):

- `{month, day}` — annual; `nextMonthDayMatch`
- `{month}` — month-only (day defaults to 1); `nextMonthDayMatch`
- `{day}` — month-walking (e.g. 1st of every month); `nextMonthDayMatch`
- `{weekday}` — RD-modular; `nextWeekdayMatch`
- `{month, weekday, weekdayOrdinal}` — Nth weekday of month; `nextMonthWeekdayOrdinalMatch`
- `{weekday, weekdayOrdinal}` — Nth weekday no-month; `nextWeekdayOrdinalMatch`

Rejects (returns nil → generic framework handles): `era`, `year`, `weekOfYear`, `yearForWeekOfYear`, `dayOfYear`, `weekOfMonth`, `weekday + day` combos, time-only DCs.

## Uncommitted stack on top of `c2668eb` (v8 → v22)

Each layer is in `backup/vN-*/` with its own README. **All parity-verified at v22 against `_CalendarICU(.hebrew)` via Suite C** (392 rule shapes × 2,088 date comparisons, 0 divergences).

| Layer | Touched | Mechanism | Headline benchmark | Pre → post (µs) | Speedup | vs ICU |
|---|---|---|---|---:|---:|---:|
| **v8** | shared (`Calendar.swift`, `Calendar_Enumerate.swift`) | Wire `_calendar.nextDate` into `_enumerateDatesStep` so the Sequence API and step-level enumerators benefit too | `nextThousandThanksgivingsSequence` | 1,096 → 4.2 µs | ~260× | ~244× |
| **v9** | shared (`Calendar_Enumerate.swift`) | Hoist `_calendarNextDate` probe-and-commit into `DatesByMatching.Iterator` init; skip per-call step overhead | (uniform across) | 2–5% trim | — | — |
| **v10** | Hebrew (`Calendar_Hebrew.swift`) | Add `{m, wd, weekOfMonth}` fast path | `nextThousandThursdaysInTheFourthWeekOfNovember` | 527 → 4.1 µs | ~129× | ~111× |
| **v11** | shared (`Calendar_Enumerate.swift`) + Hebrew | Hijack `dateAfterMatchingWeekOfMonth` / `dateAfterMatchingWeekdayOrdinal` to route through Hebrew's fast path with month enrichment; add `{wd, wdOrd}` no-month support | `RecurrenceRuleThanksgivings` | 1,882 → 1,688 µs | 1.1× | 0.97× |
| **v12** | shared (`Calendar_Recurrence.swift`) + tests | `_unadjustedDates` single-combination short-circuit + `dateAfterMatchingMonth` / `dateAfterMatchingWeekday` hijacks. Adds `HebrewRecurrenceRuleParityProbe` (Suite C). | `RecurrenceRuleThanksgivings` | 1,688 → 107 µs | 15.8× | **19× ICU** |
| **v13** | shared (`Calendar_Recurrence.swift`) | When a rule has multi-valued fields (e.g. `hours = [14, 18]`), list out every combination upfront (`{Nov, 4th Thu, 14:00}`, `{Nov, 4th Thu, 18:00}`) and ask the calendar's fast path for each. Skip the expand-and-filter pipeline entirely. Falls back to the pipeline if any combination isn't fast-path-eligible. Positive ordinals only. | `RecurrenceRuleThanksgivingMeals` | 1,469 → 89 µs | 16.5× | **15× ICU** |
| **v14** | shared (`Calendar_Recurrence.swift`) | Same trick as v13, extended to handle negative weekday ordinals (e.g. `last Friday`). Translates them at runtime to a `{month, weekday, weekOfMonth}` shape using the anchor's month structure, which Hebrew's existing fast path handles. | `RecurrenceRuleBikeParties` | 1,463 → 115 µs | 12.7× | **10.8× ICU** |
| **v15** | Hebrew (`Calendar_Hebrew.swift`) | For daily-frequency rules with weekday filters, the combinations passed in are time-only (`{hour, minute, second}`). Hebrew used to reject these. v15 accepts them, so v13's same-trick combination-listing kicks in. The weekday filter still runs as a post-pass. | `RecurrenceRuleDailyWithTimes` | 3,024 → 191 µs | 15.8× | **~8× ICU** |
| **v16** | Hebrew (`Calendar_Hebrew.swift`) | Sync from `port/hebrew-main`: `LockedState` → `Mutex` for the YearData cache, `var newYear` → `let` warning fix, removed icu4swift provenance from doc comments. No perf impact — code-shape sync only. | (no headline) | — | — | — |
| **v17** | Hebrew (`Calendar_Hebrew.swift`) + Tests + Benchmarks | Sync from `port/hebrew-main`'s PR-feedback commit `ef191c1`: strip 10 lines of unused libc imports from Hebrew, parameterize `HebrewDSTPolicyParityTests.swift` (better failure output, same semantics), delete `HebrewCalendarPerformanceTests.swift` (functionality moved to `BenchmarkCalendar.swift`), replace `BenchmarkCalendar.swift` with upstream version (adds 5 Hebrew-specific package benchmarks). No perf impact — code/test-shape sync only. | (no headline) | — | — | — |
| **v18** | Hebrew (`Calendar_Hebrew.swift`) | Sync from `port/hebrew-main`'s PR-feedback commit `26c1377` (round 2): trim verbose comments at 12 sites in `Calendar_Hebrew.swift` and add `// TODO` for shared weekend logic. Comment-only, no code changes, -88/+16 lines net. | (no headline) | — | — | — |
| **v19** | Hebrew + Gregorian + NEW `CalendarConstants.swift` | SHAREABLE_APIS Tier 0: extracted 5 time-unit constants (`kSecondsInWeek/Day/Hour/Minute`, `inf_ti`) to `internal enum _CalendarConstants`. Removed instance declarations from both calendars; updated 29 Gregorian callsites + 1 Hebrew callsite. PR #1953 reviewer comment #6 addressed. | (no headline) | — | — | — |
| **v20** | Hebrew + Gregorian + `Calendar_Protocol.swift` | SHAREABLE_APIS — `hash(into:)` default impl in `_CalendarProtocol` extension. Removed identical hash impls from Hebrew + Gregorian. Three conformers keep specialized overrides (Autoupdating sentinel, ICU locked accessors, Bridged underlying NSCalendar). PR #1953 reviewer comment #7 partially addressed. | (no headline) | — | — | — |
| **v21** | Hebrew + Gregorian + NEW `CalendarUtility.swift` | SHAREABLE_APIS — shared accessor helpers (`firstWeekday`/`minimumDaysInFirstWeek` getters/setters + `copy()` body) via 5 static methods on new `_CalendarUtility` enum. Thinned Hebrew + Gregorian by ~74 lines combined. No protocol changes, no composition struct, no class-layout changes. PR #1953 comment #7 substantively addressed. | (no headline) | — | — | — |
| **v22** | Hebrew + Gregorian + `CalendarUtility.swift` | SHAREABLE_APIS — `isDateInWeekend` body extracted to `_CalendarUtility`. Net -29 LOC. Side benefit: Hebrew's `timeInDay` now uses integer truncation (matching Gregorian), fixing previously-flagged fractional-second divergence. | (no headline) | — | — | — |

## Cross-reference

| Topic | Read |
|---|---|
| Per-layer details + restoration | `backup/vN-*/README.md` (one per snapshot) |
| Apples-to-apples table v8 → v15, all 9 benchmarks | `backup/BENCHMARKS_PACKAGE.md` § "Apples-to-apples through the v8–v15 stack" |
| How to run benchmarks (footguns) | `backup/BENCHMARKS_PACKAGE.md` § Running |
| Why each shared-code change is safe for non-Hebrew | `backup/SHARED_CODE_SAFETY.md` |
| Multi-combination analysis history | `backup/RECURRENCE_VS_NEXTDATE.md` |
| Hebrew parity vs ICU | `backup/PARITY.md` |
| Cold-resume entrypoint | `backup/HANDOFF.md` |
| Merging v8–v15 onto `port/hebrew-main` (upstream-bound branch) | `backup/MAIN_MERGE.md` |
| Post-PR-1953 follow-up refactor (extract shared `_CalendarHebrew`/`_CalendarGregorian` logic to a common base) | `backup/SHAREABLE_APIS.md` |

## At v15 — vs ICU, all 9 calendar benchmarks (debug-mode, p50)

| Benchmark | v15 | vs ICU |
|---|---:|---:|
| `nextThousandThanksgivings` | 3.97 µs | ~250× |
| `nextThousandThanksgivingsSequence` | 4.10 µs | ~240× |
| `nextThousandThursdaysInTheFourthWeekOfNovember` | 4.17 µs | ~107× |
| `RecurrenceRuleThanksgivings` | 107 µs | 19× |
| `RecurrenceRuleThanksgivingMeals` | 88 µs | 15× |
| `RecurrenceRuleLaborDay` | 107 µs | 15× |
| `RecurrenceRuleBikeParties` | 118 µs | 10.5× |
| `RecurrenceRuleDailyWithTimes` | 191 µs | ~8× |
| `CurrentDateComponentsFromThanksgivings` | 5,884 µs | — *(not exercising Hebrew — uses `Calendar.current`; see SESSION_2026-05-04.md § 6)* |

8 of 9 calendar benchmarks ≥8× ICU. Single remaining "—" is a benchmark wiring issue, not a calendar gap.

## Two open items before upstream PR (unchanged from v14)

- **#11** — Hebcal fixture-size decision (sole pre-PR blocker; update `HebrewRegressionTests.swift` to load from a SwiftPM resource bundle).
- **#37** — Commit strategy for v8–v15 stack: one PR vs split shared-code (`Calendar.swift`, `Calendar_Enumerate.swift`, `Calendar_Recurrence.swift`) into a separate upstream PR and Hebrew-specific stays on `port/hebrew`. `SHARED_CODE_SAFETY.md` is the cover note for the shared-code PR.
