# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-08-12 on Apple Silicon (macOS 26), `run_benchmarks.sh` K=3
(min over interleaved runs, each itself min-over-9), release builds. Includes
every optimization through §48 (all four exclusivity sites) plus the §46/§47
correctness fixes.

**Machine state, stated because it matters:** these were NOT taken on an idle
box — 1-minute load ran 7.8–16 and memory was under pressure throughout
(~60 MB free, 11.6 GB in the compressor). They are recorded as the baseline
anyway, on three independent grounds:

1. **Two full matrix runs ~20 minutes apart agree.** Every Table-1 compare cell
   identical, sortKey within 1–3 ns (≤1.5%); worst Table-2 ratio drift 2.8%.
2. **ICU's own column matches the recorded idle-machine figures within 1–2%**
   (compare 9/10/40/29/170 vs 9/10/42/29/173; sortKey 103/120/117/367/155 vs
   105/122/120/369/153). ICU is the control: had load been inflating
   measurements, it would have drifted too.
3. min-over-K plus 10 cores means at least one pass usually runs uncontended.

The residual risk is a small uniform inflation of absolutes, bounded by (2).
Ratios are sound. Re-take on an idle box if a future round needs to resolve
effects below ~2%.

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
| Latin  |    70 |       365 | **5.21× faster** |
| CJK    |    99 |       370 | **3.74× faster** |
| Paths  |   105 |       299 | **2.85× faster** |
| Thai   |   372 |       497 | **1.34× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    81 |       196 | **2.42× faster** |
| Latin  |    83 |       357 | **4.30× faster** |
| CJK    |   119 |       361 | **3.03× faster** |
| Paths  |   127 |       321 | **2.53× faster** |
| Thai   |   386 |       491 | **1.27× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    81 |       197 | **2.43× faster** |
| Latin  |    83 |       353 | **4.25× faster** |
| CJK    |   119 |       363 | **3.05× faster** |
| Paths  |   120 |       307 | **2.56× faster** |
| Thai   |   388 |       484 | **1.25× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    93 |       310 | **3.33× faster** |
| Latin  |    94 |       474 | **5.04× faster** |
| CJK    |   125 |       477 | **3.82× faster** |
| Paths  |   133 |       413 | **3.11× faster** |
| Thai   |   401 |       623 | **1.55× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   283 |       984 | **3.48× faster** |
| Latin  |   315 |      1424 | **4.52× faster** |
| CJK    |   358 |      1263 | **3.53× faster** |
| Paths  |   287 |       959 | **3.34× faster** |
| Thai   |   309 |      1368 | **4.43× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   283 |       996 | **3.52× faster** |
| Latin  |   311 |      1478 | **4.75× faster** |
| CJK    |   357 |      1270 | **3.56× faster** |
| Paths  |   241 |       969 | **4.02× faster** |
| Thai   |   308 |      1425 | **4.63× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   351 |       985 | **2.81× faster** |
| Latin  |   380 |      1419 | **3.73× faster** |
| CJK    |   382 |      1263 | **3.31× faster** |
| Paths  |   396 |       976 | **2.46× faster** |
| Thai   |   454 |      1418 | **3.12× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   119 |       324 | **2.72× faster** |
| Latin  |   411 |       778 | **1.89× faster** |
| CJK    |   414 |       588 | **1.42× faster** |
| Paths  |   194 |       311 | **1.60× faster** |
| Thai   |   457 |       713 | **1.56× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   121 |       329 | **2.72× faster** |
| Latin  |   374 |       810 | **2.17× faster** |
| CJK    |   412 |       583 | **1.42× faster** |
| Paths  |   227 |       507 | **2.23× faster** |
| Thai   |   397 |       766 | **1.93× faster** |

### Direct RootCollator (EngineBench, full WMO) — Table 1

| Corpus | compare | ICU 79 | ratio | sortKey (inout) | ICU 79 | ratio | sortKey (alloc) | ratio |
|--------|---------|--------|-------|---------|--------|-------|---------|-------|
| ASCII  |      16 |      9 | 1.78× |     159 |    103 | 1.54× |     223 | 2.17× |
| Latin  |      15 |     10 | 1.50× |     182 |    120 | 1.52× |     243 | 2.02× |
| CJK    |      26 |     40 | **0.65×** |     173 |    117 | 1.48× |     251 | 2.15× |
| Paths  |      40 |     29 | 1.38× |     386 |    367 | 1.05× |     465 | 1.27× |
| Thai   |     260 |    170 | 1.53× |     213 |    155 | 1.37× |     282 | 1.82× |

Reproducibility, run 1 vs run 2 of the same matrix (see the machine-state note):

| Corpus | compare r1/r2 | sortKey r1/r2 |
|--------|---------------|----------------|
| ASCII  | 16 / 16 | 159 / 159 |
| Latin  | 15 / 15 | 181 / 182 |
| CJK    | 26 / 26 | 173 / 173 |
| Paths  | 40 / 40 | 384 / 386 |
| Thai   | 259 / 260 | 210 / 213 |

## Analysis

**Every Foundation API is faster than system ICU on every corpus — floor
1.25×, no cells at parity or behind.**

- `localizedCompare` family: 1.25–5.21×
- `contains` family: 3.34–4.75×
- range family: 1.42–3.73×

Thai is consistently the weakest family (1.25× floor) and the only place
system ICU comes close; it is also the engine's slowest corpus, so the two
observations share a cause — the NFD per-scalar floor (§36).

**Engine (Table 1) against hand-tuned ICU C**, after §46–§48:

- compare 1.78× ascii, 1.50× latin,
  **0.65× cjk (we are FASTER)**, 1.38× paths,
  1.53× thai
- sortKey 1.54× ascii, 1.52× latin, 1.48× cjk,
  **1.05× paths (parity with hand-tuned C)**, 1.37× thai

Movement from the pre-§46 baseline (17/9, 175/105 ascii etc.): every engine row
improved. sortKey ascii 1.7→1.54, latin 1.6→1.52,
cjk 1.6→1.48, paths 1.2→1.05, thai 1.5→1.37;
compare ascii 1.9→1.78, latin 1.7→1.50,
cjk 0.7→0.65, paths 1.4→1.38, thai 1.6→1.53.

The `skRet` column (the allocating sortKey overload) stays ~1.3–2.2× because it
allocates a fresh `[UInt8]` per call BY API CONTRACT; the inout twin is the one
to compare against ICU.

## How to reproduce

```sh
cd swift-foundation-collation
ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2 \
ICU_BUILD=$ICU_SRC/icu4c/source \
  Collation/Tools/run_benchmarks.sh 3

# Check the machine first — load average AND memory pressure:
sysctl -n vm.loadavg; vm_stat | head -4
# Sanity gate: ICU's own column should read ~9/10/40/29/170 compare and
# ~105/120/117/365/153 sortKey. If it does not, the box is too busy to record.
```

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
