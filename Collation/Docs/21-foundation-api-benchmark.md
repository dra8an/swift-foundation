# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-21 late evening on Apple Silicon (macOS 26),
`run_benchmarks.sh` K=3 (min over interleaved runs, each itself min-over-9),
release builds, at `6d0d26f9`. Includes every optimization through §51 (t):
new since the morning baseline are (q) the resource lookup, (r) and (s) the
sortKey writer, and (t) the ASCII run in CE production.

**Machine state:** 1-minute load 16 at the start of run A, 11 at its end; on
AC power, under `caffeinate -i`. **The tables show run A** (the convention
is run B; run B's control read cjk +3.3% and thai +3.0%, just above the
gate). Recorded on these grounds (the control decides, not the load —
Docs/27):

1. **The system-ICU control (Table 2) matches the reference within 2.4% in
   run A** (`localizedCompare` 198/369/375/306/505 against
   194/365/369/300/494).
2. **Runs A and B agree:** Table 1 within 1.8% in every cell (ours and ICU
   C).

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
| ASCII  |    52 |       198 | **3.81× faster** |
| Latin  |    50 |       369 | **7.38× faster** |
| CJK    |    72 |       375 | **5.21× faster** |
| Paths  |    66 |       306 | **4.64× faster** |
| Thai   |   289 |       506 | **1.75× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    64 |       199 | **3.11× faster** |
| Latin  |    66 |       358 | **5.42× faster** |
| CJK    |    99 |       371 | **3.75× faster** |
| Paths  |    87 |       327 | **3.76× faster** |
| Thai   |   312 |       492 | **1.58× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    65 |       200 | **3.08× faster** |
| Latin  |    66 |       359 | **5.44× faster** |
| CJK    |   102 |       370 | **3.63× faster** |
| Paths  |    81 |       314 | **3.88× faster** |
| Thai   |   312 |       492 | **1.58× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    71 |       315 | **4.44× faster** |
| Latin  |    73 |       483 | **6.62× faster** |
| CJK    |    96 |       488 | **5.08× faster** |
| Paths  |    94 |       418 | **4.45× faster** |
| Thai   |   316 |       634 | **2.01× faster** |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    91 |       318 | **3.49× faster** |
| Latin  |    93 |       472 | **5.08× faster** |
| CJK    |   129 |       485 | **3.76× faster** |
| Paths  |   112 |       426 | **3.80× faster** |
| Thai   |   344 |       568 | **1.65× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   249 |      1012 | **4.06× faster** |
| Latin  |   277 |      1456 | **5.26× faster** |
| CJK    |   317 |      1286 | **4.06× faster** |
| Paths  |   255 |       988 | **3.87× faster** |
| Thai   |   274 |      1404 | **5.12× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   248 |      1021 | **4.12× faster** |
| Latin  |   277 |      1512 | **5.46× faster** |
| CJK    |   316 |      1299 | **4.11× faster** |
| Paths  |   211 |       992 | **4.70× faster** |
| Thai   |   274 |      1453 | **5.30× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   315 |      1010 | **3.21× faster** |
| Latin  |   340 |      1458 | **4.29× faster** |
| CJK    |   339 |      1296 | **3.82× faster** |
| Paths  |   314 |       997 | **3.18× faster** |
| Thai   |   408 |      1453 | **3.56× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   116 |       327 | **2.82× faster** |
| Latin  |   377 |       798 | **2.12× faster** |
| CJK    |   369 |       590 | **1.60× faster** |
| Paths  |   131 |       317 | **2.42× faster** |
| Thai   |   426 |       725 | **1.70× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   119 |       331 | **2.78× faster** |
| Latin  |   338 |       832 | **2.46× faster** |
| CJK    |   369 |       597 | **1.62× faster** |
| Paths  |   167 |       515 | **3.08× faster** |
| Thai   |   365 |       773 | **2.12× faster** |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2263 |     15069 | **6.66× faster** |
| Latin  |  2350 |     17662 | **7.52× faster** |
| CJK    |  3894 |     18857 | **4.84× faster** |
| Paths  |   233 |      1297 | **5.57× faster** |
| Thai   |  1250 |      5792 | **4.63× faster** |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2167 |      5193 | **2.40× faster** |
| Latin  |  2249 |      7539 | **3.35× faster** |
| CJK    |  2712 |      7918 | **2.92× faster** |
| Paths  |   186 |       487 | **2.62× faster** |
| Thai   |  1212 |      2491 | **2.06× faster** |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  3742 |     16773 | **4.48× faster** |
| Latin  |  3861 |     19408 | **5.03× faster** |
| CJK    |  5609 |     20795 | **3.71× faster** |
| Paths  |   329 |      1396 | **4.24× faster** |
| Thai   |  1743 |      6382 | **3.66× faster** |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2733 |     16654 | **6.09× faster** |
| Latin  |  2832 |     19338 | **6.83× faster** |
| CJK    |  4458 |     20439 | **4.58× faster** |
| Paths  |   247 |      1352 | **5.47× faster** |
| Thai   |  1375 |      6203 | **4.51× faster** |

### The sort rows

One op is one ELEMENT of a sort. Swift's sort makes about 14 comparisons
per element on these 200-line corpora (counted; not n·log2(n) ≈ 7.6), so ns
per element ≈ 14 × (ns per comparison) plus the sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run A.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    10.6 |   9.4 | 1.13× |    80.0 | 105.9 | **0.76×** |   133.8 | 1.26× |
| Latin  |    11.2 |  10.3 | 1.09× |   105.6 | 123.1 | **0.86×** |   162.4 | 1.32× |
| CJK    |    20.1 |  40.8 | **0.49×** |   114.8 | 119.4 | **0.96×** |   166.4 | 1.39× |
| Paths  |    18.8 |  29.8 | **0.63×** |   200.4 | 371.8 | **0.54×** |   248.1 | 0.67× |
| Thai   |   194.7 | 174.7 | 1.11× |   153.0 | 156.5 | **0.98×** |   207.1 | 1.32× |

Change against the morning baseline (2026-10-21 ~11:30, run B):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 10.6 → 10.6 | 123.1 → 80.0 (**−35.0%**) |
| Latin  | 11.0 → 11.2 | 131.4 → 105.6 (**−19.6%**) |
| CJK    | 20.0 → 20.1 | 144.0 → 114.8 (**−20.3%**) |
| Paths  | 18.5 → 18.8 | 331.8 → 200.4 (**−39.6%**) |
| Thai   | 195.7 → 194.7 | 177.6 → 153.0 (**−13.9%**) |

The moves are §51 (r) the writer's level cursors, (s) the writer specialized
for the default options, and (t) the ASCII run in CE production (ascii and
paths). Compare did not change.

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 10.6 / 10.5 | 80.0 / 80.0 | 9.4 / 9.4 | 105.9 / 105.9 |
| Latin  | 11.2 / 11.0 | 105.6 / 105.2 | 10.3 / 10.3 | 123.1 / 122.4 |
| CJK    | 20.1 / 20.2 | 114.8 / 114.4 | 40.8 / 40.9 | 119.4 / 121.3 |
| Paths  | 18.8 / 18.9 | 200.4 / 201.6 | 29.8 / 30.0 | 371.8 / 371.6 |
| Thai   | 194.7 / 194.1 | 153.0 / 153.0 | 174.7 / 175.2 | 156.5 / 157.2 |

**Table 2 against the morning:** the compare and sort rows within 1–3%
(session drift; the control also read +0.5..+2.4% higher). The search rows
read 1–9% higher on `range(of:)` (ascii 108 → 116, backwards 109 → 119)
in this `-no-WMO` build. It is code placement: a count of one call
(BenchFoundation `-no-WMO -g`, ascii) gives exactly the same instructions as
the morning code — 1260.2 for a String, 1725.2 for a Substring, call for
call — and a WMO A/B of the same code against HEAD showed ascii
`range(of:)` −5% (§51 (t)).

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.13× ascii, 1.09× latin, **0.49× cjk** and **0.63× paths (we are
  FASTER)**, 1.11× thai
- sortKey **0.76× ascii, 0.86× latin, 0.96× cjk, 0.54× paths, 0.98× thai
  (all FASTER)** — since §51 (r), (s) and (t)

Seven of the ten rows are at or ahead of ICU C (every sortKey row, cjk and
paths compare). The three behind are compare on ascii and latin (1.09–1.13×;
~1 ns of each is the API's call shape, Docs/27) and thai (1.11×).

The `skRet` column (the allocating sortKey overload) stays ~0.67–1.39× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.58× (14 APIs).
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
