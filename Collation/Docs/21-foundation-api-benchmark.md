# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-13 at 14:39–14:57 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`5f15c0a6` plus the EngineBench loop of 2026-11-13 (not committed at the time
of the run; the engine code is HEAD's). **The tables show the MEDIAN of 4
runs** (the recording rule of 2026-11-04, Docs/27; technique log §51 (au)).

**A new start for the Swift columns of Table 1 (2026-11-13, technique log
§52 (k)).** Until this recording, EngineBench's loop read three globals and
called `Order.rawValue`; that cost 1.2–1.5 ns of each compare and about 1 ns
of each sortKey, and the C loop of the ICU columns costs nothing that shows.
The loop now uses local values (10 instructions around the call). The engine
did not change: **do not compare the Swift columns of Table 1 with any
recording before 2026-11-13.** The ICU columns and Table 2 are comparable
with the recordings since 2026-11-04 (§51 (at): not with numbers before it
at the level of a few percent).

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

**Machine state:** 1-minute load 6.0 → 5.8 → 5.9 → 8.3 → 8.6 at the starts
and ends of the four runs, memory full (12.0 GB swap; the user's apps stay
open by decision), on AC power, under `caffeinate -i`. **A first series the
same day (14:06–14:29) did not count and is not recorded:** every column read
about 2% slow in all four runs (ICU C compare within 2.2%, sortKey within
2.7%, macOS within 3.5% of the gates).

**The checks (Docs/27), medians of the four runs:**

1. **ICU C** within 0.5% on compare (9.3/10.1/40.5/29.5/171.4 against
   9.3/10.1/40.7/29.5/172.0) and within 1.7% on sortKey
   (105.2/122.8/120.9/365.9/154.1 against 104.1/120.7/119.3/365.2/153.7) of
   its gates. The ICU checkout is on branch `main`, as before.
2. **macOS** `localizedCompare` 202/350/354/312/502 against the reference
   200/341/354/314/502: within 2.6% — latin is 0.1 point over the 2.5%
   limit (it read 349 on 2026-11-06 and 347 on 2026-11-12); the others are
   within 1.0%. With ICU C and the frozen binary on their values, the rule of
   Docs/27 for this case applies: recorded, and said here (user decision
   2026-11-13).
3. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`,
   load 7–11): `localizedStandardCompare` 53/55/81/75/273 against
   53/55/82/75/276, `localizedCompare` 38/40/58/57/258 against 39/40/58/56/257
   (within 3 ns).
4. **The loop check** (new, Docs/27; `Collation/Tools/insn-count/loop_check.sh`
   on the EngineBench binary of the series): per pass, ascii / latin / cjk
   150.2 / 149.2 / 287.0 instructions inside `compare` and 11.7 in the loop;
   no position rule applies.
5. **Two-level cells** (the four runs 5% or more apart; ‡, ranges under
   Table 2): four, all WMO — `localizedCompare` latin (12–13),
   `compare(_:locale:)` ascii (17–18), the `.localizedStandard` sort latin
   (1008–1091) and paths (97–102).

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
| ASCII  | 12 | **16.83× faster** | 30 | 6.73× faster | 202 |
| Latin  | 12‡ | **28.00× faster** | 31 | 11.29× faster | 350 |
| CJK    | 24 | **14.77× faster** | 49 | 7.23× faster | 354.5 |
| Paths  | 23 | **13.54× faster** | 44 | 7.08× faster | 311.5 |
| Thai   | 165.5 | **3.03× faster** | 217.5 | 2.31× faster | 501.5 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 14 | **14.39× faster** | 33 | 6.11× faster | 201.5 |
| Latin  | 15 | **22.77× faster** | 34 | 10.04× faster | 341.5 |
| CJK    | 31 | **11.40× faster** | 62 | 5.70× faster | 353.5 |
| Paths  | 26 | **12.56× faster** | 53 | 6.16× faster | 326.5 |
| Thai   | 166 | **2.92× faster** | 220 | 2.21× faster | 485.5 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 15 | **13.47× faster** | 34 | 5.94× faster | 202 |
| Latin  | 16 | **21.31× faster** | 34 | 10.03× faster | 341 |
| CJK    | 32 | **11.00× faster** | 62 | 5.68× faster | 352 |
| Paths  | 26 | **12.12× faster** | 51 | 6.18× faster | 315 |
| Thai   | 167 | **2.90× faster** | 220.5 | 2.20× faster | 484 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17‡ | **18.26× faster** | 31 | 10.02× faster | 310.5 |
| Latin  | 18 | **25.64× faster** | 32 | 14.42× faster | 461.5 |
| CJK    | 29 | **16.14× faster** | 52 | 9.00× faster | 468 |
| Paths  | 29 | **14.10× faster** | 46 | 8.89× faster | 409 |
| Thai   | 171.5 | **3.58× faster** | 218.5 | 2.81× faster | 614 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 25 | **12.32× faster** | 48 | 6.42× faster | 308 |
| Latin  | 25 | **18.28× faster** | 49 | 9.33× faster | 457 |
| CJK    | 42 | **11.24× faster** | 76 | 6.21× faster | 472 |
| Paths  | 35 | **11.96× faster** | 65 | 6.44× faster | 418.5 |
| Thai   | 177.5 | **3.12× faster** | 239 | 2.32× faster | 553.5 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 129 | **7.45× faster** | 227 | 4.24× faster | 961.5 |
| Latin  | 147.5 | **9.49× faster** | 254 | 5.51× faster | 1400.5 |
| CJK    | 153.5 | **7.95× faster** | 262 | 4.66× faster | 1220 |
| Paths  | 129 | **7.13× faster** | 220 | 4.18× faster | 920 |
| Thai   | 150.5 | **8.87× faster** | 235.5 | 5.67× faster | 1334.5 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 129 | **7.52× faster** | 226 | 4.29× faster | 970.5 |
| Latin  | 149 | **9.73× faster** | 252 | 5.75× faster | 1450 |
| CJK    | 153.5 | **8.00× faster** | 260.5 | 4.71× faster | 1228 |
| Paths  | 98 | **9.46× faster** | 176 | 5.27× faster | 927 |
| Thai   | 150.5 | **9.20× faster** | 236 | 5.87× faster | 1385 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 138 | **6.95× faster** | 295.5 | 3.25× faster | 959 |
| Latin  | 155.5 | **8.99× faster** | 321 | 4.36× faster | 1398 |
| CJK    | 158.5 | **7.68× faster** | 281.5 | 4.33× faster | 1217.5 |
| Paths  | 168 | **5.55× faster** | 270 | 3.46× faster | 933 |
| Thai   | 202.5 | **6.81× faster** | 366.5 | 3.76× faster | 1379 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38.5 | **8.71× faster** | 79 | 4.25× faster | 335.5 |
| Latin  | 170.5 | **4.65× faster** | 345 | 2.30× faster | 793.5 |
| CJK    | 171.5 | **3.40× faster** | 299 | 1.95× faster | 582.5 |
| Paths  | 49 | **6.49× faster** | 88 | 3.61× faster | 318 |
| Thai   | 191 | **3.76× faster** | 371.5 | 1.94× faster | 719 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 39 | **8.78× faster** | 82 | 4.18× faster | 342.5 |
| Latin  | 169.5 | **4.87× faster** | 288 | 2.87× faster | 825.5 |
| CJK    | 169.5 | **3.48× faster** | 292.5 | 2.02× faster | 590.5 |
| Paths  | 84 | **5.86× faster** | 123 | 4.00× faster | 492 |
| Thai   | 187 | **4.11× faster** | 310.5 | 2.47× faster | 768 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1037.5 | **12.51× faster** | 1428 | 9.09× faster | 12978.5 |
| Latin  | 1069‡ | **14.38× faster** | 1491 | 10.31× faster | 15371.5 |
| CJK    | 1301.5 | **12.38× faster** | 1881 | 8.57× faster | 16116.5 |
| Paths  | 100‡ | **10.83× faster** | 155.5 | 6.93× faster | 1077.5 |
| Thai   | 628.5 | **8.40× faster** | 893.5 | 5.91× faster | 5278.5 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 831.5 | **4.68× faster** | 1141.5 | 3.41× faster | 3887.5 |
| Latin  | 867.5 | **7.00× faster** | 1195.5 | 5.08× faster | 6071 |
| CJK    | 1169.5 | **5.43× faster** | 1540 | 4.13× faster | 6353.5 |
| Paths  | 80 | **4.81× faster** | 105 | 3.67× faster | 385 |
| Thai   | 615.5 | **3.65× faster** | 822 | 2.74× faster | 2249.5 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2392 | **6.02× faster** | 2796 | 5.15× faster | 14389.5 |
| Latin  | 2454.5 | **6.80× faster** | 2874.5 | 5.80× faster | 16682.5 |
| CJK    | 2858.5 | **6.16× faster** | 3416 | 5.15× faster | 17598 |
| Paths  | 210 | **5.68× faster** | 246 | 4.85× faster | 1192 |
| Thai   | 1134 | **5.08× faster** | 1394.5 | 4.13× faster | 5762.5 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1402 | **9.42× faster** | 1881 | 7.02× faster | 13207 |
| Latin  | 1469 | **10.67× faster** | 1953.5 | 8.02× faster | 15676 |
| CJK    | 1758.5 | **9.34× faster** | 2337 | 7.03× faster | 16419.5 |
| Paths  | 131 | **8.40× faster** | 170 | 6.47× faster | 1100 |
| Thai   | 772.5 | **6.90× faster** | 1043.5 | 5.11× faster | 5328.5 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 4 runs:
- localizedCompare, Latin, WMO: 12–13
- compare(locale:), ASCII, WMO: 17–18
- sortStdComparator, Latin, WMO: 1008–1091
- sortStdComparator, Paths, WMO: 97–102

Floor (lowest speedup): WMO 2.90× (localizedCaseICmp thai); `-no-WMO` 1.94× (range(of:locale:) thai).

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
| ASCII  | 7.6 | 9.3 | **1.22× faster** | 71.5 | 105.2 | **1.47× faster** | 119.5 | 0.88× (slower) |
| Latin  | 7.9 | 10.1 | **1.28× faster** | 91.6 | 122.8 | **1.34× faster** | 144.1 | 0.85× (slower) |
| CJK    | 17.8 | 40.5 | **2.28× faster** | 100.2 | 120.9 | **1.21× faster** | 148.1 | 0.82× (slower) |
| Paths  | 18.1 | 29.5 | **1.63× faster** | 172.6 | 365.9 | **2.12× faster** | 218.2 | **1.68× faster** |
| Thai   | 158.1 | 171.4 | **1.08× faster** | 141.8 | 154.1 | **1.09× faster** | 190.4 | 0.81× (slower) |

**The loop of EngineBench (2026-11-13, technique log §52 (k)).** These Swift columns are the first with the loop that uses local values. The recording of 2026-11-06 (the old loop, the same engine but for comment and cold-path changes) read compare 8.9 / 9.1 / 18.4 / 19.9 / 160.4, sortKey 71.8 / 92.1 / 101.1 / 173.4 / 143.1 and allocating sortKey 120.3 / 142.8 / 149.2 / 219.9 / 192.8; the differences are the cost of the old loop (and, on latin and cjk compare, 0.3–0.5 ns of a call that the old loop made since `b30a9e66` — the unrecorded series of 2026-11-12 read 9.4 / 18.9), not a change of the engine. The ICU columns are within 2% of 2026-11-06.

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

- compare: ascii **1.22×**, latin **1.28×**, cjk **2.28×**, paths
  **1.63×**, thai **1.08× faster**
- sortKey (inout): ascii **1.47×**, latin **1.34×**, cjk **1.21×**, paths
  **2.12×**, thai **1.09× faster**

**All ten rows are ahead of ICU C.** The `throws` and the two `String`
arguments of our API are included in our numbers; the cost of the old
benchmark loop (1.2–1.5 ns per compare until 2026-11-13, Docs/27) is not. The
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
