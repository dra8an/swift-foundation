# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-04 between 10:59 and 13:39 on Apple Silicon (M1 Max, 32
GB), **macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds; engine code
of `f64250b6` (§51 (as)). **The tables show the MEDIAN of 6 runs of the same
binaries** (the pair of 10:59–11:09 and the four calibration runs of
13:21–13:39), by the recording rule of 2026-11-04 (Docs/27, "Recording";
technique log §51 (au)). **A new start:** the compiler, the SDK and macOS
all changed on 2026-11-04 (§51 (at)); do not compare these numbers with
older ones at the level of a few percent.

**Two Swift columns in Table 2 (since 2026-11-04):** **WMO** — the main
column, because release builds of swift-foundation compile WMO
(`CMakeLists.txt`); and `-no-WMO` — the column of the history (and the only
one on machine 1). Both are built with SwiftPM's native build system, so
WMO is the only difference.

**Machine state:** 1-minute load 9–43 during the six runs, memory full
(31 GB used, ~7–8 GB swap; the user's apps stay open by decision), on AC
power, under `caffeinate -i`; the calibration runs started 20 minutes after
a wake (a move between offices).

**The checks (Docs/27), over the six runs:**

1. **ICU C** is steady: every row within 1.5% across the runs; its medians
   are the new gates (compare 9.3/10.1/40.7/29.5/172.0, sortKey
   104.1/120.7/119.3/365.2/153.7), within 2.2% of the old gates of
   2026-10-29. The ICU checkout is on branch `main`, as before.
2. **The frozen binary** of 2026-10-30 (`.build/l4/nowmo-base`, built with
   the old compiler; `Collation/Tools/frozen_check.py`) read its recorded
   values twice: `localizedCompare` 40/40/58/57/256 and 39/37/59/57/258
   (recorded 40/37–41/59–61/57/258), `localizedStandardCompare`
   53/55/81/75/272 and 53/55/81/75/275 (recorded 54/55/83/75/273–276). Its
   short `compare(_:locale:)` cells read 38/40 in one check and 43/45 in the
   other: the two-level behaviour (below) is not new.
3. **The macOS column** is steady: all 70 cells within 2.0% across the six
   runs (median 0.7%). Its `localizedCompare` medians are **the new macOS
   reference** (macOS 27.2.1): **200/341/354/314/502** (the old one, macOS
   26.4: 194/365/369/300/494).
4. **Our columns:** most cells within 2% (WMO 52 of 70, `-no-WMO` 59 of
   70), but the short calls (15–56 ns: `localizedCompare`,
   `localizedStandardCompare`, `compare(_:locale:)` on ascii, latin, paths)
   take one of two levels per run (for example `localizedCompare` ascii
   WMO 18, 15, 15, 15, 18, 17): **two-level cells, marked ‡**, with their
   range listed under Table 2. In Table 1 only paths compare is two-level
   (19.0–20.6 ns).

So the machine and the harness measured correctly with the user's apps open.

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout: ICU 79.1 with Unicode 18 data, not the 79.0.1 data that our
collator bundles. Its speed matches 79.0.1, so the ratios stay comparable.
Its KEYS do not: do not generate golden files from that checkout (technique
log §49).

**The harness:** the Swift loop costs about 1 ns per call more than the C
loop, and that is the call shape of our API (`throws`, two `String`
arguments, `options`), which every caller pays. Details: Docs/27, "What the
harness itself costs".

Same Foundation APIs, two backends:

- **Swift Collator**: `BenchFoundation`, release, WMO and `-no-WMO`
- **System ICU**: pre-compiled `bench_system` (system Foundation → NSString →
  CoreFoundation → ICU), compiled with the same Swift 6.5

Table 2 values are whole nanoseconds (both sources truncate, the same way in
every run).

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 16‡ | **12.53× faster** | 35‡ | 5.73× faster | 200.5 |
| Latin  | 18‡ | **18.94× faster** | 35‡ | 9.74× faster | 341 |
| CJK    | 28 | **12.64× faster** | 49 | 7.22× faster | 354 |
| Paths  | 27‡ | **11.63× faster** | 49.5 | 6.34× faster | 314 |
| Thai   | 167 | **3.01× faster** | 225 | 2.23× faster | 502 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 19‡ | **10.53× faster** | 34 | 5.88× faster | 200 |
| Latin  | 20‡ | **17.10× faster** | 35 | 9.77× faster | 342 |
| CJK    | 34 | **10.53× faster** | 65 | 5.51× faster | 358 |
| Paths  | 29 | **11.28× faster** | 55 | 5.95× faster | 327 |
| Thai   | 168.5 | **2.91× faster** | 228.5 | 2.15× faster | 491 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17 | **11.65× faster** | 34 | 5.82× faster | 198 |
| Latin  | 17 | **20.09× faster** | 35 | 9.76× faster | 341.5 |
| CJK    | 34 | **10.51× faster** | 65 | 5.50× faster | 357.5 |
| Paths  | 29 | **10.90× faster** | 53 | 5.96× faster | 316 |
| Thai   | 169 | **2.90× faster** | 228.5 | 2.14× faster | 489.5 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 19 | **15.95× faster** | 36‡ | 8.42× faster | 303 |
| Latin  | 20 | **23.00× faster** | 37‡ | 12.43× faster | 460 |
| CJK    | 33 | **14.38× faster** | 52.5 | 9.04× faster | 474.5 |
| Paths  | 33‡ | **12.52× faster** | 52‡ | 7.94× faster | 413 |
| Thai   | 172.5 | **3.57× faster** | 228 | 2.70× faster | 616 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 25 | **12.14× faster** | 48 | 6.32× faster | 303.5 |
| Latin  | 26 | **17.58× faster** | 49 | 9.33× faster | 457 |
| CJK    | 44 | **10.82× faster** | 79.5 | 5.99× faster | 476 |
| Paths  | 37 | **11.31× faster** | 67 | 6.25× faster | 418.5 |
| Thai   | 177.5 | **3.15× faster** | 245 | 2.28× faster | 558.5 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 127 | **7.44× faster** | 223 | 4.24× faster | 945.5 |
| Latin  | 148 | **9.39× faster** | 251 | 5.53× faster | 1389 |
| CJK    | 155 | **7.92× faster** | 263 | 4.67× faster | 1227.5 |
| Paths  | 129 | **7.14× faster** | 218 | 4.22× faster | 920.5 |
| Thai   | 150.5 | **8.88× faster** | 235 | 5.69× faster | 1336 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 127.5 | **7.49× faster** | 222 | 4.30× faster | 955 |
| Latin  | 148 | **9.73× faster** | 250.5 | 5.75× faster | 1440.5 |
| CJK    | 156 | **7.93× faster** | 263 | 4.70× faster | 1237 |
| Paths  | 98 | **9.47× faster** | 176 | 5.28× faster | 928.5 |
| Thai   | 150.5 | **9.22× faster** | 235 | 5.90× faster | 1387.5 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 134 | **7.07× faster** | 288 | 3.29× faster | 947 |
| Latin  | 155.5 | **8.95× faster** | 316 | 4.40× faster | 1391 |
| CJK    | 162 | **7.57× faster** | 282 | 4.35× faster | 1226.5 |
| Paths  | 166 | **5.63× faster** | 268.5 | 3.48× faster | 935 |
| Thai   | 203 | **6.81× faster** | 363 | 3.81× faster | 1383 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 37 | **8.99× faster** | 80 | 4.16× faster | 332.5 |
| Latin  | 168 | **4.72× faster** | 333.5 | 2.38× faster | 793.5 |
| CJK    | 174.5 | **3.39× faster** | 300 | 1.97× faster | 591 |
| Paths  | 48 | **6.65× faster** | 89.5 | 3.56× faster | 319 |
| Thai   | 189.5 | **3.82× faster** | 366 | 1.98× faster | 723 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38 | **8.84× faster** | 83 | 4.05× faster | 336 |
| Latin  | 167 | **4.96× faster** | 280 | 2.96× faster | 827.5 |
| CJK    | 172 | **3.49× faster** | 291 | 2.06× faster | 599.5 |
| Paths  | 83 | **5.95× faster** | 125 | 3.95× faster | 494 |
| Thai   | 186 | **4.17× faster** | 304 | 2.55× faster | 775.5 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1041 | **12.39× faster** | 1436.5 | 8.98× faster | 12901.5 |
| Latin  | 1092 | **14.06× faster** | 1496.5 | 10.26× faster | 15358 |
| CJK    | 1365.5 | **11.90× faster** | 1876 | 8.66× faster | 16252 |
| Paths  | 103 | **10.47× faster** | 155.5 | 6.94× faster | 1078.5 |
| Thai   | 628 | **8.46× faster** | 924.5 | 5.75× faster | 5312.5 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 826 | **4.70× faster** | 1126 | 3.45× faster | 3884 |
| Latin  | 871.5 | **6.98× faster** | 1177.5 | 5.17× faster | 6083 |
| CJK    | 1178.5 | **5.46× faster** | 1553 | 4.14× faster | 6437 |
| Paths  | 83 | **4.63× faster** | 107 | 3.59× faster | 384 |
| Thai   | 623.5 | **3.63× faster** | 851.5 | 2.66× faster | 2265.5 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2418.5 | **5.88× faster** | 2870 | 4.95× faster | 14211 |
| Latin  | 2502 | **6.67× faster** | 2957 | 5.64× faster | 16689.5 |
| CJK    | 2906 | **6.10× faster** | 3456.5 | 5.13× faster | 17730.5 |
| Paths  | 213 | **5.60× faster** | 252.5 | 4.72× faster | 1192 |
| Thai   | 1120.5 | **5.16× faster** | 1432 | 4.04× faster | 5786 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1442 | **9.11× faster** | 1879 | 6.99× faster | 13143.5 |
| Latin  | 1514 | **10.30× faster** | 1927 | 8.09× faster | 15591 |
| CJK    | 1799.5 | **9.17× faster** | 2358.5 | 7.00× faster | 16499.5 |
| Paths  | 135.5 | **8.12× faster** | 173 | 6.36× faster | 1100 |
| Thai   | 772.5 | **6.95× faster** | 1065 | 5.04× faster | 5366.5 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 6 runs:
- localizedCompare, ASCII, `-no-WMO`: 30–35
- localizedCompare, ASCII, WMO: 15–18
- localizedCompare, Latin, `-no-WMO`: 31–35
- localizedCompare, Latin, WMO: 15–18
- localizedCompare, Paths, WMO: 24–27
- localizedStdCmp, ASCII, WMO: 16–19
- localizedStdCmp, Latin, WMO: 17–20
- compare(locale:), ASCII, `-no-WMO`: 32–36
- compare(locale:), Latin, `-no-WMO`: 34–37
- compare(locale:), Paths, `-no-WMO`: 51–56
- compare(locale:), Paths, WMO: 31–34

Floor (lowest speedup): WMO 2.90× (localizedCaseICmp thai); `-no-WMO` 1.97× (range(of:locale:) cjk).

### The sort rows

One op is one ELEMENT of a sort. Swift's sort makes about 14 comparisons
per element on these 200-line corpora (counted; not n·log2(n) ≈ 7.6), so ns
per element ≈ 14 × (ns per comparison) plus the sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

| Corpus | compare | ICU | speedup | sortKey (inout) | ICU | speedup | sortKey (alloc) | speedup |
|--------|--------:|----:|---------|----------------:|----:|---------|----------------:|---------|
| ASCII  | 9.0 | 9.3 | **1.03× faster** | 71.9 | 104.1 | **1.45× faster** | 120.3 | 0.87× (slower) |
| Latin  | 9.5 | 10.1 | **1.06× faster** | 92.2 | 120.7 | **1.31× faster** | 143.2 | 0.84× (slower) |
| CJK    | 20.1 | 40.7 | **2.03× faster** | 102.3 | 119.3 | **1.17× faster** | 151.2 | 0.79× (slower) |
| Paths  | 20.4‡ | 29.5 | **1.44× faster** | 173.9 | 365.2 | **2.10× faster** | 221.1 | **1.65× faster** |
| Thai   | 161.7 | 172.0 | **1.06× faster** | 142.7 | 153.7 | **1.08× faster** | 192.1 | 0.80× (slower) |

‡ Two-level cells in Table 1, with the range: Paths compare 19.0–20.6


Change against 2026-11-02 (run B then; Swift 6.4-dev, macOS 26.4 — **a different
compiler**: these differences are mostly the compiler's, not our code's; the
engine code changed in between only on the options paths, §51 (aq)–(as)):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 9.3 → 9.0 (1.00× → 1.03×) | 77.5 → 71.9 (1.34× → 1.45×) |
| Latin  | 9.6 → 9.5 (1.05× → 1.06×) | 97.3 → 92.2 (1.24× → 1.31×) |
| CJK    | 19.0 → **20.1** (2.15× → 2.03×) | 105.5 → 102.3 (1.12× → 1.17×) |
| Paths  | 19.3 → **20.4** (1.53× → 1.44×) | 195.8 → 173.9 (1.89× → 2.10×) |
| Thai   | 162.9 → 161.7 (1.06× → 1.06×) | 148.8 → 142.7 (1.04× → 1.08×) |

With Swift 6.5 the same engine source executes fewer instructions per
compare (ascii 173.9 → 168.6, paths 324.8 → 312.8; §51 (at)), and every
sortKey row is faster. cjk compare is 5.8% slower (not yet analysed). Paths
compare is two-level (19.0–20.6 ns across the six runs of the same binary,
and ~7% between two builds of the same source, §51 (at)), so its +6% here
is not a finding.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file (speedup = ICU C / ours, above 1 = ours faster):

- compare: ascii **1.03×**, latin **1.06×**, cjk **2.03×**, paths
  **1.44×**, thai **1.06× faster**
- sortKey (inout): ascii **1.45×**, latin **1.31×**, cjk **1.17×**, paths
  **2.10×**, thai **1.08× faster**

**All ten rows are ahead of ICU C.** The `throws` and the two `String`
arguments of our API (Docs/27, ~1 ns) are included in our numbers. The
allocating sortKey (`skRet`) is 0.79–0.87× of ICU's speed (1.65× faster on
paths) because it allocates a fresh `[UInt8]` per call BY API CONTRACT; the
inout twin is the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU — floor
**2.90× in WMO** (`localizedCaseInsensitiveCompare` on thai) and **1.97× in
`-no-WMO`** (`range(of:locale:)` on cjk). Most of that lead comes from
removing the system path's NSString → CoreFoundation → C++ bridge layers,
not from the collation engine. Do not use Table 2 as evidence about engine
quality; Table 1 is that evidence. The WMO column is 1.3–2.3× faster than the
`-no-WMO` column on the short rows: in `-no-WMO` each file compiles alone,
so calls across files stay calls (§51 (as)).

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

K=3 takes about 5 minutes per run with both Table 2 columns (the first run
after a clean checkout builds the two BenchFoundation scratch paths, ~16
minutes). The compiler comes from `Collation/Tools/swift_toolchain.sh` (the
selected Xcode's). Check the machine first — load average, memory, and the
time since the last wake (Docs/27):

```sh
sysctl -n vm.loadavg; memory_pressure | grep "free percentage"
pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -3
```

Sanity gates before you record a run:

- **When:** at least 10 minutes after a wake, and no burst (the 1-minute
  load not far above the 5-minute one). No fixed load limit: on 2026-11-04
  the checks held at loads of 9–43 with full memory.
- **The checks decide** (gates of 2026-11-04, six runs): ICU C within 2% of
  9.3/10.1/40.7/29.5/172.0 compare and 104.1/120.7/119.3/365.2/153.7
  sortKey; system-ICU `localizedCompare` within 2.5% of
  200/341/354/314/502. If the system side drifts, run the frozen-binary
  check (`python3 Collation/Tools/frozen_check.py Collation/Tools/bench_system 3`).
  First check which ICU the checkout holds (`git -C $ICU_SRC branch --show-current`).
- **Record the median of at least 4 runs:**
  `python3 Collation/Tools/matrix_record.py <run files>` prints these tables
  (medians, ‡ for cells whose runs differ by 5% or more, the checks).

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
