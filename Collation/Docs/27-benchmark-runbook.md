# Benchmark Runbook — DO NOT GUESS, run the script

> If you are benchmarking collation on a cold start: **do not reconstruct the
> procedure or write a one-off harness.** Run the committed script. This file
> exists because that reconstruction kept happening and kept being wrong.

## The one command

From the repo root (the dir containing `Collation/`):

```sh
Collation/Tools/run_benchmarks.sh          # K=7 repeats per metric (a few minutes)
Collation/Tools/run_benchmarks.sh 3        # faster, K=3, for a quick read
```

It builds all three harnesses and prints two tables. That's the whole procedure.

## What it does (so you trust it, not re-derive it)

`run_benchmarks.sh` (machine-1/Intel defaults; override `ICU_SRC`/`ICU_BUILD`
env for machine 2):
1. Builds **`bench_icu`** (pure ICU C reference) via `clang` against the local
   ICU build.
2. Builds **`BenchFoundation`** release **with `-Xswiftc -no-whole-module-optimization`**.
   This flag is **mandatory on machine 1** — a normal release WMO executable
   SIGILLs at startup (the `_localeICUClass` `@_dynamicReplacement` miscompile;
   full root cause in `Docs/25`). Harmless on machine 2.
3. Builds **EngineBench** (`build_engine_bench.sh`): the engine sources
   copied into a scratch package and built FULL-WMO — no Locale, so machine
   1's WMO SIGILL never trips. Table 1 reads from it (the shipping
   optimization level); Table 2 keeps the -no-WMO BenchFoundation on
   machine 1.
4. Runs **`bench_matrix.py <BenchFoundation> K`**, which drives:
   - `bench_icu` — pure ICU `ucol_strcollUTF8` / `ucol_getSortKey`.
   - `BenchFoundation` (ours) — `RootCollator.cmp`/`.sk`/`.skRet` (pure
     engine; `.skRet` is the allocating sortKey) **and** the Foundation APIs
     (`compare(locale:)`, `localizedCompare`, `localizedStandardCompare`,
     `localizedCaseInsensitiveCompare`, `localizedStandardContains`,
     `localizedCaseInsensitiveContains`, `localizedStandardRange`,
     `range(of:options:locale:)`, `range(of:.backwards,locale:)`).
   - `bench_system` — the same Foundation APIs through system Foundation
     (NSString → ICU). Compiled once by the script (`swiftc -O` from
     `bench_system_foundation.swift`); the old per-run `swift -O` recompiles
     dominated wall time. Note: the compiled binary runs `range(of:locale:)`
     faster on the system side than script mode did, so that API's ratios
     shifted across the 2026-07-04 harness change (see `Docs/25`).
   - **min ns/op** over K interleaved runs; corpora with per-corpus reps
     (ASCII/Latin/CJK 300, paths 150, thai 10 — thai is ~33k lines, so it is
     the longest leg of the matrix by far).

## Reading the output

- **Table 1 (pure engine)**: `ratio = ours / ICU`. Pure Swift vs hand-tuned C —
  expect ~2.5–4× compare, ~1.7–2.5× sortKey. This is the floor, not a regression.
- **Table 2 (Foundation APIs)**: `ratio = ours / system-ICU`, so **<1 means ours
  is faster**. The compare family is ~0.3–0.8× (we beat system ICU by skipping
  the NSString→CF→ICU bridge it pays per call); `localizedStandardContains` is
  also <1 on most corpora after the scratch-iterator reuse.

## Prerequisites (one-time)

- A local ICU 79 build for `bench_icu`:
  - Machine 1: source `~/Projects/claude/icu`, build `~/Projects/claude/collation/icu-build`.
  - Machine 2: source+build under `~/Projects/Unicode/icu-DraganBesevic-2/icu4c/source`
    — run with `ICU_SRC=… ICU_BUILD=… Collation/Tools/run_benchmarks.sh`.
- Recorded results live in `Docs/25` (Intel) and `Docs/21` (Apple Silicon); update
  the doc for *your* machine, never paste cross-machine numbers into the other's.

## If you only want our numbers (skip ICU/system comparison)

`BenchFoundation` alone prints every metric for one corpus:
```sh
swift build -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation
"$(swift build -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation --show-bin-path)/BenchFoundation" \
  Collation/Tools/bench/bench-ascii.txt 200
```
(Always the `-no-WMO` flag on machine 1, or it SIGILLs.)

## Before you record anything: check the machine

Load average alone is misleading on this hardware. A box can read load 9 with
**52% of CPU idle**, because Darwin's load average counts threads blocked in
uninterruptible states — memory pressure inflates it while the cores sit free.
Check both:

```sh
sysctl -n vm.loadavg          # 1m / 5m / 15m
vm_stat | head -4             # Pages free; and see the compressor below
top -l 1 -n 0 | grep -E "CPU usage|PhysMem"
```

What actually degrades measurements, in order:

1. **Memory pressure** — the dangerous one. Free memory in the tens of MB with
   GBs "in compressor" means decompression stalls that land unpredictably on
   any measurement pass. Min-over-K mitigates but cannot remove it.
2. **CPU oversubscription** — steady and largely ridden out by min-over-K on a
   10-core box, up to ~load 10.
3. Disk activity — mostly irrelevant to these benchmarks after warm-up.

**The sanity gate — use the ICU column as a control.** ICU 79 is a fixed
binary, so its numbers should not move between sessions. On Apple Silicon
(macOS 26) expect roughly:

| corpus | ICU compare | ICU sortKey |
|---|---:|---:|
| ascii | 9 | 105 |
| latin | 10 | 120 |
| cjk | 40 | 117 |
| paths | 29 | 365 |
| thai | 170 | 153 |

If the ICU column matches those within ~2%, the run is trustworthy even at
nonzero load — that is the justification the 2026-08-12 baseline in `Docs/21`
rests on. If ICU has drifted, so has everything else: do not record the run.

And regardless of load: **run the matrix twice.** Two runs agreeing cell-for-cell
is worth more than one run on a quiet machine.
