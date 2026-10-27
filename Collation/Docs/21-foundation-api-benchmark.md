# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-23 at about 12:45 on Apple Silicon (macOS 26),
`run_benchmarks.sh` K=3 (min over interleaved runs, each itself min-over-9),
release builds, at `91237c5a`. Includes every optimization through §51 (ab):
new since the 2026-10-21 late-evening baseline are (v) the CJK fast path and
(w) the mark table in CE production, (y) the UTF-8 source for the NFD front
end, (z) the restart for non-default options (with the two prefix-skip bug
fixes), and (ab) the search scans out of line.

**Machine state:** 1-minute load 13.6 at the start of run B, 14.0 at its
end (run A: 20.5 → 15.5); on AC power, under `caffeinate -i`, more than 3
hours after the last wake. **The tables show run B** (the convention).
Recorded on these grounds (the control decides, not the load — Docs/27):

1. **The system-ICU control (Table 2) matches the reference within 1.0% in
   run B** (`localizedCompare` 196/363/370/302/497 against
   194/365/369/300/494; run A within 2.1%).
2. **Runs A and B agree:** Table 1 within 1.9% in every cell (ours and ICU
   C).

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout: ICU 79.1 with Unicode 18 data, not the 79.0.1 data that our
collator bundles. On 2026-10-23 the checkout was on branch `main` (headers
79.1), with the libraries unchanged since 2026-10-21 14:45 (built on the
CLDR 49 integration branch `ICU-23250-CLDR-79-integration-beta4`). Its speed
matches 79.0.1, so the ratios stay comparable. Its KEYS do not: do not
generate golden files from that checkout (technique log §49).

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
| ASCII  |    50 |       196 | **3.92× faster** |
| Latin  |    50 |       363 | **7.26× faster** |
| CJK    |    71 |       370 | **5.21× faster** |
| Paths  |    64 |       302 | **4.72× faster** |
| Thai   |   269 |       497 | **1.85× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    69 |       196 | **2.84× faster** |
| Latin  |    71 |       353 | **4.97× faster** |
| CJK    |    95 |       361 | **3.80× faster** |
| Paths  |    91 |       321 | **3.53× faster** |
| Thai   |   281 |       484 | **1.72× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    69 |       197 | **2.86× faster** |
| Latin  |    71 |       354 | **4.99× faster** |
| CJK    |    95 |       364 | **3.83× faster** |
| Paths  |    85 |       309 | **3.64× faster** |
| Thai   |   279 |       484 | **1.73× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    68 |       309 | **4.54× faster** |
| Latin  |    70 |       475 | **6.79× faster** |
| CJK    |    93 |       481 | **5.17× faster** |
| Paths  |    89 |       411 | **4.62× faster** |
| Thai   |   293 |       625 | **2.13× faster** |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    93 |       311 | **3.34× faster** |
| Latin  |    96 |       466 | **4.85× faster** |
| CJK    |   120 |       478 | **3.98× faster** |
| Paths  |   114 |       425 | **3.73× faster** |
| Thai   |   311 |       558 | **1.79× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   241 |       993 | **4.12× faster** |
| Latin  |   270 |      1431 | **5.30× faster** |
| CJK    |   281 |      1270 | **4.52× faster** |
| Paths  |   242 |       967 | **4.00× faster** |
| Thai   |   263 |      1379 | **5.24× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   242 |      1004 | **4.15× faster** |
| Latin  |   268 |      1491 | **5.56× faster** |
| CJK    |   280 |      1276 | **4.56× faster** |
| Paths  |   200 |       979 | **4.89× faster** |
| Thai   |   263 |      1432 | **5.44× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   309 |       993 | **3.21× faster** |
| Latin  |   334 |      1441 | **4.31× faster** |
| CJK    |   307 |      1273 | **4.15× faster** |
| Paths  |   298 |       985 | **3.31× faster** |
| Thai   |   404 |      1427 | **3.53× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   108 |       323 | **2.99× faster** |
| Latin  |   361 |       789 | **2.19× faster** |
| CJK    |   331 |       582 | **1.76× faster** |
| Paths  |   128 |       312 | **2.44× faster** |
| Thai   |   412 |       714 | **1.73× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   111 |       325 | **2.93× faster** |
| Latin  |   325 |       819 | **2.52× faster** |
| CJK    |   326 |       591 | **1.81× faster** |
| Paths  |   166 |       509 | **3.07× faster** |
| Thai   |   349 |       763 | **2.19× faster** |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2250 |     14880 | **6.61× faster** |
| Latin  |  2342 |     17445 | **7.45× faster** |
| CJK    |  3789 |     18467 | **4.87× faster** |
| Paths  |   237 |      1298 | **5.48× faster** |
| Thai   |  1260 |      5713 | **4.53× faster** |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2098 |      5148 | **2.45× faster** |
| Latin  |  2183 |      7407 | **3.39× faster** |
| CJK    |  2632 |      7798 | **2.96× faster** |
| Paths  |   182 |       488 | **2.68× faster** |
| Thai   |  1128 |      2456 | **2.18× faster** |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  3685 |     16467 | **4.47× faster** |
| Latin  |  3811 |     19144 | **5.02× faster** |
| CJK    |  5384 |     20380 | **3.79× faster** |
| Paths  |   323 |      1386 | **4.29× faster** |
| Thai   |  1745 |      6333 | **3.63× faster** |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2712 |     16363 | **6.03× faster** |
| Latin  |  2815 |     19016 | **6.76× faster** |
| CJK    |  4290 |     20225 | **4.71× faster** |
| Paths  |   245 |      1335 | **5.45× faster** |
| Thai   |  1395 |      6129 | **4.39× faster** |

### The sort rows

One op is one ELEMENT of a sort. Swift's sort makes about 14 comparisons
per element on these 200-line corpora (counted; not n·log2(n) ≈ 7.6), so ns
per element ≈ 14 × (ns per comparison) plus the sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    10.5 |   9.3 | 1.13× |    76.0 | 104.0 | **0.73×** |   128.4 | 1.23× |
| Latin  |    11.0 |  10.1 | 1.09× |    96.8 | 122.5 | **0.79×** |   150.7 | 1.23× |
| CJK    |    20.1 |  40.5 | **0.50×** |   105.6 | 118.2 | **0.89×** |   155.9 | 1.32× |
| Paths  |    18.5 |  29.5 | **0.63×** |   185.7 | 366.2 | **0.51×** |   230.9 | 0.63× |
| Thai   |   164.7 | 172.3 | **0.96×** |   152.0 | 154.9 | **0.98×** |   203.5 | 1.31× |

Change against the 2026-10-21 late-evening baseline (run A):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 10.6 → 10.5 | 80.0 → 76.0 (**−5.0%**) |
| Latin  | 11.2 → 11.0 | 105.6 → 96.8 (**−8.3%**) |
| CJK    | 20.1 → 20.1 | 114.8 → 105.6 (**−8.0%**) |
| Paths  | 18.8 → 18.5 | 200.4 → 185.7 (**−7.3%**) |
| Thai   | 194.7 → 164.7 (**−15.4%**) | 153.0 → 152.0 |

The moves are §51 (y) the UTF-8 source for the NFD front end (thai compare,
every sortKey row), (v) the CJK fast path (cjk sortKey) and (w) the mark
table (latin sortKey). (z) and (ab) do not reach Table 1 (default options,
no search), apart from the (z) check on the restart path (thai compare
+0.5% in its A/B).

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 10.6 / 10.5 | 77.5 / 76.0 | 9.4 / 9.3 | 105.9 / 104.0 |
| Latin  | 11.2 / 11.0 | 97.5 / 96.8 | 10.3 / 10.1 | 123.4 / 122.5 |
| CJK    | 20.0 / 20.1 | 107.4 / 105.6 | 41.3 / 40.5 | 120.1 / 118.2 |
| Paths  | 18.5 / 18.5 | 186.2 / 185.7 | 29.5 / 29.5 | 370.8 / 366.2 |
| Thai   | 165.5 / 164.7 | 154.5 / 152.0 | 173.5 / 172.3 | 155.9 / 154.9 |

**Table 2 against 2026-10-21:**
- thai faster on every row except the identical-strength sorts:
  `localizedCompare` 289 → 269, `localizedStandardCompare` 312 → 281
  (−10%), `localizedCaseInsensitiveCompare` 312 → 279 (−11%), the options
  compare 344 → 311 (−10%), `compare(_:locale:)` 316 → 293; contains −4%;
- cjk −3..−12% on every compare and search row;
- the search rows −1..−12% on every corpus ((y), (ab));
- **`localizedStandardCompare` and `localizedCaseInsensitiveCompare` on
  ascii / latin / paths +5..+8% (64 → 69, 66 → 71, 87 → 91), the options
  compare +2..+3%.** The 2026-10-22 matrix at (y) (not recorded) still
  read 64 / 66 / 87, and (ab) cannot change `RootCollator.swift` in this
  `-no-WMO` build: the cost comes with (z) in the `-no-WMO` build. The WMO
  A/B of (z) had these rows −2.5..−7%. Fixed in §51 (ac) (2026-10-27,
  A/B only: back at the speed from before (z) in both build modes).

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.13× ascii, 1.09× latin, **0.50× cjk**, **0.63× paths** and
  **0.96× thai (we are FASTER)** — thai since §51 (y)
- sortKey **0.73× ascii, 0.79× latin, 0.89× cjk, 0.51× paths, 0.98× thai
  (all FASTER)**

Eight of the ten rows are at or ahead of ICU C (every sortKey row; cjk,
paths and thai compare). The two behind are compare on ascii and latin
(1.09–1.13×; ~1 ns of each is the API's call shape, Docs/27).

The `skRet` column (the allocating sortKey overload) stays ~0.63–1.32× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.72× (14 APIs).
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. Against
the 2026-10-20 14:35 run, the wrapper rows moved with §51 (p) (the generic
String conversion removed): `localizedCompare` 59/62/82/78/304 →
48/51/70/65/285, `localizedStandardCompare` 72/74/106/94/311 →
63/65/99/85/311, `compare(_:locale:)` 85 → 70 and the options compare
101 → 89 on ascii, `range(of:locale:)` ascii 119 → 108; contains and
`localizedStandardRange` −1..−2%. This table uses the `-no-WMO` build; the
WMO A/B of §51 (p) shows larger gains. Thai is the weakest family; it is
also the engine's slowest corpus.

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

K=3 takes about 6–8 minutes (14 Table 2 APIs). Check the machine first — load average, memory,
and the time since the last wake (Docs/27):

```sh
sysctl -n vm.loadavg; memory_pressure | grep "free percentage"
pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -3
```

Sanity gates before you record a run:

- **The load control:** system ICU in Table 2 should read about
  194/365/369/300/494 for `localizedCompare`. If it drifts by more than
  ~3%, the box is too busy to record.
- **ICU C** in Table 1 should read about 9.5/10.1/40.8/29.7/172.0 compare
  and 106.1/122.1/119.3/369.6/154.7 sortKey (2026-10-21, run B). First check which ICU the
  checkout holds (`git -C $ICU_SRC branch --show-current`); a different ICU
  build can change this column for reasons that have nothing to do with load.
- **Run the matrix twice;** the two runs must agree.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
