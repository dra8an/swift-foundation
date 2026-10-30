# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-30 at about 09:40 on Apple Silicon (macOS 26),
`run_benchmarks.sh` K=3 (min over interleaved runs, each itself min-over-9),
release builds, at `22af5f68`. Includes every optimization through §51 (am):
new since the 2026-10-29 baseline are the Foundation wrapper steps — (aj)
lock-free reads of the collator cache slots, (ak) the cached collator used in
place with the default-options compare, (am) a fast path for two `String`
arguments in the generic wrappers. The engine did not change (Table 1).

**Machine state:** 1-minute load 62 at the start of run B, 49 at its end
(run A: 42 → 62); on AC power, under `caffeinate -i`, 18 minutes after a
wake (09:16), during the post-wake burst (15-minute load 115 → 93). **The
tables show run B** (the convention). Recorded on these grounds (the control
decides, not the load — Docs/27), with the drift stated:

1. **The system-ICU control (Table 2) is within 3% of the reference, but
   near the limit: +1.1..+2.8% in run B** (`localizedCompare`
   199/369/378/306/508 against 194/365/369/300/494; run A
   198/369/376/306/509). ICU C: compare 0..+2.0%, sortKey −0.5..+1.9%
   against the 2026-10-29 gates. So every cell of this run, ours included,
   reads about 2% slow; the gains against 2026-10-29 are slightly larger
   than shown.
2. **Runs A and B agree:** Table 1 within 1.8% (ours and ICU C).

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout: ICU 79.1 with Unicode 18 data, not the 79.0.1 data that our
collator bundles. On 2026-10-23 the checkout was on branch `main` (headers
79.1), with the libraries unchanged since 2026-10-21 14:45 (built on the
CLDR 49 integration branch `ICU-23250-CLDR-79-integration-beta4`). Its speed
matches 79.0.1, so the ratios stay comparable. Its KEYS do not: do not
generate golden files from that checkout (technique log §49).

**The harness:** the Swift loop costs about 1 ns per call more than the C
loop, and that is the call shape of our API (`throws`, two `String`
arguments, `options`), which every caller pays. `bench_icu` gives
`ucol_getSortKey` UTF-16 that it converted before its timer, because that
function takes UTF-16 only; that stays by decision. Details: Docs/27, "What
the harness itself costs".

Same Foundation APIs, two backends:

- **Swift Collator**: `BenchFoundation`, release, `-no-WMO` (Docs/27 —
  required on machine 1, a handicap here, so these UNDERSTATE the framework
  build)
- **System ICU**: pre-compiled `bench_system` (system Foundation → NSString →
  CoreFoundation → ICU)

Table 2 values are whole nanoseconds (both sources truncate, the same way in
every run).

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    40 |       199 | **4.97× faster** |
| Latin  |    41 |       369 | **9.00× faster** |
| CJK    |    61 |       378 | **6.20× faster** |
| Paths  |    57 |       306 | **5.37× faster** |
| Thai   |   258 |       508 | **1.97× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    54 |       200 | **3.70× faster** |
| Latin  |    55 |       359 | **6.53× faster** |
| CJK    |    83 |       369 | **4.45× faster** |
| Paths  |    75 |       328 | **4.37× faster** |
| Thai   |   273 |       495 | **1.81× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    53 |       201 | **3.79× faster** |
| Latin  |    54 |       358 | **6.63× faster** |
| CJK    |    83 |       371 | **4.47× faster** |
| Paths  |    73 |       314 | **4.30× faster** |
| Thai   |   271 |       495 | **1.83× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    44 |       317 | **7.20× faster** |
| Latin  |    41 |       482 | **11.76× faster** |
| CJK    |    63 |       489 | **7.76× faster** |
| Paths  |    62 |       416 | **6.71× faster** |
| Thai   |   261 |       640 | **2.45× faster** |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    69 |       317 | **4.59× faster** |
| Latin  |    71 |       472 | **6.65× faster** |
| CJK    |   101 |       485 | **4.80× faster** |
| Paths  |    92 |       425 | **4.62× faster** |
| Thai   |   295 |       572 | **1.94× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   234 |      1012 | **4.32× faster** |
| Latin  |   260 |      1454 | **5.59× faster** |
| CJK    |   273 |      1297 | **4.75× faster** |
| Paths  |   234 |       990 | **4.23× faster** |
| Thai   |   256 |      1411 | **5.51× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   233 |      1027 | **4.41× faster** |
| Latin  |   261 |      1512 | **5.79× faster** |
| CJK    |   275 |      1307 | **4.75× faster** |
| Paths  |   192 |       998 | **5.20× faster** |
| Thai   |   258 |      1462 | **5.67× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   299 |      1018 | **3.40× faster** |
| Latin  |   325 |      1456 | **4.48× faster** |
| CJK    |   294 |      1295 | **4.40× faster** |
| Paths  |   289 |      1001 | **3.46× faster** |
| Thai   |   390 |      1463 | **3.75× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    95 |       329 | **3.46× faster** |
| Latin  |   354 |       797 | **2.25× faster** |
| CJK    |   320 |       593 | **1.85× faster** |
| Paths  |   111 |       318 | **2.86× faster** |
| Thai   |   399 |       729 | **1.83× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    96 |       332 | **3.46× faster** |
| Latin  |   312 |       829 | **2.66× faster** |
| CJK    |   316 |       598 | **1.89× faster** |
| Paths  |   149 |       514 | **3.45× faster** |
| Thai   |   335 |       780 | **2.33× faster** |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2014 |     15144 | **7.52× faster** |
| Latin  |  2092 |     17795 | **8.51× faster** |
| CJK    |  3630 |     18812 | **5.18× faster** |
| Paths  |   225 |      1299 | **5.77× faster** |
| Thai   |  1196 |      5844 | **4.89× faster** |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  1722 |      5197 | **3.02× faster** |
| Latin  |  1790 |      7637 | **4.27× faster** |
| CJK    |  2224 |      7939 | **3.57× faster** |
| Paths  |   156 |       487 | **3.12× faster** |
| Thai   |   977 |      2513 | **2.57× faster** |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  3488 |     16866 | **4.84× faster** |
| Latin  |  3609 |     19376 | **5.37× faster** |
| CJK    |  5257 |     20885 | **3.97× faster** |
| Paths  |   312 |      1388 | **4.45× faster** |
| Thai   |  1698 |      6451 | **3.80× faster** |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2495 |     16702 | **6.69× faster** |
| Latin  |  2591 |     19404 | **7.49× faster** |
| CJK    |  4129 |     20537 | **4.97× faster** |
| Paths  |   231 |      1347 | **5.83× faster** |
| Thai   |  1340 |      6228 | **4.65× faster** |

### The sort rows

One op is one ELEMENT of a sort. Swift's sort makes about 14 comparisons
per element on these 200-line corpora (counted; not n·log2(n) ≈ 7.6), so ns
per element ≈ 14 × (ns per comparison) plus the sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B. **Speedup = ICU C / ours: above 1 means ours is
faster** — the same convention as Table 2. Since 2026-10-29, when every
compare and sortKey row reached ICU C, Table 1 shows the speedup; before,
it showed the ratio ours / ICU (below 1 = faster), and older text in this
file's history and in the technique log uses that ratio.

| Corpus | compare | ICU | speedup | sortKey (inout) | ICU | speedup | sortKey (alloc) | speedup |
|--------|---------|-----|---------|---------|-----|---------|---------|---------|
| ASCII  |     9.4 |   9.4 | **1.00× (equal)** |    76.9 | 105.9 | **1.38× faster** |   130.7 | 0.81× (slower) |
| Latin  |    10.0 |  10.3 | **1.03× faster** |    97.3 | 123.3 | **1.27× faster** |   152.2 | 0.81× (slower) |
| CJK    |    19.7 |  41.3 | **2.10× faster** |   107.3 | 119.6 | **1.11× faster** |   158.3 | 0.76× (slower) |
| Paths  |    18.9 |  30.0 | **1.59× faster** |   189.5 | 371.6 | **1.96× faster** |   235.9 | 1.58× faster |
| Thai   |   167.5 | 176.1 | **1.05× faster** |   152.3 | 157.6 | **1.03× faster** |   204.2 | 0.77× (slower) |

Change against the 2026-10-29 baseline (run B). The engine did not change;
this run reads about 2% slow on every column (see the controls above):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 9.3 → 9.4 (1.00× → 1.00×) | 75.0 → 76.9 (1.39× → 1.38×) |
| Latin  | 9.7 → 10.0 (1.04× → 1.03×) | 95.0 → 97.3 (1.27× → 1.27×) |
| CJK    | 19.3 → 19.7 (2.11× → 2.10×) | 105.2 → 107.3 (1.12× → 1.11×) |
| Paths  | 18.8 → 18.9 (1.60× → 1.59×) | 179.8 → 189.5 (2.08× → 1.96×) |
| Thai   | 164.9 → 167.5 (1.05× → 1.05×) | 149.3 → 152.3 (1.04× → 1.03×) |

**Paths sortKey +5.4% is code placement, not work** (checked 2026-10-30,
§51 (am)): one call executes 2487.2 instructions against 2465.8 in §51
(ah) (+0.9%; ascii 1235.4 against 1254.2); an EngineBench A/B of HEAD
against `624e0fa5` (before §51 (ak) changed `RootCollator.swift`) gives paths
sortKey +3.9% (5/5) in the plain build and −0.2% in the aligned build
(every function start at 64 bytes), latin sortKey +1.7% plain and −0.2%
aligned. With the ~2% load drift of this run, that covers the cell.

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 9.5 / 9.4 | 77.2 / 76.9 | 9.4 / 9.4 | 105.9 / 105.9 |
| Latin  | 9.9 / 10.0 | 97.4 / 97.3 | 10.4 / 10.3 | 125.6 / 123.3 |
| CJK    | 19.6 / 19.7 | 107.1 / 107.3 | 41.3 / 41.3 | 120.4 / 119.6 |
| Paths  | 19.2 / 18.9 | 188.9 / 189.5 | 30.0 / 30.0 | 371.8 / 371.6 |
| Thai   | 166.5 / 167.5 | 151.4 / 152.3 | 174.8 / 176.1 | 156.5 / 157.6 |

**Table 2 against 2026-10-29: every cell is faster**, although this run
reads about 2% slow. The wrapper steps of §51 (aj), (ak), (am):

| API (ns, `-no-WMO`) | ascii | latin | cjk | paths | thai |
|---|---|---|---|---|---|
| `localizedCompare` | 51 → 40 | 50 → 41 | 70 → 61 | 69 → 57 | 264 → 258 |
| `compare(_:locale:)` | 68 → 44 | 70 → 41 | 93 → 63 | 93 → 62 | 290 → 261 |
| `compare(_:options:range:locale:)` | 85 → 69 | 86 → 71 | 116 → 101 | 110 → 92 | 310 → 295 |
| `localizedStandardCompare` | 60 → 54 | 61 → 55 | 89 → 83 | 82 → 75 | 284 → 273 |
| `localizedCaseInsensitiveCompare` | 60 → 53 | 62 → 54 | 90 → 83 | 80 → 73 | 277 → 271 |
| `range(of:options:locale:)` | 110 → 95 | 363 → 354 | 335 → 320 | 135 → 111 | 417 → 399 |
| `range(of:options:.backwards,locale:)` | 111 → 96 | 324 → 312 | 331 → 316 | 171 → 149 | 351 → 335 |
| `sorted(using: String.Comparator(…))`, per element | 2098 → 1722 | 2174 → 1790 | 2608 → 2224 | 182 → 156 | 1093 → 977 |

The contains rows, `localizedStandardRange` and the other three sorts are
2–8% faster. The Table 2 floor rises from 1.71× to 1.81×
(`localizedStandardCompare` thai).

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

(speedup = ICU C / ours, above 1 = ours faster)

- compare: ascii **1.00× (equal)**, latin **1.03× faster**, cjk **2.10×
  faster**, paths **1.59× faster**, thai **1.05× faster** — ascii and latin
  since §51 (ae), (af), (ah)
- sortKey (inout): ascii **1.38×**, latin **1.27×**, cjk **1.11×**, paths
  **1.96×**, thai **1.03× faster**

**All ten rows are at or ahead of ICU C**: ascii compare equals it (9.4
against 9.4 ns), every other row is faster. The `throws` and the two
`String` arguments of our API (Docs/27, ~1 ns) are included in our
numbers.

The allocating sortKey (`skRet`) is 0.76–0.81× of ICU's speed (1.58× faster
on paths) because it allocates a fresh `[UInt8]` per call BY API CONTRACT;
the inout twin is the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.81× (14 APIs).
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. Against
the 2026-10-20 14:35 run, the wrapper rows moved with §51 (p) (the generic
String conversion removed): `localizedCompare` 59/62/82/78/304 →
48/51/70/65/285, `localizedStandardCompare` 72/74/106/94/311 →
63/65/99/85/311, `compare(_:locale:)` 85 → 70 and the options compare
101 → 89 on ascii, `range(of:locale:)` ascii 119 → 108; contains and
`localizedStandardRange` −1..−2%. This table uses the `-no-WMO` build; the
WMO A/B of §51 (p) shows larger gains. Thai is the weakest family; it is
also the engine's slowest corpus.

**The sort rows, split (2026-10-20, temporary probe rows; ascii, load ~58,
so approximate).** Swift's sort makes **14.0 comparisons per element** on 200
lines (counted), not n·log2(n) ≈ 7.6 — an earlier version of this paragraph
assumed 7.6 and gave 280–330 ns per comparison, about twice too much.
Per comparison (ns per element ÷ 14):

| how the sort compares | ns per comparison |
|---|---:|
| `sorted { (try? collator.compare($0, $1)) == .ascending }` (engine) | ~20 |
| `sorted { $0.localizedCompare($1) == .orderedAscending }` | ~67 |
| `sorted { comparator.compare($0, $1) == … }`, `String.Comparator` | ~74 |
| `sorted(using: String.Comparator(…))` | ~153 |
| `sorted { comparator.compare … }`, `.localizedStandard` | ~103 |
| `sorted(using: .localizedStandard)` | ~183 |
| `sorted(using: SortDescriptor(…))` | ~210 |
| `sorted(using: KeyPathComparator(…))` | ~288 |

So `Sequence.sorted(using:)` itself adds ~80 ns per comparison: it is a
public generic in FoundationEssentials that is not `@inlinable`, so a caller
in another module runs the unspecialized generic sort (elements moved through
value witnesses, every comparison through the `SortComparator` witness
table). The system side runs the same generic code. `.localizedStandard`
costs ~31 ns more per call than `localizedStandardCompare`, and
`KeyPathComparator` ~100 ns more than `SortDescriptor`.

## How to reproduce

```sh
cd swift-foundation-collation
ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2 \
ICU_BUILD=$ICU_SRC/icu4c/source \
  caffeinate -i /Users/dragan/Projects/dra8an/swift-foundation-collation/Collation/Tools/run_benchmarks.sh 3   # absolute path: HANDOFF START HERE, "Full matrix"
```

K=3 takes about 6–8 minutes (14 Table 2 APIs). Check the machine first — load average, memory,
and the time since the last wake (Docs/27):

```sh
sysctl -n vm.loadavg; memory_pressure | grep "free percentage"
pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -3
```

Sanity gates before you record a run:

- **The load control:** system ICU in Table 2 should read about
  194/365/369/300/494 for `localizedCompare`. If it drifts by more than
  ~3%, the box is too busy to record.
- **ICU C** in Table 1 should read about 9.3/10.1/40.8/30.0/172.8 compare
  and 104.4/121.0/117.7/373.3/155.5 sortKey (2026-10-29, run B). First check which ICU the
  checkout holds (`git -C $ICU_SRC branch --show-current`); a different ICU
  build can change this column for reasons that have nothing to do with load.
- **Run the matrix twice;** the two runs must agree.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
