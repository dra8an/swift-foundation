# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-06 at 16:23–16:42 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`630ec5c7` — **the final matrix of the round** (pushed): the engine of
§51 (az)–(bb) plus §51 (bd), whose change is collator creation only (not
timed by the matrix). **The tables show the MEDIAN of 4 runs** (the
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

**Machine state:** 1-minute load 6.0 → 3.6 → 21.2 → 13.5 → 4.2 during the
four runs (a burst during run 3: its checks and cells agree with the other
runs), 7 h after the last wake, memory full (~11 GB swap; the user's apps
stay open by decision), on AC power, under `caffeinate -i`.

**The checks (Docs/27), medians of the four runs:**

1. **ICU C** within 0.5% (compare 9.3/10.1/40.5/29.5/172.2 against
   9.3/10.1/40.7/29.5/172.0; sortKey 104.0/120.7/119.8/365.3/153.9 against
   104.1/120.7/119.3/365.2/153.7) of its gates. The ICU checkout is on branch
   `main`, as before.
2. **macOS** `localizedCompare` 201/349/356/312/504 against the reference
   200/341/354/314/502: within 2.3% (latin, as in every series since
   2026-11-05; the others within 0.6%).
3. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`,
   load 4–10): `localizedStandardCompare` 53/55/82/75/277 against
   53/55/82/75/276, `localizedCompare` 36/40/59/56/261 against 39/40/58/56/257
   (within 4 ns).
4. **Two-level cells** (the four runs 5% or more apart; ‡, ranges under
   Table 2): two, `range(of:locale:)` and `range(backwards)` ascii `-no-WMO`
   (82–87, 83–88).

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
| Latin  | 12 | **29.08× faster** | 31 | 11.26× faster | 349 |
| CJK    | 24 | **14.81× faster** | 48 | 7.41× faster | 355.5 |
| Paths  | 23 | **13.59× faster** | 44.5 | 7.02× faster | 312.5 |
| Thai   | 166.5 | **3.03× faster** | 220.5 | 2.29× faster | 504.5 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 14 | **14.21× faster** | 34 | 5.85× faster | 199 |
| Latin  | 15 | **22.60× faster** | 34 | 9.97× faster | 339 |
| CJK    | 31 | **11.45× faster** | 62 | 5.73× faster | 355 |
| Paths  | 26 | **12.60× faster** | 51 | 6.42× faster | 327.5 |
| Thai   | 167 | **2.92× faster** | 224 | 2.18× faster | 488 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 15 | **13.30× faster** | 34 | 5.87× faster | 199.5 |
| Latin  | 16 | **21.12× faster** | 34 | 9.94× faster | 338 |
| CJK    | 32 | **11.09× faster** | 62 | 5.73× faster | 355 |
| Paths  | 26 | **12.17× faster** | 52 | 6.09× faster | 316.5 |
| Thai   | 168 | **2.90× faster** | 225.5 | 2.16× faster | 486.5 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17 | **17.91× faster** | 30 | 10.15× faster | 304.5 |
| Latin  | 18 | **25.39× faster** | 31 | 14.74× faster | 457 |
| CJK    | 29 | **16.19× faster** | 52 | 9.03× faster | 469.5 |
| Paths  | 29 | **14.19× faster** | 45 | 9.14× faster | 411.5 |
| Thai   | 173 | **3.57× faster** | 220 | 2.80× faster | 617 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 24 | **12.73× faster** | 46 | 6.64× faster | 305.5 |
| Latin  | 24 | **18.90× faster** | 48 | 9.45× faster | 453.5 |
| CJK    | 42 | **11.31× faster** | 77.5 | 6.13× faster | 475 |
| Paths  | 35 | **11.97× faster** | 64 | 6.55× faster | 419 |
| Thai   | 178 | **3.13× faster** | 240.5 | 2.31× faster | 556.5 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 129 | **7.38× faster** | 222.5 | 4.28× faster | 952.5 |
| Latin  | 148 | **9.37× faster** | 248 | 5.59× faster | 1386.5 |
| CJK    | 155.5 | **7.87× faster** | 259 | 4.72× faster | 1223.5 |
| Paths  | 133 | **6.96× faster** | 218 | 4.25× faster | 925.5 |
| Thai   | 151 | **8.90× faster** | 233.5 | 5.75× faster | 1343.5 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 129 | **7.43× faster** | 222 | 4.32× faster | 959 |
| Latin  | 148 | **9.69× faster** | 247.5 | 5.80× faster | 1434.5 |
| CJK    | 155.5 | **7.89× faster** | 260 | 4.72× faster | 1226.5 |
| Paths  | 99.5 | **9.38× faster** | 175 | 5.33× faster | 933.5 |
| Thai   | 151 | **9.22× faster** | 233 | 5.97× faster | 1391.5 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 135 | **7.03× faster** | 288.5 | 3.29× faster | 949.5 |
| Latin  | 154 | **9.01× faster** | 314.5 | 4.41× faster | 1388 |
| CJK    | 159.5 | **7.69× faster** | 281.5 | 4.36× faster | 1226 |
| Paths  | 167 | **5.62× faster** | 270.5 | 3.47× faster | 939 |
| Thai   | 204 | **6.80× faster** | 364.5 | 3.81× faster | 1387 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 37 | **9.07× faster** | 87‡ | 3.86× faster | 335.5 |
| Latin  | 167.5 | **4.70× faster** | 340 | 2.31× faster | 786.5 |
| CJK    | 173 | **3.39× faster** | 307.5 | 1.91× faster | 586 |
| Paths  | 48 | **6.65× faster** | 96 | 3.32× faster | 319 |
| Thai   | 190 | **3.80× faster** | 372.5 | 1.94× faster | 722 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38 | **8.88× faster** | 87‡ | 3.88× faster | 337.5 |
| Latin  | 169 | **4.88× faster** | 288.5 | 2.86× faster | 824 |
| CJK    | 171.5 | **3.45× faster** | 296.5 | 1.99× faster | 591.5 |
| Paths  | 83.5 | **5.91× faster** | 130 | 3.80× faster | 493.5 |
| Thai   | 188.5 | **4.11× faster** | 312 | 2.48× faster | 774 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 964.5 | **13.43× faster** | 1426 | 9.08× faster | 12950 |
| Latin  | 1066.5 | **14.38× faster** | 1480.5 | 10.36× faster | 15335 |
| CJK    | 1327.5 | **12.22× faster** | 1861 | 8.72× faster | 16224 |
| Paths  | 103 | **10.47× faster** | 147 | 7.33× faster | 1078 |
| Thai   | 632 | **8.37× faster** | 911.5 | 5.80× faster | 5290 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 821.5 | **4.72× faster** | 1124 | 3.45× faster | 3880 |
| Latin  | 866 | **6.95× faster** | 1179 | 5.10× faster | 6016 |
| CJK    | 1173.5 | **5.42× faster** | 1538 | 4.14× faster | 6361.5 |
| Paths  | 80 | **4.81× faster** | 103 | 3.73× faster | 384.5 |
| Thai   | 629.5 | **3.59× faster** | 828 | 2.73× faster | 2259.5 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2387.5 | **5.95× faster** | 2805.5 | 5.07× faster | 14210.5 |
| Latin  | 2477.5 | **6.70× faster** | 2880 | 5.77× faster | 16607 |
| CJK    | 2880 | **6.14× faster** | 3396 | 5.20× faster | 17674 |
| Paths  | 213 | **5.60× faster** | 244 | 4.89× faster | 1192 |
| Thai   | 1139 | **5.08× faster** | 1399 | 4.13× faster | 5783.5 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1406 | **9.38× faster** | 1865.5 | 7.07× faster | 13182 |
| Latin  | 1476.5 | **10.52× faster** | 1902.5 | 8.16× faster | 15525.5 |
| CJK    | 1780.5 | **9.27× faster** | 2315 | 7.13× faster | 16498.5 |
| Paths  | 132.5 | **8.31× faster** | 168.5 | 6.53× faster | 1100.5 |
| Thai   | 776 | **6.90× faster** | 1047 | 5.12× faster | 5358 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 4 runs:
- range(of:locale:), ASCII, `-no-WMO`: 82–87
- range(backwards), ASCII, `-no-WMO`: 83–88

Floor (lowest speedup): WMO 2.90× (localizedCaseICmp thai); `-no-WMO` 1.91× (range(of:locale:) cjk).

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
| ASCII  | 8.9 | 9.3 | **1.04× faster** | 71.8 | 104.0 | **1.45× faster** | 120.3 | 0.86× (slower) |
| Latin  | 9.1 | 10.1 | **1.11× faster** | 92.1 | 120.7 | **1.31× faster** | 142.8 | 0.84× (slower) |
| CJK    | 18.4 | 40.5 | **2.20× faster** | 101.1 | 119.8 | **1.19× faster** | 149.2 | 0.80× (slower) |
| Paths  | 19.9 | 29.5 | **1.49× faster** | 173.4 | 365.3 | **2.11× faster** | 219.9 | **1.66× faster** |
| Thai   | 160.4 | 172.2 | **1.07× faster** | 143.1 | 153.9 | **1.08× faster** | 192.8 | 0.80× (slower) |


**The skRet column (the allocating `sortKey(for:)`) and ICU** (technique log §51 (be), 2026-11-09): ICU's `ucol_getSortKey` writes into the caller's buffer; ours returns a new `[UInt8]`. About three quarters of the extra ~530 instructions per key are the new array itself (`malloc` ~265, the standard library's `malloc_size` ~130 with macOS 27's allocator); the rest is array plumbing, already in its cheapest form (three other forms tried, all slower). The like-for-like cell is the inout `sortKey`.

**Change against the recording of 2026-11-06 afternoon (13:45–14:04,
`6266beef`; the same engine but for §51 (bd), which changes creation
only).** Table 1 within 1% except ascii compare 8.8 → 8.9 (+1.1%: the
machine code of every compare function is identical, 320 bytes lower in the
binary — §51 (bd), whose plain EngineBench A/B read the same +1.1% at the
minimum and the aligned one 0.0%). Table 2: the `-no-WMO` sorts 3.5–5.5%
faster (`SortDescriptor` latin 2013.5 → 1902.5, the `.localizedStandard`
sort ascii / latin / paths −3.7..−3.9%), WMO `localizedStandardCompare` /
`localizedCaseInsensitiveCompare` paths 27 → 26; two "+" cells:
`localizedStandardCompare` ascii `-no-WMO` 33 → 34 (the step of the plain
`-no-WMO` A/B of §51 (bd); aligned 33 → 33) and `range(of:locale:)` cjk
`-no-WMO` 297.5 → 307.5 (+3.4%; the search does not run the changed code);
the rest within ±3%. Floor 2.90× WMO, 1.91× `-no-WMO`.

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
step). The first two were checked afterwards (technique log §51 (bb), the
paragraph after the matrix line): every counted call runs the same or fewer
instructions than at `d7508847`; `d7508847` itself reads 52 ns on
`compare(_:locale:)` cjk in a new `-no-WMO` build; the `SortDescriptor` sort
changes sign between a plain and an aligned `-no-WMO` build, and one
`SortDescriptor` comparison is not slower in either — code placement, not
work.

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
