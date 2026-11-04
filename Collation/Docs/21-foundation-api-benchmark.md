# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-04 at 10:59–11:09 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`18313630` (engine code of `f64250b6`, §51 (as)). **A new start:** the
compiler, the SDK and macOS all changed on 2026-11-04 (technique log §51
(at)); do not compare these numbers with older ones at the level of a few
percent.

**Two Swift columns in Table 2 (since 2026-11-04):** **WMO** — the main
column, because release builds of swift-foundation compile WMO
(`CMakeLists.txt`); and `-no-WMO` — the column of the history (and the only
one on machine 1). Both are built with SwiftPM's native build system, so
WMO is the only difference.

**Machine state:** 1-minute load 17–43 during the pair (run A 22 → 17, run
B 17 → 43), memory full (31 GB used, ~8 GB swap; the user's apps stay open
by decision), on AC power, under `caffeinate -i`. **The tables show run B.**

**The checks (Docs/27):**

1. **ICU C** read its gates of 2026-10-29: compare 9.3/10.1/40.7/29.5/172.0
   (gates 9.3/10.1/40.8/30.0/172.8), sortKey 104.0/120.3/119.6/365.3/153.4
   (gates 104.4/121.0/117.7/373.3/155.5) — within 2.2%. The ICU checkout is
   on branch `main`, as before.
2. **The frozen binary** of 2026-10-30 (`.build/l4/nowmo-base`, built with
   the old compiler) read its recorded values next to the new macOS:
   `localizedCompare` 40/40/58/57/256 (recorded 40/37–41/59–61/57/258),
   `localizedStandardCompare` 53/55/81/75/272 (recorded 54/55/83/75/273–276).
3. **Runs A and B agree:** Table 1 within 0.9%; the macOS column within
   1.0%; our columns with a median difference of 0.0–0.1% — but seven short
   cells (15–36 ns) differ by 3–17% between the runs with the same binary
   (marked †, run A's value listed under the tables).

So the machine and the harness measured correctly, and the macOS column is
**the new macOS reference** (macOS 27.2.1): `localizedCompare`
**200/342/353/314/502** (the old one, macOS 26.4: 194/365/369/300/494).

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

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 15† | **13.33× faster** | 35† | 5.71× faster | 200 |
| Latin  | 15† | **22.80× faster** | 35 | 9.77× faster | 342 |
| CJK    | 28 | **12.61× faster** | 49 | 7.20× faster | 353 |
| Paths  | 27 | **11.63× faster** | 50 | 6.28× faster | 314 |
| Thai   | 166 | **3.02× faster** | 225 | 2.23× faster | 502 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 19 | **10.53× faster** | 34 | 5.88× faster | 200 |
| Latin  | 20† | **17.10× faster** | 35 | 9.77× faster | 342 |
| CJK    | 34† | **10.53× faster** | 65 | 5.51× faster | 358 |
| Paths  | 29 | **11.28× faster** | 55 | 5.95× faster | 327 |
| Thai   | 169 | **2.91× faster** | 229 | 2.15× faster | 492 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 17 | **11.65× faster** | 34 | 5.82× faster | 198 |
| Latin  | 17 | **20.12× faster** | 35 | 9.77× faster | 342 |
| CJK    | 34 | **10.53× faster** | 64 | 5.59× faster | 358 |
| Paths  | 29 | **10.97× faster** | 53 | 6.00× faster | 318 |
| Thai   | 169 | **2.90× faster** | 229 | 2.14× faster | 490 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 19 | **15.95× faster** | 36† | 8.42× faster | 303 |
| Latin  | 20 | **23.00× faster** | 37 | 12.43× faster | 460 |
| CJK    | 33 | **14.36× faster** | 53 | 8.94× faster | 474 |
| Paths  | 33 | **12.52× faster** | 52 | 7.94× faster | 413 |
| Thai   | 172 | **3.60× faster** | 228 | 2.72× faster | 620 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 25 | **12.16× faster** | 48 | 6.33× faster | 304 |
| Latin  | 26 | **17.54× faster** | 49 | 9.31× faster | 456 |
| CJK    | 44 | **10.82× faster** | 79 | 6.03× faster | 476 |
| Paths  | 37 | **11.32× faster** | 67 | 6.25× faster | 419 |
| Thai   | 177 | **3.18× faster** | 246 | 2.28× faster | 562 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 127 | **7.44× faster** | 223 | 4.24× faster | 945 |
| Latin  | 149 | **9.35× faster** | 250 | 5.57× faster | 1393 |
| CJK    | 155 | **7.92× faster** | 264 | 4.65× faster | 1228 |
| Paths  | 129 | **7.14× faster** | 218 | 4.22× faster | 921 |
| Thai   | 150 | **8.91× faster** | 235 | 5.69× faster | 1336 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 127 | **7.50× faster** | 222 | 4.29× faster | 953 |
| Latin  | 148 | **9.74× faster** | 250 | 5.77× faster | 1442 |
| CJK    | 156 | **7.93× faster** | 263 | 4.70× faster | 1237 |
| Paths  | 98 | **9.47× faster** | 176 | 5.27× faster | 928 |
| Thai   | 150 | **9.26× faster** | 235 | 5.91× faster | 1389 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 134 | **7.04× faster** | 289 | 3.26× faster | 943 |
| Latin  | 156 | **8.92× faster** | 317 | 4.39× faster | 1391 |
| CJK    | 162 | **7.57× faster** | 283 | 4.33× faster | 1226 |
| Paths  | 164 | **5.70× faster** | 269 | 3.48× faster | 935 |
| Thai   | 203 | **6.82× faster** | 364 | 3.80× faster | 1384 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 37 | **8.97× faster** | 80 | 4.15× faster | 332 |
| Latin  | 168 | **4.72× faster** | 333 | 2.38× faster | 793 |
| CJK    | 174 | **3.39× faster** | 300 | 1.97× faster | 590 |
| Paths  | 48 | **6.65× faster** | 90 | 3.54× faster | 319 |
| Thai   | 189 | **3.85× faster** | 367 | 1.98× faster | 728 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 38 | **8.82× faster** | 83 | 4.04× faster | 335 |
| Latin  | 167 | **4.96× faster** | 282 | 2.94× faster | 828 |
| CJK    | 170 | **3.53× faster** | 291 | 2.06× faster | 600 |
| Paths  | 83 | **5.95× faster** | 125 | 3.95× faster | 494 |
| Thai   | 186 | **4.19× faster** | 304 | 2.56× faster | 779 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 1042 | **12.35× faster** | 1436 | 8.96× faster | 12864 |
| Latin  | 1093 | **14.08× faster** | 1497 | 10.28× faster | 15384 |
| CJK    | 1365 | **11.92× faster** | 1875 | 8.68× faster | 16277 |
| Paths  | 99† | **10.89× faster** | 156 | 6.91× faster | 1078 |
| Thai   | 626 | **8.51× faster** | 923 | 5.77× faster | 5329 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 826 | **4.71× faster** | 1125 | 3.46× faster | 3888 |
| Latin  | 873 | **6.96× faster** | 1177 | 5.17× faster | 6080 |
| CJK    | 1180 | **5.45× faster** | 1547 | 4.16× faster | 6428 |
| Paths  | 83 | **4.63× faster** | 107 | 3.59× faster | 384 |
| Thai   | 610 | **3.71× faster** | 851 | 2.66× faster | 2264 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 2418 | **5.89× faster** | 2866 | 4.97× faster | 14238 |
| Latin  | 2496 | **6.69× faster** | 2956 | 5.65× faster | 16692 |
| CJK    | 2901 | **6.12× faster** | 3459 | 5.13× faster | 17745 |
| Paths  | 212 | **5.63× faster** | 253 | 4.72× faster | 1193 |
| Thai   | 1109 | **5.22× faster** | 1429 | 4.05× faster | 5790 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU (macOS 27.2.1) |
|--------|-----------:|---------|-----------------:|---------|---------------------------:|
| ASCII  | 1437 | **9.16× faster** | 1897 | 6.94× faster | 13159 |
| Latin  | 1499 | **10.38× faster** | 1927 | 8.08× faster | 15562 |
| CJK    | 1798 | **9.19× faster** | 2349 | 7.03× faster | 16525 |
| Paths  | 135 | **8.15× faster** | 176 | 6.25× faster | 1100 |
| Thai   | 760 | **7.07× faster** | 1071 | 5.01× faster | 5370 |

† Unstable between the two runs of the pair (more than 3% apart; the same binary in both runs): run B is recorded, run A read:
- localizedCompare, ASCII, WMO: run A 18, run B 15
- localizedCompare, ASCII, `-no-WMO`: run A 30, run B 35
- localizedCompare, Latin, WMO: run A 18, run B 15
- localizedStdCmp, Latin, WMO: run A 17, run B 20
- localizedStdCmp, CJK, WMO: run A 33, run B 34
- compare(locale:), ASCII, `-no-WMO`: run A 32, run B 36
- sortStdComparator, Paths, WMO: run A 104, run B 99

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
| ASCII  | 9.0 | 9.3 | **1.03× faster** | 71.8 | 104.0 | **1.45× faster** | 120.6 | 0.86× (slower) |
| Latin  | 9.5 | 10.1 | **1.06× faster** | 92.4 | 120.3 | **1.30× faster** | 142.9 | 0.84× (slower) |
| CJK    | 20.1 | 40.7 | **2.02× faster** | 102.1 | 119.6 | **1.17× faster** | 150.6 | 0.79× (slower) |
| Paths  | 20.5 | 29.5 | **1.44× faster** | 174.3 | 365.3 | **2.10× faster** | 220.5 | **1.66× faster** |
| Thai   | 162.0 | 172.0 | **1.06× faster** | 142.8 | 153.4 | **1.07× faster** | 192.2 | 0.80× (slower) |

Reproducibility, run A / run B:

| Corpus | compare | sortKey | ICU compare | ICU sortKey |
|--------|---------|---------|-------------|-------------|
| ASCII  | 9.0 / 9.0 | 71.9 / 71.8 | 9.3 / 9.3 | 104.0 / 104.0 |
| Latin  | 9.5 / 9.5 | 91.7 / 92.4 | 10.1 / 10.1 | 120.5 / 120.3 |
| CJK    | 20.1 / 20.1 | 102.1 / 102.1 | 40.7 / 40.7 | 119.4 / 119.6 |
| Paths  | 20.5 / 20.5 | 173.5 / 174.3 | 29.5 / 29.5 | 365.1 / 365.3 |
| Thai   | 161.8 / 162.0 | 142.8 / 142.8 | 172.0 / 172.0 | 153.8 / 153.4 |

Change against 2026-11-02 (run B; Swift 6.4-dev, macOS 26.4 — **a different
compiler**: these differences are mostly the compiler's, not our code's; the
engine code changed in between only on the options paths, §51 (aq)–(as)):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 9.3 → 9.0 (1.00× → 1.03×) | 77.5 → 71.8 (1.34× → 1.45×) |
| Latin  | 9.6 → 9.5 (1.05× → 1.06×) | 97.3 → 92.4 (1.24× → 1.30×) |
| CJK    | 19.0 → **20.1** (2.15× → 2.02×) | 105.5 → 102.1 (1.12× → 1.17×) |
| Paths  | 19.3 → **20.5** (1.53× → 1.44×) | 195.8 → 174.3 (1.89× → 2.10×) |
| Thai   | 162.9 → 162.0 (1.06× → 1.06×) | 148.8 → 142.8 (1.04× → 1.07×) |

With Swift 6.5 the same engine source executes fewer instructions per
compare (ascii 173.9 → 168.6, paths 324.8 → 312.8; §51 (at)), and every
sortKey row is faster. cjk compare is 5.8% slower (not yet analysed). Paths
compare moves ~7% with code placement between two builds of the same
source (§51 (at), A against A), so its +6% here is not a finding.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file (speedup = ICU C / ours, above 1 = ours faster):

- compare: ascii **1.03×**, latin **1.06×**, cjk **2.02×**, paths
  **1.44×**, thai **1.06× faster**
- sortKey (inout): ascii **1.45×**, latin **1.30×**, cjk **1.17×**, paths
  **2.10×**, thai **1.07× faster**

**All ten rows are ahead of ICU C.** The `throws` and the two `String`
arguments of our API (Docs/27, ~1 ns) are included in our numbers. The
allocating sortKey (`skRet`) is 0.79–0.86× of ICU's speed (1.66× faster on
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

- **The system-ICU control:** `localizedCompare` should read about
  200/342/353/314/502 (macOS 27.2.1, the reference of 2026-11-04). If it
  drifts by more than ~3%, check ICU C and the frozen binary (Docs/27,
  "Third check") before you decide.
- **ICU C** in Table 1 should read about 9.3/10.1/40.8/30.0/172.8 compare
  and 104.4/121.0/117.7/373.3/155.5 sortKey (2026-10-29, run B). First check
  which ICU the checkout holds (`git -C $ICU_SRC branch --show-current`).
- **Run the matrix twice;** the two runs must agree. Short rows (below ~40
  ns) can differ by up to ~17% between runs of the same binary (2026-11-04):
  mark such cells.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
