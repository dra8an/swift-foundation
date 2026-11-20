# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-19 at 15:40–16:08 on Apple Silicon (M1 Max, 32 GB),
**macOS 27.2.1 (26B125)**, **Swift 6.5** (the compiler of the selected
`Xcode2.app`, swiftlang-6.5.0.107.5, SDK macOS 27.5), `run_benchmarks.sh`
K=3 (min over 3 runs, each itself min-over-9), release builds, at
`1cbc4682` (the code of `e6e747fe`; the later commits change tests and
documents only). **The tables show the MEDIAN of 6 runs** (the recording
rule of 2026-11-04 asks for at least 4; Docs/27, technique log §51 (au)).

**This recording replaces the one of 2026-11-17 (`0d757075`).** The code
differs in one setup function, `CollationFastLatin.getOptions` (two ICU
fixes, technique log §52 (p)); the bench programs, the compiler, macOS and
ICU are the same. Table 1 and the WMO column of Table 2 read the values of
2026-11-17 (each cell of ours within 1.1%, the `.localizedStandard` sort
apart); the `-no-WMO` column reads other values in some rows with the same
hot code (see the paragraph on that column below, and "Change against the
recording of 2026-11-17" under Table 1). The references of the checks (ICU
C, macOS) are still those of 2026-11-17.

**The baseline of 2026-11-17 had three new things, which still hold; compare
with recordings before it only as said here** (technique log §52 (k), (l), (m)):

1. **The benchmark loops (2026-11-13).** EngineBench's loop read three
   globals and called `Order.rawValue`; that cost 1.2–1.5 ns of each compare (no
   cost is shown for sortKey: its rows moved by about 1 ns in the A/B, but so
   did a control binary whose sortKey loops did not change). All three bench
   programs now use local
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

**The `-no-WMO` column belongs to the binary of its series, cell by cell
(found 2026-11-18, technique log §52 (r)).** Two `-no-WMO` builds with the
same hot code and other positions read several rows 1–7 ns apart: the
binary of 2026-11-17 against a build of HEAD (`getOptions`, a setup
function, is 56 bytes longer there) reads `localizedCompare` 31.5 → 30.3,
the options compare 46.9 → 48.2 and `range(of:locale:)` 79.7 → 85.8 on
ascii. The WMO column and Table 1 did not move in the same comparison. So
judge a change by the WMO column, and compare `-no-WMO` cells of two
commits only with a control (the same program built twice). The cause is
not examined. **The series of 2026-11-19 repeats it over six runs** (the
`-no-WMO` cells of this recording against those of 2026-11-17:
`localizedCompare` 31.6 → 30.3, the options compare 46.9 → 48.2,
`range(of:locale:)` 79.8 → 85.8 on ascii), and it shows that one cell takes
both levels with one binary: `range(of:locale:)` on ascii read 85.7–85.8 in
five runs and 79.5 in one.

**Machine state:** on AC power from start to end, under `caffeinate -i`;
7 hours after the last wake; 1-minute load 4 → 10 → 8 → 6 → 7 → 11 → 4 at
the starts and ends of the six runs (62% of the processor idle before the
start); memory full (14.3 → 14.2 GB swap; the user's apps stay open by
decision). Before the start, ICU C read 9.3 / 10.1 / 172.3 and the
EngineBench binary of the series of 2026-11-17 read 7.6 / 7.9 / 159.6
(compare on ascii / latin / thai).

**The checks (Docs/27), medians of the six runs:**

1. **macOS** `localizedCompare` 201.8/347.6/355.9/313.4/507.6 against the
   reference 201.3/347.2/355.2/313.6/505.0: within 0.5% (limit 2.5%).
2. **The frozen binary** of 2026-10-30 (`Collation/Tools/frozen_check.py`,
   load 4): `localizedStandardCompare` 53/55/81/76/274 against
   53/55/82/75/276, `localizedCompare` 39/39/58/57/258 against 39/40/58/56/257
   (within 1 ns).
3. **ICU C** (ICU 80.0.1; the gates of 2026-11-17, not changed): compare
   9.3/10.1/40.7/30.0/173.0 against 9.3/10.1/40.8/30.0/171.9, within 0.6%;
   sortKey 100.8/116.8/115.8/351.0/151.8 against
   100.9/117.0/115.7/349.6/151.2, within 0.4% (limit 2%).
4. **The loop check** (Docs/27; `Collation/Tools/insn-count/loop_check.sh`),
   run on 2026-11-19 on the new EngineBench binary of this series: per
   pass, ascii / latin / cjk 150.2 / 149.2 / 287.0 instructions inside
   `compare` and 11.7 in the loop, the same as the reference; no position
   rule applies. The binary differs from the one of 2026-11-17 in one
   function (`getOptions`; 620 of 621 identical).
5. **The six runs against each other:** the compare cells of Table 1 are
   equal in all six runs on ascii and latin (7.6, 7.9) and differ by 0.2 ns
   on paths, 0.3 on cjk. **Two-level cells** (the runs 5% or more apart; ‡,
   ranges under Table 2): three — the `.localizedStandard` sort, WMO, on
   ascii (961.8–1023.9) and latin (1007.4–1067.4), as on 2026-11-17; and
   `range(of:locale:)` on ascii, `-no-WMO` (85.7–85.8 in five runs, 79.5 in
   one).

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout: **ICU 80.0.1** since 2026-11-16 (before: ICU 79.1 with Unicode 18
data), not the 79.0.1 data that our collator bundles. Its KEYS differ from
ours: do not generate golden files from that checkout (technique log §49).

**The harness** (Docs/27, "What the harness itself costs"): since 2026-11-13
EngineBench's loop has 10 instructions around a compare (recorded), the C
loop 13 plus a library stub of 3; neither has a part that can be removed with
an effect. The loops of the Table 2 programs are not recorded; an A/B shows
no cost that matters (technique log §52 (l)). What stays in our numbers is what a caller pays: two
`String` arguments, the options, the call, the error check of a throwing
call.

Same Foundation APIs, two backends:

- **Swift Collator**: `BenchFoundation`, release, WMO and `-no-WMO`
- **System ICU**: pre-compiled `bench_system` (system Foundation → NSString →
  CoreFoundation → ICU), compiled with the same Swift 6.5

Table 2 values have one decimal (both programs round the same way; the table
rounds the median of six runs to one decimal again).

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 12.4 | **16.27× faster** | 30.3 | 6.66× faster | 201.8 |
| Latin  | 13.0 | **26.74× faster** | 31.1 | 11.18× faster | 347.6 |
| CJK    | 24.1 | **14.74× faster** | 48.3 | 7.37× faster | 355.9 |
| Paths  | 23.8 | **13.19× faster** | 43.7 | 7.17× faster | 313.4 |
| Thai   | 167.1 | **3.04× faster** | 222.2 | 2.28× faster | 507.6 |

### localizedStandardCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 14.6 | **13.69× faster** | 33.7 | 5.93× faster | 199.8 |
| Latin  | 15.2 | **22.30× faster** | 34.1 | 9.94× faster | 338.9 |
| CJK    | 31.8 | **11.20× faster** | 61.7 | 5.77× faster | 355.8 |
| Paths  | 26.9 | **12.24× faster** | 53.6 | 6.12× faster | 328.6 |
| Thai   | 167.8 | **2.93× faster** | 224.6 | 2.19× faster | 491.4 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 15.5 | **12.96× faster** | 34.1 | 5.89× faster | 200.9 |
| Latin  | 16.2 | **20.93× faster** | 34.4 | 9.85× faster | 339.0 |
| CJK    | 33.1 | **10.73× faster** | 62.2 | 5.71× faster | 355.2 |
| Paths  | 26.8 | **11.87× faster** | 52.5 | 6.05× faster | 317.6 |
| Thai   | 169.2 | **2.88× faster** | 225.3 | 2.17× faster | 488.1 |

### compare(_:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 17.1 | **17.86× faster** | 30.1 | 10.14× faster | 305.4 |
| Latin  | 17.6 | **25.98× faster** | 30.9 | 14.80× faster | 457.2 |
| CJK    | 29.3 | **16.05× faster** | 51.6 | 9.11× faster | 470.2 |
| Paths  | 28.4 | **14.51× faster** | 45.0 | 9.17× faster | 412.2 |
| Thai   | 173.1 | **3.58× faster** | 220.4 | 2.81× faster | 620.1 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 24.2 | **12.63× faster** | 48.2 | 6.34× faster | 305.6 |
| Latin  | 24.7 | **18.47× faster** | 49.4 | 9.24× faster | 456.3 |
| CJK    | 42.7 | **11.15× faster** | 77.8 | 6.12× faster | 475.9 |
| Paths  | 35.3 | **11.96× faster** | 65.8 | 6.42× faster | 422.1 |
| Thai   | 179.0 | **3.13× faster** | 240.2 | 2.33× faster | 559.7 |

### localizedStandardContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 127.8 | **7.46× faster** | 224.8 | 4.24× faster | 953.6 |
| Latin  | 147.3 | **9.43× faster** | 249.9 | 5.56× faster | 1389.3 |
| CJK    | 155.8 | **7.88× faster** | 262.6 | 4.68× faster | 1228.8 |
| Paths  | 130.6 | **7.10× faster** | 220.4 | 4.21× faster | 927.2 |
| Thai   | 151.7 | **8.86× faster** | 236.9 | 5.67× faster | 1344.1 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 128.4 | **7.49× faster** | 224.7 | 4.28× faster | 961.0 |
| Latin  | 148.1 | **9.72× faster** | 249.5 | 5.77× faster | 1438.9 |
| CJK    | 155.1 | **7.96× faster** | 263.4 | 4.69× faster | 1234.5 |
| Paths  | 99.2 | **9.45× faster** | 177.8 | 5.27× faster | 937.2 |
| Thai   | 152.5 | **9.15× faster** | 236.8 | 5.89× faster | 1395.4 |

### localizedStandardRange(of:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 135.7 | **7.04× faster** | 290.4 | 3.29× faster | 954.6 |
| Latin  | 154.8 | **8.99× faster** | 316.9 | 4.39× faster | 1391.5 |
| CJK    | 159.1 | **7.72× faster** | 284.6 | 4.32× faster | 1229.3 |
| Paths  | 172.6 | **5.45× faster** | 269.1 | 3.49× faster | 940.5 |
| Thai   | 204.9 | **6.80× faster** | 366.8 | 3.80× faster | 1392.7 |

### range(of:options:locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 38.6 | **8.68× faster** | 85.8‡ | 3.91× faster | 335.1 |
| Latin  | 170.0 | **4.64× faster** | 343.1 | 2.30× faster | 789.0 |
| CJK    | 174.0 | **3.36× faster** | 305.9 | 1.91× faster | 585.0 |
| Paths  | 49.3 | **6.51× faster** | 95.7 | 3.35× faster | 320.8 |
| Thai   | 193.3 | **3.75× faster** | 372.4 | 1.95× faster | 724.6 |

### range(of:options:.backwards,locale:)

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 39.5 | **8.56× faster** | 88.1 | 3.84× faster | 338.4 |
| Latin  | 169.4 | **4.87× faster** | 283.6 | 2.91× faster | 824.7 |
| CJK    | 172.7 | **3.44× faster** | 292.4 | 2.03× faster | 594.5 |
| Paths  | 84.5 | **5.89× faster** | 130.1 | 3.83× faster | 497.6 |
| Thai   | 189.1 | **4.11× faster** | 305.4 | 2.54× faster | 776.9 |

### sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1023.3‡ | **12.65× faster** | 1469.1 | 8.81× faster | 12948.4 |
| Latin  | 1008.5‡ | **15.23× faster** | 1529.5 | 10.04× faster | 15357.6 |
| CJK    | 1323.6 | **12.29× faster** | 1902.7 | 8.55× faster | 16261.5 |
| Paths  | 102.7 | **10.50× faster** | 153.2 | 7.04× faster | 1078.0 |
| Thai   | 630.6 | **8.41× faster** | 915.1 | 5.79× faster | 5302.4 |

### sorted(using: String.Comparator(options: [], locale:)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 822.4 | **4.72× faster** | 1124.8 | 3.45× faster | 3882.6 |
| Latin  | 867.6 | **6.94× faster** | 1180.0 | 5.11× faster | 6024.6 |
| CJK    | 1171.1 | **5.45× faster** | 1545.4 | 4.13× faster | 6385.3 |
| Paths  | 80.6 | **4.78× faster** | 104.6 | 3.68× faster | 385.1 |
| Thai   | 618.0 | **3.65× faster** | 831.8 | 2.71× faster | 2254.2 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 2363.2 | **6.03× faster** | 2813.7 | 5.07× faster | 14254.7 |
| Latin  | 2435.2 | **6.84× faster** | 2899.5 | 5.75× faster | 16663.8 |
| CJK    | 2844.9 | **6.24× faster** | 3425.1 | 5.18× faster | 17752.5 |
| Paths  | 210.2 | **5.67× faster** | 249.9 | 4.77× faster | 1192.6 |
| Thai   | 1130.2 | **5.17× faster** | 1408.3 | 4.15× faster | 5841.1 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard)) — ns per element

| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |
|--------|-----------:|---------|-----------------:|---------|-----------:|
| ASCII  | 1386.0 | **9.50× faster** | 1897.1 | 6.94× faster | 13173.5 |
| Latin  | 1440.8 | **10.83× faster** | 1931.6 | 8.08× faster | 15605.2 |
| CJK    | 1762.0 | **9.40× faster** | 2371.2 | 6.99× faster | 16566.0 |
| Paths  | 133.7 | **8.23× faster** | 174.1 | 6.32× faster | 1100.6 |
| Thai   | 780.1 | **6.90× faster** | 1056.2 | 5.10× faster | 5381.8 |

‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the 6 runs:
- range(of:locale:), ASCII, `-no-WMO`: 79.5–85.8
- sortStdComparator, ASCII, WMO: 961.8–1023.9
- sortStdComparator, Latin, WMO: 1007.4–1067.4

Floor (lowest speedup): WMO 2.88× (localizedCaseICmp thai); `-no-WMO` 1.91× (range(of:locale:) cjk).

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
| ASCII  | 7.6 | 9.3 | **1.22× faster** | 70.9 | 100.8 | **1.42× faster** | 119.2 | 0.85× (slower) |
| Latin  | 7.9 | 10.1 | **1.28× faster** | 91.2 | 116.8 | **1.28× faster** | 142.7 | 0.82× (slower) |
| CJK    | 17.8 | 40.7 | **2.28× faster** | 100.3 | 115.8 | **1.15× faster** | 148.8 | 0.78× (slower) |
| Paths  | 18.2 | 30.0 | **1.65× faster** | 173.1 | 351.0 | **2.03× faster** | 218.9 | **1.60× faster** |
| Thai   | 159.4 | 173.0 | **1.08× faster** | 142.2 | 151.8 | **1.07× faster** | 191.2 | 0.79× (slower) |

**Change against the recording of 2026-11-17 (09:49–10:17, `0d757075`; the same bench programs, compiler, macOS and ICU; the code differs in the setup function `getOptions`).** Table 1, ours: compare 7.6 / 7.9 / 17.7 / 18.1 / 158.8 → 7.6 / 7.9 / 17.8 / 18.2 / 159.4, sortKey 71.0 / 91.3 / 100.8 / 173.2 / 142.1 → 70.9 / 91.2 / 100.3 / 173.1 / 142.2, allocating sortKey 119.1 / 142.4 / 148.1 / 219.1 / 191.3 → 119.2 / 142.7 / 148.8 / 218.9 / 191.2: each cell within 0.6%. The ICU columns: within 0.6% (thai compare 171.9 → 173.0, paths sortKey 349.6 → 351.0). Table 2, WMO: each cell within 1.1% (the largest: the backward search on latin, 171.2 → 169.4), except the `.localizedStandard` sort (latin 1066.7 → 1008.5, a two-level cell in both series; cjk 1286.7 → 1323.6, +2.9%). Table 2, `-no-WMO`, with the same hot code (technique log §52 (r), (t)): the three current-locale compares read lower (`localizedCompare` 31.6 / 32.4 / 50.8 / 44.9 → 30.3 / 31.1 / 48.3 / 43.7; `localizedStandardCompare` and `localizedCaseInsensitiveCompare` −2.0 … −4.7% on ascii, latin, cjk, paths), the options compare reads higher (46.9 / 48.3 → 48.2 / 49.4 on ascii / latin), and `range(of:locale:)` and the backward search read 6–7 ns higher on ascii and paths (79.8 → 85.8, 89.0 → 95.7; 81.8 → 88.1, 123.7 → 130.1); the other `-no-WMO` cells are within 3%. The macOS column: within 0.8%. Floors: 2.88× WMO (the same), 1.91× `-no-WMO` (1.94×).

**History — the recording of 2026-11-17 against the one of 2026-11-13 (14:39–14:57, the same engine and the same EngineBench binary; ICU 79.1 then).** Our columns of Table 1 are within 1.2% (compare 7.6 / 7.9 / 17.8 / 18.1 / 158.1 → 7.6 / 7.9 / 17.7 / 18.1 / 158.8; sortKey 71.5 / 91.6 / 100.2 / 172.6 / 141.8 → 71.0 / 91.3 / 100.8 / 173.2 / 142.1). The ICU columns changed with the ICU version: compare 9.3 / 10.1 / 40.5 / 29.5 / 171.4 → 9.3 / 10.1 / 40.8 / 30.0 / 171.9, sortKey 105.2 / 122.8 / 120.9 / 365.9 / 154.1 → 100.9 / 117.0 / 115.7 / 349.6 / 151.2; so the sortKey speedups went from 1.47× / 1.34× / 1.21× / 2.12× / 1.09× to 1.42× / 1.28× / 1.15× / 2.02× / 1.06× without a change on our side.

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
- **The checks decide** (gates of 2026-11-17, six runs, ICU 80.0.1; Docs/27):
  ICU C within 2% of 9.3/10.1/40.8/30.0/171.9 compare and
  100.9/117.0/115.7/349.6/151.2 sortKey; system-ICU `localizedCompare` within
  2.5% of 201.3/347.2/355.2/313.6/505.0. First: AC power, and the loop check
  for a new EngineBench binary. If the system side drifts, run the frozen-binary
  check (`python3 Collation/Tools/frozen_check.py Collation/Tools/bench_system 3`).
  First check which ICU the checkout holds (`git -C $ICU_SRC branch --show-current`).
- **Record the median of at least 4 runs:**
  `python3 Collation/Tools/matrix_record.py <run files>` prints these tables
  (medians, ‡ for cells whose runs differ by 5% or more, the checks).

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
