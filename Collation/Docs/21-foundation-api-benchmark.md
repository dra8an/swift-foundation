# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-06 at 13:45–14:04 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`6266beef` (the engine of `726821fc`: §51 (az) the option sets of the
Foundation wrappers resolved at init; §51 (ba) ko's hanja in the quick CJK
compare; §51 (bb) the OFFSET primaries of CJK ideographs with unsigned
arithmetic). **The tables show the MEDIAN of 4 runs** (the
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

**Machine state:** 1-minute load 9.2 → 3.5 → 4.4 during the four runs (a
burst to 27.7 at the end of run 4, after its timed part: run 4 agrees with
runs 1–3 cell for cell), 4 h 28 min after the last wake, memory full (~12 GB
swap; the user's apps stay open by decision), on AC power, under
`caffeinate -i`.

**The checks (Docs/27), medians of the four runs:**

1. **ICU C** within 0.2% (compare 9.3/10.1/40.6/29.5/172.3 against
   9.3/10.1/40.7/29.5/172.0; sortKey 104.2/120.8/119.6/365.8/154.0 against
   104.1/120.7/119.3/365.2/153.7) of its gates. The ICU checkout is on branch
   `main`, as before.
2. **macOS** `localizedCompare` 202/348/356/313/504 against the reference
   200/341/354/314/502: within 1.9% (latin; run 1 alone read latin 350,
   +2.6%; the others within 0.9%).
3. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`,
   run in the burst after run 4, load 20–28): `localizedStandardCompare`
   53/55/82/75/279 against 53/55/82/75/276, `localizedCompare` 36/40/60/56/260
   against 39/40/58/56/257 (within 3 ns); not needed for the decision, because
   the macOS side is within its gate.
4. **Two-level cells** (the four runs 5% or more apart; ‡, ranges under
   Table 2): three, all the `.localizedStandard` sort (ascii, latin, paths
   WMO, 6–7% apart; not explained, as in the series of 2026-11-05).

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
| Latin  | 12 | **28.96× faster** | 31 | 11.21× faster | 347.5 |
| CJK    | 24 | **14.81× faster** | 48 | 7.41× faster | 355.5 |
| Paths  | 23.5 | **13.32× faster** | 44 | 7.11× faster | 313 |
| Thai   | 166 | **3.04× faster** | 220.5 | 2.29× faster | 504.5 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 14 | **14.21× faster** | 33 | 6.03× faster | 199 |
| Latin  | 15 | **22.63× faster** | 34 | 9.99× faster | 339.5 |
| CJK    | 31.5 | **11.27× faster** | 61 | 5.82× faster | 355 |
| Paths  | 27 | **12.15× faster** | 51 | 6.43× faster | 328 |
| Thai   | 168 | **2.90× faster** | 223 | 2.19× faster | 488 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 15 | **13.33× faster** | 34 | 5.88× faster | 200 |
| Latin  | 16 | **21.19× faster** | 34 | 9.97× faster | 339 |
| CJK    | 33 | **10.73× faster** | 62 | 5.71× faster | 354 |
| Paths  | 27 | **11.74× faster** | 52 | 6.10× faster | 317 |
| Thai   | 168 | **2.90× faster** | 223 | 2.18× faster | 486.5 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17 | **17.94× faster** | 30 | 10.17× faster | 305 |
| Latin  | 18 | **25.33× faster** | 31 | 14.71× faster | 456 |
| CJK    | 29.5 | **15.97× faster** | 52 | 9.06× faster | 471 |
| Paths  | 29 | **14.14× faster** | 45 | 9.11× faster | 410 |
| Thai   | 173 | **3.56× faster** | 220 | 2.80× faster | 616.5 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 24 | **12.69× faster** | 47 | 6.48× faster | 304.5 |
| Latin  | 24 | **18.85× faster** | 48 | 9.43× faster | 452.5 |
| CJK    | 42 | **11.31× faster** | 77 | 6.17× faster | 475 |
| Paths  | 35 | **12.00× faster** | 65 | 6.46× faster | 420 |
| Thai   | 177 | **3.14× faster** | 237.5 | 2.34× faster | 555.5 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128 | **7.43× faster** | 222 | 4.28× faster | 951 |
| Latin  | 147 | **9.42× faster** | 248 | 5.58× faster | 1385 |
| CJK    | 155 | **7.89× faster** | 258.5 | 4.73× faster | 1223 |
| Paths  | 132 | **7.00× faster** | 217 | 4.26× faster | 924.5 |
| Thai   | 151 | **8.88× faster** | 232 | 5.78× faster | 1340.5 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128 | **7.49× faster** | 222 | 4.32× faster | 959 |
| Latin  | 147 | **9.75× faster** | 247.5 | 5.79× faster | 1433.5 |
| CJK    | 154.5 | **7.96× faster** | 259 | 4.75× faster | 1230.5 |
| Paths  | 98 | **9.48× faster** | 174 | 5.34× faster | 929 |
| Thai   | 151 | **9.20× faster** | 233 | 5.96× faster | 1389.5 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 134 | **7.10× faster** | 289 | 3.29× faster | 951 |
| Latin  | 154 | **9.01× faster** | 313 | 4.43× faster | 1388 |
| CJK    | 159 | **7.71× faster** | 279.5 | 4.38× faster | 1225.5 |
| Paths  | 168 | **5.59× faster** | 268.5 | 3.50× faster | 938.5 |
| Thai   | 203.5 | **6.81× faster** | 362.5 | 3.82× faster | 1385 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 37 | **9.05× faster** | 85 | 3.94× faster | 335 |
| Latin  | 171.5 | **4.60× faster** | 335 | 2.36× faster | 789 |
| CJK    | 175.5 | **3.33× faster** | 297.5 | 1.96× faster | 584 |
| Paths  | 47 | **6.81× faster** | 94.5 | 3.39× faster | 320 |
| Thai   | 191 | **3.78× faster** | 364.5 | 1.98× faster | 722 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38 | **8.89× faster** | 87 | 3.89× faster | 338 |
| Latin  | 168 | **4.89× faster** | 280.5 | 2.93× faster | 821.5 |
| CJK    | 170 | **3.49× faster** | 288 | 2.06× faster | 593 |
| Paths  | 82 | **6.02× faster** | 129.5 | 3.81× faster | 494 |
| Thai   | 186.5 | **4.15× faster** | 304 | 2.55× faster | 774 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 997‡ | **12.97× faster** | 1481.5 | 8.73× faster | 12933.5 |
| Latin  | 1038‡ | **14.78× faster** | 1538 | 9.98× faster | 15352 |
| CJK    | 1330 | **12.16× faster** | 1904.5 | 8.49× faster | 16170 |
| Paths  | 102‡ | **10.53× faster** | 153 | 7.05× faster | 1079 |
| Thai   | 625.5 | **8.47× faster** | 912 | 5.81× faster | 5297 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 822.5 | **4.72× faster** | 1143 | 3.40× faster | 3882 |
| Latin  | 866.5 | **6.99× faster** | 1198 | 5.05× faster | 6054 |
| CJK    | 1175.5 | **5.46× faster** | 1558.5 | 4.12× faster | 6414 |
| Paths  | 80 | **4.80× faster** | 105.5 | 3.64× faster | 384 |
| Thai   | 622.5 | **3.61× faster** | 833.5 | 2.70× faster | 2247 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2363.5 | **6.02× faster** | 2884 | 4.93× faster | 14221.5 |
| Latin  | 2422 | **6.90× faster** | 2963.5 | 5.64× faster | 16716.5 |
| CJK    | 2841.5 | **6.22× faster** | 3478 | 5.08× faster | 17677 |
| Paths  | 208.5 | **5.73× faster** | 249 | 4.80× faster | 1194 |
| Thai   | 1122 | **5.17× faster** | 1414 | 4.10× faster | 5797 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1395 | **9.40× faster** | 1919.5 | 6.83× faster | 13114.5 |
| Latin  | 1450.5 | **10.70× faster** | 2013.5 | 7.71× faster | 15517.5 |
| CJK    | 1776.5 | **9.29× faster** | 2398 | 6.88× faster | 16497.5 |
| Paths  | 133.5 | **8.25× faster** | 175 | 6.29× faster | 1101 |
| Thai   | 772.5 | **6.94× faster** | 1056.5 | 5.07× faster | 5357.5 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 4 runs:
- sortStdComparator, ASCII, WMO: 967–1027
- sortStdComparator, Latin, WMO: 1009–1068
- sortStdComparator, Paths, WMO: 97–104

Floor (lowest speedup): WMO 2.90× (localizedCaseICmp thai); `-no-WMO` 1.96× (range(of:locale:) cjk).

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
| ASCII  | 8.8 | 9.3 | **1.06× faster** | 71.7 | 104.2 | **1.45× faster** | 120.4 | 0.87× (slower) |
| Latin  | 9.1 | 10.1 | **1.11× faster** | 92.2 | 120.8 | **1.31× faster** | 143.7 | 0.84× (slower) |
| CJK    | 18.4 | 40.6 | **2.20× faster** | 101.0 | 119.6 | **1.18× faster** | 149.5 | 0.80× (slower) |
| Paths  | 19.9 | 29.5 | **1.48× faster** | 173.5 | 365.8 | **2.11× faster** | 220.8 | **1.66× faster** |
| Thai   | 160.4 | 172.3 | **1.07× faster** | 143.1 | 154.0 | **1.08× faster** | 192.1 | 0.80× (slower) |


**Change against the recording of 2026-11-05 (14:33–14:52, `d7508847`)**,
from §51 (az) (every compare with non-default options −26..−43
instructions), (ba) (ko only; no ko row in the matrix) and (bb) (cjk compare
−6.1% instructions, cjk sortKey −2.3%). Table 1: cjk compare **19.6 →
18.4** (2.08× → **2.20×**), cjk sortKey 102.7 → 101.0 (1.17× → 1.18×); the
other cells within 1% (ascii compare 8.7 → 8.8, paths compare 19.1 → 19.9:
the two levels of paths since §51 (au)). Table 2, ns, ours:

| row, column | ascii | latin | cjk | paths | thai |
|---|---|---|---|---|---|
| `localizedStandardCompare`, WMO | 15 → **14** | 16 → **15** | 33 → **31.5** | 28 → **27** | 169 → 168 |
| `localizedStandardCompare`, `-no-WMO` | 34 → **33** | 35 → **34** | 64.5 → **61** | 54 → **51** | 227 → 223 |
| `localizedCaseInsensitiveCompare`, WMO | 16 → **15** | 16 → 16 | 34 → **33** | 27 → 27 | 169 → 168 |
| `localizedCaseInsensitiveCompare`, `-no-WMO` | 34 → 34 | 35 → **34** | 64 → **62** | 54 → **52** | 226.5 → 223 |
| options compare, WMO | 24 → 24 | 25 → **24** | 44 → **42** | 36 → **35** | 179.5 → 177 |
| options compare, `-no-WMO` | 47 → 47 | 48 → 48 | 78.5 → 77 | 68 → **65** | 239 → 237.5 |
| search rows (contains, range), cjk / paths / thai | | | −1.4..−3.3% | −0.5..−2.3% | 0..−2.5% |

The rest moved within ±1.5%. Three "+" cells, each steady over the four
runs (not two-level): `compare(_:locale:)` cjk `-no-WMO` 49 → 52 (+6.1%;
no probe group counts this row on cjk; its sibling `localizedCompare` cjk
`-no-WMO` 48 → 48, and every counted root cjk group −11 instructions in both
modes since (bb)); the `SortDescriptor` sort `-no-WMO` ascii / latin 1882.5 /
1961.5 → 1919.5 / 2013.5 (+2.0 / +2.7%; its comparator `.localizedStandard`
counted −12 instructions in `-no-WMO` in (az), the same comparator in the
`.localizedStandard` sort row +0.8 / +0.8%, the WMO column −1.1 / −3.4%);
`localizedCompare` paths WMO 23 → 23.5 (runs 23, 24, 24, 23: a whole-ns
step). The first two are not explained by a count or an A/B yet.

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
