# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-20 14:35 on Apple Silicon (macOS 26), `run_benchmarks.sh`
K=3 (min over interleaved runs, each itself min-over-9), release builds, at
`cfd2ab9d` plus the five new Table 2 rows (an options compare and four sort
APIs). Includes every optimization through §51 (k).

**Machine state:** busy — 1-minute load 48 at the start of run A, 18 at the
start of run B, 17 at its end, on AC power, under `caffeinate -i`. **The
tables show run B.** Recorded on these grounds (the control decides, not the
load — Docs/27):

1. **The system-ICU control (Table 2) matches the reference within 0.8% in
   run B** and within 2.2% in run A (`localizedCompare` 194/362/369/301/497
   in run B, against 194/365/369/300/494).
2. **Runs A and B agree:** our compare within 1.8% (latin; every other row
   within 0.9%), sortKey within 1.0%; ICU C within 2.8% (thai compare).

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout: ICU 79.1 with Unicode 18 data (branch
`ICU-23250-CLDR-79-integration-beta4`), not the 79.0.1 data that our collator
bundles. Its speed matches 79.0.1, so the ratios stay comparable. Its KEYS do
not: do not generate golden files from that checkout (technique log §49).

**The harness:** the Swift loop costs about 1 ns per call more than the C
loop, and that is the call shape of our API (`throws`, two `String`
arguments, `options`), which every caller pays. `bench_icu` gives
`ucol_getSortKey` UTF-16 that it converted before its timer, because that
function takes UTF-16 only; that stays by decision. Details: Docs/27, "What
the harness itself costs".

Same Foundation APIs, two backends:

- **Swift Collator**: `BenchFoundation`, release, `-no-WMO` (Docs/27 —
  required on machine 1, a handicap here, so these UNDERSTATE the framework
  build)
- **System ICU**: pre-compiled `bench_system` (system Foundation → NSString →
  CoreFoundation → ICU)

Table 2 values are whole nanoseconds (both sources truncate, the same way in
every run).

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    59 |       194 | **3.29× faster** |
| Latin  |    62 |       362 | **5.84× faster** |
| CJK    |    82 |       369 | **4.50× faster** |
| Paths  |    78 |       301 | **3.86× faster** |
| Thai   |   304 |       497 | **1.63× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    72 |       195 | **2.71× faster** |
| Latin  |    74 |       353 | **4.77× faster** |
| CJK    |   106 |       362 | **3.42× faster** |
| Paths  |    94 |       322 | **3.43× faster** |
| Thai   |   311 |       483 | **1.55× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    72 |       196 | **2.72× faster** |
| Latin  |    74 |       353 | **4.77× faster** |
| CJK    |   106 |       363 | **3.42× faster** |
| Paths  |    88 |       309 | **3.51× faster** |
| Thai   |   312 |       483 | **1.55× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    85 |       310 | **3.65× faster** |
| Latin  |    87 |       473 | **5.44× faster** |
| CJK    |   108 |       480 | **4.44× faster** |
| Paths  |   107 |       406 | **3.79× faster** |
| Thai   |   334 |       624 | **1.87× faster** |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   101 |       311 | **3.08× faster** |
| Latin  |   103 |       465 | **4.51× faster** |
| CJK    |   136 |       476 | **3.50× faster** |
| Paths  |   121 |       416 | **3.44× faster** |
| Thai   |   345 |       560 | **1.62× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   254 |       994 | **3.91× faster** |
| Latin  |   281 |      1430 | **5.09× faster** |
| CJK    |   324 |      1267 | **3.91× faster** |
| Paths  |   264 |       964 | **3.65× faster** |
| Thai   |   276 |      1376 | **4.99× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   255 |      1003 | **3.93× faster** |
| Latin  |   280 |      1488 | **5.31× faster** |
| CJK    |   322 |      1280 | **3.98× faster** |
| Paths  |   217 |       974 | **4.49× faster** |
| Thai   |   275 |      1426 | **5.19× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   324 |       997 | **3.08× faster** |
| Latin  |   347 |      1433 | **4.13× faster** |
| CJK    |   347 |      1272 | **3.67× faster** |
| Paths  |   368 |       978 | **2.66× faster** |
| Thai   |   426 |      1428 | **3.35× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   119 |       322 | **2.71× faster** |
| Latin  |   383 |       782 | **2.04× faster** |
| CJK    |   377 |       582 | **1.54× faster** |
| Paths  |   196 |       311 | **1.59× faster** |
| Thai   |   422 |       711 | **1.68× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   121 |       327 | **2.70× faster** |
| Latin  |   339 |       813 | **2.40× faster** |
| CJK    |   377 |       586 | **1.55× faster** |
| Paths  |   228 |       505 | **2.21× faster** |
| Thai   |   367 |       763 | **2.08× faster** |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2540 |     14917 | **5.87× faster** |
| Latin  |  2658 |     17380 | **6.54× faster** |
| CJK    |  3857 |     18403 | **4.77× faster** |
| Paths  |   338 |      1274 | **3.77× faster** |
| Thai   |  1206 |      5678 | **4.71× faster** |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2133 |      5130 | **2.41× faster** |
| Latin  |  2208 |      7390 | **3.35× faster** |
| CJK    |  2648 |      7777 | **2.94× faster** |
| Paths  |   183 |       478 | **2.61× faster** |
| Thai   |  1222 |      2451 | **2.01× faster** |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  3958 |     16518 | **4.17× faster** |
| Latin  |  4105 |     18953 | **4.62× faster** |
| CJK    |  5479 |     20372 | **3.72× faster** |
| Paths  |   422 |      1355 | **3.21× faster** |
| Thai   |  1689 |      6311 | **3.74× faster** |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2978 |     16383 | **5.50× faster** |
| Latin  |  3093 |     18957 | **6.13× faster** |
| CJK    |  4348 |     19982 | **4.60× faster** |
| Paths  |   342 |      1324 | **3.87× faster** |
| Thai   |  1352 |      6104 | **4.51× faster** |

### The sort rows

One op is one ELEMENT of a sort: a sort of n lines makes about n·log2(n)
comparisons, so ns per element ≈ log2(n) × (ns per comparison) plus the
sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    10.5 |   9.3 | 1.13× |   124.2 | 104.6 | 1.19× |   176.7 | 1.69× |
| Latin  |    11.0 |  10.1 | 1.09× |   131.3 | 121.6 | 1.08× |   182.5 | 1.50× |
| CJK    |    20.1 |  40.8 | **0.49×** |   144.5 | 117.8 | 1.23× |   198.9 | 1.69× |
| Paths  |    18.5 |  29.7 | **0.62×** |   332.5 | 366.5 | **0.91×** |   378.7 | 1.03× |
| Thai   |   198.4 | 170.7 | 1.16× |   176.1 | 154.6 | 1.14× |   230.5 | 1.49× |

Change against the previous baseline (2026-10-19 18:03):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 10.5 → 10.5 | 142.3 → 124.2 (**−12.7%**) |
| Latin  | 11.0 → 11.0 | 161.8 → 131.3 (**−18.9%**) |
| CJK    | 20.1 → 20.1 | 164.6 → 144.5 (**−12.2%**) |
| Paths  | 18.5 → 18.5 | 361.2 → 332.5 (**−7.9%**) |
| Thai   | 221.0 → 198.4 (**−10.2%**) | 201.4 → 176.1 (**−12.6%**) |

The moves are §51 (j) and (k): the writer under one access scope with the
whole key written in one `replaceSubrange` (W1 + W2), and the scratch
iterators behind pointers, with no dynamic exclusivity scope left (sortKey
on every corpus; thai compare). The fast-path compare did not change.

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 10.5 / 10.5 | 124.6 / 124.2 | 9.5 / 9.3 | 106.0 / 104.6 |
| Latin  | 11.2 / 11.0 | 131.3 / 131.3 | 10.3 / 10.1 | 123.4 / 121.6 |
| CJK    | 20.1 / 20.1 | 145.6 / 144.5 | 40.8 / 40.8 | 119.1 / 117.8 |
| Paths  | 18.6 / 18.5 | 335.7 / 332.5 | 29.7 / 29.7 | 370.0 / 366.5 |
| Thai   | 200.2 / 198.4 | 177.4 / 176.1 | 175.4 / 170.7 | 157.9 / 154.6 |

Run A started at load 48 and read up to ~2% higher. In Table 2, system ICU
is within 2.6% over all 70 cells, ours within 2.8%.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.13× ascii, 1.09× latin, **0.49× cjk** and **0.62× paths (we are
  FASTER)**, 1.16× thai
- sortKey 1.19× ascii, 1.08× latin, 1.23× cjk, **0.91× paths (FASTER)**, 1.14× thai

Three of the ten rows are ahead of ICU C (cjk and paths compare, paths
sortKey). Every other row is within 1.06–1.23×: ascii and latin compare
(~1 ns of each is the API's call shape, Docs/27), latin sortKey 1.08×, thai
compare and sortKey 1.14–1.16×, ascii and cjk sortKey 1.19–1.23×.

The `skRet` column (the allocating sortKey overload) stays ~1.2–2.1× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.54× (now 14 APIs).
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. The
compare rows of Table 2 move with the engine, because they call it (for
example `localizedCompare` thai 325 → 304 ns against the 2026-10-19 18:03
run, from §51 (k)). Thai is the weakest family; it is also the engine's
slowest corpus.

**The comparator path costs more per comparison than the String methods.**
A 200-line sort makes about 7.6 comparisons per element, so the ascii sort
rows put one comparison at about 2133 / 7.6 ≈ 280 ns through
`String.Comparator(options: [], locale:)`, and about 330 ns through
`.localizedStandard` (`String.StandardComparator`), against 59 ns for
`localizedCompare` and 77 ns for `localizedStandardCompare` on the same
corpus. Part of that is the sort's own work (moving String values), but the
gap is large enough to be worth a profile (not yet done). The system side
pays even more (about 0.7–2 µs per comparison), so these rows are still
2.4–6.5× ahead.

## How to reproduce

```sh
cd swift-foundation-collation
ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2 \
ICU_BUILD=$ICU_SRC/icu4c/source \
  caffeinate -i Collation/Tools/run_benchmarks.sh 3
```

K=3 takes about 4–7 minutes. Check the machine first — load average, memory,
and the time since the last wake (Docs/27):

```sh
sysctl -n vm.loadavg; memory_pressure | grep "free percentage"
pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -3
```

Sanity gates before you record a run:

- **The load control:** system ICU in Table 2 should read about
  194/365/369/300/494 for `localizedCompare`. If it drifts by more than
  ~3%, the box is too busy to record.
- **ICU C** in Table 1 should read about 9.3/10.1/40.5/29.7/173.8 compare
  and 104.5/120.9/119.0/370.3/155.5 sortKey. First check which ICU the
  checkout holds (`git -C $ICU_SRC branch --show-current`); a different ICU
  build can change this column for reasons that have nothing to do with load.
- **Run the matrix twice;** the two runs must agree.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
