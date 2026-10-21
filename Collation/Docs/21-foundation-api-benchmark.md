# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-21 ~11:30 on Apple Silicon (macOS 26), `run_benchmarks.sh`
K=3 (min over interleaved runs, each itself min-over-9), release builds, at
`4c24d059` plus §51 (p) (the localized* wrappers, not yet committed at the
time of the run). Includes every optimization through §51 (p): new since the
previous baseline are (l) thai compare, (o) identical strength and (p).

**Machine state:** 1-minute load 12 at the start of run A, 11 at its end,
26 at the end of run B, on AC power, under `caffeinate -i`, three hours
after the last wake. **The tables show run B.** Recorded on these grounds
(the control decides, not the load — Docs/27):

1. **The system-ICU control (Table 2) matches the reference within 2.2% in
   run B** and within 1.2% in run A (`localizedCompare` 196/363/370/301/505
   in run B, against 194/365/369/300/494); between the runs it moves at
   most 1.6% over all 70 cells.
2. **Runs A and B agree:** Table 1 within 2.1% in every cell (ours and ICU
   C); Table 2 ours within 2.0% except one cell (`localizedCompare` ascii,
   52 in run A, 48 in run B).

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
| ASCII  |    48 |       196 | **4.08× faster** |
| Latin  |    51 |       363 | **7.12× faster** |
| CJK    |    70 |       370 | **5.29× faster** |
| Paths  |    65 |       301 | **4.63× faster** |
| Thai   |   285 |       505 | **1.77× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    63 |       198 | **3.14× faster** |
| Latin  |    65 |       351 | **5.40× faster** |
| CJK    |    99 |       364 | **3.68× faster** |
| Paths  |    85 |       323 | **3.80× faster** |
| Thai   |   311 |       492 | **1.58× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    63 |       199 | **3.16× faster** |
| Latin  |    65 |       354 | **5.45× faster** |
| CJK    |   100 |       363 | **3.63× faster** |
| Paths  |    79 |       310 | **3.92× faster** |
| Thai   |   311 |       491 | **1.58× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    70 |       311 | **4.44× faster** |
| Latin  |    73 |       478 | **6.55× faster** |
| CJK    |    94 |       484 | **5.15× faster** |
| Paths  |    91 |       412 | **4.53× faster** |
| Thai   |   315 |       633 | **2.01× faster** |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    89 |       311 | **3.49× faster** |
| Latin  |    91 |       467 | **5.13× faster** |
| CJK    |   125 |       483 | **3.86× faster** |
| Paths  |   109 |       420 | **3.85× faster** |
| Thai   |   346 |       566 | **1.64× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   249 |       994 | **3.99× faster** |
| Latin  |   274 |      1436 | **5.24× faster** |
| CJK    |   318 |      1274 | **4.01× faster** |
| Paths  |   255 |       970 | **3.80× faster** |
| Thai   |   274 |      1388 | **5.07× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   249 |      1006 | **4.04× faster** |
| Latin  |   273 |      1485 | **5.44× faster** |
| CJK    |   320 |      1283 | **4.01× faster** |
| Paths  |   211 |       975 | **4.62× faster** |
| Thai   |   272 |      1444 | **5.31× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   320 |       994 | **3.11× faster** |
| Latin  |   342 |      1434 | **4.19× faster** |
| CJK    |   343 |      1277 | **3.72× faster** |
| Paths  |   309 |       982 | **3.18× faster** |
| Thai   |   406 |      1442 | **3.55× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   108 |       324 | **3.00× faster** |
| Latin  |   371 |       782 | **2.11× faster** |
| CJK    |   369 |       583 | **1.58× faster** |
| Paths  |   130 |       312 | **2.40× faster** |
| Thai   |   427 |       719 | **1.68× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   109 |       325 | **2.98× faster** |
| Latin  |   329 |       821 | **2.50× faster** |
| CJK    |   367 |       588 | **1.60× faster** |
| Paths  |   162 |       508 | **3.14× faster** |
| Thai   |   360 |       771 | **2.14× faster** |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2241 |     14922 | **6.66× faster** |
| Latin  |  2329 |     17474 | **7.50× faster** |
| CJK    |  3875 |     18518 | **4.78× faster** |
| Paths  |   236 |      1272 | **5.39× faster** |
| Thai   |  1255 |      5771 | **4.60× faster** |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2111 |      5142 | **2.44× faster** |
| Latin  |  2192 |      7382 | **3.37× faster** |
| CJK    |  2627 |      7786 | **2.96× faster** |
| Paths  |   182 |       478 | **2.63× faster** |
| Thai   |  1224 |      2481 | **2.03× faster** |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  3694 |     16604 | **4.49× faster** |
| Latin  |  3781 |     19026 | **5.03× faster** |
| CJK    |  5502 |     20416 | **3.71× faster** |
| Paths  |   321 |      1356 | **4.22× faster** |
| Thai   |  1729 |      6368 | **3.68× faster** |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2724 |     16395 | **6.02× faster** |
| Latin  |  2790 |     18998 | **6.81× faster** |
| CJK    |  4404 |     20111 | **4.57× faster** |
| Paths  |   242 |      1325 | **5.48× faster** |
| Thai   |  1379 |      6185 | **4.49× faster** |

### The sort rows

One op is one ELEMENT of a sort. Swift's sort makes about 14 comparisons
per element on these 200-line corpora (counted; not n·log2(n) ≈ 7.6), so ns
per element ≈ 14 × (ns per comparison) plus the sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

**Re-measured 2026-10-21 afternoon, after §51 (r) and (s)** (the sortKey
writer: level cursors, and a specialization for the default options; HEAD
`15f74f4b` + (s)). Three matrix runs: run A (load 20 → 13, system-ICU
control within 1.8%) is recorded below; runs B and E ran at load 27–89 with
the control ~3% high, read 1–4% higher in every cell (ours and ICU alike),
and give the same ratios within 0.01–0.02. Confirm the absolute values on a
quiet machine before you quote them to 1 ns. Table 2 does not call sortKey;
it keeps the morning baseline above.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    10.6 |   9.4 | 1.13× |    94.0 | 106.1 | **0.89×** |   147.5 | 1.39× |
| Latin  |    11.0 |  10.3 | 1.07× |   107.3 | 123.6 | **0.87×** |   163.4 | 1.32× |
| CJK    |    20.3 |  40.9 | **0.50×** |   114.0 | 118.8 | **0.96×** |   167.7 | 1.41× |
| Paths  |    18.4 |  29.8 | **0.62×** |   265.9 | 369.6 | **0.72×** |   312.5 | 0.85× |
| Thai   |   194.8 | 173.0 | 1.13× |   153.3 | 154.7 | **0.99×** |   209.3 | 1.35× |

sortKey against the morning run (below): ascii 123.1 → 94.0 (−23.6%),
latin 131.4 → 107.3 (−18.3%), cjk 144.0 → 114.0 (−20.8%), paths 331.8 →
265.9 (−19.9%), thai 177.6 → 153.3 (−13.7%). Every sortKey row is now at
or below ICU C.

The morning run (2026-10-21 ~11:30, run B, before (r) and (s)):

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    10.6 |   9.5 | 1.12× |   123.1 | 106.1 | 1.16× |   175.1 | 1.65× |
| Latin  |    11.0 |  10.1 | 1.09× |   131.4 | 122.1 | 1.08× |   181.8 | 1.49× |
| CJK    |    20.0 |  40.8 | **0.49×** |   144.0 | 119.3 | 1.21× |   197.3 | 1.65× |
| Paths  |    18.5 |  29.7 | **0.62×** |   331.8 | 369.6 | **0.90×** |   377.8 | 1.02× |
| Thai   |   195.7 | 172.0 | 1.14× |   177.6 | 154.7 | 1.15× |   231.9 | 1.50× |

Change against the previous baseline (2026-10-20 14:35):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 10.5 → 10.6 | 124.2 → 123.1 |
| Latin  | 11.0 → 11.0 | 131.3 → 131.4 |
| CJK    | 20.1 → 20.0 | 144.5 → 144.0 |
| Paths  | 18.5 → 18.5 | 332.5 → 331.8 |
| Thai   | 198.4 → 195.7 (−1.4%; run A 191.8, −3.3%) | 176.1 → 177.6 |

The only engine move is §51 (l) on thai compare (its A/B gave −3.5%; run B
read it at a higher load than run A). (o) and (p) do not touch Table 1.

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 10.4 / 10.6 | 123.9 / 123.1 | 9.5 / 9.5 | 103.9 / 106.1 |
| Latin  | 11.0 / 11.0 | 131.1 / 131.4 | 10.1 / 10.1 | 121.0 / 122.1 |
| CJK    | 20.2 / 20.0 | 143.1 / 144.0 | 40.6 / 40.8 | 118.3 / 119.3 |
| Paths  | 18.5 / 18.5 | 331.3 / 331.8 | 29.7 / 29.7 | 367.1 / 369.6 |
| Thai   | 191.8 / 195.7 | 175.4 / 177.6 | 171.3 / 172.0 | 154.3 / 154.7 |

Run B ended at load 26 and read up to ~2% higher on thai. In Table 2,
system ICU is within 1.6% over all 70 cells, ours within 2.0% except
`localizedCompare` ascii (52 / 48).

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.13× ascii, 1.07× latin, **0.50× cjk** and **0.62× paths (we are
  FASTER)**, 1.13× thai
- sortKey **0.89× ascii, 0.87× latin, 0.96× cjk, 0.72× paths, 0.99× thai
  (all FASTER)** — since §51 (r) and (s), afternoon run A

Seven of the ten rows are at or ahead of ICU C (every sortKey row, cjk and
paths compare). The three behind are compare on ascii and latin (1.07–1.13×;
~1 ns of each is the API's call shape, Docs/27) and thai (1.13×).

The `skRet` column (the allocating sortKey overload) stays ~0.85–1.41× because
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
