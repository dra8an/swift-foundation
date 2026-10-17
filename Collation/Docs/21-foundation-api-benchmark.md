# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-16 17:29 on Apple Silicon (macOS 26), `run_benchmarks.sh`
K=3 (min over interleaved runs, each itself min-over-9), release builds, at
`481cd3ce`. Includes every optimization through §50: the default fast-Latin
setup in one box (Fix A3), the restart-safety table below U+0300, and
RestartSafety passed by pointer (§50 (g)).

**Machine state:** not idle — 1-minute load 10–17 across the two runs, on AC
power, 8 hours after the last wake, under `caffeinate -i`. Two runs: A at
17:22 and B at 17:29. **The tables show run B** (lower load, better control);
the reproducibility table is under Table 1. Recorded on these grounds:

1. **The system-ICU control (Table 2) matches the reference within 1.7% in
   run B** and within 2.1% in run A (`localizedCompare` 197/368/375/305/500
   in run B, against 194/365/369/300/494).
2. **Runs A and B agree:** our compare within 1.4%, sortKey within 2.1%,
   `skRet` within 1.1%. ICU C within 2.2%.

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
| ASCII  |    66 |       197 | **2.98× faster** |
| Latin  |    70 |       368 | **5.26× faster** |
| CJK    |    97 |       375 | **3.87× faster** |
| Paths  |    84 |       305 | **3.63× faster** |
| Thai   |   371 |       500 | **1.35× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    79 |       197 | **2.49× faster** |
| Latin  |    81 |       357 | **4.41× faster** |
| CJK    |   117 |       367 | **3.14× faster** |
| Paths  |   104 |       326 | **3.13× faster** |
| Thai   |   389 |       490 | **1.26× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    79 |       199 | **2.52× faster** |
| Latin  |    81 |       357 | **4.41× faster** |
| CJK    |   118 |       369 | **3.13× faster** |
| Paths  |    97 |       314 | **3.24× faster** |
| Thai   |   390 |       488 | **1.25× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    92 |       315 | **3.42× faster** |
| Latin  |    92 |       477 | **5.18× faster** |
| CJK    |   123 |       487 | **3.96× faster** |
| Paths  |   111 |       415 | **3.74× faster** |
| Thai   |   401 |       632 | **1.58× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   290 |      1002 | **3.46× faster** |
| Latin  |   319 |      1451 | **4.55× faster** |
| CJK    |   365 |      1287 | **3.53× faster** |
| Paths  |   292 |       971 | **3.33× faster** |
| Thai   |   311 |      1389 | **4.47× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   291 |      1015 | **3.49× faster** |
| Latin  |   317 |      1506 | **4.75× faster** |
| CJK    |   364 |      1286 | **3.53× faster** |
| Paths  |   244 |       984 | **4.03× faster** |
| Thai   |   309 |      1438 | **4.65× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   360 |      1001 | **2.78× faster** |
| Latin  |   383 |      1448 | **3.78× faster** |
| CJK    |   388 |      1290 | **3.32× faster** |
| Paths  |   400 |       991 | **2.48× faster** |
| Thai   |   462 |      1443 | **3.12× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   119 |       327 | **2.75× faster** |
| Latin  |   417 |       799 | **1.92× faster** |
| CJK    |   424 |       591 | **1.39× faster** |
| Paths  |   193 |       315 | **1.63× faster** |
| Thai   |   466 |       717 | **1.54× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   119 |       328 | **2.76× faster** |
| Latin  |   378 |       827 | **2.19× faster** |
| CJK    |   419 |       591 | **1.41× faster** |
| Paths  |   227 |       513 | **2.26× faster** |
| Thai   |   408 |       767 | **1.88× faster** |

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    15.1 |   9.3 | 1.62× |   157.2 | 104.5 | 1.50× |   220.1 | 2.11× |
| Latin  |    14.6 |  10.1 | 1.45× |   175.7 | 120.9 | 1.45× |   234.2 | 1.94× |
| CJK    |    25.4 |  40.5 | **0.63×** |   174.5 | 119.0 | 1.47× |   254.8 | 2.14× |
| Paths  |    23.2 |  29.7 | **0.78×** |   381.4 | 370.3 | 1.03× |   458.9 | 1.24× |
| Thai   |   257.9 | 173.8 | 1.48× |   209.5 | 155.5 | 1.35× |   280.0 | 1.80× |

Change against the previous baseline (2026-10-15 13:21, also one decimal):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 16.7 → 15.1 (**−9.6%**) | 158.6 → 157.2 |
| Latin  | 15.6 → 14.6 (**−6.4%**) | 175.4 → 175.7 |
| CJK    | 26.7 → 25.4 (**−4.9%**) | 175.1 → 174.5 |
| Paths  | 41.1 → 23.2 (**−43.6%**) | 392.2 → 381.4 |
| Thai   | 261.7 → 257.9 | 211.4 → 209.5 |

The compare moves are §50: Fix A3 and §50 (g). The interleaved A/B of §50 (g)
alone gave paths −43%, ascii −8.5%, cjk −7%, latin −2%. sortKey code did not
change; its moves (paths −2.8% the largest) are between-run variation — the
§50 A/Bs measured sortKey flat in every round.

Reproducibility, run A vs run B of the same matrix (7 minutes apart):

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 15.3 / 15.1 | 160.5 / 157.2 | 9.4 / 9.3 | 106.0 / 104.5 |
| Latin  | 14.8 / 14.6 | 177.9 / 175.7 | 10.3 / 10.1 | 123.5 / 120.9 |
| CJK    | 25.7 / 25.4 | 176.2 / 174.5 | 41.4 / 40.5 | 119.1 / 119.0 |
| Paths  | 23.4 / 23.2 | 383.6 / 381.4 | 30.3 / 29.7 | 371.7 / 370.3 |
| Thai   | 258.5 / 257.9 | 209.3 / 209.5 | 173.0 / 173.8 | 156.9 / 155.5 |

Run A ran at the higher load (5-minute load up to 17.5) and reads up to 2%
higher on both sides. In Table 2, system ICU is within 2.1% over all 45 cells,
ours within 2.9%.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.62× ascii, 1.45× latin, **0.63× cjk** and **0.78× paths (we are
  FASTER)**, 1.48× thai
- sortKey 1.50× ascii, 1.45× latin, 1.47× cjk, 1.03× paths, 1.35× thai

Six of the ten rows are behind ICU C; paths compare moved ahead with §50 (g).
The worst row is ascii compare (15.1 against 9.3 ns). Instruction counts
(§50 (g)) put our fast-Latin core near ICU's (74 against 65 instructions on
ascii); the gap is the entry. The lines of the ascii and latin corpora are
about 7 bytes long, so those rows measure mostly the FIXED cost per call.

The `skRet` column (the allocating sortKey overload) stays ~1.2–2.1× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.25×.
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. The paths
compare rows of Table 2 (for example `localizedCompare` 107 → 84 ns) moved
with the engine, because they call it. Thai is the weakest family; it is also
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
