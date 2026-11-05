# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-05 at 14:33–14:52 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`d7508847` (§51 (ax): same-file copies in the CE compare and the sort key
writer; §51 (ay): no stack protector in the options pass and the
identical-strength pass). **The tables show the MEDIAN of 4 runs** (the
recording rule of 2026-11-04, Docs/27; technique log §51 (au)). **A new
start** since 2026-11-04 (§51 (at)): do not compare with numbers before it
at the level of a few percent.

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

**Machine state:** 1-minute load 5.4 → 15.5 → 7.0 during the four runs, 1 h 20
min after the last wake, memory full (~10 GB swap; the user's apps stay open
by decision), on AC power, under `caffeinate -i`.

**The checks (Docs/27), medians of the four runs:**

1. **ICU C** within 0.4% (compare 9.3/10.1/40.8/29.5/172.7 against
   9.3/10.1/40.7/29.5/172.0) and 0.7% (sortKey 104.2/121.2/120.1/366.8/154.6
   against 104.1/120.7/119.3/365.2/153.7) of its gates. The ICU checkout is on
   branch `main`, as before.
2. **macOS** `localizedCompare` 201/349/355/314/504 against the reference
   200/341/354/314/502: within 2.3% (latin, as in the morning series; the
   others within 0.5%).
3. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`)
   on its recorded values within 1 ns: `localizedCompare` 39/40/58/56/257,
   `localizedStandardCompare` 53/55/82/75/276.
4. **Two-level cells** (the four runs 5% or more apart; ‡, ranges under
   Table 2): five. Two are one step of the whole-nanosecond output (12–13,
   16–17 ns); three are the `.localizedStandard` sort (ascii, latin, paths
   WMO, 5–7% apart; not explained, as in the morning).

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
| ASCII  | 12 | **16.75× faster** | 30 | 6.70× faster | 201 |
| Latin  | 12‡ | **29.08× faster** | 31 | 11.26× faster | 349 |
| CJK    | 24 | **14.79× faster** | 48 | 7.40× faster | 355 |
| Paths  | 23 | **13.63× faster** | 44 | 7.12× faster | 313.5 |
| Thai   | 166.5 | **3.02× faster** | 223.5 | 2.25× faster | 503.5 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 15 | **13.30× faster** | 34 | 5.87× faster | 199.5 |
| Latin  | 16 | **21.25× faster** | 35 | 9.71× faster | 340 |
| CJK    | 33 | **10.76× faster** | 64.5 | 5.50× faster | 355 |
| Paths  | 28 | **11.71× faster** | 54 | 6.07× faster | 328 |
| Thai   | 169 | **2.88× faster** | 227 | 2.15× faster | 487 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 16 | **12.47× faster** | 34 | 5.87× faster | 199.5 |
| Latin  | 16‡ | **21.12× faster** | 35 | 9.66× faster | 338 |
| CJK    | 34 | **10.41× faster** | 64 | 5.53× faster | 354 |
| Paths  | 27 | **11.80× faster** | 54 | 5.90× faster | 318.5 |
| Thai   | 169 | **2.88× faster** | 226.5 | 2.15× faster | 487.5 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17 | **17.91× faster** | 30 | 10.15× faster | 304.5 |
| Latin  | 18 | **25.33× faster** | 31 | 14.71× faster | 456 |
| CJK    | 30 | **15.73× faster** | 49 | 9.63× faster | 472 |
| Paths  | 29 | **14.19× faster** | 45 | 9.14× faster | 411.5 |
| Thai   | 172 | **3.58× faster** | 223 | 2.76× faster | 616 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 24 | **12.71× faster** | 47 | 6.49× faster | 305 |
| Latin  | 25 | **18.20× faster** | 48 | 9.48× faster | 455 |
| CJK    | 44 | **10.77× faster** | 78.5 | 6.04× faster | 474 |
| Paths  | 36 | **11.67× faster** | 68 | 6.18× faster | 420 |
| Thai   | 179.5 | **3.10× faster** | 239 | 2.33× faster | 556.5 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128 | **7.43× faster** | 224 | 4.25× faster | 951.5 |
| Latin  | 147 | **9.44× faster** | 250 | 5.55× faster | 1388 |
| CJK    | 157.5 | **7.77× faster** | 263 | 4.66× faster | 1224.5 |
| Paths  | 131 | **7.07× faster** | 222 | 4.17× faster | 926 |
| Thai   | 151 | **8.85× faster** | 238 | 5.62× faster | 1337 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128 | **7.49× faster** | 224 | 4.28× faster | 958.5 |
| Latin  | 147.5 | **9.72× faster** | 250.5 | 5.72× faster | 1433 |
| CJK    | 158 | **7.80× faster** | 263.5 | 4.68× faster | 1232.5 |
| Paths  | 98.5 | **9.47× faster** | 178 | 5.24× faster | 932.5 |
| Thai   | 151 | **9.17× faster** | 237.5 | 5.83× faster | 1385 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 136 | **6.96× faster** | 289.5 | 3.27× faster | 947 |
| Latin  | 157 | **8.84× faster** | 313.5 | 4.43× faster | 1387.5 |
| CJK    | 164.5 | **7.46× faster** | 283.5 | 4.33× faster | 1227 |
| Paths  | 169 | **5.57× faster** | 273.5 | 3.44× faster | 942 |
| Thai   | 205 | **6.74× faster** | 367.5 | 3.76× faster | 1382.5 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 37 | **9.07× faster** | 85 | 3.95× faster | 335.5 |
| Latin  | 169.5 | **4.66× faster** | 334.5 | 2.36× faster | 790 |
| CJK    | 176.5 | **3.31× faster** | 299.5 | 1.95× faster | 585 |
| Paths  | 48 | **6.69× faster** | 95 | 3.38× faster | 321 |
| Thai   | 190 | **3.81× faster** | 368.5 | 1.96× faster | 723 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38 | **8.91× faster** | 87 | 3.89× faster | 338.5 |
| Latin  | 168 | **4.90× faster** | 282.5 | 2.92× faster | 823.5 |
| CJK    | 173.5 | **3.41× faster** | 291.5 | 2.03× faster | 592.5 |
| Paths  | 82.5 | **6.00× faster** | 131 | 3.78× faster | 495 |
| Thai   | 188 | **4.13× faster** | 306.5 | 2.53× faster | 776 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1004‡ | **12.89× faster** | 1460 | 8.87× faster | 12947.5 |
| Latin  | 1077‡ | **14.29× faster** | 1526 | 10.08× faster | 15388 |
| CJK    | 1342 | **12.13× faster** | 1903.5 | 8.55× faster | 16272 |
| Paths  | 102‡ | **10.52× faster** | 154.5 | 6.98× faster | 1078.5 |
| Thai   | 622.5 | **8.50× faster** | 918 | 5.76× faster | 5288.5 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 822 | **4.73× faster** | 1128.5 | 3.45× faster | 3889.5 |
| Latin  | 865.5 | **6.97× faster** | 1183.5 | 5.09× faster | 6028.5 |
| CJK    | 1177 | **5.43× faster** | 1558 | 4.10× faster | 6393 |
| Paths  | 80 | **4.80× faster** | 104 | 3.69× faster | 384 |
| Thai   | 625 | **3.60× faster** | 838.5 | 2.69× faster | 2252 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2359 | **6.06× faster** | 2842.5 | 5.03× faster | 14307 |
| Latin  | 2448 | **6.80× faster** | 2932 | 5.68× faster | 16642.5 |
| CJK    | 2849.5 | **6.22× faster** | 3434.5 | 5.16× faster | 17713.5 |
| Paths  | 211 | **5.66× faster** | 248 | 4.82× faster | 1194.5 |
| Thai   | 1124 | **5.15× faster** | 1407 | 4.11× faster | 5788.5 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1411 | **9.33× faster** | 1882.5 | 6.99× faster | 13159.5 |
| Latin  | 1501.5 | **10.37× faster** | 1961.5 | 7.94× faster | 15571.5 |
| CJK    | 1765.5 | **9.32× faster** | 2373 | 6.93× faster | 16451 |
| Paths  | 134.5 | **8.18× faster** | 176 | 6.25× faster | 1100.5 |
| Thai   | 770.5 | **6.97× faster** | 1057 | 5.08× faster | 5369.5 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 4 runs:
- localizedCompare, Latin, WMO: 12–13
- localizedCaseICmp, Latin, WMO: 16–17
- sortStdComparator, ASCII, WMO: 976–1032
- sortStdComparator, Latin, WMO: 1021–1080
- sortStdComparator, Paths, WMO: 99–106

Floor (lowest speedup): WMO 2.88× (localizedStdCmp thai); `-no-WMO` 1.95× (range(of:locale:) cjk).

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
| ASCII  | 8.7 | 9.3 | **1.07× faster** | 72.1 | 104.2 | **1.45× faster** | 120.8 | 0.86× (slower) |
| Latin  | 9.1 | 10.1 | **1.11× faster** | 92.7 | 121.2 | **1.31× faster** | 143.8 | 0.84× (slower) |
| CJK    | 19.6 | 40.8 | **2.08× faster** | 102.7 | 120.1 | **1.17× faster** | 151.9 | 0.79× (slower) |
| Paths  | 19.1 | 29.5 | **1.54× faster** | 174.5 | 366.8 | **2.10× faster** | 222.4 | **1.65× faster** |
| Thai   | 161.1 | 172.7 | **1.07× faster** | 143.2 | 154.6 | **1.08× faster** | 193.7 | 0.80× (slower) |


**Change against the recording of the morning of 2026-11-05 (10:06–10:25,
`b8d61638`)**, from §51 (ax) (`-no-WMO` only) and §51 (ay) (every compare with
non-default options −11 instructions, the `.localizedStandard` comparator −20
on Latin). Table 1 within 1% except paths compare 19.8 → 19.1 (two-level
since (au)) and thai 162.1 → 161.1. Table 2, ns, ours:

| row, column | ascii | latin | cjk | paths | thai |
|---|---|---|---|---|---|
| `localizedStandardCompare`, WMO | 16 → **15** | 16 → 16 | 33 → 33 | 28 → 28 | 168.5 → 169 |
| `localizedCaseInsensitiveCompare`, WMO | 17 → **16** | 17 → **16** | 34 → 34 | 28 → **27** | 168.5 → 169 |
| options compare, WMO | 25 → **24** | 25 → 25 | 44 → 44 | 36 → 36 | 179 → 179.5 |
| options compare, `-no-WMO` | 48 → **47** | 50 → **48** | 80 → 78.5 | 68 → 68 | 246 → **239** |
| `compare(_:locale:)`, `-no-WMO` | 31 → 30 | 32 → 31 | 50.5 → 49 | 46 → 45 | 228 → 223 |
| the thai rows, `-no-WMO` (compares, sorts) | | | | | −1.5..−2.8% |
| `localizedCaseInsensitiveCompare`, `-no-WMO` | 34 → 34 | 35 → 35 | 65 → 64 | **51 → 54** | 231.5 → 226.5 |

The rest moved within ±1.5%. Two "+" cells: `localizedCaseInsensitiveCompare`
paths `-no-WMO` +5.9% (its instructions −11; not in the A/Bs of (ay), which
ran ascii, latin and thai) and the `.localizedStandard` sort cjk WMO +3.2%
(a row with a spread of 5–8% between runs).

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file (speedup = ICU C / ours, above 1 = ours faster):

- compare: ascii **1.07×**, latin **1.11×**, cjk **2.08×**, paths
  **1.54×**, thai **1.07× faster**
- sortKey (inout): ascii **1.45×**, latin **1.31×**, cjk **1.17×**, paths
  **2.10×**, thai **1.08× faster**

**All ten rows are ahead of ICU C.** The `throws` and the two `String`
arguments of our API (Docs/27, ~1 ns) are included in our numbers. The
allocating sortKey (`skRet`) is 0.79–0.86× of ICU's speed (1.65× faster on
paths) because it allocates a fresh `[UInt8]` per call BY API CONTRACT; the
inout twin is the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU — floor
**2.88× in WMO** (`localizedStandardCompare` on thai) and **1.95× in
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
