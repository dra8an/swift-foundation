# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-05 at 10:06–10:25 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`b8d61638` (§51 (aw): the warm-up in both Foundation benches; the engine of
§51 (av)). **The tables show the MEDIAN of 4 runs** (the recording rule of
2026-11-04, Docs/27; technique log §51 (au)). **A new start** since
2026-11-04 (§51 (at)): do not compare with numbers before it at the level of
a few percent.

**The warm-up (since 2026-11-05, §51 (aw)).** Both Foundation benches run
every API once and the short compares for 100 ms before the first measured
row. Without it, the first wrapper rows of each run fell partly into a ~25 ms
start-up window after the first wrapper call (`dispatch_once` of two lazy
globals, ~+6 ns per call), and the end of the window changed from run to
run: the two-level cells of 2026-11-04. The macOS side did not change with
the warm-up; Table 1 (EngineBench, `bench_icu`) has none and needs none.

**Two Swift columns in Table 2 (since 2026-11-04):** **WMO** — the main
column, because release builds of swift-foundation compile WMO
(`CMakeLists.txt`); and `-no-WMO` — the column of the history (and the only
one on machine 1). Both are built with SwiftPM's native build system, so
WMO is the only difference.

**Machine state:** 1-minute load 6.5 → 3.1 during the four runs, 1.5 hours
after the last wake, memory full (~6.7 GB swap; the user's apps stay open by
decision), on AC power, under `caffeinate -i`.

**The checks (Docs/27), medians of the four runs:**

1. **ICU C** within 1.0% (compare 9.3/10.2/40.8/29.5/172.1 against
   9.3/10.1/40.7/29.5/172.0) and 1.4% (sortKey 104.8/122.4/120.0/366.1/154.6
   against 104.1/120.7/119.3/365.2/153.7) of its gates. The ICU checkout is on
   branch `main`, as before.
2. **macOS** `localizedCompare` 202/349/356/314/503 against the reference
   200/341/354/314/502: within 2.3% (latin; the others within 1%).
3. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`)
   on its recorded values within 1 ns: `localizedCompare` 40/41/59/57/259,
   `localizedStandardCompare` 53/55/82/75/275.
4. **Two-level cells** (the four runs 5% or more apart; ‡, ranges under
   Table 2): five, against nine on 2026-11-04. Two of them are one step of
   the whole-nanosecond output (12–13, 17–18 ns); three are the
   `.localizedStandard` sort (ascii, cjk, paths WMO, 5–8% apart; not
   explained).

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
| ASCII  | 12 | **16.79× faster** | 30 | 6.72× faster | 201.5 |
| Latin  | 12‡ | **29.08× faster** | 31 | 11.26× faster | 349 |
| CJK    | 24 | **14.83× faster** | 48.5 | 7.34× faster | 356 |
| Paths  | 23 | **13.65× faster** | 44 | 7.14× faster | 314 |
| Thai   | 167 | **3.01× faster** | 227 | 2.22× faster | 503 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 16 | **12.50× faster** | 34 | 5.88× faster | 200 |
| Latin  | 16 | **21.25× faster** | 35 | 9.71× faster | 340 |
| CJK    | 33 | **10.79× faster** | 65.5 | 5.44× faster | 356 |
| Paths  | 28 | **11.68× faster** | 53 | 6.17× faster | 327 |
| Thai   | 168.5 | **2.89× faster** | 231.5 | 2.10× faster | 486.5 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17 | **11.76× faster** | 34 | 5.88× faster | 200 |
| Latin  | 17 | **19.91× faster** | 35 | 9.67× faster | 338.5 |
| CJK    | 34 | **10.43× faster** | 65 | 5.45× faster | 354.5 |
| Paths  | 28 | **11.29× faster** | 51 | 6.20× faster | 316 |
| Thai   | 168.5 | **2.88× faster** | 231.5 | 2.10× faster | 485 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17‡ | **18.03× faster** | 31 | 9.89× faster | 306.5 |
| Latin  | 18 | **25.42× faster** | 32 | 14.30× faster | 457.5 |
| CJK    | 30 | **15.88× faster** | 50.5 | 9.44× faster | 476.5 |
| Paths  | 29 | **14.12× faster** | 46 | 8.90× faster | 409.5 |
| Thai   | 173 | **3.55× faster** | 228 | 2.69× faster | 614 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 25 | **12.22× faster** | 48 | 6.36× faster | 305.5 |
| Latin  | 25 | **18.22× faster** | 50 | 9.11× faster | 455.5 |
| CJK    | 44 | **10.89× faster** | 80 | 5.99× faster | 479 |
| Paths  | 36 | **11.64× faster** | 68 | 6.16× faster | 419 |
| Thai   | 179 | **3.11× faster** | 246 | 2.26× faster | 556 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 129 | **7.39× faster** | 223 | 4.27× faster | 953 |
| Latin  | 147.5 | **9.44× faster** | 251.5 | 5.53× faster | 1392 |
| CJK    | 156 | **7.83× faster** | 265 | 4.61× faster | 1221 |
| Paths  | 131.5 | **7.04× faster** | 217.5 | 4.26× faster | 925.5 |
| Thai   | 150.5 | **8.89× faster** | 237 | 5.64× faster | 1337.5 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128.5 | **7.52× faster** | 223.5 | 4.32× faster | 966.5 |
| Latin  | 149 | **9.63× faster** | 251 | 5.72× faster | 1435 |
| CJK    | 156.5 | **7.85× faster** | 266 | 4.62× faster | 1228.5 |
| Paths  | 98 | **9.48× faster** | 175 | 5.31× faster | 929.5 |
| Thai   | 151 | **9.17× faster** | 236 | 5.87× faster | 1385 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 137 | **6.97× faster** | 290 | 3.29× faster | 955 |
| Latin  | 158 | **8.81× faster** | 317.5 | 4.38× faster | 1392 |
| CJK    | 163 | **7.50× faster** | 285 | 4.29× faster | 1222 |
| Paths  | 171 | **5.49× faster** | 269 | 3.49× faster | 938.5 |
| Thai   | 204 | **6.77× faster** | 364.5 | 3.79× faster | 1381 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 37 | **9.07× faster** | 85 | 3.95× faster | 335.5 |
| Latin  | 169 | **4.69× faster** | 335.5 | 2.36× faster | 792 |
| CJK    | 175 | **3.34× faster** | 301 | 1.94× faster | 584.5 |
| Paths  | 48 | **6.69× faster** | 96 | 3.34× faster | 321 |
| Thai   | 189.5 | **3.80× faster** | 365.5 | 1.97× faster | 719.5 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38 | **8.92× faster** | 88 | 3.85× faster | 339 |
| Latin  | 169 | **4.88× faster** | 282 | 2.92× faster | 824 |
| CJK    | 172.5 | **3.43× faster** | 291.5 | 2.03× faster | 592.5 |
| Paths  | 83 | **5.96× faster** | 131 | 3.78× faster | 495 |
| Thai   | 187 | **4.12× faster** | 304 | 2.54× faster | 771 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1006‡ | **12.88× faster** | 1471.5 | 8.81× faster | 12968.5 |
| Latin  | 1081 | **14.18× faster** | 1526.5 | 10.04× faster | 15323.5 |
| CJK    | 1301‡ | **12.44× faster** | 1896 | 8.54× faster | 16187 |
| Paths  | 102‡ | **10.62× faster** | 152 | 7.09× faster | 1077.5 |
| Thai   | 619.5 | **8.56× faster** | 938.5 | 5.65× faster | 5304 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 822 | **4.74× faster** | 1128.5 | 3.45× faster | 3898.5 |
| Latin  | 866.5 | **6.99× faster** | 1185.5 | 5.11× faster | 6056 |
| CJK    | 1179 | **5.42× faster** | 1560 | 4.09× faster | 6387 |
| Paths  | 80 | **4.80× faster** | 104 | 3.69× faster | 384 |
| Thai   | 620 | **3.65× faster** | 857.5 | 2.64× faster | 2260 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2357 | **6.05× faster** | 2842.5 | 5.01× faster | 14252 |
| Latin  | 2431.5 | **6.89× faster** | 2948 | 5.68× faster | 16749 |
| CJK    | 2833 | **6.25× faster** | 3450.5 | 5.13× faster | 17708.5 |
| Paths  | 208 | **5.74× faster** | 250 | 4.77× faster | 1193.5 |
| Thai   | 1125.5 | **5.16× faster** | 1434.5 | 4.05× faster | 5805 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1418 | **9.25× faster** | 1881 | 6.97× faster | 13111.5 |
| Latin  | 1495 | **10.44× faster** | 1985.5 | 7.86× faster | 15612 |
| CJK    | 1765 | **9.36× faster** | 2378.5 | 6.95× faster | 16520 |
| Paths  | 131.5 | **8.38× faster** | 175.5 | 6.28× faster | 1101.5 |
| Thai   | 768.5 | **6.96× faster** | 1072 | 4.99× faster | 5350 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 4 runs:
- localizedCompare, Latin, WMO: 12–13
- compare(locale:), ASCII, WMO: 17–18
- sortStdComparator, ASCII, WMO: 978–1036
- sortStdComparator, CJK, WMO: 1294–1366
- sortStdComparator, Paths, WMO: 97–105

Floor (lowest speedup): WMO 2.88× (localizedCaseICmp thai); `-no-WMO` 1.94× (range(of:locale:) cjk).

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
| ASCII  | 8.8 | 9.3 | **1.06× faster** | 72.2 | 104.8 | **1.45× faster** | 121.8 | 0.86× (slower) |
| Latin  | 9.1 | 10.2 | **1.12× faster** | 93.0 | 122.4 | **1.32× faster** | 145.4 | 0.84× (slower) |
| CJK    | 19.6 | 40.8 | **2.08× faster** | 103.0 | 120.0 | **1.17× faster** | 152.6 | 0.79× (slower) |
| Paths  | 19.8 | 29.5 | **1.49× faster** | 174.3 | 366.1 | **2.10× faster** | 222.4 | **1.65× faster** |
| Thai   | 162.1 | 172.1 | **1.06× faster** | 144.3 | 154.6 | **1.07× faster** | 194.2 | 0.80× (slower) |


**Change against the recording of 2026-11-04 (15:20–15:38, `c275fd45`),
from the warm-up of §51 (aw)** — the engine is the same; Table 1 moved
within 1% (paths compare 19.9 → 19.8, its levels have another cause). Table 2,
the rows that ran inside the start-up window (ns, ours):

| row, column | ascii | latin | cjk | paths | thai |
|---|---|---|---|---|---|
| `localizedCompare`, WMO | 16‡ → **12** | 18‡ → **12** | 28 → **24** | 27‡ → **23** | 167.5 → 167 |
| `localizedStandardCompare`, WMO | 18‡ → **16** | 19‡ → **16** | 33 → 33 | 28 → 28 | 169 → 168.5 |
| `localizedCaseInsensitiveCompare`, WMO | 16‡ → 17 | 17 → 17 | 34 → 34 | 28 → 28 | 170 → 168.5 |
| `compare(_:locale:)`, WMO | 19 → **17** | 20 → **18** | 32 → **30** | 31 → **29** | 172 → 173 |
| `localizedCompare`, `-no-WMO` | 35‡ → **30** | 36‡ → **31** | 49 → 48.5 | 44 → 44 | 225.5 → 227 |
| `compare(_:locale:)`, `-no-WMO` | 37 → **31** | 38‡ → **32** | 53 → **50.5** | 47.5 → 46 | 227 → 228 |

The other rows moved within their usual spread (the options compare, the
search rows, the sorts). `localizedCaseInsensitiveCompare` ascii 16‡ → 17:
the old median mixed the two levels; the warm-up gives the one level, 17.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file (speedup = ICU C / ours, above 1 = ours faster):

- compare: ascii **1.06×**, latin **1.12×**, cjk **2.08×**, paths
  **1.49×**, thai **1.06× faster**
- sortKey (inout): ascii **1.45×**, latin **1.32×**, cjk **1.17×**, paths
  **2.10×**, thai **1.07× faster**

**All ten rows are ahead of ICU C.** The `throws` and the two `String`
arguments of our API (Docs/27, ~1 ns) are included in our numbers. The
allocating sortKey (`skRet`) is 0.79–0.86× of ICU's speed (1.65× faster on
paths) because it allocates a fresh `[UInt8]` per call BY API CONTRACT; the
inout twin is the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU — floor
**2.88× in WMO** (`localizedCaseInsensitiveCompare` on thai) and **1.94× in
`-no-WMO`** (`range(of:locale:)` on cjk). Most of that lead comes from
removing the system path's NSString → CoreFoundation → C++ bridge layers,
not from the collation engine. Do not use Table 2 as evidence about engine
quality; Table 1 is that evidence. The WMO column is 1.3–2.6× faster than the
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
