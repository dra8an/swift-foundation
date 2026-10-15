# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-15 13:21 on Apple Silicon (macOS 26), `run_benchmarks.sh`
K=3 (min over interleaved runs, each itself min-over-9), release builds, at
`56358e08`. Includes every optimization through §49 (the writer assembly
tail, "variant C").

**First baseline with one-decimal output.** Since `56358e08`, EngineBench and
`bench_icu` print one decimal. Every earlier Table-1 value was TRUNCATED by
integer division (16.6 printed as 16, ICU's 9.5 as 9), so earlier values read
up to 1 ns low. Do not compare this table with earlier ones at the 1-ns level.
The effect of §49 was measured by an interleaved A/B, not by baselines:
sortKey latin −4.3%, thai −3.2%, the other rows flat (technique log §49).

**Machine state:** not idle — 1-minute load 12–14, 5-minute 13–14, on AC
power, 31 minutes after a wake from sleep. Two runs, A at 13:21 and B at
13:25. The tables show run A; the reproducibility table is under Table 1.
Two earlier runs the same day were DISCARDED: they started 2 and 6 minutes
after a wake, and read 1–3% slow on the system-ICU control (Docs/27).
Recorded on these grounds:

1. **The system-ICU control (Table 2) matches the reference within 1.5% in
   run A** and within 2.6% in run B (`localizedCompare` 197/366/373/304/501
   in run A, against 194/365/369/300/494). System ICU did not change, so it
   is the load control.
2. **Runs A and B agree:** our compare within 1.2%, sortKey within 1.5%,
   `skRet` within 2.0%.

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
| ASCII  |    70 |       197 | **2.81× faster** |
| Latin  |    71 |       366 | **5.15× faster** |
| CJK    |   100 |       373 | **3.73× faster** |
| Paths  |   107 |       304 | **2.84× faster** |
| Thai   |   373 |       501 | **1.34× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    81 |       198 | **2.44× faster** |
| Latin  |    83 |       355 | **4.28× faster** |
| CJK    |   119 |       368 | **3.09× faster** |
| Paths  |   128 |       325 | **2.54× faster** |
| Thai   |   389 |       491 | **1.26× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    81 |       198 | **2.44× faster** |
| Latin  |    83 |       355 | **4.28× faster** |
| CJK    |   119 |       367 | **3.08× faster** |
| Paths  |   119 |       311 | **2.61× faster** |
| Thai   |   391 |       489 | **1.25× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    93 |       314 | **3.38× faster** |
| Latin  |    95 |       477 | **5.02× faster** |
| CJK    |   123 |       487 | **3.96× faster** |
| Paths  |   136 |       414 | **3.04× faster** |
| Thai   |   399 |       631 | **1.58× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   287 |      1000 | **3.48× faster** |
| Latin  |   317 |      1447 | **4.56× faster** |
| CJK    |   360 |      1286 | **3.57× faster** |
| Paths  |   293 |       979 | **3.34× faster** |
| Thai   |   311 |      1390 | **4.47× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   284 |      1015 | **3.57× faster** |
| Latin  |   317 |      1501 | **4.74× faster** |
| CJK    |   364 |      1297 | **3.56× faster** |
| Paths  |   245 |       984 | **4.02× faster** |
| Thai   |   312 |      1440 | **4.62× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   354 |      1005 | **2.84× faster** |
| Latin  |   383 |      1441 | **3.76× faster** |
| CJK    |   385 |      1297 | **3.37× faster** |
| Paths  |   399 |       992 | **2.49× faster** |
| Thai   |   464 |      1439 | **3.10× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   120 |       325 | **2.71× faster** |
| Latin  |   415 |       792 | **1.91× faster** |
| CJK    |   417 |       591 | **1.42× faster** |
| Paths  |   194 |       315 | **1.62× faster** |
| Thai   |   467 |       721 | **1.54× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   121 |       332 | **2.74× faster** |
| Latin  |   374 |       825 | **2.21× faster** |
| CJK    |   417 |       599 | **1.44× faster** |
| Paths  |   229 |       507 | **2.21× faster** |
| Thai   |   405 |       770 | **1.90× faster** |

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run A.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    16.7 |   9.3 | 1.80× |   158.6 | 103.8 | 1.53× |   220.0 | 2.12× |
| Latin  |    15.6 |  10.1 | 1.54× |   175.4 | 121.6 | 1.44× |   234.9 | 1.93× |
| CJK    |    26.7 |  41.1 | **0.65×** |   175.1 | 120.4 | 1.45× |   249.5 | 2.07× |
| Paths  |    41.1 |  29.7 | 1.38× |   392.2 | 367.7 | 1.07× |   467.7 | 1.27× |
| Thai   |   261.7 | 173.8 | 1.51× |   211.4 | 156.3 | 1.35× |   283.0 | 1.81× |

Reproducibility, run A vs run B of the same matrix (4 minutes apart):

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 16.7 / 16.9 | 158.6 / 160.5 | 9.3 / 9.6 | 103.8 / 108.6 |
| Latin  | 15.6 / 15.5 | 175.4 / 177.0 | 10.1 / 10.1 | 121.6 / 121.0 |
| CJK    | 26.7 / 26.7 | 175.1 / 172.5 | 41.1 / 40.7 | 120.4 / 119.3 |
| Paths  | 41.1 / 41.1 | 392.2 / 390.0 | 29.7 / 29.7 | 367.7 / 368.0 |
| Thai   | 261.7 / 263.6 | 211.4 / 213.5 | 173.8 / 172.6 | 156.3 / 155.8 |

Ours: compare within 1.2%, sortKey within 1.5%. ICU moved more in one cell
(ascii sortKey 103.8 → 108.6, +4.6%, run B only). In Table 2, system ICU is
within 2.2% over all 45 cells, ours within 3.2%.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.80× ascii, 1.54× latin, **0.65× cjk (we are FASTER)**,
  1.38× paths, 1.51× thai
- sortKey 1.53× ascii, 1.44× latin, 1.45× cjk, 1.07× paths, 1.35× thai

Seven of the ten rows are behind ICU C. The worst is ascii compare
(16.7 against 9.3 ns); the harness explains about 1 ns of that gap (Docs/27),
the rest is engine time. The lines of the ascii and latin corpora are very
short (about 7 bytes), so those rows measure mostly the FIXED cost per call.

The `skRet` column (the allocating sortKey overload) stays ~1.3–2.1× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.25×.
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. Thai is
the weakest family; it is also the engine's slowest corpus — the NFD
per-scalar floor (§36).

## How to reproduce

```sh
cd swift-foundation-collation
ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2 \
ICU_BUILD=$ICU_SRC/icu4c/source \
  Collation/Tools/run_benchmarks.sh 3
```

K=3 takes about 4 minutes. Check the machine first — load average, memory,
and the time since the last wake (Docs/27):

```sh
sysctl -n vm.loadavg; memory_pressure | grep "free percentage"
pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -3
```

Sanity gates before you record a run:

- **The load control:** system ICU in Table 2 should read about
  194/365/369/300/494 for `localizedCompare`. If it drifts by more than
  ~3%, the box is too busy to record.
- **ICU C** in Table 1 should read about 9.3/10.1/41.1/29.7/173.8 compare
  and 103.8/121.6/120.4/367.7/156.3 sortKey. First check which ICU the
  checkout holds (`git -C $ICU_SRC branch --show-current`); a different ICU
  build can change this column for reasons that have nothing to do with load.
- **Run the matrix twice;** the two runs must agree.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
