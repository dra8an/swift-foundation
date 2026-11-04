# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-04 at 15:20–15:38 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`c275fd45` (§51 (av): no stack protector in `compare`). **The tables show
the MEDIAN of 4 runs** (the recording rule of 2026-11-04, Docs/27; technique
log §51 (au)). **A new start** since 2026-11-04 (§51 (at)): do not compare
with numbers before it at the level of a few percent.

**Two Swift columns in Table 2 (since 2026-11-04):** **WMO** — the main
column, because release builds of swift-foundation compile WMO
(`CMakeLists.txt`); and `-no-WMO` — the column of the history (and the only
one on machine 1). Both are built with SwiftPM's native build system, so
WMO is the only difference.

**Machine state:** 1-minute load 13 → 4 during the four runs, memory full
(31 GB used, ~6.7 GB swap; the user's apps stay open by decision), on AC
power, under `caffeinate -i`.

**The checks (Docs/27), medians of the four runs:**

1. **ICU C** within 0.4% of its gates (compare 9.3/10.1/40.5/29.5/171.6
   against 9.3/10.1/40.7/29.5/172.0; sortKey 104.0/120.6/119.2/365.9/153.4
   against 104.1/120.7/119.3/365.2/153.7). The ICU checkout is on branch
   `main`, as before.
2. **macOS** `localizedCompare` 201/342/354/314/504 against the reference
   200/341/354/314/502: within 0.5%.
3. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`)
   on its recorded values: `localizedCompare` 39/40/58/56/258,
   `localizedStandardCompare` 53/55/81/75/273.
4. **Two-level cells** (the four runs 5% or more apart; ‡, ranges under
   Table 2): nine short cells, the same kind as in the calibration of
   §51 (au).

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
| ASCII  | 16‡ | **12.18× faster** | 35‡ | 5.74× faster | 201 |
| Latin  | 18‡ | **19.00× faster** | 36‡ | 9.50× faster | 342 |
| CJK    | 28 | **12.64× faster** | 49 | 7.22× faster | 354 |
| Paths  | 27‡ | **11.61× faster** | 44 | 7.12× faster | 313.5 |
| Thai   | 167.5 | **3.01× faster** | 225.5 | 2.23× faster | 503.5 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 18‡ | **10.84× faster** | 34 | 5.90× faster | 200.5 |
| Latin  | 19‡ | **18.03× faster** | 35 | 9.79× faster | 342.5 |
| CJK    | 33 | **10.85× faster** | 64.5 | 5.55× faster | 358 |
| Paths  | 28 | **11.70× faster** | 54 | 6.06× faster | 327.5 |
| Thai   | 169 | **2.91× faster** | 229.5 | 2.14× faster | 491 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 16‡ | **12.00× faster** | 34 | 5.82× faster | 198 |
| Latin  | 17 | **20.15× faster** | 35 | 9.79× faster | 342.5 |
| CJK    | 34 | **10.51× faster** | 65 | 5.50× faster | 357.5 |
| Paths  | 28 | **11.32× faster** | 53 | 5.98× faster | 317 |
| Thai   | 170 | **2.88× faster** | 229 | 2.14× faster | 489 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 19 | **15.95× faster** | 37 | 8.19× faster | 303 |
| Latin  | 20 | **23.00× faster** | 38‡ | 12.11× faster | 460 |
| CJK    | 32 | **14.86× faster** | 53 | 8.97× faster | 475.5 |
| Paths  | 31 | **13.31× faster** | 47.5 | 8.68× faster | 412.5 |
| Thai   | 172 | **3.59× faster** | 227 | 2.72× faster | 617 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 25 | **12.14× faster** | 47 | 6.46× faster | 303.5 |
| Latin  | 25 | **18.32× faster** | 49 | 9.35× faster | 458 |
| CJK    | 43.5 | **10.98× faster** | 79 | 6.04× faster | 477.5 |
| Paths  | 36 | **11.60× faster** | 67 | 6.23× faster | 417.5 |
| Thai   | 179 | **3.12× faster** | 245 | 2.28× faster | 558.5 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128 | **7.39× faster** | 223 | 4.24× faster | 946 |
| Latin  | 147 | **9.47× faster** | 250 | 5.57× faster | 1391.5 |
| CJK    | 156 | **7.87× faster** | 263.5 | 4.66× faster | 1228 |
| Paths  | 131 | **7.02× faster** | 219 | 4.20× faster | 919.5 |
| Thai   | 151 | **8.85× faster** | 235.5 | 5.68× faster | 1337 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128 | **7.47× faster** | 223 | 4.29× faster | 956 |
| Latin  | 147.5 | **9.76× faster** | 250 | 5.76× faster | 1440 |
| CJK    | 155.5 | **7.97× faster** | 263.5 | 4.70× faster | 1239 |
| Paths  | 98 | **9.49× faster** | 175.5 | 5.30× faster | 930 |
| Thai   | 151 | **9.21× faster** | 234.5 | 5.93× faster | 1390 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 136 | **6.95× faster** | 288 | 3.28× faster | 945.5 |
| Latin  | 157 | **8.86× faster** | 313 | 4.44× faster | 1390.5 |
| CJK    | 164 | **7.51× faster** | 281.5 | 4.37× faster | 1231 |
| Paths  | 169 | **5.55× faster** | 269 | 3.49× faster | 937.5 |
| Thai   | 204 | **6.79× faster** | 364 | 3.81× faster | 1385.5 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 37 | **8.99× faster** | 85 | 3.91× faster | 332.5 |
| Latin  | 168.5 | **4.72× faster** | 338 | 2.35× faster | 795 |
| CJK    | 176 | **3.37× faster** | 304 | 1.95× faster | 592.5 |
| Paths  | 47 | **6.79× faster** | 94 | 3.39× faster | 319 |
| Thai   | 190 | **3.81× faster** | 370 | 1.95× faster | 723 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38 | **8.82× faster** | 87 | 3.85× faster | 335 |
| Latin  | 167 | **4.96× faster** | 284.5 | 2.91× faster | 827.5 |
| CJK    | 171.5 | **3.50× faster** | 296.5 | 2.03× faster | 600.5 |
| Paths  | 82 | **6.02× faster** | 129.5 | 3.81× faster | 494 |
| Thai   | 186 | **4.18× faster** | 308 | 2.52× faster | 777.5 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1038.5 | **12.41× faster** | 1465 | 8.79× faster | 12884.5 |
| Latin  | 1059.5 | **14.49× faster** | 1527 | 10.06× faster | 15356.5 |
| CJK    | 1354.5 | **12.03× faster** | 1909.5 | 8.54× faster | 16298.5 |
| Paths  | 104 | **10.36× faster** | 152 | 7.09× faster | 1077.5 |
| Thai   | 624 | **8.53× faster** | 944.5 | 5.64× faster | 5323.5 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 823 | **4.72× faster** | 1139 | 3.41× faster | 3881 |
| Latin  | 867 | **7.03× faster** | 1195.5 | 5.10× faster | 6093.5 |
| CJK    | 1179.5 | **5.49× faster** | 1567 | 4.13× faster | 6475 |
| Paths  | 80 | **4.80× faster** | 104 | 3.69× faster | 384 |
| Thai   | 622.5 | **3.64× faster** | 854 | 2.65× faster | 2266.5 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2405 | **5.92× faster** | 2867.5 | 4.96× faster | 14232 |
| Latin  | 2486.5 | **6.70× faster** | 2963 | 5.62× faster | 16653 |
| CJK    | 2905 | **6.09× faster** | 3454.5 | 5.12× faster | 17703.5 |
| Paths  | 212 | **5.62× faster** | 251.5 | 4.74× faster | 1192 |
| Thai   | 1126.5 | **5.13× faster** | 1444.5 | 4.00× faster | 5780.5 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1466 | **8.97× faster** | 1892 | 6.95× faster | 13155 |
| Latin  | 1517 | **10.29× faster** | 1959.5 | 7.96× faster | 15604.5 |
| CJK    | 1823 | **9.09× faster** | 2378 | 6.97× faster | 16575.5 |
| Paths  | 139 | **7.91× faster** | 173.5 | 6.34× faster | 1100 |
| Thai   | 779.5 | **6.91× faster** | 1077.5 | 5.00× faster | 5387.5 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 4 runs:
- localizedCompare, ASCII, `-no-WMO`: 32–35
- localizedCompare, ASCII, WMO: 15–18
- localizedCompare, Latin, `-no-WMO`: 33–36
- localizedCompare, Latin, WMO: 18–19
- localizedCompare, Paths, WMO: 24–27
- localizedStdCmp, ASCII, WMO: 16–19
- localizedStdCmp, Latin, WMO: 16–19
- localizedCaseICmp, ASCII, WMO: 16–17
- compare(locale:), Latin, `-no-WMO`: 33–38

Floor (lowest speedup): WMO 2.88× (localizedCaseICmp thai); `-no-WMO` 1.95× (range(of:locale:) cjk).

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
| ASCII  | 8.8 | 9.3 | **1.06× faster** | 72.5 | 104.0 | **1.43× faster** | 121.9 | 0.85× (slower) |
| Latin  | 9.1 | 10.1 | **1.11× faster** | 92.6 | 120.6 | **1.30× faster** | 144.6 | 0.83× (slower) |
| CJK    | 19.7 | 40.5 | **2.06× faster** | 103.0 | 119.2 | **1.16× faster** | 151.9 | 0.78× (slower) |
| Paths  | 19.9 | 29.5 | **1.48× faster** | 173.8 | 365.9 | **2.11× faster** | 221.5 | **1.65× faster** |
| Thai   | 162.1 | 171.6 | **1.06× faster** | 143.6 | 153.4 | **1.07× faster** | 193.7 | 0.79× (slower) |


**Change against the recording of the morning of 2026-11-04** (the median
of six runs at `f64250b6`'s engine; the same compiler, SDK and macOS), from
§51 (av) — the stack protector that Swift 6.5 put into `compare` is gone:

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 9.0 → **8.8** (1.03× → 1.06×) | 71.9 → 72.5 (1.45× → 1.43×) |
| Latin  | 9.5 → **9.1** (1.06× → 1.11×) | 92.2 → 92.6 (1.31× → 1.30×) |
| CJK    | 20.1 → **19.7** (2.03× → 2.06×) | 102.3 → 103.0 (1.17× → 1.16×) |
| Paths  | 20.4 → 19.9 (1.44× → 1.48×; two-level) | 173.9 → 173.8 (2.10× → 2.11×) |
| Thai   | 161.7 → 162.1 (1.06× → 1.06×) | 142.7 → 143.6 (1.08× → 1.07×) |

sortKey did not change (its code is the same). In Table 2 the change is
small, because a Foundation call is long against 10 saved instructions: WMO
mostly 0..−5% (`localizedStandardCompare` −3..−5%, `compare(_:locale:)`
paths −6%), a few short or two-level cells +1..+3%; `-no-WMO`
`localizedCompare` paths −11%, `compare(_:locale:)` paths −9%, but the sorts
+1..+2% and `range(of:options:locale:)` ascii / paths +6 / +5% — the search
does not use the changed fast path, and in the aligned builds of §51 (av)
the sorts read about 0: the layout of this `-no-WMO` binary.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file (speedup = ICU C / ours, above 1 = ours faster):

- compare: ascii **1.06×**, latin **1.11×**, cjk **2.06×**, paths
  **1.48×**, thai **1.06× faster**
- sortKey (inout): ascii **1.43×**, latin **1.30×**, cjk **1.16×**, paths
  **2.11×**, thai **1.07× faster**

**All ten rows are ahead of ICU C.** The `throws` and the two `String`
arguments of our API (Docs/27, ~1 ns) are included in our numbers. The
allocating sortKey (`skRet`) is 0.78–0.85× of ICU's speed (1.65× faster on
paths) because it allocates a fresh `[UInt8]` per call BY API CONTRACT; the
inout twin is the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU — floor
**2.88× in WMO** (`localizedCaseInsensitiveCompare` on thai) and **1.95× in
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
