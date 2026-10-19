# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-19 14:14 on Apple Silicon (macOS 26), `run_benchmarks.sh`
K=3 (min over interleaved runs, each itself min-over-9), release builds, at
`6d6cc1f6`. Includes every optimization through §51: QuickCJKSetup by
pointer, the `Tag` switch, `RestartSafety.isUnsafe` by pointer, the BMP
restart-safety table, collators and data parsed once per process, and the
lock-free fast-Latin cache.

**Machine state:** not idle — 1-minute load 7–15, 5-minute load 13 at each
start (it rose to 23 during run A), on AC power, 5 hours after the last
wake, under `caffeinate -i`. Two runs: A at 14:00 and B at 14:14. **The
tables show run B** (steady load 11–12, better control); the
reproducibility table is under Table 1. Recorded on these grounds:

1. **The system-ICU control (Table 2) matches the reference within 1.8% in
   run B** and within 2.4% in run A (`localizedCompare` 195/365/374/303/503
   in run B, against 194/365/369/300/494).
2. **Runs A and B agree:** our compare within 1.4%, sortKey within 2.0%.
   ICU C within 2.0%.

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
| ASCII  |    68 |       195 | **2.87× faster** |
| Latin  |    72 |       365 | **5.07× faster** |
| CJK    |    91 |       374 | **4.11× faster** |
| Paths  |    85 |       303 | **3.56× faster** |
| Thai   |   354 |       503 | **1.42× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    77 |       197 | **2.56× faster** |
| Latin  |    78 |       356 | **4.56× faster** |
| CJK    |   111 |       367 | **3.31× faster** |
| Paths  |    99 |       325 | **3.28× faster** |
| Thai   |   361 |       489 | **1.35× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    77 |       199 | **2.58× faster** |
| Latin  |    79 |       357 | **4.52× faster** |
| CJK    |   110 |       365 | **3.32× faster** |
| Paths  |    93 |       308 | **3.31× faster** |
| Thai   |   363 |       491 | **1.35× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    91 |       311 | **3.42× faster** |
| Latin  |    93 |       480 | **5.16× faster** |
| CJK    |   117 |       487 | **4.16× faster** |
| Paths  |   110 |       414 | **3.76× faster** |
| Thai   |   380 |       632 | **1.66× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   286 |      1006 | **3.52× faster** |
| Latin  |   313 |      1438 | **4.59× faster** |
| CJK    |   353 |      1275 | **3.61× faster** |
| Paths  |   286 |       977 | **3.42× faster** |
| Thai   |   308 |      1390 | **4.51× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   285 |      1015 | **3.56× faster** |
| Latin  |   313 |      1494 | **4.77× faster** |
| CJK    |   354 |      1294 | **3.66× faster** |
| Paths  |   240 |       979 | **4.08× faster** |
| Thai   |   307 |      1443 | **4.70× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   354 |      1001 | **2.83× faster** |
| Latin  |   379 |      1440 | **3.80× faster** |
| CJK    |   381 |      1279 | **3.36× faster** |
| Paths  |   398 |       992 | **2.49× faster** |
| Thai   |   461 |      1444 | **3.13× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   120 |       326 | **2.72× faster** |
| Latin  |   408 |       793 | **1.94× faster** |
| CJK    |   408 |       588 | **1.44× faster** |
| Paths  |   194 |       315 | **1.62× faster** |
| Thai   |   453 |       727 | **1.60× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   121 |       330 | **2.73× faster** |
| Latin  |   368 |       827 | **2.25× faster** |
| CJK    |   404 |       596 | **1.48× faster** |
| Paths  |   229 |       511 | **2.23× faster** |
| Thai   |   397 |       774 | **1.95× faster** |

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    15.0 |   9.3 | 1.61× |   157.9 | 104.0 | 1.52× |   218.7 | 2.10× |
| Latin  |    14.7 |  10.1 | 1.46× |   176.3 | 121.2 | 1.45× |   234.8 | 1.94× |
| CJK    |    22.0 |  41.2 | **0.53×** |   175.7 | 118.4 | 1.48× |   249.9 | 2.11× |
| Paths  |    20.6 |  29.7 | **0.69×** |   391.3 | 369.8 | 1.06× |   466.9 | 1.26× |
| Thai   |   243.6 | 172.9 | 1.41× |   212.3 | 155.6 | 1.36× |   281.7 | 1.81× |

Change against the previous baseline (2026-10-16 17:29):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 15.1 → 15.0 | 157.2 → 157.9 |
| Latin  | 14.6 → 14.7 | 175.7 → 176.3 |
| CJK    | 25.4 → 22.0 (**−13.4%**) | 174.5 → 175.7 |
| Paths  | 23.2 → 20.6 (**−11.2%**) | 381.4 → 391.3 |
| Thai   | 257.9 → 243.6 (**−5.5%**) | 209.5 → 212.3 |

The compare moves are §51 (C1–C3): QuickCJKSetup by pointer and the `Tag`
switch (cjk), `RestartSafety.isUnsafe` by pointer without the struct copy
(paths), and the BMP restart-safety table (thai). sortKey executes the same
instructions as before on every corpus (instruction counts); its moves are
code placement — the interleaved A/B of HEAD against `8485740c` read paths
sortKey +2.6% (5/5), and the same A/B with every function aligned to 64 bytes
in both builds read −0.5% (5/5), with all five sortKey rows at −0.2..−1.8%.

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 15.2 / 15.0 | 161.1 / 157.9 | 9.4 / 9.3 | 105.9 / 104.0 |
| Latin  | 14.9 / 14.7 | 178.8 / 176.3 | 10.3 / 10.1 | 123.4 / 121.2 |
| CJK    | 22.2 / 22.0 | 176.3 / 175.7 | 41.2 / 41.2 | 119.2 / 118.4 |
| Paths  | 20.7 / 20.6 | 395.6 / 391.3 | 30.3 / 29.7 | 371.0 / 369.8 |
| Thai   | 244.6 / 243.6 | 213.6 / 212.3 | 174.5 / 172.9 | 156.9 / 155.6 |

Run A read up to 2% higher on both sides (the load rose to 23 during it). In
Table 2, system ICU is within 2.3% over all 45 cells, ours within 2.9%.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.61× ascii, 1.46× latin, **0.53× cjk** and **0.69× paths (we are
  FASTER)**, 1.41× thai
- sortKey 1.52× ascii, 1.45× latin, 1.48× cjk, 1.06× paths, 1.36× thai

Six of the ten rows are behind ICU C. §51 moved cjk compare from 0.63× to
0.53×, paths from 0.78× to 0.69× and thai from 1.48× to 1.41×. The worst
row is still ascii compare (15.0 against 9.3 ns). Instruction counts
(§50 (g)) put our fast-Latin core near ICU's (74 against 65 instructions on
ascii); the gap is the entry. The lines of the ascii and latin corpora are
about 7 bytes long, so those rows measure mostly the FIXED cost per call.

The `skRet` column (the allocating sortKey overload) stays ~1.2–2.1× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.35×.
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. The paths
and cjk rows of Table 2 move with the engine, because they call it;
`localizedStandardCompare` (numeric options) also gained from the lock-free
fast-Latin cache (thai 389 → 361, cjk 117 → 111 ns against the 2026-10-16
run). Thai is the weakest family; it is also
the engine's slowest corpus — the NFD per-scalar floor (§36).

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
