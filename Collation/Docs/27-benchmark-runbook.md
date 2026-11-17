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
- **After a compiler or Xcode update**, run
  `Collation/Tools/check_stack_protection.sh`: it lists the engine
  functions that the compiler gives a stack protector (10 instructions per
  call in `compare` with Swift 6.5 before §51 (av)); expected: "none".
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
  against hand-tuned C. Values as of 2026-11-04 (median of 4 runs, Swift 6.5, macOS 27.2.1, after
  §51 (av)): compare 1.06–2.06× faster, sortKey 1.07–2.11× faster (current numbers:
  `Docs/21`). Since 2026-10-15 both engine harnesses print one decimal; the
  old integer output was TRUNCATED (16.6 printed as 16, ICU's 9.5 as 9).
- **Table 2 (Foundation APIs)**: `speedup = system-ICU / ours`, so **above 1
  means ours is faster**. Most of that lead comes from skipping the system
  path's NSString → CoreFoundation → C++ bridge, not from the engine. Do not
  use Table 2 as evidence about engine quality; Table 1 is that evidence.

## What the harness itself costs (measured 2026-11-13; technique log §52 (k))

EngineBench (Swift) and `bench_icu` (C) are different programs, so the loop
around each call is not the same. Measured with the same engine object and the
loop reduced in stages (edits of the assembly of the benchmark's `main`):

| compare, ns per call | ascii | latin | cjk |
|---|---:|---:|---:|
| Swift loop until 2026-11-13 (42 instructions around the call; 40 before `b30a9e66`) | 8.9 | 9.4 | 18.9 |
| Swift loop cut to the minimum (14 instructions) | 7.7 | 8.0 | 17.4 |
| C loop as it is (13 instructions, plus 3 in the library stub) | 9.3 | 10.1 | 40.6 |
| C loop with 3 instructions fewer (the sum in a register, no status reset) | 9.3 | 10.1 | 40.5 |

(The two Swift rows are one interleaved run; paths reads 20.0 → 18.6.) So the
old Swift loop cost 1.2–1.5 ns of each compare on ascii, latin and cjk
(1.4–1.6 on paths), and the C loop has nothing that can be removed with an
effect; its library stub stays, because a caller of ICU pays it. The staged
times below are from one run each, and each stage also moved the engine by 0,
64 or 128 bytes, so the split per part is less sure than the total. The parts
of the old loop (latin): the call of
`Order.rawValue` 0.3 ns (a `package` getter of another module, a call only in
the bench programs); the options word packed again from the global `opts` on
every pass 0.6 ns; the sum in the global `sink` 0.1 ns; the reload of the
global `lines` with two bounds checks 0.4 ns. **Since 2026-11-13 EngineBench's
timed loops use local copies and a local sum**; the compiler builds 10
instructions around the call, and the rows read the minimum (7.6 / 7.9 / 17.6).
What stays in the loop is what a caller pays: two `String` arguments, the
options as a ready value, the call, the error check of a throwing call.

**The method of 2026-10-15 was wrong, and so was its conclusion** ("the extra
~1 ns per Swift call is the API's call shape, not the loop … do not optimize
the harness"). It timed each loop with an empty function in place of the
collator (C 1.0, Swift 2.0 ns then; C 2.4, Swift 2.2 ns with the empty
functions of 2026-11-13). Those numbers do not predict what a loop adds to a
real compare: the measured cost above is 1.2–1.5 ns for Swift and nothing for
C. Why an empty loop misleads is NOT established (a first explanation, "the
sum in memory limits both loops", is wrong: the C probe of 2026-10-15 had the
same sum and read 1.0 ns; technique log §52 (n)). To measure a loop's cost,
keep the call and change the loop.

**Rule for a change of a bench loop:** keep every value that the loop reads in
a local, never add a call or a branch on the result, and run the loop check
(below) before and after.

The sortKey array work (clear, fill, terminate) is real: our
`sortKey(for:into:)` does it inside the call.

**Asymmetry that stays, by decision:** `bench_icu` converts each line to
UTF-16 BEFORE its timer, because `ucol_getSortKey` takes UTF-16 only (ICU's
compare takes UTF-8, so compare is symmetric). That conversion costs ICU
+14..+89 ns per key. It is NOT added to ICU's timed part: Table 1 compares
each engine on its own native input, and making the reference slower would
hide our gap rather than measure it.

## The loop check (since 2026-11-13; technique log §52 (k))

A compare of 8 ns is about 150 instructions. Two instructions more in the
benchmark's loop show as 1–3%, and they are not engine time: the step of latin
compare from 9.1 to 9.4 between 2026-11-06 and 2026-11-12 was one call that a
visibility change (`public` to `package`) put into the loop. The counts of
`count_compare.sh` start at the entry of `compare` and do not see the loop.

```sh
Collation/Tools/insn-count/loop_check.sh <EngineBench binary>      # about 5 minutes, times nothing; ascii, latin, cjk
Collation/Tools/insn-count/loop_check.sh <EngineBench binary> paths # another corpus (not thai: too long for a recording)
```

It records whole passes under lldb and prints, for ascii, latin and cjk: the
instructions per pass inside `compare` (the engine) and outside it (the loop),
the taken branches, and two position rules. It compares with
`Collation/Tools/insn-count/loop_check.ref` and ends with an error when the
loop count changed or a rule applies. `--write-ref` after the binary's name
replaces the reference (do that only with a recorded baseline).

- **"LOOP CHANGED":** the benchmark, not the engine, differs from the
  reference build. Do not compare the compare rows of the two builds; find
  the cause in `main` first (`pc_trace.py` writes the executed addresses).
- **Rule 1 applies:** a 4 KB address boundary cuts a hot run of code THAT
  ENDS IN A RETURN so that it needs one more piece (the processor takes in
  code in pieces of at most 16 instructions; a taken branch and a 4 KB
  boundary end a piece). Seen cost: 0.5–0.7 ns on latin (one run: the exit of
  `compareUTF8`). A cut run that ends in another instruction is printed as a
  **note** and is not an error: one such case (a run that ends in a call) was
  measured without a loss (technique log §52 (n)).
- **Rule 2 applies:** two hot pieces of code that end in a return start a
  multiple of 2 KB apart. Seen cost: 0.4 ns on latin (one pair in one real
  build; the period of 2 KB is from the micro test).
- The rules tell which positions are suspect, not how much they cost: the
  same case cost 0.5–0.7 ns in one build and at most 0.2 ns in another.
- With rule 1 or 2, the binary's latin / ascii / cjk compare rows are slower
  than the same code at another position. Do not record a baseline from that
  binary, and do not "fix" it with padding in the benchmark: say so in the
  record, and measure the next build. The micro tests of both rules:
  `Collation/Tools/layout-micro/run.sh`.

Run it once for each new EngineBench binary of a matrix series (the four runs
of a series use one binary), and for both binaries of an engine A/B whose
latin, ascii or cjk compare rows differ by less than 5%.

## Prerequisites (one-time)

- A local ICU build for `bench_icu` (ICU 80.0.1 since 2026-11-16; the gates below belong to that version):
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
- **The gates** (since 2026-11-17 the medians of the six runs of the baseline
  series, see below; `Collation/Tools/matrix_record.py` checks them):

  | corpus | ICU C compare | ICU C sortKey | macOS `localizedCompare` |
  |---|---:|---:|---:|
  | ascii | 9.3 | 100.9 | 201.3 |
  | latin | 10.1 | 117.0 | 347.2 |
  | cjk | 40.8 | 115.7 | 355.2 |
  | paths | 30.0 | 349.6 | 313.6 |
  | thai | 171.9 | 151.2 | 505.0 |

  **The ICU C gates are for ICU 80.0.1 (since 2026-11-17, technique log
  §52 (m)).** The local ICU checkout was rebuilt on 2026-11-16; `bench_icu`
  links whatever version the checkout has. The gates until then (ICU 79.1,
  2026-11-04): compare 9.3 / 10.1 / 40.7 / 29.5 / 172.0, sortKey 104.1 /
  120.7 / 119.3 / 365.2 / 153.7. **When the ICU version changes** (check
  `otool -L Collation/Tools/bench_icu` and `uvernum.h` before a series): the
  ICU gates no longer apply; judge the machine with the macOS check and the
  frozen binary, take the medians of at least 4 runs that pass both as the
  new gates, and write the old ones here. **The macOS gates are also of
  2026-11-17** (the same six runs; the frozen binary within 1 ns and the
  unchanged EngineBench on its values showed a machine at its speed). Until
  then (2026-11-04): 200 / 341 / 354 / 314 / 502 — latin read 347–350 in
  every series since 2026-11-05, close to the 2.5% limit with a healthy
  machine. The frozen binary of 2026-10-30 and its expected values (Docs/21)
  stay as they are: it is the one check that no update of a reference can
  move.

  A set of runs counts if ICU C is within 2% and macOS within 2.5% of these.
  If only the macOS side drifts, run the frozen-binary check (below).
- **Table 2 prints one decimal (since 2026-11-13, technique log §52 (l)):**
  BenchFoundation and `bench_system_foundation.swift` print rounded tenths;
  before that, whole nanoseconds, cut off — a cell on the edge of a whole
  number then looked like a two-level cell (`localizedCompare` latin "12–13"
  is 13.0). The macOS gates have one decimal since 2026-11-17.
- **The loop check (since 2026-11-13):** before a series is recorded, run
  `Collation/Tools/insn-count/loop_check.sh` on its EngineBench binary (the
  section "The loop check" above). A series whose binary reports a changed
  loop or a position rule is not a baseline.
- **Recording:** run the matrix **at least 4 times** and record the
  **median** of each cell: `python3 Collation/Tools/matrix_record.py
  <run1.txt> … <run4.txt>` prints the Docs/21 tables and the checks. A cell
  whose runs differ by 5% or more is a **two-level cell**, marked ‡ with its
  range. On 2026-11-04 these were the short calls (15–56 ns) —
  `localizedCompare`, `localizedStandardCompare`, `compare(_:locale:)` on
  ascii, latin, paths — and paths compare in Table 1 (19.0–20.6 ns). They
  take one of two levels per run (program start), not a spread of values.
  **Paths compare, checked again 2026-11-17:** no two levels with the engine
  of the baseline. Forty program starts each, compare on paths: the bench
  loop with local values 18.0–18.4 (one start 18.7), the loop of before
  2026-11-13 19.8–20.2 (three starts 20.5–20.9) — one group each. The two
  levels of 2026-11-04 belong to the engine and bench of that date; their
  cause was not found, and the binary no longer exists.
- **The cause of the Table 2 levels, and the warm-up (since 2026-11-05,
  technique log §51 (aw)):** after the first use of a Swift `static let`,
  `dispatch_once` keeps its guard out of the fast path for ~16–28 ms, and
  each Foundation call reads two such globals (~+6 ns per call in that
  window). The first wrapper rows of a run fell into the window, and its end
  moved from start to start. Both Foundation benches (BenchFoundation and
  `bench_system_foundation.swift`) now run every API once and the short
  compares for 100 ms before the first measured row; with it the short rows
  read one level (`localizedCompare` ascii WMO 12–12 ns over 15 starts,
  before 16–19), and the macOS side did not change. Keep the same warm-up
  in both programs. EngineBench and `bench_icu` have none: the engine rows
  read no such global per call, and the paths compare levels of 2026-11-04
  had another cause (not known; they do not show any more, see above).
- **A/B decisions on two-level rows:** trust the instruction count and the
  aligned builds; a timing difference below their range is not a finding.

## Before you record anything: check the machine

**First: the power source.** `pmset -g ps` must say "AC Power". On 2026-11-13
a series was not started because the machine was on battery and `bench_icu`
read ascii 9.5–9.9 against its gate of 9.3. Then run `bench_icu` on ascii,
latin and thai five times each (one minute): the best of five must be at the
gate before a series of 25–35 minutes starts. The unchanged EngineBench
binary is a second thermometer, and it does not depend on the ICU version:
it must read its recorded Table 1 values.

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

Note on the controls: until 2026-11-13 `bench_system` and BenchFoundation
(Table 2) printed whole nanoseconds by integer division, cut off; since then
they print one rounded decimal (technique log §52 (l)). Do not compare the
decimal Table-1 values of a new run with the truncated Table-1 values
recorded before 2026-10-15: they read up to 1 ns lower for that reason alone.

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
(macOS 27.2.1, the reference of 2026-11-17) `localizedCompare` should read
about 201.3/347.2/355.2/313.6/505.0 for ascii/latin/cjk/paths/thai (the
reference of 2026-11-04 was 200/341/354/314/502; macOS 26.4, until
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
