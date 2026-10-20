# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-19 18:03 on Apple Silicon (macOS 26), `run_benchmarks.sh`
K=3 (min over interleaved runs, each itself min-over-9), release builds, at
`32292a45`. Includes every optimization through §51 (i): C1–C3, the
collator and data caches with the lock-free fast-Latin cache (C7), the
options bit-pattern guard (C4), the CE buffer with an explicit count (C5 +
C6), and `compareFastPath` inlined into `compare`.

**Machine state:** 1-minute load 7–9 at each start (the 5-minute load rose
to 19 during run A), on AC power, 8 hours after the last wake, under
`caffeinate -i`. Two runs: A at 17:50 and B at 18:03. **The tables show run
B** (load 9–10, ICU C exactly at its reference); the reproducibility table
is under Table 1. Recorded on these grounds:

1. **The system-ICU control (Table 2) matches the reference within 2.0% in
   run B** and within 2.3% in run A (`localizedCompare` 196/366/372/303/504
   in run B, against 194/365/369/300/494).
2. **Runs A and B agree:** our compare and sortKey within 2.0%.

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
| ASCII  |    58 |       196 | **3.38× faster** |
| Latin  |    61 |       366 | **6.00× faster** |
| CJK    |    82 |       372 | **4.54× faster** |
| Paths  |    76 |       303 | **3.99× faster** |
| Thai   |   325 |       504 | **1.55× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    70 |       197 | **2.81× faster** |
| Latin  |    73 |       355 | **4.86× faster** |
| CJK    |   106 |       365 | **3.44× faster** |
| Paths  |    93 |       325 | **3.49× faster** |
| Thai   |   332 |       490 | **1.48× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    70 |       199 | **2.84× faster** |
| Latin  |    73 |       355 | **4.86× faster** |
| CJK    |   106 |       365 | **3.44× faster** |
| Paths  |    86 |       311 | **3.62× faster** |
| Thai   |   334 |       491 | **1.47× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    83 |       315 | **3.80× faster** |
| Latin  |    84 |       481 | **5.73× faster** |
| CJK    |   106 |       485 | **4.58× faster** |
| Paths  |   104 |       413 | **3.97× faster** |
| Thai   |   352 |       635 | **1.80× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   259 |      1004 | **3.88× faster** |
| Latin  |   287 |      1434 | **5.00× faster** |
| CJK    |   332 |      1279 | **3.85× faster** |
| Paths  |   272 |       976 | **3.59× faster** |
| Thai   |   286 |      1396 | **4.88× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   258 |      1018 | **3.95× faster** |
| Latin  |   287 |      1499 | **5.22× faster** |
| CJK    |   330 |      1294 | **3.92× faster** |
| Paths  |   222 |       988 | **4.45× faster** |
| Thai   |   286 |      1446 | **5.06× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   326 |      1005 | **3.08× faster** |
| Latin  |   351 |      1450 | **4.13× faster** |
| CJK    |   353 |      1284 | **3.64× faster** |
| Paths  |   381 |       988 | **2.59× faster** |
| Thai   |   437 |      1446 | **3.31× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   119 |       327 | **2.75× faster** |
| Latin  |   384 |       791 | **2.06× faster** |
| CJK    |   384 |       587 | **1.53× faster** |
| Paths  |   193 |       314 | **1.63× faster** |
| Thai   |   437 |       724 | **1.66× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   122 |       330 | **2.70× faster** |
| Latin  |   349 |       828 | **2.37× faster** |
| CJK    |   385 |       593 | **1.54× faster** |
| Paths  |   231 |       513 | **2.22× faster** |
| Thai   |   385 |       774 | **2.01× faster** |

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B.

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |    10.5 |   9.3 | 1.13× |   142.3 | 104.0 | 1.37× |   208.2 | 2.00× |
| Latin  |    11.0 |  10.1 | 1.09× |   161.8 | 121.1 | 1.34× |   220.1 | 1.82× |
| CJK    |    20.1 |  40.5 | **0.50×** |   164.6 | 118.2 | 1.39× |   242.9 | 2.05× |
| Paths  |    18.5 |  29.7 | **0.62×** |   361.2 | 369.8 | **0.98×** |   434.1 | 1.17× |
| Thai   |   221.0 | 173.9 | 1.27× |   201.4 | 155.1 | 1.30× |   273.4 | 1.76× |

Change against the previous baseline (2026-10-19 14:14):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 15.0 → 10.5 (**−30.0%**) | 157.9 → 142.3 (**−9.9%**) |
| Latin  | 14.7 → 11.0 (**−25.2%**) | 176.3 → 161.8 (**−8.2%**) |
| CJK    | 22.0 → 20.1 (**−8.6%**) | 175.7 → 164.6 (**−6.3%**) |
| Paths  | 20.6 → 18.5 (**−10.2%**) | 391.3 → 361.2 (**−7.7%**) |
| Thai   | 243.6 → 221.0 (**−9.3%**) | 212.3 → 201.4 (**−5.1%**) |

The moves are §51 (g)–(i): the options bit-pattern guard and the word
computed once (C4), the CE buffer with an explicit count (C5 + C6: every
sortKey row and thai compare), and `compareFastPath` inlined into `compare`
(ascii and latin compare −22%). paths sortKey is now below ICU (0.98×).

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 10.7 / 10.5 | 145.2 / 142.3 | 9.7 / 9.3 | 106.2 / 104.0 |
| Latin  | 11.2 / 11.0 | 164.2 / 161.8 | 10.3 / 10.1 | 123.5 / 121.1 |
| CJK    | 20.2 / 20.1 | 166.8 / 164.6 | 41.3 / 40.5 | 120.5 / 118.2 |
| Paths  | 18.5 / 18.5 | 364.1 / 361.2 | 30.2 / 29.7 | 372.7 / 369.8 |
| Thai   | 221.6 / 221.0 | 201.8 / 201.4 | 174.7 / 173.9 | 157.1 / 155.1 |

Run A read up to 2% higher on our side and up to 4% on ICU C (the load rose
to 19 during it). In Table 2, system ICU is within 1.8% over all 45 cells,
ours within 3.4%.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.13× ascii, 1.09× latin, **0.50× cjk** and **0.62× paths (we are
  FASTER)**, 1.27× thai
- sortKey 1.37× ascii, 1.34× latin, 1.39× cjk, **0.98× paths (FASTER)**, 1.30× thai

Three of the ten rows are now ahead of ICU C (cjk and paths compare, paths
sortKey). ascii and latin compare are within ~13% of ICU (10.5 against 9.3,
11.0 against 10.1 ns); about 1 ns of each is the API's call shape (Docs/27),
so the engine itself is close to parity there. The largest remaining gaps
are sortKey (1.30–1.39× on the short corpora; the writer is about half of
each call) and thai compare (1.27×).

The `skRet` column (the allocating sortKey overload) stays ~1.2–2.1× because
it allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is
the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.47×.
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. The
compare rows of Table 2 move with the engine, because they call it (for
example `localizedCompare` ascii 68 → 58 ns, thai 354 → 325 ns against the
14:14 run). Thai is the weakest family; it is also the engine's slowest
corpus.

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
