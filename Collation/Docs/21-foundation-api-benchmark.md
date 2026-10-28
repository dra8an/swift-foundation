# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-28 at about 13:35 on Apple Silicon (macOS 26),
`run_benchmarks.sh` K=3 (min over interleaved runs, each itself min-over-9),
release builds, at `853492cc`. Includes every optimization through §51 (af):
new since the 2026-10-23 baseline are (ac) the options compares' byte pass
as before (z), and (ae) + (af) the first-byte test before the prefix scan,
the 8-word `compareUTF8` call and the scan in its own function (compare
ascii / latin).

**Machine state:** 1-minute load 27 at the start of run B, 39 at its end
(run A: 16 → 27); on AC power, under `caffeinate -i`, more than 20 minutes
after the last wake. **The tables show run B** (the convention). Recorded
on these grounds (the control decides, not the load — Docs/27):

1. **The system-ICU control (Table 2) matches the reference within 1.0% in
   run B** (`localizedCompare` 195/364/369/300/499 against
   194/365/369/300/494; run A within 1.4%).
2. **Runs A and B agree:** our Table 1 cells within 1.1%; ICU C within
   1.3% except ICU sortKey ascii (106.7 / 104.0, 2.5%).

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
| ASCII  |    47 |       195 | **4.15× faster** |
| Latin  |    51 |       364 | **7.14× faster** |
| CJK    |    70 |       369 | **5.27× faster** |
| Paths  |    67 |       300 | **4.48× faster** |
| Thai   |   266 |       499 | **1.88× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    61 |       196 | **3.21× faster** |
| Latin  |    62 |       355 | **5.73× faster** |
| CJK    |    90 |       363 | **4.03× faster** |
| Paths  |    83 |       322 | **3.88× faster** |
| Thai   |   283 |       486 | **1.72× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    61 |       197 | **3.23× faster** |
| Latin  |    63 |       353 | **5.60× faster** |
| CJK    |    90 |       365 | **4.06× faster** |
| Paths  |    81 |       308 | **3.80× faster** |
| Thai   |   280 |       484 | **1.73× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    69 |       311 | **4.51× faster** |
| Latin  |    70 |       477 | **6.81× faster** |
| CJK    |    93 |       485 | **5.22× faster** |
| Paths  |    92 |       408 | **4.43× faster** |
| Thai   |   289 |       625 | **2.16× faster** |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    86 |       312 | **3.63× faster** |
| Latin  |    87 |       465 | **5.34× faster** |
| CJK    |   116 |       478 | **4.12× faster** |
| Paths  |   111 |       419 | **3.77× faster** |
| Thai   |   310 |       560 | **1.81× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   240 |       998 | **4.16× faster** |
| Latin  |   265 |      1432 | **5.40× faster** |
| CJK    |   282 |      1267 | **4.49× faster** |
| Paths  |   240 |       973 | **4.05× faster** |
| Thai   |   267 |      1382 | **5.18× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   240 |      1005 | **4.19× faster** |
| Latin  |   267 |      1491 | **5.58× faster** |
| CJK    |   280 |      1279 | **4.57× faster** |
| Paths  |   200 |       979 | **4.89× faster** |
| Thai   |   265 |      1439 | **5.43× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   307 |       996 | **3.24× faster** |
| Latin  |   331 |      1439 | **4.35× faster** |
| CJK    |   305 |      1276 | **4.18× faster** |
| Paths  |   293 |       982 | **3.35× faster** |
| Thai   |   396 |      1435 | **3.62× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   110 |       324 | **2.95× faster** |
| Latin  |   364 |       782 | **2.15× faster** |
| CJK    |   332 |       580 | **1.75× faster** |
| Paths  |   132 |       312 | **2.36× faster** |
| Thai   |   419 |       714 | **1.70× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   111 |       325 | **2.93× faster** |
| Latin  |   323 |       818 | **2.53× faster** |
| CJK    |   328 |       589 | **1.80× faster** |
| Paths  |   167 |       506 | **3.03× faster** |
| Thai   |   350 |       766 | **2.19× faster** |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2209 |     14836 | **6.72× faster** |
| Latin  |  2290 |     17472 | **7.63× faster** |
| CJK    |  3792 |     18452 | **4.87× faster** |
| Paths  |   239 |      1271 | **5.32× faster** |
| Thai   |  1262 |      5748 | **4.55× faster** |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2087 |      5107 | **2.45× faster** |
| Latin  |  2170 |      7378 | **3.40× faster** |
| CJK    |  2598 |      7844 | **3.02× faster** |
| Paths  |   182 |       478 | **2.63× faster** |
| Thai   |  1102 |      2466 | **2.24× faster** |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  3663 |     16545 | **4.52× faster** |
| Latin  |  3772 |     19047 | **5.05× faster** |
| CJK    |  5367 |     20385 | **3.80× faster** |
| Paths  |   325 |      1355 | **4.17× faster** |
| Thai   |  1740 |      6359 | **3.65× faster** |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2663 |     16342 | **6.14× faster** |
| Latin  |  2752 |     19017 | **6.91× faster** |
| CJK    |  4272 |     20139 | **4.71× faster** |
| Paths  |   244 |      1322 | **5.42× faster** |
| Thai   |  1396 |      6162 | **4.41× faster** |

### The sort rows

One op is one ELEMENT of a sort. Swift's sort makes about 14 comparisons
per element on these 200-line corpora (counted; not n·log2(n) ≈ 7.6), so ns
per element ≈ 14 × (ns per comparison) plus the sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |     9.9 |   9.3 | 1.06× |    75.6 | 104.0 | **0.73×** |   128.8 | 1.24× |
| Latin  |    10.3 |  10.1 | 1.02× |    96.0 | 121.2 | **0.79×** |   150.7 | 1.24× |
| CJK    |    18.6 |  40.9 | **0.45×** |   104.9 | 118.8 | **0.88×** |   156.3 | 1.32× |
| Paths  |    19.4 |  29.4 | **0.66×** |   184.3 | 366.0 | **0.50×** |   233.7 | 0.64× |
| Thai   |   163.2 | 172.1 | **0.95×** |   152.5 | 154.1 | **0.99×** |   204.3 | 1.33× |

Change against the 2026-10-23 baseline (run B):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 10.5 → 9.9 (**−5.7%**, 1.13× → 1.06×) | 76.0 → 75.6 |
| Latin  | 11.0 → 10.3 (**−6.4%**, 1.09× → 1.02×) | 96.8 → 96.0 |
| CJK    | 20.1 → 18.6 (**−7.5%**) | 105.6 → 104.9 |
| Paths  | 18.5 → 19.4 (+4.9%, accepted: the scan call, §51 (af)) | 185.7 → 184.3 |
| Thai   | 164.7 → 163.2 | 152.0 → 152.5 |

The moves are §51 (ae) + (af) (compare); sortKey did not change.

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 9.9 / 9.9 | 76.6 / 75.6 | 9.4 / 9.3 | 106.7 / 104.0 |
| Latin  | 10.3 / 10.3 | 96.7 / 96.0 | 10.1 / 10.1 | 123.0 / 121.2 |
| CJK    | 18.6 / 18.6 | 106.1 / 104.9 | 40.8 / 40.9 | 118.2 / 118.8 |
| Paths  | 19.4 / 19.4 | 185.9 / 184.3 | 29.5 / 29.4 | 367.4 / 366.0 |
| Thai   | 164.9 / 163.2 | 152.0 / 152.5 | 171.9 / 172.1 | 154.9 / 154.1 |

**Table 2 against 2026-10-23:** `localizedStandardCompare` and
`localizedCaseInsensitiveCompare` ascii 69 → 61, latin 71 → 62–63 (−11..−13%;
(ac) and (ae)/(af)), the options compare ascii / latin 93 / 96 → 86 / 87;
`localizedCompare` and `compare(_:locale:)` within ±2; the search and sort
rows within −2..+2%.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.06× ascii, 1.02× latin, **0.45× cjk**, **0.66× paths** and
  **0.95× thai (we are FASTER)** — ascii and latin since §51 (ae), (af)
- sortKey **0.73× ascii, 0.79× latin, 0.88× cjk, 0.50× paths, 0.99× thai
  (all FASTER)**

Eight of the ten rows are at or ahead of ICU C (every sortKey row; cjk,
paths and thai compare). The two behind are compare on ascii (1.06×, 0.6 ns)
and latin (1.02×, 0.2 ns); our instruction count there is at ICU's level
(174 against 175 on ascii, §51 (af)), and the rest is the API's call shape
(`throws`, two `String` arguments; Docs/27).

The `skRet` column (the allocating sortKey overload) stays ~0.63–1.32× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.70× (14 APIs).
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
- **ICU C** in Table 1 should read about 9.5/10.1/40.8/29.7/172.0 compare
  and 106.1/122.1/119.3/369.6/154.7 sortKey (2026-10-21, run B). First check which ICU the
  checkout holds (`git -C $ICU_SRC branch --show-current`); a different ICU
  build can change this column for reasons that have nothing to do with load.
- **Run the matrix twice;** the two runs must agree.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
