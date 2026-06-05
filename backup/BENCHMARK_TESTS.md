# Benchmark & ad-hoc correctness tests (not committed)

> **See also: [`BENCHMARKS_PACKAGE.md`](BENCHMARKS_PACKAGE.md)** — covers the
> swift-benchmark (Ordo One) package target at `Benchmarks/`, which is
> upstream-committed and runs via `swift package benchmark` with real
> metrics (CPU, mallocCount, peakMemoryResident, throughput). This file
> covers our **local research** benchmarks living in `Tests/...`, run via
> `swift test`, debug-mode timing only.

These tests live in the working tree but are **deliberately not in the Hebrew
port PR**. They're investigation/research tools — useful for capturing
performance numbers, validating fast-path correctness, and tracking
regressions during development. They will be removed (or moved into a
separate testing-utilities target) before the Hebrew port lands upstream.

All four files live in `Tests/FoundationInternationalizationTests/`:

| File | Purpose |
|---|---|
| [`HebrewVsICUBenchmark.swift`](#hebrewvsicubenchmark) | ICU baseline vs `_CalendarHebrew`, GMT + LA, best of 10 |
| [`AllocationsBreakdown.swift`](#allocationsbreakdown) | Splits construction cost from arithmetic cost |
| [`EnumerateBreakdown.swift`](#enumeratebreakdown) | 3-layer cost breakdown of `nextThousandHanukkahs` |
| [`EnumerateMicroProfile.swift`](#enumerationmicroprofile) | Fast-path vs generic framework + extended-pattern correctness |

## Running

All tests use the standard Swift Testing framework. Run individual benchmarks with:

```sh
cd ~/Projects/claude/swift-foundation
export SWIFTCI_USE_LOCAL_DEPS=1
swift test --filter "<test name>"
```

Or run all benchmarks at once:

```sh
swift test --filter "benchmark_|fullBreakdown|protocolCallsOnly|directNextHanukkah|extendedFastPath"
```

All numbers are **debug mode**. Release-mode timing is not yet possible on
Intel x86_64 + Swift 6.3.1 due to the `swiftpm-testing-helper` SIGBUS
(see `OPEN_ISSUES.md` #3). Numbers reproduce well within ~10% across runs;
absolute timings differ by hardware (ratios are stable).

---

## HebrewVsICUBenchmark

ICU (`_CalendarICU(.hebrew)`) vs `_CalendarHebrew`, both wrapped in
`Calendar(inner:)`. 10 timed runs each, reports `min/max ns·µs/iter`.

| `@Test func` | What it measures |
|---|---|
| `benchmark_nextThousandHanukkahs` | `{month: 3, day: 25}` × 1000 matches via `Calendar.enumerateDates`. Hits the fast path when wired. |
| `benchmark_nextThousandHanukkahsWithTime` | `{month: 3, day: 25, hour: 18, minute: 30, second: 0}` × 1000. Tests time-of-day preservation. |
| `benchmark_nextThousandRoshChodesh` | `{day: 1}` × 1000. Tests month-walk fast path. |
| `benchmark_nextThousandTishriStarts` | `{month: 1}` × 1000. Tests month-only fast path (day defaults to 1). |
| `benchmark_nextThousandSaturdays` | `{weekday: 7}` × 1000. Tests weekday RD-modular fast path. |
| `benchmark_allocations` | 100 fresh `Calendar` constructions + day-add. Measures heap-allocation cost. |
| `benchmark_copyOnWrite` | 100 mutations triggering CoW. Measures `_CalendarHebrew` value-type advantage. |
| `benchmark_roundTrip` | `dateComponents → date(from:)` round-trip × 10,000. |

### Headline numbers — Intel iMac, debug mode (2026-05-01)

**Enumerate fast paths (with wiring + extended patterns):**

| Pattern | TZ | ICU (µs/match) | Hebrew (µs/match) | Speedup |
|---|---|---:|---:|---:|
| `{m, d}` | GMT | 1,447 | 2 | 723× |
| `{m, d, h, m, s}` | GMT | 1,910 | 2 | 955× |
| `{day: 1}` | GMT | 1,570 | 2 | 785× |
| `{month: 1}` | GMT | 186 | 2 | 93× |
| `{weekday: 7}` | GMT | 432 | 1 | 432× |
| `{m, d}` | LA | 1,518 | 3 | 506× |
| `{m, d, h, m, s}` | LA | 1,095 | 2 | 547× |
| `{day: 1}` | LA | 1,194 | 2 | 597× |
| `{month: 1}` | LA | 202 | 3 | 67× |
| `{weekday: 7}` | LA | 474 | 1 | 474× |

**Other benchmarks (no fast path needed — pure-Swift wins):**

| Benchmark | TZ | ICU (ns/iter) | Hebrew (ns/iter) | Speedup |
|---|---|---:|---:|---:|
| `roundTrip` | GMT | 12,052 | 4,854 | 2.5× |
| `roundTrip` | LA | 14,178 | 5,735 | 2.5× |
| `allocations` | GMT | 34,753 | 905 | 38× |
| `allocations` | LA | 66,559 | 1,531 | 43× |
| `copyOnWrite` | GMT | 34,995 | 1,024 | 34× |
| `copyOnWrite` | LA | 69,507 | 1,648 | 42× |

---

## AllocationsBreakdown

Separates the alloc-benchmark speedup into construction-cost and
arithmetic-cost components.

| `@Test func` | What it measures |
|---|---|
| `fullBreakdown` | 3 layers: <br>**1.** `_CalendarX` construction only (Hebrew is 50–80× cheaper than ICU's heap `icu::HebrewCalendar`).<br>**2.** `date(byAdding: .day, value: 1)` only (7–9× — the calendar arithmetic).<br>**3.** Construct + day-add together (matches the headline `benchmark_allocations` number). |

### Headline (Intel iMac, debug mode)

| Layer | TZ | ICU (ns/iter) | Hebrew (ns/iter) | Speedup |
|---|---|---:|---:|---:|
| Construction only | GMT | 18,139 | 311 | 58× |
| Construction only | LA | 20,358 | 263 | 77× |
| `date(byAdding: .day)` | GMT | 5,781 | 709 | 8.2× |
| `date(byAdding: .day)` | LA | 8,100 | 1,135 | 7.1× |
| Construction + day-add | GMT | 27,981 | 986 | 28× |
| Construction + day-add | LA | 60,421 | 1,485 | 41× |

Conclusion: most of the alloc-benchmark win comes from avoiding ICU's C++
heap-object construction. Pure-Swift arithmetic is ~7–9× faster on top of that.

---

## EnumerateBreakdown

Decomposes the cost of `nextThousandHanukkahs` into 3 framework layers.

| `@Test func` | What it measures |
|---|---|
| `fullBreakdown` | Per match, in 4 layers:<br>**1.** Direct: `dateComponents` + `date(from:)` (2 protocol calls).<br>**1b.** Pure Hebrew arithmetic: `hebrewFromFixed` + `fixedFromHebrew` (no protocol dispatch, no `DateComponents`).<br>**2.** Manual month-loop: simulates enumerate's inner loop (~12 protocol calls per match).<br>**3.** Full `enumerateDates` framework. |

### Headline — GMT (Intel iMac)

| Layer | What | ICU | Hebrew | Speedup |
|---|---|---:|---:|---:|
| 1 | Direct (decompose + construct) | 50 µs | 6 µs | 8.3× |
| 1b | Pure arithmetic (Hebrew only) | — | 5 µs | — |
| 2 | Manual month-loop | 329 µs | 201 µs | 1.6× |
| 3 | Full `enumerateDates` (no fast path) | 641 µs | 598 µs | 1.07× |

Conclusion: real calendar-arithmetic advantage is **8×**, but Foundation's
shared enumerate framework adds ~245–280 µs of constant overhead per match,
diluting the visible ratio at Layer 3 to ~1.07×. The fast-path wiring
bypasses the framework entirely — see `EnumerateMicroProfile`.

---

## EnumerateMicroProfile

Isolates protocol-dispatch cost vs framework cost; verifies fast-path
correctness against ICU.

| `@Test func` | What it measures |
|---|---|
| `protocolCallsOnly` | Bare `dateComponents` + `date(byAdding: .day)` per call (2 calls = 1 "match"). Measures protocol-dispatch cost in isolation. |
| `directNextHanukkah` | 3 things in one test: <br>**1.** `_CalendarHebrew.nextDate(after:matching:)` direct call.<br>**2.** Wrapper `Calendar.enumerateDates` (now wired).<br>**3.** Comparison: 20 dates from each, expects 0 mismatches. |
| `extendedFastPath_correctnessVsICU` | 9 component patterns × 50–100 matches each, compared to **ICU's `enumerateDates`** as ground truth. Expects 0 divergences. Critical for verifying the new fast paths. |

### Headline — GMT (Intel iMac)

| Measurement | Value |
|---|---|
| `protocolCalls` ICU | 17,493 ns/call-pair |
| `protocolCalls` Hebrew | 15,416 ns/call-pair |
| `directNextHanukkah` Hebrew | 5 µs/match |
| `enumerateHanukkah` Hebrew (wired) | 619 µs/match (without wiring) → **~1 µs/match** (with wiring) |
| `fastPath nextDate` Hebrew direct | **1,403 ns/match** |
| `fastPath` vs Hebrew enumerate (no wiring) | **441×** |

### `extendedFastPath_correctnessVsICU` patterns

| Pattern | Description | Matches checked |
|---|---|---:|
| `{m: 3, d: 25}` | Hanukkah baseline | 50 |
| `{m: 3, d: 25, h: 18, mi: 30}` | Hanukkah at 18:30 | 50 |
| `{m: 8, d: 15, h: 19}` | Passover at 19:00 | 50 |
| `{m: 1}` | Tishri 1 each year | 50 |
| `{m: 1, h: 6}` | Tishri 1 at 06:00 | 50 |
| `{d: 1}` | Rosh Chodesh | 100 |
| `{d: 15, h: 12}` | Mid-month at noon | 100 |
| `{wd: 7}` | Every Saturday | 100 |
| `{wd: 2, h: 9, mi: 0}` | Every Monday at 09:00 | 100 |

**Result: 0 divergences from ICU across all patterns** (verified 2026-05-01).

---

## Why these aren't in the PR

1. **Performance benchmarks shouldn't gate CI** — they're noisy on shared
   runners and don't measure correctness.
2. **Layer-by-layer breakdowns are research artifacts** — useful when
   investigating a slowdown, dead weight in steady state.
3. **The correctness tests overlap** with what's already covered by Suite
   A and Suite B parity probes. The `extendedFastPath_correctnessVsICU`
   test was added during fast-path development; once the fast path is
   exercised by the Hebrew Suite B probes (which is already true), it's
   redundant for CI.

When the Hebrew port is upstreamed, these files stay in
`backup/benchmarks/` (or similar local-only location) for ongoing
development. If/when the fast-path infrastructure becomes a separate PR,
`extendedFastPath_correctnessVsICU` should be promoted into a real test
file.
