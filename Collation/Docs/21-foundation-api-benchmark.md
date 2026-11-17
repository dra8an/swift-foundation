# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-17 at 09:49–10:17 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`0d757075` (pushed). **The tables show the MEDIAN of 6 runs** (the recording
rule of 2026-11-04 asks for at least 4; Docs/27, technique log §51 (au)).

**THE BASELINE of 2026-11-17 — three things are new, so compare with older
recordings only as said here** (technique log §52 (k), (l), (m)):

1. **The benchmark loops (2026-11-13).** EngineBench's loop read three
   globals and called `Order.rawValue`; that cost 1.2–1.5 ns of each compare
   and about 1 ns of each sortKey. All three bench programs now use local
   values in their timed loops. The engine did not change. **The Swift
   columns of Table 1 are not comparable with any recording before
   2026-11-13.** In Table 2 only `compare(_:locale:)` moved with the loops
   (−0.6 ns on ascii and latin).
2. **Table 2 has one decimal (2026-11-13).** Both Table 2 programs print
   rounded tenths; before, whole nanoseconds, cut off. Compare Table 2 with
   older recordings at the level of one nanosecond only.
3. **The ICU reference is ICU 80.0.1 (2026-11-16).** The local ICU checkout
   was rebuilt; until then it was ICU 79.1. In this matrix, ICU 80.0.1
   reads compare within 1.7% of 79.1 (paths 29.5 → 30.0) and **sortKey
   1.6–4.3% faster** (104.1 / 120.7 / 119.3 / 365.2 / 153.7 → 100.9 / 117.0 /
   115.7 / 349.6 / 151.2). So the sortKey speedups of Table 1 are lower than
   on 2026-11-13 with unchanged Swift times. **The ICU columns are not
   comparable with older recordings at the level of 2–5%.**

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

**Machine state:** on AC power from start to end, under `caffeinate -i`;
41 minutes after the last wake; 1-minute load 31 → 14 → 6 → 5 → 4 → 4 → 7 at
the starts and ends of the six runs (a busy phase ended as the series
started; 72% of the processor was idle); memory full (13.4 → 12.8 GB swap;
the user's apps stay open by decision). Before the start, the unchanged
EngineBench binary read its values of 2026-11-13 (compare 7.6 / 7.9 / 157.7
on ascii / latin / thai).

**The checks (Docs/27), medians of the six runs:**

1. **macOS** `localizedCompare` 201/347/355/314/505 against the reference
   200/341/354/314/502: within 1.8% (limit 2.5%). From this series on, its
   medians are the reference (201.3/347.2/355.2/313.6/505.0; user decision
   2026-11-17, Docs/27): latin read 347–350 against 341 in every series
   since 2026-11-05.
2. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`,
   load 7–8): `localizedStandardCompare` 53/55/81/75/275 against
   53/55/82/75/276, `localizedCompare` 38/40/59/56/258 against 39/40/58/56/257
   (within 1 ns).
3. **ICU C: new gates.** The two checks above do not depend on the ICU
   version, and both passed; so the medians of this series are the gates for
   ICU 80.0.1 (user decision 2026-11-17; `matrix_record.py`, Docs/27):
   compare 9.3/10.1/40.8/30.0/171.9, sortKey 100.9/117.0/115.7/349.6/151.2.
4. **The loop check** (Docs/27; `Collation/Tools/insn-count/loop_check.sh`):
   the EngineBench binary is the one checked on 2026-11-13, unchanged — per
   pass, ascii / latin / cjk 150.2 / 149.2 / 287.0 instructions inside
   `compare` and 11.7 in the loop; no position rule applies.
5. **The six runs against each other:** the compare cells of Table 1 on
   ascii, latin and paths differ by 0.2 ns at most. **Two-level cells** (the
   runs 5% or more apart; ‡, ranges under Table 2): two, both the
   `.localizedStandard` sort, WMO — ascii (961.9–1024.5) and latin
   (1009.6–1069.4). The marks of 2026-11-13 on `localizedCompare` latin and
   `compare(_:locale:)` ascii were the cut-off at a whole number; with the
   decimal they are gone (13.0 and 17.1).

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout: **ICU 80.0.1** since 2026-11-16 (before: ICU 79.1 with Unicode 18
data), not the 79.0.1 data that our collator bundles. Its KEYS differ from
ours: do not generate golden files from that checkout (technique log §49).

**The harness** (Docs/27, "What the harness itself costs"): since 2026-11-13
the Swift loops have 10 instructions around a compare, the C loop 13; neither
adds time that shows. What stays in our numbers is what a caller pays: two
`String` arguments, the options, the call, the error check of a throwing
call.

Same Foundation APIs, two backends:

- **Swift Collator**: `BenchFoundation`, release, WMO and `-no-WMO`
- **System ICU**: pre-compiled `bench_system` (system Foundation → NSString →
  CoreFoundation → ICU), compiled with the same Swift 6.5

Table 2 values have one decimal (both programs round the same way); a median
of six runs can end in a half tenth.

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 12.4 | **16.23× faster** | 31.6 | 6.38× faster | 201.3 |
| Latin  | 13 | **26.71× faster** | 32.4 | 10.72× faster | 347.2 |
| CJK    | 24.1 | **14.71× faster** | 50.8 | 6.99× faster | 355.2 |
| Paths  | 23.7 | **13.23× faster** | 44.9 | 6.98× faster | 313.6 |
| Thai   | 166.4 | **3.03× faster** | 220 | 2.30× faster | 505 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 14.6 | **13.68× faster** | 35.1 | 5.69× faster | 199.8 |
| Latin  | 15.2 | **22.26× faster** | 35.5 | 9.53× faster | 338.4 |
| CJK    | 31.9 | **11.14× faster** | 63.8 | 5.56× faster | 354.8 |
| Paths  | 26.8 | **12.25× faster** | 54.7 | 6.01× faster | 328.2 |
| Thai   | 166.9 | **2.93× faster** | 223.4 | 2.19× faster | 488.6 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 15.5 | **12.89× faster** | 35.8 | 5.58× faster | 199.8 |
| Latin  | 16.1 | **20.98× faster** | 36.0 | 9.37× faster | 337.8 |
| CJK    | 33 | **10.74× faster** | 64.3 | 5.51× faster | 354.4 |
| Paths  | 26.8 | **11.83× faster** | 54.0 | 5.88× faster | 317.1 |
| Thai   | 168.5 | **2.88× faster** | 223.4 | 2.18× faster | 486 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17.1 | **17.74× faster** | 30.1 | 10.08× faster | 303.4 |
| Latin  | 17.7 | **25.69× faster** | 30.9 | 14.72× faster | 454.8 |
| CJK    | 29.2 | **16.04× faster** | 51.8 | 9.05× faster | 469.1 |
| Paths  | 28.5 | **14.37× faster** | 44.8 | 9.13× faster | 409.6 |
| Thai   | 172.2 | **3.57× faster** | 219.1 | 2.81× faster | 615 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 24 | **12.73× faster** | 46.9 | 6.51× faster | 305.5 |
| Latin  | 24.7 | **18.35× faster** | 48.3 | 9.38× faster | 453.1 |
| CJK    | 42.8 | **11.10× faster** | 76.8 | 6.18× faster | 475 |
| Paths  | 35.2 | **11.92× faster** | 64.7 | 6.49× faster | 419.6 |
| Thai   | 178.7 | **3.11× faster** | 238.6 | 2.33× faster | 555.5 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 127.8 | **7.43× faster** | 222.5 | 4.27× faster | 949.5 |
| Latin  | 148.2 | **9.35× faster** | 248.1 | 5.59× faster | 1386.2 |
| CJK    | 154.8 | **7.90× faster** | 261.9 | 4.67× faster | 1222.3 |
| Paths  | 130.6 | **7.08× faster** | 218.7 | 4.23× faster | 924.8 |
| Thai   | 151.1 | **8.84× faster** | 235.2 | 5.68× faster | 1336.2 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128.4 | **7.46× faster** | 223.6 | 4.29× faster | 958.2 |
| Latin  | 148.1 | **9.68× faster** | 249.4 | 5.75× faster | 1433.8 |
| CJK    | 154.9 | **7.95× faster** | 263.7 | 4.67× faster | 1230.8 |
| Paths  | 99.2 | **9.39× faster** | 176.9 | 5.26× faster | 930.9 |
| Thai   | 152.3 | **9.11× faster** | 236 | 5.88× faster | 1387.3 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 135.8 | **6.99× faster** | 288.9 | 3.29× faster | 949.9 |
| Latin  | 154.4 | **8.99× faster** | 314.5 | 4.42× faster | 1388.8 |
| CJK    | 159.8 | **7.65× faster** | 283.4 | 4.31× faster | 1221.8 |
| Paths  | 173 | **5.43× faster** | 268.7 | 3.49× faster | 938.5 |
| Thai   | 203.8 | **6.79× faster** | 364.4 | 3.80× faster | 1384.0 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38.5 | **8.63× faster** | 79.8 | 4.17× faster | 332.9 |
| Latin  | 170.1 | **4.63× faster** | 335.8 | 2.35× faster | 788.0 |
| CJK    | 173.7 | **3.35× faster** | 301.0 | 1.94× faster | 582.8 |
| Paths  | 49.4 | **6.48× faster** | 89 | 3.60× faster | 320.1 |
| Thai   | 192.4 | **3.74× faster** | 368.7 | 1.95× faster | 719.8 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 39.6 | **8.53× faster** | 81.8 | 4.12× faster | 337.6 |
| Latin  | 171.2 | **4.79× faster** | 282.0 | 2.91× faster | 820.5 |
| CJK    | 173.2 | **3.42× faster** | 292.4 | 2.02× faster | 591.8 |
| Paths  | 84.7 | **5.85× faster** | 123.7 | 4.00× faster | 495.1 |
| Thai   | 188.5 | **4.09× faster** | 306.5 | 2.52× faster | 771.7 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1022.4‡ | **12.63× faster** | 1468.7 | 8.79× faster | 12914.8 |
| Latin  | 1066.7‡ | **14.40× faster** | 1529.7 | 10.04× faster | 15358.4 |
| CJK    | 1286.7 | **12.63× faster** | 1919.5 | 8.46× faster | 16244.8 |
| Paths  | 102.5 | **10.52× faster** | 158 | 6.82× faster | 1078.0 |
| Thai   | 632.1 | **8.36× faster** | 909.1 | 5.81× faster | 5284.8 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 821.2 | **4.73× faster** | 1124.3 | 3.46× faster | 3885.1 |
| Latin  | 867.0 | **6.97× faster** | 1179.3 | 5.12× faster | 6039.4 |
| CJK    | 1171.4 | **5.45× faster** | 1543.9 | 4.13× faster | 6380.2 |
| Paths  | 80.5 | **4.78× faster** | 104.5 | 3.68× faster | 384.8 |
| Thai   | 623 | **3.61× faster** | 828.8 | 2.71× faster | 2249.9 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2366.6 | **6.01× faster** | 2832.7 | 5.02× faster | 14231.5 |
| Latin  | 2446.1 | **6.81× faster** | 2907.4 | 5.73× faster | 16646.2 |
| CJK    | 2846.9 | **6.22× faster** | 3457.7 | 5.12× faster | 17720.1 |
| Paths  | 210.4 | **5.67× faster** | 252.8 | 4.72× faster | 1193.4 |
| Thai   | 1131.8 | **5.15× faster** | 1400.7 | 4.16× faster | 5833.3 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1396.9 | **9.40× faster** | 1901.4 | 6.91× faster | 13132.5 |
| Latin  | 1443.8 | **10.80× faster** | 1942.8 | 8.03× faster | 15593.0 |
| CJK    | 1768.5 | **9.32× faster** | 2366 | 6.96× faster | 16477.7 |
| Paths  | 133.2 | **8.26× faster** | 174.9 | 6.29× faster | 1100.0 |
| Thai   | 779.2 | **6.87× faster** | 1052.0 | 5.09× faster | 5354.1 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 6 runs:
- sortStdComparator, ASCII, WMO: 961.9–1024.5
- sortStdComparator, Latin, WMO: 1009.6–1069.4

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
| ASCII  | 7.6 | 9.3 | **1.22× faster** | 71.0 | 100.9 | **1.42× faster** | 119.1 | 0.85× (slower) |
| Latin  | 7.9 | 10.1 | **1.28× faster** | 91.3 | 117.0 | **1.28× faster** | 142.4 | 0.82× (slower) |
| CJK    | 17.7 | 40.8 | **2.31× faster** | 100.8 | 115.7 | **1.15× faster** | 148.1 | 0.78× (slower) |
| Paths  | 18.1 | 30.0 | **1.66× faster** | 173.2 | 349.6 | **2.02× faster** | 219.1 | **1.60× faster** |
| Thai   | 158.8 | 171.9 | **1.08× faster** | 142.1 | 151.2 | **1.06× faster** | 191.3 | 0.79× (slower) |

**Change against the recording of 2026-11-13 (14:39–14:57, the same engine and the same EngineBench binary; ICU 79.1 then).** Our columns of Table 1 are within 1.2% (compare 7.6 / 7.9 / 17.8 / 18.1 / 158.1 → 7.6 / 7.9 / 17.7 / 18.1 / 158.8; sortKey 71.5 / 91.6 / 100.2 / 172.6 / 141.8 → 71.0 / 91.3 / 100.8 / 173.2 / 142.1). The ICU columns changed with the ICU version: compare 9.3 / 10.1 / 40.5 / 29.5 / 171.4 → 9.3 / 10.1 / 40.8 / 30.0 / 171.9, sortKey 105.2 / 122.8 / 120.9 / 365.9 / 154.1 → 100.9 / 117.0 / 115.7 / 349.6 / 151.2; so the sortKey speedups went from 1.47× / 1.34× / 1.21× / 2.12× / 1.09× to 1.42× / 1.28× / 1.15× / 2.02× / 1.06× without a change on our side.

**The loop of EngineBench (2026-11-13, technique log §52 (k)).** The recording of 2026-11-06 (the old loop, the same engine but for comment and cold-path changes) read compare 8.9 / 9.1 / 18.4 / 19.9 / 160.4, sortKey 71.8 / 92.1 / 101.1 / 173.4 / 143.1 and allocating sortKey 120.3 / 142.8 / 149.2 / 219.9 / 192.8; the differences to this table are the cost of the old loop (and, on latin and cjk compare, 0.3–0.5 ns of a call that the old loop made since `b30a9e66` — the unrecorded series of 2026-11-12 read 9.4 / 18.9), not a change of the engine.

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

- compare: ascii **1.22×**, latin **1.28×**, cjk **2.31×**, paths
  **1.66×**, thai **1.08× faster**
- sortKey (inout): ascii **1.42×**, latin **1.28×**, cjk **1.15×**, paths
  **2.02×**, thai **1.06× faster** (against ICU 80.0.1, whose sortKey is
  2–4% faster than that of ICU 79.1)

**All ten rows are ahead of ICU C.** The `throws` and the two `String`
arguments of our API are included in our numbers; the cost of the old
benchmark loop (1.2–1.5 ns per compare until 2026-11-13, Docs/27) is not. The
allocating sortKey (`skRet`) is 0.78–0.85× of ICU's speed (1.60× faster on
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
