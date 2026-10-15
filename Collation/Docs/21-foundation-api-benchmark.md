# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-15 on Apple Silicon (macOS 26), `run_benchmarks.sh` K=3
(min over interleaved runs, each itself min-over-9), release builds, at
`ba9a6491` plus the build-script path fix. Includes every optimization
through §49 (the writer assembly tail, "variant C"). The previous baseline
was 2026-08-12 (post-§48); the changes against it are listed under Table 1.

**Machine state:** not idle. The 1-minute load was 10–15 during the run
(10.9 at the start, 10.0 at the end; 10 cores), and 31–35% of memory was
free. The run took under 4 minutes. A second run 12 minutes later (load
9–14) agrees with it; the reproducibility table is under Table 1. The
tables show the first run. It is recorded as the baseline on these grounds:

1. **The system-ICU column (Table 2) matches 2026-08-12 within 1.3%**, for
   example `localizedCompare` 194/365/369/300/494 vs 194/365/370/299/497.
   System ICU did not change, so it is the load control: had load inflated
   the measurements, it would have drifted too.
2. **ICU C's own column (Table 1) matches 2026-08-12 within 2%**: compare
   9/10/40/29/171 vs 9/10/40/29/170, sortKey 103/120/117/364/152 vs
   103/120/117/367/155. (See the ICU note below for why this is a second
   result, not the control.)
3. **Table 1 compare is unchanged** (16/15/27/40/258 vs 16/15/26/40/260),
   which is correct: §49 changed only the sortKey writer.

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout, which is NOT 79.0.1 any more: it is on branch
`ICU-23250-CLDR-79-integration-beta4` (CLDR 49), with 79.1 libraries and
Unicode 18 root collation data. Our collator bundles 79.0.1 data. ICU's
speed did not change (ground 2), so the ratios stay comparable with
2026-08-12, but the ICU column now measures a different ICU build than every
earlier baseline. Do not generate golden files from that checkout
(technique log §49).

Same Foundation APIs, two backends:

- **Swift Collator**: `BenchFoundation`, release, `-no-WMO` (Docs/27 —
  required on machine 1, a handicap here, so these UNDERSTATE the framework
  build)
- **System ICU**: pre-compiled `bench_system` (system Foundation → NSString →
  CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    70 |       194 | **2.77× faster** |
| Latin  |    71 |       365 | **5.14× faster** |
| CJK    |   101 |       369 | **3.65× faster** |
| Paths  |   105 |       300 | **2.86× faster** |
| Thai   |   368 |       494 | **1.34× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    81 |       196 | **2.42× faster** |
| Latin  |    83 |       351 | **4.23× faster** |
| CJK    |   119 |       359 | **3.02× faster** |
| Paths  |   127 |       321 | **2.53× faster** |
| Thai   |   387 |       483 | **1.25× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    81 |       199 | **2.46× faster** |
| Latin  |    82 |       351 | **4.28× faster** |
| CJK    |   120 |       361 | **3.01× faster** |
| Paths  |   120 |       309 | **2.58× faster** |
| Thai   |   387 |       483 | **1.25× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    93 |       312 | **3.35× faster** |
| Latin  |    96 |       474 | **4.94× faster** |
| CJK    |   124 |       480 | **3.87× faster** |
| Paths  |   135 |       410 | **3.04× faster** |
| Thai   |   396 |       624 | **1.58× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   287 |       997 | **3.47× faster** |
| Latin  |   314 |      1430 | **4.55× faster** |
| CJK    |   361 |      1268 | **3.51× faster** |
| Paths  |   290 |       966 | **3.33× faster** |
| Thai   |   307 |      1377 | **4.49× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   285 |      1007 | **3.53× faster** |
| Latin  |   315 |      1482 | **4.70× faster** |
| CJK    |   361 |      1275 | **3.53× faster** |
| Paths  |   242 |       978 | **4.04× faster** |
| Thai   |   308 |      1430 | **4.64× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   353 |       998 | **2.83× faster** |
| Latin  |   382 |      1430 | **3.74× faster** |
| CJK    |   382 |      1270 | **3.32× faster** |
| Paths  |   395 |       980 | **2.48× faster** |
| Thai   |   458 |      1426 | **3.11× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   120 |       326 | **2.72× faster** |
| Latin  |   413 |       782 | **1.89× faster** |
| CJK    |   414 |       583 | **1.41× faster** |
| Paths  |   190 |       312 | **1.64× faster** |
| Thai   |   457 |       713 | **1.56× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   121 |       328 | **2.71× faster** |
| Latin  |   374 |       815 | **2.18× faster** |
| CJK    |   414 |       588 | **1.42× faster** |
| Paths  |   226 |       508 | **2.25× faster** |
| Thai   |   398 |       761 | **1.91× faster** |

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).

| Corpus | compare | ICU | ratio | sortKey (inout) | ICU | ratio | sortKey (alloc) | ratio |
|--------|---------|-----|-------|---------|-----|-------|---------|-------|
| ASCII  |      16 |   9 | 1.78× |     158 | 103 | 1.53× |     220 | 2.14× |
| Latin  |      15 |  10 | 1.50× |     175 | 120 | 1.46× |     234 | 1.95× |
| CJK    |      27 |  40 | **0.68×** |     174 | 117 | 1.49× |     253 | 2.16× |
| Paths  |      40 |  29 | 1.38× |     389 | 364 | 1.07× |     462 | 1.27× |
| Thai   |     258 | 171 | 1.51× |     209 | 152 | 1.38× |     277 | 1.82× |

Change against 2026-08-12 (ours, ns/op):

| Corpus | compare | sortKey (inout) | sortKey (alloc) |
|--------|---------|-----------------|-----------------|
| ASCII  | 16 → 16 | 159 → 158 | 223 → 220 |
| Latin  | 15 → 15 | **182 → 175 (−3.8%)** | **243 → 234 (−3.7%)** |
| CJK    | 26 → 27 | 173 → 174 | 251 → 253 |
| Paths  | 40 → 40 | 386 → 389 | 465 → 462 |
| Thai   | 260 → 258 | **213 → 209 (−1.9%)** | **282 → 277 (−1.8%)** |

The latin and thai sortKey moves are §49's variant C, seen here in a second
harness (its interleaved A/B gave −4.3% and −3.2%). The other cells are
inside noise; compare rows are rounded to 1 ns. The thai and paths sortKey
RATIOS also moved because ICU's own times moved (155 → 152, 367 → 364).

Reproducibility, run 1 vs run 2 of the same matrix (2026-10-15, 12 minutes
apart):

| Corpus | compare r1/r2 | sortKey r1/r2 | ICU compare r1/r2 | ICU sortKey r1/r2 |
|--------|---------------|---------------|-------------------|-------------------|
| ASCII  | 16 / 16 | 158 / 157 | 9 / 9 | 103 / 104 |
| Latin  | 15 / 15 | 175 / 175 | 10 / 10 | 120 / 122 |
| CJK    | 27 / 26 | 174 / 174 | 40 / 40 | 117 / 117 |
| Paths  | 40 / 41 | 389 / 391 | 29 / 29 | 364 / 365 |
| Thai   | 258 / 260 | 209 / 211 | 171 / 172 | 152 / 153 |

Our sortKey within 1.0%, ICU within 1.7%. The two compare cells that differ
(cjk, paths) move by one 1-ns rounding step. In Table 2, system ICU is within
1.7% over all 45 cells; ours is within 3% except one cell, `localizedCompare`
latin 71 → 74 (4.2%, 3 ns, in the `-no-WMO` BenchFoundation build).

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

- compare 1.78× ascii, 1.50× latin, **0.68× cjk (we are FASTER)**,
  1.38× paths, 1.51× thai
- sortKey 1.53× ascii, **1.46× latin**, 1.49× cjk, 1.07× paths, 1.38× thai

Seven of the ten rows are still behind ICU C. The worst is ascii compare
(1.78×); the best non-cjk row is paths sortKey (1.07×).

The `skRet` column (the allocating sortKey overload) stays ~1.3–2.2× because it
allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is the one
to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.25×
(`localizedCompare` family 1.25–5.14×, `contains` family 3.33–4.70×, range
family 1.41–3.74×). Most of that lead comes from removing the system path's
NSString → CoreFoundation → C++ bridge layers, not from the collation engine.
Do not use Table 2 as evidence about engine quality; Table 1 is that
evidence. Thai is the weakest family (1.25× floor); it is also the engine's
slowest corpus — the NFD per-scalar floor (§36).

Table 2 did not change against 2026-08-12 (for example `localizedCompare`
70/71/101/105/368 vs 70/70/99/105/372), which is expected: §49 changed only
the sortKey writer.

## How to reproduce

```sh
cd swift-foundation-collation
ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2 \
ICU_BUILD=$ICU_SRC/icu4c/source \
  Collation/Tools/run_benchmarks.sh 3
```

K=3 takes about 4 minutes. Check the machine first — load average AND memory:

```sh
sysctl -n vm.loadavg; memory_pressure | grep "free percentage"
```

Sanity gates before you record a run:

- **The load control:** system ICU in Table 2 should read about
  194/365/369/300/494 for `localizedCompare`. If it drifts by more than
  ~3%, the box is too busy to record.
- **ICU C** in Table 1 should read about 9/10/40/29/171 compare and
  103/120/117/364/152 sortKey. First check which ICU the checkout holds
  (`git -C $ICU_SRC branch --show-current`); a different ICU build can
  change this column for reasons that have nothing to do with load.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
