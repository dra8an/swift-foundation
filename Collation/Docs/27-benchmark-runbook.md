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

- **Table 1 (pure engine)**: `ratio = ours / ICU`, so **below 1 means ours is
  faster**. The Swift implementation against hand-tuned C. Values as of
  2026-10-19: compare 0.53–1.61×, sortKey 1.06–1.52× (current numbers:
  `Docs/21`). Since 2026-10-15 both engine harnesses print one decimal; the
  old integer output was TRUNCATED (16.6 printed as 16, ICU's 9.5 as 9).
- **Table 2 (Foundation APIs)**: `speedup = system-ICU / ours`, so **above 1
  means ours is faster**. Most of that lead comes from skipping the system
  path's NSString → CoreFoundation → C++ bridge, not from the engine. Do not
  use Table 2 as evidence about engine quality; Table 1 is that evidence.

## What the harness itself costs (measured 2026-10-15)

EngineBench (Swift) and `bench_icu` (C) are different programs, so the loop
around each call is not the same. Probes with empty stubs instead of the
collator measured the difference (Apple Silicon, min of 3 runs × 9 passes):

| empty loop, ns per call | ascii | paths | thai |
|---|---:|---:|---:|
| C compare loop (`char *` arguments) | 1.0 | 0.9 | 0.9 |
| Swift compare loop (our API shape) | 2.0 | 2.0 | 2.0 |
| C sortKey loop (stack buffer) | 1.0 | 0.9 | 0.9 |
| Swift sortKey loop + the `[UInt8]` work | 9.7 | 12.7 | 14.0 |

**The extra ~1 ns per Swift call is the API's call shape, not the loop:**
about 0.5 ns for `throws` (the error check after each call), 0.4 ns for two
`String` arguments (two words each, against one for `char *`), and 0.2 ns
for the `options` argument. Every Swift caller pays it. Three loop shapes
(the current one, a local copy of the array, `withUnsafeBufferPointer`) all
cost 2.02 ns, and paths — 100% heap strings — costs the same as ascii, so
the loop does no reference counting. **Do not "optimize" the harness to
remove this cost: it would measure a call that no user makes.**

The sortKey array work (clear, fill, terminate) is also real: our
`sortKey(for:into:)` does it inside the call.

**Asymmetry that stays, by decision:** `bench_icu` converts each line to
UTF-16 BEFORE its timer, because `ucol_getSortKey` takes UTF-16 only (ICU's
compare takes UTF-8, so compare is symmetric). That conversion costs ICU
+14..+89 ns per key. It is NOT added to ICU's timed part: Table 1 compares
each engine on its own native input, and making the reference slower would
hide our gap rather than measure it.

Net effect on the gap: the harness explains about 1 ns of the ascii compare
gap — about 1 of 5.8 ns in the 2026-10-16 baseline (15.1 against 9.3); it was
1 of 7.4 ns before §50 (16.7 against 9.3). The rest is engine time.

Probe sources (not committed) lived in `.build/harness-probe/`; rebuild them
from this description if the question comes back.

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
pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -5   # the last wake
pmset -g therm                # thermal or performance limits, if any
```

**After a wake from sleep, wait at least 10 minutes, and until the 5-minute
load is also low** (measured 2026-10-15). After a wake, `dasd` runs the
background tasks that waited during sleep, and a new network adds more:
the load reached 724 one morning and 290 after a move between offices,
with no thermal limit in `pmset -g therm`. A run that started 2 minutes
after a wake, and one 6 minutes after, both read 1–3% slow on the
system-ICU control, while the 1-minute load already read 13–27. The
5-minute and 15-minute values show such bursts; the 1-minute value does
not. Also: a closed lid sleeps the machine and freezes a running benchmark;
keep it awake (`caffeinate -i <command>`) if you leave it.

Note on the controls: `bench_system` and BenchFoundation (Table 2) still
print whole nanoseconds by integer division, so they truncate. That is
harmless for the system-ICU control, because it truncates the same way in
every run. Do not compare the decimal Table-1 values of a new run with the
truncated Table-1 values recorded before 2026-10-15: they read up to 1 ns
lower for that reason alone.

What actually degrades measurements, in order:

1. **Memory pressure** — the dangerous one. Free memory in the tens of MB with
   GBs "in compressor" means decompression stalls that land unpredictably on
   any measurement pass. Min-over-K mitigates but cannot remove it.
2. **CPU oversubscription** — steady and largely ridden out by min-over-K on a
   10-core box, up to ~load 10.
3. Disk activity — mostly irrelevant to these benchmarks after warm-up.

**The sanity gate — use a column that did not change as the control.**

**Primary control (since 2026-10-15): the system ICU in Table 2.** It is part
of macOS, so it does not change unless the OS updates. On Apple Silicon
(macOS 26) `localizedCompare` should read about 194/365/369/300/494 for
ascii/latin/cjk/paths/thai. If it matches within ~2–3%, the load did not
distort the run.

**Second check: ICU C in Table 1.** This column links against the LOCAL ICU
checkout, so it is NOT a fixed binary: it changes when that checkout changes
branch or rebuilds. On 2026-10-15 the checkout held ICU 79.1 with Unicode 18
data (the CLDR 49 integration branch), and its speed matched the old 79.0.1
build. Check the branch first (`git -C $ICU_SRC branch --show-current`).
Then expect roughly (one decimal, 2026-10-16 17:29):

| corpus | ICU compare | ICU sortKey |
|---|---:|---:|
| ascii | 9.3 | 104.5 |
| latin | 10.1 | 120.9 |
| cjk | 40.5 | 119.0 |
| paths | 29.7 | 370.3 |
| thai | 173.8 | 155.5 |

If a control has drifted, so has everything else: do not record the run.

And regardless of load: **run the matrix twice.** Two runs agreeing cell-for-cell
is worth more than one run on a quiet machine.
