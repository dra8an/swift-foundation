# Draft PR description — Buddhist + Japanese calendars (pure Swift)

> Status: DRAFT, written 2026-06-11. To be used when the combined PR is cut
> from `port/buddhist-japanese-main` after PR #2028 merges. Numbers are
> debug-mode Intel; re-capture on Apple Silicon before posting.

---

## Add pure-Swift Buddhist and Japanese calendars behind feature flags

### Summary

Implements `_CalendarBuddhist` and `_CalendarJapanese` as pure-Swift
calendar backends, following the `_CalendarHebrew` precedent (#1953):
gated behind feature flags in `Calendar_Cache.swift` (off by default),
validated against the existing ICU-backed implementations with
zero-divergence parity suites.

Both calendars share Gregorian day/month/week structure and differ only in
year/era reckoning, so they are implemented by **composition over
`_CalendarGregorian`** rather than re-implementing arithmetic:

- **`_CalendarBuddhist`** (~140 LOC): Thai Solar Buddhist calendar.
  Year = Gregorian + 543, single era (BE). All arithmetic forwards to the
  wrapped `_CalendarGregorian`; only era/year components are mapped.
- **`_CalendarJapanese`** (~450 LOC): Japanese imperial calendar.
  237-era table (Taika 645 → Reiwa 2019) sourced from CLDR
  `supplementalData.txt`, sorted descending for newest-first lookup.
  Years are era-relative; era boundaries are exact Gregorian dates.
  When `date(from:)` receives a year without an era, the latest era is
  assumed (matching ICU's behavior, and required by the generic
  enumeration machinery, which round-trips year-in-era without era).

`bridgeToNSCalendar()` is implemented for both (and for `_CalendarHebrew`,
replacing its placeholder) via `_NSSwiftCalendar(calendar: Calendar(inner:
self))` — the same pattern `_CalendarGregorian` uses.

### Correctness

Each calendar is validated by three parity suites against the ICU-backed
implementation (constructed directly, independent of the feature flag):

| Suite | Buddhist | Japanese |
|---|---|---|
| A — protocol-level fields/intervals/ordinality | ~1,162 checks | ~35,000 checks incl. all 237 eras |
| B — public `Calendar` API surface (8 topics: DST, locale variants, boundaries, era transitions, enumeration) | ~10,000 checks | ~600 anchors × full surface |
| C — `RecurrenceRule` streams | 140 comparisons | 5 generic + 3 era-transition tests |

**Zero divergences** across all suites, with three documented ICU quirks
excluded:

1. ICU returns `quarter = 0` at year-wrap dates (both calendars).
2. ICU's Japanese `dateInterval(of: .era)` ends an era at the *start
   month/day* projected into the next era's start year (e.g. Heisei "ends"
   2019-01-08 rather than the actual Reiwa accession 2019-05-01). The Swift
   implementation returns the true `[era.start, nextEra.start)` interval.
3. The Meiji era start is encoded as **1868-09-08** to match ICU runtime
   behavior; CLDR's canonical value is 1868-10-23. Flagged with a TODO —
   input from maintainers on the authoritative source is welcome.

### Performance — relative to the pure-Swift Gregorian calendar

Because both calendars delegate to `_CalendarGregorian`, the relevant
question is what the composition layer costs. Identical benchmark bodies
were run for all three calendars (`Benchmarks/.../BenchmarkCalendar.swift`,
new mirrored `*Calendar-*` blocks; debug mode, p50):

| Shape | Gregorian | Buddhist | Japanese |
|---|---:|---:|---:|
| construct + `date(byAdding: .day)` | 20,705 ns | 20,837 ns | 19,743 ns |
| copy-on-write (`firstWeekday` set) | 566 ns | 783 ns | 782 ns |
| `dateComponents([.y, .m, .d])` | 54 ns | 59 ns | 126 ns |
| components → `date(from:)` round-trip | 73 ns | 80 ns | 163 ns |

- **Buddhist is Gregorian within noise** on every shape (the year offset is
  a single integer add).
- **Japanese adds ~70–90 ns** on component extraction and round-trips —
  the era lookup (a probe of the Gregorian y/m/d plus a short walk of the
  descending era table; modern dates resolve in ≤5 steps). A follow-up can
  fold era resolution into a single pass if this matters.
- CoW adds ~215 ns for re-wrapping the inner Gregorian on copy.

No regressions to existing benchmarks. Three pre-existing benchmark
crashes are also fixed in this PR (machine-dependent `en_US` asserts and
an invalid `firstWeekday = 0`), so the benchmark target now runs clean.

### Test plan

- [ ] `swift test` — full suite (1448 tests / 115 suites at time of writing)
- [ ] Parity suites A/B/C for both calendars — zero divergences
- [ ] `swift package benchmark run --target InternationalizationBenchmarks` — runs clean, no crashes
- [ ] Feature flags off by default — `Calendar(identifier: .buddhist/.japanese)` behavior unchanged until enabled
