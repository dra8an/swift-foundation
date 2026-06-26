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
3. Runs **`bench_matrix.py <BenchFoundation> K`**, which drives:
   - `bench_icu` — pure ICU `ucol_strcollUTF8` / `ucol_getSortKey`.
   - `BenchFoundation` (ours) — `RootCollator.cmp`/`.sk` (pure engine) **and** the
     Foundation APIs (`compare(locale:)`, `localizedCompare`,
     `localizedStandardCompare`, `localizedStandardContains`,
     `localizedStandardRange`, `range(of:options:locale:)`).
   - `bench_system_foundation.swift` (`swift -O`) — the same Foundation APIs
     through system Foundation (NSString → ICU).
   - **min ns/op** over K interleaved runs; corpora with per-corpus reps
     (ASCII/Latin/CJK 300, paths 150, thai 3 — thai is ~33k lines).

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
