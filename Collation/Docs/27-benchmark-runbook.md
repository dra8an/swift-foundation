# Benchmark Runbook — DO NOT GUESS, run the script

> If you are benchmarking collation on a cold start: **do not reconstruct the
> procedure or write a one-off harness.** Run the committed script. This file
> exists because that reconstruction kept happening and kept being wrong.

## The one command

From the repo root (the dir containing `Collation/`):

```sh
/Users/dragan/Projects/dra8an/swift-foundation-collation/Collation/Tools/run_benchmarks.sh      # K=7 repeats per metric
/Users/dragan/Projects/dra8an/swift-foundation-collation/Collation/Tools/run_benchmarks.sh 3    # K=3, about 6–8 minutes
```

**Start it by its absolute path** (2026-10-21): under Apple Claude Code, a
shell command runs outside the process sandbox only if its text matches the
user's tool allowlist (`swift,contains_match` — the repo path contains
"swift"). Started by a relative path, the script runs sandboxed, and its
`swift build` fails with "Invalid manifest … sandbox-exec: sandbox_apply:
Operation not permitted" whenever SwiftPM must compile a manifest. On
machine 2 also set `ICU_SRC`/`ICU_BUILD` (below).

It builds all three harnesses and prints two tables (Table 2 has 14 API families since 2026-10-20: the nine String methods, an options compare, and four sort APIs whose ns/op is per sorted ELEMENT). That's the whole procedure.

**Since 2026-11-04 (technique log §51 (at)):**
- **The compiler** comes from `Collation/Tools/swift_toolchain.sh`: on Apple
  Silicon the compiler of the selected Xcode (`xcrun --find swift`; Swift 6.5
  with `Xcode2.app`), so that it matches the SDK; `SWIFT=<path>` overrides.
  The swiftly snapshot (6.4-dev) cannot use the macOS 27 SDK.
- **Table 2 has two Swift columns on Apple Silicon:** `-noWMO` (the column of
  the history; machine 1 has only this one) and `WMO` — release builds of
  swift-foundation compile WMO (`CMakeLists.txt`), so the WMO column is what
  release users get. Both are built with SwiftPM's native build system
  (`.build-matrix-nowmo`, `.build-matrix-wmo`): the default build system
  cannot build `-no-WMO` from an empty scratch path.
- **Every number before 2026-11-04 is from Swift 6.4-dev, the old SDK and
  macOS 26.4.** The first matrix pair after the move is a new start, and it
  sets the new system-ICU reference (see "Third check").

## What it does (so you trust it, not re-derive it)

`run_benchmarks.sh` (machine-1/Intel defaults; override `ICU_SRC`/`ICU_BUILD`
env for machine 2):
1. Builds **`bench_icu`** (pure ICU C reference) via `clang` against the local
   ICU build.
2. Builds **`BenchFoundation`** release **with `-Xswiftc -no-whole-module-optimization`**.
   This flag is **mandatory on machine 1** — a normal release WMO executable
   SIGILLs at startup (the `_localeICUClass` `@_dynamicReplacement` miscompile;
   full root cause in `Docs/25`). Harmless on machine 2 IN THE MAIN TREE,
   where the swift-syntax objects are already built: a FRESH release
   `-no-whole-module-optimization` build (an empty scratch path, a new
   worktree) fails in swift-syntax with "unable to open dependencies file"
   (2026-10-20). For A/Bs in a fresh scratch path, build both sides with
   normal WMO instead (HANDOFF START HERE, "How to measure").
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
     `range(of:options:locale:)`, `range(of:.backwards,locale:)`, and since
     2026-10-20 `compare(_:options:range:locale:)` with
     `[.caseInsensitive, .diacriticInsensitive]` and four sort APIs —
     `sorted(using:)` with `.localizedStandard`, `String.Comparator(locale:)`,
     `KeyPathComparator` and `SortDescriptor`, whose ns/op is per sorted
     ELEMENT, about 14 comparisons each: 14 API families in all).
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

- **Table 1 (pure engine)**: `speedup = ICU C / ours`, so **above 1 means
  ours is faster** — the same convention as Table 2 since 2026-10-29, when
  every compare and sortKey row reached ICU C (before, Table 1 showed the
  ratio `ours / ICU`, below 1 = faster; the history in the technique log
  and in older Docs/21 text uses that ratio). The Swift implementation
  against hand-tuned C. Values as of 2026-11-04 (median of 6 runs, Swift 6.5, macOS 27.2.1, after
  §51 (as)): compare 1.03–2.03× faster, sortKey 1.08–2.10× faster (current numbers:
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

## The rules since 2026-11-04 (the calibration, technique log §51 (au)) — read first

Six matrix runs of the same binaries on 2026-11-04 (Swift 6.5, macOS
27.2.1, the user's apps open, memory full, load 9–43) set these rules. They
replace the older load limits and the "two runs, record run B" rule below.

- **When to measure:** at least 10 minutes after a wake, and no burst (the
  1-minute load not far above the 5-minute one). No fixed load limit: ICU C
  stayed within 1.5% and the macOS column within 2.0% across all six runs.
- **The gates** (medians of the six runs; `Collation/Tools/matrix_record.py`
  checks them):

  | corpus | ICU C compare | ICU C sortKey | macOS `localizedCompare` |
  |---|---:|---:|---:|
  | ascii | 9.3 | 104.1 | 200 |
  | latin | 10.1 | 120.7 | 341 |
  | cjk | 40.7 | 119.3 | 354 |
  | paths | 29.5 | 365.2 | 314 |
  | thai | 172.0 | 153.7 | 502 |

  A set of runs counts if ICU C is within 2% and macOS within 2.5% of these.
  If only the macOS side drifts, run the frozen-binary check (below).
- **Recording:** run the matrix **at least 4 times** and record the
  **median** of each cell: `python3 Collation/Tools/matrix_record.py
  <run1.txt> … <run4.txt>` prints the Docs/21 tables and the checks. A cell
  whose runs differ by 5% or more is a **two-level cell**, marked ‡ with its
  range. On 2026-11-04 these were the short calls (15–56 ns) —
  `localizedCompare`, `localizedStandardCompare`, `compare(_:locale:)` on
  ascii, latin, paths — and paths compare in Table 1 (19.0–20.6 ns). They
  take one of two levels per run (program start), not a spread of values.
- **A/B decisions on two-level rows:** trust the instruction count and the
  aligned builds; a timing difference below their range is not a finding.

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
(macOS 27.2.1, the reference of 2026-11-04) `localizedCompare` should read
about 200/342/353/314/502 for ascii/latin/cjk/paths/thai (macOS 26.4, until
2026-11-03: 194/365/369/300/494). If it matches within ~2–3%, the load did
not distort the run.

**Second check: ICU C in Table 1.** This column links against the LOCAL ICU
checkout, so it is NOT a fixed binary: it changes when that checkout changes
branch or rebuilds. On 2026-10-15 the checkout held ICU 79.1 with Unicode 18
data (the CLDR 49 integration branch), and its speed matched the old 79.0.1
build. Check the branch first (`git -C $ICU_SRC branch --show-current`).
Then expect the gates of the table at the top ("The rules since
2026-11-04"); the older gates (2026-10-29, run B) were compare
9.3/10.1/40.8/30.0/172.8 and sortKey 104.4/121.0/117.7/373.3/155.5.

If a control has drifted, so has everything else: do not record the run.

**Third check (since 2026-11-02): a frozen binary of our own code.** On
2026-11-02 the system-ICU control read 1–14% slow with no load and the same
macOS build: macOS's own collation had changed, not the machine. ICU C read
its gates, and our BenchFoundation binary of 2026-10-30 (`22af5f68`,
`-no-WMO`; kept in `.build/l4/nowmo-base/`, with its bundle) read its
recorded numbers. So when the system-ICU control drifts, run the frozen
binary next to `bench_system` (three interleaved rounds of
`localizedCompare`, `compare(_:locale:)`, `localizedStandardCompare`;
Docs/21 has the expected values) — the script
`Collation/Tools/frozen_check.py Collation/Tools/bench_system 3` does it
(from the repo root, after a matrix run has built `bench_system`):
- frozen binary and ICU C on target, the system side off: macOS changed —
  record with the long-term reference for the speedups (Docs/21) and say so;
- everything slow: the machine is slow — do not record.
After a macOS update, set a new system-ICU reference from two quiet runs
that pass the other two checks (done 2026-11-04 for macOS 27.2.1: ICU C
within 2.2%, the frozen binary on its values, A and B within 1.0% on the
system side).

And regardless of load: **run the matrix at least four times and record the
medians** (since 2026-11-04; until then: twice, run B recorded). Several runs
agreeing cell for cell are worth more than one run on a quiet machine.
