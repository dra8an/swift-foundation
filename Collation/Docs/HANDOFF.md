# HANDOFF — Cold-Start Guide for the Collation Project

## START HERE (current as of 2026-11-04 — everything below this section is history)

**If anything in the history below contradicts this section, this section
wins.** The history has stale rules and numbers on purpose; it is the record.
The history and the technique log up to §51 (ah) show Table 1 as the RATIO
ours / ICU (below 1 = faster); since 2026-10-29 this section and Docs/21 show
the SPEEDUP ICU / ours (above 1 = ours faster), like Table 2.

**What this is.** A Swift implementation of the Unicode Collation Algorithm
(ICU4C collation v2 design, ICU4X model) inside swift-foundation:
`Sources/FoundationInternationalization/Collation/`. Repo
`~/Projects/dra8an/swift-foundation-collation`, branch `port/collation`,
remote `origin` = `git@github-personal:dra8an/swift-foundation.git` (an SSH
alias to ssh.github.com:443 — see "Network" below; never push `upstream`,
which this repo does not even have). The tools and docs live under
`Collation/`.

**Toolchain since 2026-11-04 — read first (§51 (at)).** After the macOS
27.2.1 update the selected Xcode is `/Applications/Xcode2.app`; its SDK needs
**Swift 6.5**, and the swiftly snapshot (`swift` on `PATH`, 6.4-dev) can no
longer build anything ("this SDK is not supported by the compiler"). User
decision: move to Swift 6.5 — the compiler of the selected Xcode. The tool
scripts get it from `Collation/Tools/swift_toolchain.sh` (`SWIFT`,
`SWIFTC`, `LLDB` via `xcrun`). **For your own commands use
`X=$(xcrun --find swift)` and `$X build …`, or put `${X:h}` first in
`PATH`** (the worktree's scripts are older than the helper until it is at
a commit that has it). BenchFoundation builds for A/Bs and the matrix use
SwiftPM's **native build system** (`--build-system native`; the default
one cannot build `-no-WMO` from an empty scratch path, with either
compiler). Every older number in this file and in Docs/21 is from Swift
6.4-dev and the old SDK: the next matrix pair is a new start (and the new
macOS reference). Do not compare across the change.

**State at the time of writing (VERIFY WITH GIT — do not trust this
paragraph).** Expected: HEAD = the docs commit of the matrix after §51 (av) (Docs/21,
this file, the technique log, Docs/27) on top of the commit of §51 (av) (`RootCollator.swift`:
`untraced(_:)` in `compareFastPath`, no stack protector with Swift 6.5; the
new `Collation/Tools/check_stack_protection.sh`; the technique log and this
file) on top of the commit of §51 (au) (the calibration, `matrix_record.py`,
Docs/21 from six medians) and `0f077c86` (pushed 2026-11-04);
`origin/port/collation` at `0f077c86` unless the user pushed since. If a
commit is missing, its files are modified or new — say so and give the add /
commit lines (the memory files are outside the repo). Tree clean otherwise.
The A/B worktree `../collation-baseline` is detached at `f64250b6` (the same
engine code as `0f077c86`) with its own, unmodified `main.swift`; its builds
there, all with Swift 6.5: EngineBench `.build/engine-bench/.build`,
`.build-al`, `.build-g`; BenchFoundation (native build system) WMO `-g`
`.build-ab-wmo`, `-no-WMO -g` `.build-ab-nowmo`, aligned `.build-ab-wmo-al`
and `.build-ab-nowmo-al` — **the four BenchFoundation builds WITH the
temporary probe rows of §51 (av) (the aligned WMO one also with its CPU
Counters loop): rebuild before a Foundation A/B** (binaries in
`<scratch>/arm64-apple-macosx/release/`). The main tree has the same set.
**For the next A/B the base is HEAD:**
`git -C ../collation-baseline checkout --detach <HEAD>`, then rebuild there
(each incremental, ~1 minute):
```
W=/Users/dragan/Projects/dra8an/collation-baseline
cd $W && $W/Collation/Tools/build_engine_bench.sh            # plain EngineBench
cd $W/.build/engine-bench && swift build -c release -Xswiftc -Xllvm -Xswiftc -align-all-functions=6 --scratch-path .build-al
cd $W/.build/engine-bench && swift build -c release -Xswiftc -g --scratch-path .build-g
cd $W && swift build -c release -Xswiftc -g --product BenchFoundation --scratch-path .build-bfg
```
R=/Users/dragan/Projects/dra8an/swift-foundation-collation; W=/Users/dragan/Projects/dra8an/collation-baseline
X=$(xcrun --find swift); export PATH=${X:h}:$PATH         # Swift 6.5 (§51 (at))
cd $W && $W/Collation/Tools/build_engine_bench.sh            # plain EngineBench
cd $W/.build/engine-bench && swift build -c release -Xswiftc -Xllvm -Xswiftc -align-all-functions=6 --scratch-path .build-al
cd $W/.build/engine-bench && swift build -c release -Xswiftc -g --scratch-path .build-g
cd $W && swift build --build-system native -c release -Xswiftc -g --product BenchFoundation --scratch-path .build-ab-wmo
cd $W && swift build --build-system native -c release -Xswiftc -no-whole-module-optimization -Xswiftc -g --product BenchFoundation --scratch-path .build-ab-nowmo
```
(the same EngineBench forms in the main tree under `.build/engine-bench/`;
never build `-g` into the default scratch path — that replaces the plain
binary the A/B uses). **The worktree path has no "swift" in it** (see the
absolute-path rule below): a command whose text names only the worktree runs
in the ACC sandbox, and a `swift build` in it fails as soon as SwiftPM must
compile a manifest; it works while the manifest is cached. Start such
commands with `R=/Users/dragan/Projects/dra8an/swift-foundation-collation;`
so that the text contains "swift". If it fails with "Invalid manifest …
sandbox_apply", say so and ask the user (an allowlist entry is the user's
decision, never yours). **Keep `.build/l4/nowmo-base/`:** it holds the
FROZEN BINARY of 2026-10-30 (BenchFoundation `-no-WMO -g` at `22af5f68`,
with its bundle), the third matrix check of Docs/27 (a binary: it runs
unchanged after the compiler move). Main tree helpers in
`.build/` (git-ignored): `.build/l9/` (§51 (at): the Swift 6.5 tests,
`build_ab_tree.sh` = all A/B builds of one tree, the A-against-A outputs),
`.build/l8/` (§51 (ar): the same tools as
`.build/l7/`, the probe rows plus `tmpLocaleCmp`, the base and variant
binaries), `.build/l7/` (§51 (aq): `probe-opts.swift` = the
8 temporary probe rows, `count_groups.sh` = the instruction count of every
group for one binary, 6 lldb jobs in parallel, `cmp_groups.py` = the counts
side by side, `foundation_ab_aq.py` / `foundation_ab_check.py` = A/B copies
with all five corpora / the ascii-latin layout check, the base and variant
binaries with their bundles), `.build/l6/` (§51 (ap): `probe-modes.swift` = the 17
engine mode probe rows, `foundation_ab_q1.py`, the Q1–Q1h copies and
traces), `.build/l5/` (§51 (ao): `probe-stdcmpr.swift`, `probe-locstd.swift`),
`.build/l4/` (§51 (an)), `.build/l3/`, `.build/l2/` (§51 (aj)–(am):
`foundation_ab_*.py` with longer row lists, `probe-opt.swift`,
`probe-range.swift`), `.build/item3/probe-loc.swift` (the `tmp str locCmp`
row), `.build/counters/` (`shares.py`, CPU Counters), `.build/matrix/`
(`parse.py`, every matrix output).

**What is routine and needs no question:** builds and A/Bs of up to about 10
minutes (in TOTAL per series — see "Make a break"); the full test suite
(`swift test`, about 1–2 minutes; the Thread Sanitizer run of the
concurrency tests about 5 minutes the first time); moving the worktree and
rebuilding there; temporary probe rows in
`Collation/Sources/BenchFoundation/main.swift` — in BOTH trees when an A/B
needs them (keep a copy of the original in `.build/`, restore it after,
restore the worktree's copy before its next checkout, never commit them;
row names may contain only letters, spaces and `().:_`, no digits, or the
A/B parser skips them); CPU Counters recordings; `git fetch`. Ask before
anything longer or with wider effect. Suite gate: **1570 tests in 138
suites** — `swift test` prints three summary lines (45/5, 584/93, 941/40; since §51 (as));
add them up.

**Read next, in this order:**
1. Your memory index from disk and ALL its feedback files — the user's
   working rules; then `project-next-steps-2026-11-02` (this round's
   decisions, including one accepted exception to the ascii / latin rule).
2. `Collation/Docs/optimization-targets.md` **§51 (ai)–(aq)** — the technique
   log of the 2026-10-29…11-02 work (every change, every rejected variant,
   every measurement), all of it; the matrix line after (ap) is the last
   recorded matrix ((aq) came after it). For background: §51 (z)–(ah), §51 (l), (y), §50 (g) (the
   instruction-count method) and the ALLOCATION/RESOLUTION HUNT note at the
   top of the file.
3. `Collation/Docs/21-foundation-api-benchmark.md` — the last RECORDED
   matrix (2026-11-04, the median of 6 runs, Swift 6.5, macOS 27.2.1; WMO
   the main column; two-level cells marked ‡).
4. `Collation/Docs/27-benchmark-runbook.md` — **"The rules since
   2026-11-04" at its top**, then how to measure, the harness
   cost, the gates, the speedup convention, and **the third check (the
   frozen binary)**.
5. `Collation/Docs/30-icu4j-fastlatin-signed-pair-bug.md` — a side note (an
   ICU4J bug we do NOT have; do not make our fast-Latin `pair` type signed).

**Current numbers — RECORDED in Docs/21 on 2026-11-04, 15:20–15:38 (the
MEDIAN of 4 runs at `c275fd45`, after §51 (av); Swift 6.5, macOS 27.2.1;
load 13 → 4; ICU C within 0.4%, macOS within 0.5%, the frozen binary on
target). Table 1, EngineBench vs ICU C, ns per call ours / ICU, speedup =
ICU / ours:**

| corpus | compare | speedup | sortKey | speedup |
|---|---|---|---|---|
| ascii | 8.8 / 9.3 | 1.06× faster | 72.5 / 104.0 | 1.43× faster |
| latin | 9.1 / 10.1 | 1.11× faster | 92.6 / 120.6 | 1.30× faster |
| cjk | 19.7 / 40.5 | 2.06× faster | 103.0 / 119.2 | 1.16× faster |
| paths | 19.9 (two-level) / 29.5 | 1.48× faster | 173.8 / 365.9 | 2.11× faster |
| thai | 162.1 / 171.6 | 1.06× faster | 143.6 / 153.4 | 1.07× faster |

**All ten rows are faster than ICU C.** The allocating sortKey (`skRet`) is
0.78–0.85× of ICU (1.65× faster on paths). **Table 2** has two Swift
columns: **WMO, the main one** (user decision, 2026-11-04; release builds
are WMO) and `-no-WMO`; floor 2.88× (WMO, `localizedCaseInsensitiveCompare`
thai) and 1.95× (`-no-WMO`, `range(of:locale:)` cjk); nine short cells are
two-level (‡ in Docs/21). **The macOS reference** (macOS 27.2.1):
`localizedCompare` 200/341/354/314/502. Table 2 is mostly the skipped
NSString → CoreFoundation → C++ bridge. **Never use Table 2 as evidence
about the engine; never cite it as consolation for a Table 1 gap.**

**The measurement rules since 2026-11-04 (user decision; Docs/27 "The rules
since 2026-11-04"):** measure at least 10 minutes after a wake and outside
a burst, at any load (the user's apps, Chrome among them, stay open: "we
will have to live with this state"); the checks decide — ICU C within 2% of
9.3/10.1/40.7/29.5/172.0 compare and 104.1/120.7/119.3/365.2/153.7
sortKey, macOS within 2.5% of 200/341/354/314/502; record the **median of
at least 4 runs** with `Collation/Tools/matrix_record.py`; two-level cells
(runs 5% or more apart) get ‡ and their range; for A/B decisions on
two-level rows trust counts and aligned builds.

**What this round did (2026-10-29…11-02; details in §51 (ai)–(av)):**
- (ai) Latin compare's last mispredictions: the lead-byte ASCII test of
  `compareUTF8`, from the data (ICU C has twice as many); a branch-free
  decode gave latin −4.5% but ascii +4.5%: REJECTED.
- **The Foundation wrapper, ~360 → ~117 instructions around the engine**
  (one `localizedCompare` 516 → 265, the engine 148): (aj) lock-free reads
  of the `CollatorCache` slots (published immutable slots; one interned slot
  per explicit identifier); (ak) the cached collator used in place through
  non-generic pointer entries in `RootCollator.swift`, and the internal
  `compareWithDefaultOptions`; (al) the `-no-WMO` search "losses" of (ak)
  were placement; (am) a fast path for two `String` arguments in the eight
  generic wrappers and an inlined cache read; (an) `@_specialize(where Self
  == String, T == String)` on the eight wrappers (user decision: accepted;
  no public symbol; FoundationEssentials precedent).
- (ao) Identical strength (`.localizedStandard`) takes the bytes path when
  the tertiary pre-pass does not decide: its comparator on cjk −51..−58%,
  thai −20%; its sorts on cjk −16..−32%.
- (ap) **The sibling check** (one engine call per option mode next to its
  secondary-strength sibling) found the quick CJK compare gated off for every
  collator with reordering or a shifted default: Q1g shipped — zh cjk −69%,
  ja / th −56..−60% in both modes. **Accepted cost (user decision):** +8
  instructions on the `-no-WMO` default entry for ascii / latin (register
  allocation; WMO clean).
- Matrices recorded 2026-10-30 and 2026-11-02. **The macOS anomaly of
  2026-11-02** (the system side 1–14% slow, same build; ICU C and the frozen
  binary on target): Table 2 now uses the long-term macOS reference (user
  decision), and Docs/27 has the frozen-binary check.
- (aq) **The options compares on CJK and Thai** (START HERE items 1 and 2 of
  2026-11-02): a bail of the options pass at the end of a shared prefix
  returns a marker with the mismatch in its result, and `compareSlowPath`
  calls `compareAfterOptionsPass` directly — no second prefix scan, no
  `compareBody` hop. WMO: `localizedStandardCompare` cjk −7.3%, thai −2.8%;
  the options rows cjk −4.6..−5.2%, thai −2.8..−5.2%; ascii / latin 0..−4%.
  Thai options now +5.9% in instructions over the default path (was +13%);
  CJK options 534 against 333 (was 579). Accepted after a layout check
  (user decision, 2026-11-02). No matrix run since.
- (ar) **The fast-Latin setup for the Foundation option sets, resolved at
  init:** the default key and its numeric twin are read from the storage;
  only other option sets use the shared cache. Every options compare −35..−56
  instructions (WMO), −19..−32 (`-no-WMO`), ascii / latin included. WMO
  A/B: `localizedStandardCompare` ascii / latin −7.4 / −12.5%,
  `localizedCaseInsensitiveCompare` −7.0 / −5.8%, the options compare −8.0
  / −7.1%; `-no-WMO` −2..−4%. New `Storage` fields go at the END (in the
  middle they cost `compare(_:locale:)` +6.8% in `-no-WMO`); the plain-WMO
  `compare(_:locale:)` +5..+7% that stayed is placement (aligned builds:
  0.0%). User decision, 2026-11-03: accepted ("great wins").
- (av) **No stack protector in `compare` with Swift 6.5** (the cjk loss of
  the compiler move): the pinned bytes go through `RootCollator.untraced(_:)`
  (an integer round trip of the base address, no machine instruction), so
  the optimizer no longer traces our indexing to the stack copy of a small
  string, and `compare` loses the guard value (10 instructions per call).
  EngineBench compare aligned: ascii −4.5%, latin −5.6%, cjk −2.0%; every
  Foundation group −7..−14 instructions in both modes; the remaining "+"
  cells move with the layout (CPU Counters: front end only). User decision,
  2026-11-04: accepted. Check after every compiler update:
  `Collation/Tools/check_stack_protection.sh` (expected "none").
- (as) **The compare paths in `-no-WMO`:** enum compares by case match
  (`hasIdenticalStrength`, `isShifted`) and same-file copies of three
  constants and of `primariesKey` (`SameFileCopiesTests` checks them). In
  `-no-WMO` each file compiles alone, and every value from another file was
  a call (also with `@inlinable` / `@_transparent` — tested). `-no-WMO`:
  options compares ascii / latin −16..−26%, `localizedCompare` −9%,
  `compare(_:locale:)` −8%; WMO: no change (byte-identical code but for 1–2
  Thai instructions). **Release builds are WMO** (`CMakeLists.txt`), so this
  removes a handicap of the `-no-WMO` Table 2, not a cost that release users
  had. User decision, 2026-11-03: accepted, and plan a WMO column for
  Table 2 (NEXT TASK 1).

**NEXT TASK — not chosen yet. Ask the user.** Present these candidates in
this order, with the evidence, and let the user choose. **Present each in
plain words — what it changes and what it gives — never as variant labels
("V2 vs V1c"; memory `feedback-no-variant-labels`).**
1. **Why short rows are two-level** (§51 (au): the same binary reads
   `localizedCompare` ascii WMO 18, 15, 15, 15, 18, 17 in six runs; paths
   compare 19.0–20.6). Measurement only: per program start (ASLR, the
   memory layout of the process)? The recording rule (median of 4+ runs)
   already copes with it; knowing the cause could make A/Bs on these rows
   cheaper.
2. **The `-no-WMO` costs left** (§51 (as), "Still open"): constants of
   `CollationConstants` in the CE compare loop of `CollationCompare.swift`
   (~7 per Thai compare), the strength compares in `sortKey`, the
   `icuOptions` getter. `-no-WMO` only — since the WMO column is the main
   one in Docs/21, they matter less.
3. **The rest of the options cost on CJK and Thai** (§51 (aq), (ar)): root
   options on CJK 478 against 333 instructions (WMO, 1.43×), on Thai +3.1%.
   Left: the options word (~30) and a first pinning whose pass always bails
   on CJK. A first-byte test before the pass would skip them for CJK /
   Thai but cost every ascii / latin options compare (not tried; the user's
   rule).
4. **ko's hanja are expansions** (7 476): Korean Han text still takes the
   pipeline; the quick path could use an expansion's first CE.
5. cjk compare +3.8% since P3c (Table 1 cjk 19.0 ns, 2.15× faster than ICU;
   CJK pairs often share the first UTF-8 byte and take the helper path).
6. CE production for precomposed Latin letters (NFD decomposition, ~119
   instructions per accented letter); the run-time writer path for
   non-default options; L1 (the Thai lookahead; skipped by the user before as
   too small).
7. Creation: the bundle open (~0.9 ms) and the data read and parse (~0.75
   ms; mapping the file is the candidate; §51 (q)).
8. Measurement only: why HEAD (z) was 1–3 ns faster on the ascii / latin
   options rows in WMO (§51 (ac)).
**The macOS update happened (2026-11-04, macOS 27.2.1, 26B125):** (a) the
new system-ICU reference was set on 2026-11-04 (Docs/21); (b) the Chrome reminder
(start once without `--disable-features=AperitifHelpers`) was given on
2026-11-04.
Not an option (user decisions): public API changes — a non-throwing
`compare`, Substring or UTF-8-buffer entries (2026-10-27); FoundationEssentials
changes (the remaining wrapper cost, `LocaleNotifications.count()`'s lock,
~40 instructions in the non-framework build, is FoundationEssentials).

**Hard rules from the user (also in memory):**
- **Commit and push only when the user says so, in that message. The user
  runs every git write command.** A global hook,
  `~/.claude/hooks/block-git-write.sh`, blocks git writes for you — and it
  matches the TEXT of a shell command, so a command that only contains those
  words (a grep, an echo, a heredoc, a Python script) is blocked too; write
  docs that mention them with the Write/Edit tools. Give each commit as two
  lines: the add with the exact files, and the commit with a ONE-LINE `-m`
  message starting "Collation: ", with no backticks or `$`. No long messages,
  no message files, no heredocs. Before a push, verify for the user: the
  commits in `origin/port/collation..HEAD`, the attribution grep
  (`claude|co-authored|anthropic` must count 0), author/committer
  `dra8an <chonbey@hotmail.com>`, and that the remote tip is an ancestor of
  HEAD (fetch first). The user pushes with the `!` prefix.
- **Ask before anything long-running, hard to stop, or with wide effect.**
  Stop at once when the user says stop. Never suggest stopping work.
- **Never sit in a polling loop** (for example `sleep` until the load drops).
  Check the load ONCE; if acceptable, run — the system-ICU control decides
  whether a matrix run is valid, and interleaved A/Bs are valid for direction
  under load. Guideline (since 2026-11-04, §51 (au)): for an A/B, run at
  any load and give the load in one line (direction is what it measures).
  For a matrix: at least 10 minutes after a wake and outside a burst (the
  1-minute load far above the 5-minute one), at ANY load — the checks
  decide (ICU C within 2%, macOS within 2.5% of the gates). During a burst,
  say so in one line, do load-independent work and re-check ONCE. Do not
  ask the user to close apps (2026-11-04: "I am not planning to close
  ANYTHING"). Run unavoidable waits in the background.
- **Make a break in long work.** After about 30–45 minutes of builds, A/Bs
  or matrix runs — or at each decision point (a variant regresses, a second
  matrix pair is needed, a new hypothesis) — stop, report in a few lines,
  give the commit lines for what is ready, and ask. The ~10-minute "routine"
  limit covers the TOTAL of a series, not each job (a 2 h 14 min chain on
  2026-10-21 drew "2 hours and 14 minutes ???????"). For the current focus
  the user said: "stop after each one to report what you found". Explain
  the state and the options plainly: what was measured, the numbers in a
  table, what each option costs (2026-10-26: "You didnt explain well where
  are we and the options. Very unclear").
- **Work solo** (no Workflow tool, no multi-agent fan-out) unless the user
  asks for it (the `/handoff` skill in `~/.claude/skills/handoff/` asks for
  one quiz agent).
- **No ascii / latin loss, in either build mode** (memory
  `feedback-no-ascii-latin-regression`): ascii and latin are the rows the
  user cares about; a change that makes any ascii / latin row slower in WMO
  or `-no-WMO` is not shipped unless the user decides otherwise.
- **Scope: the collation port only.** Never propose changes to
  FoundationEssentials (an `@inlinable` on `sorted(using:)` was called "a
  non-starter"); record such costs as observations. The
  FoundationInternationalization files that the port wires
  (String+Collation.swift, StringProtocol+Locale.swift,
  String+SortComparator.swift) are in scope.
- **Do not create directories outside the project** without approval; keep
  artifacts in `.build/` (git-ignored) or the approved worktree. `/tmp` is
  cleaned between sessions. `~/.ssh` is not readable for you.
- **A/B baselines come from a git worktree, never from a stash.** Verify both
  sides before you run (a source grep, the binary hash, a symbol or a count).
- **Benchmarks:** thai at 10 repetitions maximum. Wait at least 10 minutes
  after a wake from sleep (`pmset -g log | grep -E " (Sleep|Wake|DarkWake) "
  | tail -3`). Run under `caffeinate -i`. Record the median of at least 4
  matrix runs (`Collation/Tools/matrix_record.py`; since 2026-11-04).
- **Precision means removing OUR harness overhead — never making the ICU
  reference slower.**
- **Fix bugs you find in the same pass** — never park them behind a
  known-issue marker; report the cost and let the user judge.
- **Writing:** ASD-STE100 Simplified Technical English for all user-facing
  text, docs and comments. Say "Swift implementation", never "pure Swift".
  Plain terms ("ICU reference answers", not "oracle"). Report failures and
  wrong conclusions plainly, and correct your own wrong numbers at once.
- **Explain plainly, briefly.** On 2026-11-02 the user answered a dense
  report with "I have no idea what you're talking about": say what a check
  means in everyday words before the numbers, one idea per paragraph.
- **No guessing about the user's machine.** A guess about Chrome as the cause
  of the macOS anomaly was wrong ("Chrome is working fine !!!!"): check
  facts (git, toolchain, a controlled re-run) before you name a cause.
- **Count every group before you time a variant** (§51 (ap)): code in a
  dispatch that is inlined into the hot entry moves the register allocation
  of the whole entry — root cjk, Thai under th / ja / zh, and the `-no-WMO`
  entries on ascii / latin each paid 5–51 instructions in some variant.
- **Pitfalls of this round:** zsh does not split `set -- $spec` (a corpus
  named "cjk 01" made lldb wait 15 minutes on a process that could not start
  — loop over `corpus:n` strings with `${c%%:*}` / `${c##*:}`, and check a
  long count's first line early); a series started with a trailing `&`
  inside a background command gives no completion notice; `ps` / `top` fail
  in the ACC sandbox unless the command text contains "swift"; never `sleep`
  longer than the job needs (a 15-minute sleep timed out).

**How to measure:**
- **Full matrix:** `ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2
  ICU_BUILD=$ICU_SRC/icu4c/source caffeinate -i /Users/dragan/Projects/dra8an/swift-foundation-collation/Collation/Tools/run_benchmarks.sh 3`
  (about 8–10 minutes since the WMO column; the first run builds the two
  BenchFoundation scratch paths `.build-matrix-nowmo` / `.build-matrix-wmo`
  from empty, ~10 minutes more). Since §51 (at) it builds both columns with
  Swift 6.5 and the native build system (the older note "works only because
  the swift-syntax objects are cached" no longer applies). Gates:
  the gates of "The measurement rules since 2026-11-04" above (if only the
  macOS side drifts: `python3 Collation/Tools/frozen_check.py
  Collation/Tools/bench_system 3`). Run it at least 4 times (a series
  script like `.build/matrix/cal-series-2026-11-04.sh`, about 5 minutes per
  run) and record the medians: `python3 Collation/Tools/matrix_record.py
  <run files>` prints the Docs/21 tables (and START HERE, the runbook ratio
  line, §51). Never start an extra series of matrix runs without asking. The user's calls and video calls load the
  machine: on 2026-10-29 a pair during a call drifted +2..+6% and was not
  recorded. **Start every build script with
  its ABSOLUTE path** (or any command text that contains "swift"): Apple
  Claude Code runs a shell command outside its process sandbox only if the
  command text matches `~/.claude/apple/tool_allowlist.csv`, whose entry
  `swift,contains_match` matches the repo path. A command without "swift"
  in its text runs sandboxed, and a `swift build` inside it fails with
  "Invalid manifest … sandbox-exec: sandbox_apply: Operation not permitted"
  whenever SwiftPM must compile a manifest (a new package, a new toolchain,
  or a new environment, e.g. `ICU_SRC` set). Found 2026-10-21; the earlier
  "start it through zsh" note was wrong.
- **Engine A/B:** `Collation/Tools/build_engine_bench.sh` in each tree, then
  `Collation/Tools/ab/engine_ab.sh <base> <variant> <out> 5` and
  `python3 Collation/Tools/ab/engine_ab_report.py <out>` (min, mean of
  variant − base, per-round signs). When a change moves rows whose code did
  not change, rebuild both sides with `-Xswiftc -Xllvm -Xswiftc
  -align-all-functions=6 --scratch-path .build-al` and A/B again: if the
  difference goes away, it is code placement.
- **Since §51 (at) (Swift 6.5):** build BOTH Foundation A/B sides with the
  native build system, in both trees: WMO `-g` in `.build-ab-wmo`, `-no-WMO
  -g` in `.build-ab-nowmo` (the commands under "For the next A/B" above).
  That replaces the scratch-path and copy methods in the next items (kept as
  history), which existed because the default build system could not build
  `-no-WMO` from an empty scratch path. A paths result needs the aligned
  EngineBench check: two builds of the same source differ by ~7% on paths
  compare (A against A, §51 (at)).
- **Foundation (Table 2) A/B:** `python3 Collation/Tools/ab/foundation_ab.py
  <base BenchFoundation> <variant> 5` (edit its `rows` list for the rows you
  need). A FRESH release build with `-no-whole-module-optimization` fails in
  swift-syntax ("unable to open dependencies file") — so for an A/B, build
  BOTH sides with normal WMO into fresh scratch paths (`swift build -c release
  --product BenchFoundation --scratch-path .build-wmo` here, `--scratch-path
  .build-bfg` in the worktree — both with `-Xswiftc -g` since 2026-10-21, so
  that the same binaries also serve instruction counts; the runbook allows
  WMO on this machine). For a placement check, add `-Xswiftc -Xllvm -Xswiftc
  -align-all-functions=6` and other fresh scratch paths on both sides (a
  full build, ~5 minutes each). **The committed `foundation_ab.py` runs
  ascii, latin and cjk only** — for thai or paths rows, copy it into
  `.build/` and add `("thai", 10)` (10 repetitions maximum) and/or
  `("paths", 150)` to its `corpora` list.
- **Two build modes, and why both matter for Table 2 work:** the matrix and
  the instruction counts of §51 (o) used the `-no-WMO` BenchFoundation (main
  tree, `.build/out/Products/Release/BenchFoundation`); the A/Bs use WMO
  builds. With WMO and SwiftPM's cross-module optimization, a generic
  non-`@inlinable` function MAY be specialized for the bench's types, so a
  cost seen in the `-no-WMO` count may be smaller or absent in the WMO A/B.
  Real clients of the shipping framework (library evolution) do NOT get such
  specialization, so the `-no-WMO` build is the closer model of them. But
  for code INSIDE the module the release build is WMO (`CMakeLists.txt`:
  `wholemodule` for Release), so there WMO is the model that release users
  get, and `-no-WMO` costs of calls across files are a handicap of Table 2
  only (§51 (as)). Count
  in both builds; report both; A/B in the WMO pair and say which mode it is.
- **Instruction count of a Table 2 call (the §51 (o) recipe):** add a
  temporary `@inline(never)` wrapper row to `Collation/Sources/BenchFoundation/main.swift`
  (for example `@inline(never) func tmpLocStd(_ a: String, _ b: String) -> Int
  { a.localizedStandardCompare(b).rawValue }` and a `measure(...)` loop that
  calls it; for the Substring case, pass `Substring`s); build in the MAIN tree
  with `swift build -c release -Xswiftc -no-whole-module-optimization
  -Xswiftc -g --product BenchFoundation` (~2.5 minutes); then
  `Collation/Tools/insn-count/count_calls.sh .build/out/Products/Release/BenchFoundation
  ascii "-r '^tmpLocStd'" 1000 <out.jsonl> 5` (skip 1000 warm-up calls; the
  script passes "<corpus> 1", which runs every row once — enough calls).
  Restore main.swift afterwards. **The WMO count of the same rows:** build
  with `swift build -c release -Xswiftc -g --product BenchFoundation
  --scratch-path .build-wmo` (the binary is
  `.build-wmo/out/Products/Release/BenchFoundation`) and run `count_calls.sh`
  on it with the same spec and skip. Two pitfalls (§51 (p)): Swift's
  function merging folds wrappers that differ only in the callee into one
  `…Tm` function, and lldb then finds "no locations" — give each wrapper a
  different body and check with `nm -a <binary>.dSYM/Contents/Resources/DWARF/BenchFoundation
  | grep tmp`; and `--scratch-path` is relative to the CURRENT directory,
  not to `--package-path`, so build the worktree from inside it. The `-no-WMO -g` build in the main tree
  worked four times on 2026-10-20 (about 2.5 minutes each; it rebuilds part
  of the package but keeps swift-syntax usable for the matrix).
- **Instruction counts** (exact, load-independent — the main tool of this
  round): Xcode's lldb, a `-g` build (`build_engine_bench.sh`, then
  `(cd .build/engine-bench && swift build -c release -Xswiftc -g)`).
  `Collation/Tools/insn-count/count_compare.sh <EngineBench> <corpus> <skip>
  <out> [n]` counts whole `compare(_:_:options:)` calls from the first
  instruction (skip 597 for ascii/latin/cjk, 1314 for paths, 200 for thai);
  `count_calls.sh` counts any function (sortKey: the mangled-name spec in its
  header; skip 600 for ascii/latin/cjk, 1317 for paths, 200 for thai; drop
  the first 2 calls — the bench grows its key array);
  `summarize.py` splits by function or line; `trace_lines.py` traces one call
  with source lines; `icu_count.c` counts ICU (`ucol_strcollUTF8`) on the same
  pairs. lldb pitfalls: `-r` regexes do not match names with argument types;
  `-a` addresses miss (ASLR); a copied binary cannot find its resource bundle
  (run variants from their build folder); counting 60 thai pairs takes about
  15 minutes, so run long counts in the background. **Counts find work; only
  the A/B tells its value** — on thai, −17% instructions gave −3.5% time
  (§51 (l)).
- **CPU Counters (new, §51 (ah); memory `reference-cpu-counters`):** when a
  change executes fewer instructions but runs slower, record both sides:
  `xcrun xctrace record --template 'CPU Counters' --time-limit 5s --output
  <abs>/x.trace --launch -- <binary> <args>`, then `python3
  .build/counters/shares.py x.trace 250 <t0_ms> <t1_ms>` (or `tail` for the
  last 1.2 s). The four shares, in order: **useful, instruction processing
  (back end), instruction delivery (front end), discarded (mispredictions)**
  — fixed with the control loops in `.build/counters/`. EngineBench compare
  runs first: `<corpus> 300000` fills ~6 s with compare; a Foundation row:
  a probe row ×50 at the end of `main.swift`, then `tail`. HEAD ascii
  compare: 90.4 / 0.1 / 9.4 / 0.0%. Processor Trace needs an M4-class chip
  (this machine is an M1 Max).
- **A `-no-WMO` base for a Foundation A/B** (a fresh `-no-WMO` build fails in
  swift-syntax): build the base in the MAIN tree's cached scratch from a
  CLEAN, committed tree (`git status` empty), copy
  `.build/out/Products/Release/{BenchFoundation,BenchFoundation.dSYM,swift-foundation_FoundationInternationalization.bundle}`
  to `.build/<dir>/` (a copied binary needs its bundle next to it), then
  change the code and build the variant. For an OLDER base: write the old
  files into the clean tree with `git show <commit>:<path> > <path>`, build,
  copy, restore them with `git show HEAD:<path> > <path>` and check `git
  status` — the user approved this on 2026-10-26 (about 30 seconds of
  changed files). Never use a stash.
- **One interleaved session against ICU C:** `.build/item3/fourway.py` runs
  several EngineBench binaries and `bench_icu` in one session (min of R
  rounds, rotating order) — clock times without mixing sessions.
- **Each change to `compare` must be checked in BOTH build modes** (the
  user's rule: no ascii / latin loss in WMO or `-no-WMO`): EngineBench plain
  and aligned, the WMO Foundation A/B, the `-no-WMO` Foundation A/B. The
  default-option Foundation rows (`localizedCompare`, `compare(_:locale:)`)
  move ±2–5% with the binary layout; before calling that layout, count one
  call (and run CPU Counters if the count does not explain the time).

- **Ladders** (`build_sk_ladder.sh`, `build_cmp_ladder.sh`, thai-ladder,
  disc-probe): they copy the engine sources and widen private members in the
  copy. **Build all four after any change to an internal signature** — C4
  broke two of them unnoticed until the next round (§51 (h)).

**The ICU checkout is not 79.0.1.** `~/Projects/Unicode/icu-DraganBesevic-2`
is on branch `main` (headers 79.1) with libraries built on 2026-10-21 from
the CLDR 49 integration branch (ICU 79.1, Unicode 18 data). Its speed equals
79.0.1, so Table 1 stays comparable, but its KEYS differ from our bundled
79.0.1 data. **Never generate golden files from it.** In that checkout,
build and test in-source only, never `build/icuhost` (see `~/CLAUDE.md`).
Gates (2026-11-04, medians of six runs): system-ICU `localizedCompare`
200/341/354/314/502 (macOS 27.2.1; before: 194/365/369/300/494 on macOS
26.4); ICU C compare 9.3/10.1/40.7/29.5/172.0, sortKey
104.1/120.7/119.3/365.2/153.7 (before, 2026-10-29: 9.3/10.1/40.8/30.0/172.8
and 104.4/121.0/117.7/373.3/155.5).

**The code as it is now (details in §51):**
- **compare, default options:** `compare(_:_:options:)` with
  `compareFastPath` force-inlined (§51 (i)); the guard compares the options
  as one 64-bit pattern (§51 (g)). `fastLatinUTF8`: when the first bytes
  differ (most pairs), a short path tests the lead bytes and calls
  `CollationFastLatin.compareUTF8` on the whole strings (§51 (ah)); when
  they are equal, the out-of-line `sharedPrefixRestart` (the word / byte
  scan `sharedPrefixLength`, the binary-equal test, ICU's backup, the
  restart-safety check) returns `(restart, mismatch)`. `compareUTF8` takes 8
  argument words (table, primaries pointer, options, two buffers that start
  at the restart; §51 (af)). The result becomes an `Order` through
  `RootCollator.order(fromFastResult:)` (one `add`, no branch;
  `FastResultOrderTests`). On a bail: `quickCJKDispatch` (for every collator
  since §51 (ap): the reordering applied at the decision by the
  `@inline(never)` `compareReordered`; normal CE32 accepted; no variable-top
  test in release — `QuickCJKTests` proves it for all 98 tailorings), then
  `restartScalarCount` → `compareSlowPath` → `compareBody(restart:)` →
  `compareFromRestart` (both strings pinned, bytes `ScalarSource`). The
  internal twin `compareWithDefaultOptions` (§51 (ak)) skips the options
  compare of the guard (`optionsAreDefault: true`).
- **compare, non-default options:** `compareSlowPath`'s options byte pass is
  the closure from before (z), with `fastLatinUTF8(…, marksPrefixBail:
  true)`: a bail at the end of a shared prefix returns
  `optionsPassMarker(mismatch:)` (−3 − mismatch) instead of bailOutResult
  (−2 = `optionsPassBailed`, "no mismatch"). After any bail,
  `compareSlowPath` calls `compareAfterOptionsPass(…, mismatch:)` directly
  (re-pins; scans the prefix only without a mismatch; quick CJK compare for
  any options since §51 (ap), `restartScalarCount`, `compareFromRestart`;
  §51 (z), (ac), (aq)). Identical strength: `identicalStrengthTertiaryPass` first
  (§51 (o)), then — since §51 (ao) — `compareBody(…, restart:
  optionsPassBailed)`, which calls `compareAfterOptionsPass` with no
  mismatch, the same bytes path. Bridged strings: the walk.
  The pass's fast-Latin setup: `resolveFastLatinSetup` (force-inlined)
  reads the default key and its numeric twin from `Storage` (resolved at
  init; every Foundation option set has one of them), other keys from the
  lock-free `FastLatinCache` through the `@inline(never)`
  `resolveFastLatinSetupFromCache` (§51 (e), (ar)). The compare paths test
  the option enums with the fileprivate case matches `hasIdenticalStrength`
  / `isShifted`, never `==`, and read `RootCollator.fastLatinBailOut`,
  `latinMaxLead`, `prefixDependentResult`, `fastLatinPrimariesKey` — the
  same-file copies of §51 (as) (`SameFileCopiesTests`). Keep new hot-path
  constants in the same file, or `-no-WMO` pays a call for each. The default
  fast path indexes the pinned bytes through `RootCollator.untraced(_:)`
  (§51 (av)): without it, Swift 6.5 traces the indexing to the stack copy of
  a small string and gives `compare` a stack protector (10 instructions per
  call). Keep new pinned-byte code behind `untraced`, and run
  `Collation/Tools/check_stack_protection.sh` after compiler updates.
- **The Foundation wrappers** (`StringProtocol+Locale.swift`,
  `String+Collation.swift`, `String+SortComparator.swift`): the eight public
  generic wrappers carry `@_specialize(where Self == String, T == String)`
  and a fast path for two Strings (the old body, for Substring and others, in
  `@inline(never)` `…Converting` functions; §51 (am), (an)).
  `CollatorCache.currentLocaleCollator()` / `collator(in:)` return a pointer
  to the collator in a published, never-freed slot, read with one acquiring
  load (§51 (aj)); the wrappers call it through non-generic pointer entries
  in `RootCollator.swift` (`compareWithDefaultOptions(at:)`, `compare(at:)`,
  `defaultOptions(at:)`, `contains(at:)`, `search(at:)`), which use the
  storage at +0 (`_withUnsafeGuaranteedRef`, private `withCollator`; §51
  (ak)).
- **CE compare:** `CollationCompare.compareUpToQuaternary(prefixSkipped:)` returns `prefixDependent` (2) when a
  skipped prefix can change the result (shifted: a side starts with a
  primary-ignorable CE; backward secondary: one side runs out in the first
  segment); the callers then compare from the start (§51 (z)).
- **NFD front end (§51 (y)):** `NFDIterator.source` is a `ScalarSource`
  (trivial: pointer, position, end; skips by lead bytes); `fallback` is an
  optional String iterator for String-view resets. A bytes source is valid
  only inside the string's `withContiguousStorageIfAvailable` scope.
- **CE production:** fast paths in `appendMoreBody(wholeString:)` — ASCII
  table, Thai table, combining-mark table (`markCEs`, U+0300–037F, whole
  strings only, §51 (w)), CJK computed primaries (`quickCJKPrimary`, §51
  (v)). `collectAll()` (`wholeString: true`) also takes runs of simple ASCII
  scalars (`collectSimpleASCIIRun`, §51 (t)); `appendMore()` passes false.
- **sortKey:** `sortKey` pins the string and calls a static `@inline(never)`
  body (§51 (y)); `ScratchBuffers.resetCollectAndWriteKey` runs reset, CE
  production and the writer under one access scope; the writer
  (`writeSinglePass<Config>`) is specialized for the default options
  (§51 (s)) and keeps a write cursor per level (§51 (r)).
- **search:** the entries pin pattern and text (`withPinnedUTF8`, every
  contiguous string; §51 (aa)); `containsScan`, `searchForward` and
  `produceAnnotatedCEs` are `@inline(never)` so that `appendMore` inlines
  into them (§51 (ab)).
- **Creation and caches:** root data, normalization data and Storages are
  shared per process (§51 (e)); resources are found by path (§51 (q));
  `FastLatinCache` is lock-free for readers.
- **Tests added in this round:** QuickCJKTests (§51 (ap)), CollatorCacheTests
  (§51 (ak)), `CollationConcurrencyTests.explicitLocaleCacheGivesEachLocaleItsOwnCollator`
  (§51 (aj)), `SubstringReceiverTests.substringReceiversAndArgumentsMatchStrings`
  (§51 (am)), identical-strength sets in OptionsRestartTests (§51 (ao));
  before: OptionsRestartTests (§51 (z)), FastResultOrderTests (§51 (ah));
  earlier:
  RestartSafetyTests, CollationConcurrencyTests (also under `swift test
  --sanitize=thread --scratch-path .build/tsan`), CollationOptionsBitsTests,
  RestartBackupTests, IdenticalStrengthTests, ASCIIRunTests,
  CJKFastPathTests, MarkFastPathTests, ScalarSourceTests. Tests that read the
  current locale heavily must run on the preferences actor (§51 (o)).

**Do not redo (measured and rejected; details in §51 and §49/§50):**
reading a `String` or a `RootCollator` through a pointer to avoid a copy —
`pointee` copies (a retain), also into a `borrowing` parameter (§51 (ak)
W1a, §51 (an) C1 / C2; use `_withUnsafeGuaranteedRef` for the collator and
`@_specialize` for the generic wrappers); a generic `@inline(__always)`
helper with a closure called from another file (unspecialized in
`-no-WMO`, §51 (ak) W1); in the quick CJK dispatch, a variable-top guard, the reordering inside `quickCJKPrimary`, an out-of-line reordered dispatch, or the reordering inline at the decision (§51 (ap) Q1–Q1h: each cost some group 5–51 instructions);
the bit cast in `bits(of:)` against the Swift 6.5 stack protector (no effect; the cause was the pinned-byte indexing, §51 (av)); new `Storage` fields in the middle of the class (they move the hot pointers after them; §51 (ar)); in the options pass, any value that lives across the `compareUTF8` call — the mismatch in a variable outside the pinned closures (§51 (aq) V1 / V1b: ascii / latin options +1..+3 instructions; carry it in the result instead);
a branch-free ASCII / two-byte Latin decode in `compareUTF8` (latin −4.5%,
ascii +4.5%; §51 (ai)); pinning only strings longer than 15 bytes (§51 (aa)); in `compareUTF8`,
wrapping index increments (`&+= 1`; LLVM then reads each byte with `ldrsb`
and two masks) and the table without the slice check alone (C1a: ascii
−1..−2% in WMO but `compare(_:locale:)` ascii / latin +1.7..+2.3% in
`-no-WMO`) (§51 (ad)); moving the default path's bail work out of the
pinned scope with a packed result (E1, §51 (ad)); the 8-word call with the
scan inline (P2: paths +46 instructions, §51 (af)); P3 / P3b without the
branch-free `Order` conversion (§51 (ag)); in the options path, V3 / V3b /
V3c / V5 (`@inline(__always)` on `compareSlowPath` is ignored by the
compiler; §51 (ac)); tighter per-CE byte bounds (UNSAFE); `RestartSafety` by
value out of a raw pointer; the `takeScratch` hot/cold split; golden keys
from ICU 79.1; adding cost to the ICU harness; inlining `compareUTF8` into
the entry; a forward single-pass restart count; Fix B; a one-slot or locked
`FastLatinCache`; a cache key of the whole options word; merging the
identical-strength pass into the options byte pass; Thai scalars in the
ASCII bulk run (§51 (u)); the ASCII run before every `appendMore` (§51 (t));
a `ScalarSource` with the String iterator inside (§51 (y)); any
FoundationEssentials change; any public API change.

**Machine notes (Apple Silicon, 10 cores):** the 1-minute load rests around
8–15 (`suggestd`, `WindowServer` …) and often rises to 20–70 during the
user's working day; the system-ICU control decides a matrix run, interleaving
handles A/Bs.

**Network:** on the wired network (`en18`, 10.5.141.x) SSH on port 22 to
GitHub is intercepted (TCP opens, no banner); `en0` works. `origin` therefore
uses the `github-personal` alias (ssh.github.com:443, in ~/.ssh/config), the
same as the user's other machine. Fallback: the one-off URL
`ssh://git@ssh.github.com:443/dra8an/swift-foundation.git` (memory
`reference-github-ssh-443`).

---


> HISTORY (written 2026-06-12, extended through 2026-10-20). The current
> state is in START HERE above; the sections below are the record.

## What this project is

A Swift implementation of the Unicode Collation Algorithm (UTS #10 /
CLDR root + tailorings), ported from ICU4C's "collation v2" design following
the ICU4X architectural model (always-on fused NFD decomposition, no FCD, no
canonical closure in data). Target: contribution to swift-foundation
(milestone 8 integration implemented, awaiting maintainer/community input
before proposing upstream).

## Where everything is

This project has been worked on from two machines. Paths differ:

**Machine 2 (Apple Silicon, current as of 2026-06-17):**

| Path | What |
|---|---|
| `~/Projects/dra8an/swift-foundation-collation/` | git clone, branch `port/collation` |
| `.../swift-foundation-collation/Collation/` | **the SwiftPM package root** (name: `Collation`) and these docs (`Docs/`) |
| `~/Projects/Unicode/icu-DraganBesevic-2/` | ICU4C 79.0.1 source + build (`icu4c/source/lib/`) |

**Machine 1 (Intel iMac, original development):**

| Path | What |
|---|---|
| `~/Projects/claude/collation/swift-foundation/` | git worktree, branch `port/collation`, based on `upstream/release/6.3` |
| `.../swift-foundation/Collation/` | **the SwiftPM package root** |
| `~/Projects/claude/swift-foundation/` | user's MAIN checkout — calendars project. **Never touch.** |
| `~/Projects/claude/icu/` | ICU4C 79.0.1 source clone |
| `~/Projects/claude/collation/icu-build/` | local ICU build |

Remotes: `origin` = github.com/dra8an/swift-foundation (user's fork, push
target), `upstream` = swiftlang (never push). Branch tracks origin.

## Hard rules (user-mandated)

1. **NEVER add "Co-Authored-By: Claude" or any Claude/Anthropic reference to
   commits.** History was rewritten once to purge them. Before every push:
   verify messages (`git log --format=%B | grep -ci 'claude\|co-authored\|anthropic'`
   must be 0) and author/committer identity (must be dra8an), and show the
   user the verification.
2. **Push ONLY when the user explicitly says "push" in that same request** — a
   prior "push it" authorizes that one push only, never the next task/commit.
   Commit when done, then STOP and ask. This is enforced two ways: a `deny` rule
   on `Bash(git push:*)` in `.claude/settings.local.json` (the harness blocks the
   push; the user runs it themselves via the `! git push …` prefix), and a
   feedback memory. Do not try to work around either.
3. Plain terminology: no testing jargon — "ICU reference answers" not
   "oracle", "option set" not "configuration".
4. Swift 6.4 does NOT compile on machine 1; everything bases on
   `upstream/release/6.3` (toolchain: Swift 6.3.1).
5. Transient `.git/worktrees/swift-foundation/index.lock` collisions happen
   on machine 1 (likely Atom's git polling). Wait a few seconds, re-check for
   live git processes, remove the zero-byte lock only if stale, retry.
6. The user values: decision records for surprising scope cuts, honest
   skip-counting in tests, investigating failing imported expectations
   against ICU source before "fixing" our code (twice the expectations were
   wrong, not the implementation).
7. **Git identity for this repo:** `dra8an <chonbey@hotmail.com>` (set via
   `git config --local`). GPG signing is disabled locally
   (`commit.gpgsign = false`).

## Current state (2026-06-17)

- **Milestones 1–7 complete** (plan + per-milestone reports in `Docs/`):
  full UCA runtime — fused NFD, all strengths/settings, contractions
  (incl. discontiguous S2.1) and prefixes, sort keys **byte-identical to
  ucol_getSortKey**, 15 locale tailorings incl. zh script reordering.
- **Milestone 7.5 complete** (perf rounds 1–13): every portable ICU test
  suite is ported, plus perf rounds. **61 tests / 19 suites, all green.**
  Suites: official UCA conformance (433k lines), collationtest.txt
  data-driven, Thai dictionary (31k words), 9 classic locale suites, regcoll
  (13 cases), cmsccoll (20 cases + extreme compression), g7coll locale rows,
  apicoll behavioral parts, differential matrices + byte-identical keys
  (21 option sets × 2 data variants), 52k fuzz keys.
- **Performance round 14 complete** (2026-06-16/17, documented in `Docs/14`):
  three changes shipped, four experiments tried and reverted:

  **Shipped:**
  1. **Thread-local scratch buffers** — replaced the locked `ScratchPool`
     with a process-wide pthread TLS key + monotonic collator ID. −19% CJK
     compare, −10% sort keys. Subsequently fixed for lifetime safety: one
     process-wide key (never deleted), monotonic IDs (no address reuse),
     removed dead `ScratchPool` and dead `ScratchBuffers.key` field.
  2. **`sortKey(for:into:)` inout API** — caller supplies the output buffer,
     eliminating per-call allocation + memcpy. −27% sort keys. The old
     returning variant delegates to it.
  3. **Span-based fast-Latin bail** — uses `String.utf8Span.span` (macOS 26+,
     `#available`-gated) for the byte-level prefix scan and Latin-eligibility
     check, so non-Latin text (CJK, Thai) never pays the
     `withContiguousStorageIfAvailable` closure overhead. −10% CJK compare.
     **Fixed after cross-machine review:** inline `#available` in `compare()`
     bloated codegen and regressed macOS 15 (+26% ASCII, +8% CJK). Fix:
     split into `compareClassic()` / `compareWithSpan()` / `compareBody()`
     — each compiled independently, shared tail prevents correctness drift.
     Buggy Span prefix skip (`spanPrefixSkip`) removed (53 test failures
     when isolated); Span now only handles the fast-Latin bail check.

  **Tried and reverted (do not re-attempt without reading `Docs/14`):**
  - Raw-UTF8 iterator path (approach a: nested closures, +3%; approach b:
    escaped pointer, UB — crashes)
  - Lock-free fast-Latin cache (use-after-free in concurrent tests)
  - Raw-pointer sort-key level buffers (slower than Array — see `Docs/16`)
  - Span-based prefix skip for full pipeline (+12% CJK regression — must
    rebuild iterators for CE pipeline, negating the gain; also had a scalar-
    counting correctness bug)

- **`origin/port/collation` in sync** at `99a7a67`. Milestone 8 Foundation
  integration (2026-06-22/23): Collation sources moved into
  `Sources/FoundationInternationalization/Collation/` (same module — no
  separate Collation target, no `FOUNDATION_COLLATION` flag, no
  `@inlinable` needed). Full-string comparison: `localizedCompare`,
  `localizedStandardCompare`, `String.Comparator` with locale,
  `String.StandardComparator.localizedStandard` all route through
  `RootCollator`. Substring search (forward and backward):
  `localizedStandardContains`, `localizedCaseInsensitiveContains`,
  `localizedStandardRange(of:)`, `range(of:options:range:locale:)` (incl.
  `.backwards`). Predicates: both `StringLocalizedCompare` and
  `StringLocalizedStandardContains` enabled. 98 locale tailorings bundled
  (full ICU coverage). Darwin opt-in feature flag added (defaults off).
  Performance: `localizedCompare` 1.5–2.8× faster than system ICU.
  941 tests pass (40 suites).
  Since `c683653`, the search APIs were optimized (thread-local scratch-iterator
  reuse for `contains`/`search`/`searchBackwards`, plus ASCII/UTF-8 byte-scan
  fast paths for `range(of:locale:)`): `localizedStandardContains` now beats
  system ICU on most corpora. 2026-07-04: **lazy position reporting** in the
  range search (NFD offsets on `AnnotatedCE`, `sawDecomposition` flag on
  `NFDIterator`, conversion/validation only at CE-equal candidates, index
  table deleted) — `localizedStandardRange` now beats system ICU on every
  corpus except paths (1.38×, was 2.18×). 2026-07-06: **backward byte-scan**
  + byte-scan soundness rules (clean-ASCII prefix/suffix proofs,
  ignorable-control and shifted gates) + **alternate=shifted support in
  search** (`16d0322`) — `range(of:.backwards)` went from the worst API
  (2.6×/3.45× behind on ascii/paths) to beating system ICU on latin/paths,
  ≤1.32× elsewhere. 2026-07-12/13: **engine-entry round** (§29–§30):
  compare hot/cold split (throws only paid on the pipeline path),
  duplicated-safety-check removal, word-wise prefix scan, and the
  **RootCollator storage box** — the collator was a ~768-byte struct copied
  at every call boundary (incl. the CollatorCache fetch inside every
  Foundation call); it is now one pointer. `localizedCompare` HALVED
  (ascii 117 ns = 0.27× system ICU; latin 0.14×); engine compare ascii
  39 ns (2.44×), paths 98 (2.00×). Table-1 rows recorded before 07-13
  include a ~10–12 ns receiver-copy bench artifact — do not compare across.
  2026-07-13 late: **quick-primary CJK dispatch** at the byte-scan mismatch
  + longPrimary coverage in quickPrimary (§31, `4acac0b`) — cjk compare
  232→82 ns, now **1.11× vs ICU C** (was 3.9×); hard rule recorded there:
  the pinned-buffer closures may only call STATIC functions with trivial
  parameters. Machine 2 same day: **CollationSearch storage box**
  (`67594f8`, search APIs −5..−13%) and **sortKey primary-byte batching**
  (`68156e1`, paths sortKey −18% Intel / −15% AS). Harness: **Table 1 now
  measures the FULL-WMO engine** via `Tools/build_engine_bench.sh`
  (EngineBench — no Locale, so machine 1's WMO SIGILL never trips); Table 2
  prints SPEEDUP (sys/ours); thai runs root-vs-root. Current Intel engine
  (WMO): compare 1.1–2.5×, sortKey 1.2–1.9×; Foundation APIs 1.1–7× FASTER
  than system ICU except five range cells (0.80–1.00×).
  2026-07-14: **§33** — machine 2's sortKey CE-array-as-UnsafeBufferPointer
  (`3aaa1d5`, −2..−4% AS) regressed Intel (+10% paths, call-site closure
  blocks WMO inlining of the writer); reconciled as `ces: borrowing [Int64]`
  (`44c9497`) — Intel restored, machine 2 to re-verify the ARC win on 6.4.
  Same day, **§34 (thai round part 1, `2e6c961`)**: probe ladder attributed
  the thai gap (NFD 345 / CE +200 / skip-walk 126 with 88% unsafe fallback /
  scratch 5 = settled); **lone-mark pass-through at refill's head** shipped —
  thai compare 637→615, sortKey 513→486, others neutral. §34 also records
  the **ALIGNMENT TRAP**: Intel WMO paths-sortKey deltas within ±7% are
  code-placement luck until the writer's instruction stream is diffed
  (`otool -tv`; identical instructions = not a regression).
  2026-07-16: **§37 allocation-free search** (`43c5c84`) — ~40% of every
  search() call was allocator traffic (per-call pattern/window/text CE
  arrays); they now live on ScratchBuffers, handed to the search entries
  as ONE class reference (per-buffer inout parameters opened exclusivity
  scopes before the byte-scan fast path and taxed ascii/paths range —
  rule recorded in §37). Engine cjk search −50%; contains/stdRange
  −30..45% on every corpus; **the last two sub-parity cells (cjk range)
  flipped — Docs/25 re-baselined at `1b43bbc`: ZERO Foundation-API
  cells (Table 2) behind system ICU on either machine** (sole ≤1×: paths
  range fwd at 0.99×, byte-scan-bound parity wobble). The pure-engine
  rows (Table 1, vs raw ICU C) still trail hand-tuned C 1.1–2.25×
  compare / 1.2–1.8× sortKey on Intel; AS cjk compare is the one engine
  row ahead. Machine 2 confirmed §37 on AS
  (−29..35%) and resolved §33 (borrowing neutral on 6.4). Probes
  committed: `build_thai_ladder.sh` (P0–P8), `build_cjk_probe.sh`.
  Same day, three more from the ALLOCATION/RESOLUTION HUNT audit list
  (the pattern note at the top of optimization-targets.md — read it
  before any perf work): **§38** one-slot locale-resolution cache
  (`609e6cd`) — every explicit-locale API −190..250 ns flat;
  compare(locale:) ascii 409→219, paths range(of:) — the last at-parity
  cell — to 1.50× ahead; AS confirmed −61..65%. **§39 CORRECTNESS FIX**
  (`9878236`/`702c961`): rebaseRange returned copy-space indices — every
  localizedStandardRange/range(of:locale:) result on a SUBSTRING receiver
  was misaligned by the substring's start offset; fixed with
  self-relative scalar-offset math + 3 regression tests (suite now
  1514/121). **§40** (`b4d1ce5`): StandardComparator paid Locale.current
  PER COMPARISON (~60 ns × n·log n in sorts) — now uses
  collatorForCurrentLocale (287→229/cmp; −50..64 verified on all
  corpora). §40 also records the stale-binary bench trap rules.
  2026-07-15 (machine 1): **§41 nfdMap audit box** (`13337d4`) — a
  matching search on DECOMPOSING text cost 7× a no-match scan of the
  same line (confirmMatch's map + two temp arrays PER DECOMPOSING
  SCALAR ≈ ~130 mallocs/line), invisible to the bench matrix (the
  standard corpora barely trigger the path; real-world accented Latin
  pays it on every hit). Fixed by a trie count-twin
  (fullDecompositionCount) + scratch-owned map: **match tax −86%**
  (end-match 21.3→5.6 µs on accented-64, engine probe full WMO);
  neutral on standard corpora (interleaved A/B vs `78ccaa8`, 24 rows
  ±2.6%). Probe committed: `build_accented_probe.sh`. **Docs/25
  re-baselined at `13337d4` — §38–§41 folded in; every Table-2 cell
  now ≥1.28× ahead of system ICU** (paths range(of:), the last 0.99×
  holdout, reads 1.41×). 2026-07-16: **§42 boundary-walk fusion**
  (`c1629d3`, the §41 follow-up) — confirmed matches walked the text
  up to 4× (whole-string count walk + per-boundary walks + index
  construction); fused into ONE bounded walk, validators deleted.
  Match confirmations −17..19%, no-match control −7%, **paths
  stdRange −12% in the shipping build** (frequent hits × long lines).
  §42 records the WMO INLINING TRAP: the fused tail grew confirmMatch
  past the inlining threshold and the hot equality loop paid a call
  per candidate (+9% control) until the §29 hot/cold split restored it
  (@inline(never) confirmedRange) — watch nm for symbols
  appearing/disappearing; every match-path probe needs a no-match
  control. Plus a new A/B rule: an A/B that builds base into `.build`
  leaves it STALE — symbol-verify both sides before running.
  Docs/25's `13337d4` tables predate §42's paths-stdRange change; fold
  at the next re-baseline. Same day: CollationOptions.from audit box
  CLOSED (`66fced3`) — WMO object sweep shows the symbol fully
  inlined/folded, the 85 §38-profile samples were a -no-WMO bench
  artifact; no code change. **§43 sortKey attribution complete
  (2026-07-16, ladder committed `build_sk_ladder.sh`): the entry is
  EXONERATED (TLS ~20 ns, throws ~0 — §30's box already collected it);
  the WRITER is 56–60% of sortKey on every corpus (ascii write phase
  208 ns > ICU's whole 194); its profile is 41% core / 35% Array
  append machinery / 14% ARC+exclusivity, zero allocs.**
  2026-07-20: **CONTRIBUTION_GUIDELINE.md conformance, part 1**
  (`05677e6`) — upstream added the guideline on main ("Do not manually
  wrap comments or DocC"); mechanical unwrap across all collation
  sources + our comments in the two inherited String files
  (script-verified comment-only, suite green). Remaining conformance
  items (force unwraps, §-reference comments, unsafe-API isolation,
  Benchmarks/ entries) filed as the UPSTREAM-PREP audit box. Same
  day: **§43 SHIPPED (`e232237`) — the direct multi-pass sortKey
  writer**: one pass per level straight into the key (stack-batched,
  no level buffers, no assembly), buffered writer retained as the
  identity-checked reference. **sortKey ascii/latin/cjk/thai −11..16%
  → 1.44–1.53× vs ICU C (was 1.67–1.81×)** — the biggest engine move
  since §31; paths +5% accepted residual (§43's "paths saga": the §33
  closure dead end re-confirmed at ~40 ns; writer deltas certified in
  the SHIPPING binary, not probes; machine 2 to arbitrate the
  residual). Docs/25 re-baselined at `e232237` — §42+§43 folded;
  Table-2 floor 1.31×. Same day: **§44 locale-change invalidation
  SHIPPED** (Docs/29 decision record) — collatorForCurrentLocale
  revalidates against LocaleNotifications' generation count (FE
  counter made package-visible); mid-process system locale changes
  now picked up next call, regression-tested (en↔sv flip; **suite
  gate is now 1515/122**). Bench-build cost +15..18 ns on localized
  compare rows (framework build ≈ free — relaxed atomic); Docs/25's
  `e232237` tables predate it. **§44's test also FOUND A BUG (filed,
  top of audit list): tailoring default SETTINGS (fr_CA backwards
  secondary) never apply through the no-options wrappers —
  compare() defaults to CollationOptions(), not the collator's
  defaultOptions. Darwin divergence; fix needs the options-merge
  decision.** 2026-07-22: **§45 — the tailoring-defaults bug FIXED**:
  engine entries are overload pairs (no-options overload resolves the
  collator's defaultOptions; explicit signature keeps no default arg),
  CompareOptions translation merges onto a REQUIRED base — fr_CA
  backwards secondary now applies through every wrapper, ucol_open
  semantics, root bit-for-bit unchanged. Compare entry ZERO-cost
  (overloads; the Optional shape cost +2..3 ns and is the recorded
  anti-pattern). **Suite gate is now 1517/123.** Machine 2 closed the
  §43 paths arbitration (`a9bf0d0`: AS paths −4% → Intel residual =
  placement). Audit boxes left: the UPSTREAM-PREP conformance pass
  (the last one).
  2026-07-15: **§35 (thai round part 2)** — Thai-block simple-CE table
  (`4a73ada`, thai cmp −8% / sk −6%) and the walk-skip at the byte-scan
  mismatch (`26e340f`, cmp −17 ns; P8 probe promised −110 — standalone
  probe deltas are CEILINGS when deleted work shares memory traffic with
  what remains). A Thai unsafe-mask was tried and REVERTED the same day
  (§35: −4 thai, +5..9 every other compare — the pinned-closure context
  is codegen-fragile even for two extra property reads; helper renamed
  walkIsUseless → mismatchRestartIsUnsafe, `9b1d62b`). **Round-end
  re-baseline (Docs/25, K=3 at `9b1d62b`): thai compare 534 (2.05×, was
  637/2.47×), sortKey 443 (1.65×, was 513/1.93×); thai localizedCompare
  1.53× faster than system, contains 2.8–2.9×; only the two cjk range
  cells (0.84–0.86×) remain sub-parity. The thai frontier is now the NFD
  per-scalar floor — the parked Span refactor.**
  2026-07-24 (machine 2): **automated 4-angle code review of the whole
  engine directory** — 16 findings, 4 fixed (`e5e9f51`): `reorderEx`'s
  unbounded `while q >= ranges[i]` walk and `lastPrimaryForGroup`'s
  `scriptStarts[index + 1]` both gained bounds guards (both were
  ICU-data-invariant-protected, both crash on a corrupt/truncated
  tailoring binary), `PoolLock.deallocate` gained the missing
  `deinitialize(count:)`, and the dead `ScratchPool` class (21 lines,
  never instantiated — `ThreadLocalScratch` replaced it) was removed.
  The other 12 are recorded with per-item rationale in the
  optimization-targets audit list (`62f0b14`) — read that before
  re-reviewing, it explains why each was accepted rather than fixed
  (pthread_key_delete race: mitigated by CollatorCache's long-lived
  Storage; `scalarAt` unchecked continuation bytes: relies on String's
  UTF-8 well-formedness, standard practice, and a guard would cost
  ~2 ns/scalar on the hot path; the rest latent/unreachable).
  Same round, two claims in the technique log were CHALLENGED AND
  MEASURED rather than taken on faith:
  (a) the "18 copy-pasted common-weight flush blocks" item said
  unifying them risks hot-path inlining regressions — that was an
  untested guess by analogy to §19/§34. Measured: **5 of the direct
  writer's 9 blocks unified into one `@inline(__always) flushCommon`
  (`dcd82a5`) is exactly performance-neutral** (ascii 173→171, latin
  184→184, cjk 190→190, paths 429→431 — all noise; keys byte-identical,
  suite green). The remaining 4 have genuinely different shapes
  (nibble-packed case level via `packCaseByte`, unidirectional
  quaternary-shifted, backwards-secondary writing straight to `key`)
  and stay inline.
  (b) §31's rule that the pinned-buffer closures must call STATIC
  functions — the +17-22% instance-call penalty was **verified to be
  Intel/6.3.1-specific** (`20edc9e`): on Apple Silicon 6.4 an instance
  `quickCJKDispatch` calling the instance `quickPrimary` from inside
  the closure measures identical (ascii 17/17, cjk 28/25, paths 42/42).
  The static twin + `QuickCJKSetup` box (45 lines of duplication) is an
  Intel workaround; it can be deleted when 6.3.1 is dropped, which
  upstream `main` (Swift 6.4+) would allow. Documented, not implemented.
  2026-07-31: **§22 Span RETIRED after a third investigation**
  (`16f9907`). `-enable-experimental-feature Lifetimes` DOES now lift
  the `~Escapable` struct-storage limitation (a `SpanIterator` holding
  `Span<UInt8>` compiles with `@_lifetime(borrow x)` and runs at parity
  with the closure on long strings), but: passing a Span to a helper
  function traps at runtime (exit 133, the lifetime checker rejects the
  escape even for `@inline(__always)` callees), and **the two-span
  compare shape we actually need is 3.4× SLOWER** — `utf8Span.span`
  costs ~5 ns per string and we need two, versus ~4 ns total for the
  nested `withContiguousStorageIfAvailable` that pins both. Do not
  revisit unless the property access drops below 1 ns or the compare
  path moves to long strings.
  **UPSTREAM-PREP, new box (serious, blocked):** the buffered sort-key
  writer — `writeSortKeyUpToQuaternary` + `SortKeyLevel` +
  `SortKeyLevelBuffers` (~520 lines of SortKey.swift) plus
  `ScratchBuffers.levels` — is called ONLY by the sk-ladder tool. It
  must not ship in the production module. Blocked because the ~30
  compression constants it shares with the direct writer are
  `private static` inside the `CollationKeys` enum; widening them to
  internal was rejected as API creep. Options recorded: duplicate the
  constants into the tool, restructure `CollationKeys` to separate
  constants from methods, or move the writer to a test target with
  `@testable import` (cleanest, needs the upstream package structure).
  **Current Apple Silicon baseline (2026-07-31/08-03, full-WMO
  EngineBench vs ICU 79; supersedes the tables below for AS):**
  compare ascii 17/9 (1.9×), latin 17/10 (1.7×), **cjk 28/42 = 0.7×
  (we are FASTER)**, paths 42/29 (1.4×), thai 275/173 (1.6×);
  sortKey ascii 175/105 (1.7×), latin 190/122 (1.6×), cjk 189/120
  (1.6×), paths 425/369 (1.2×), thai 229/153 (1.5×). Foundation APIs
  (Table 2) 1.9–6.9× FASTER than system ICU with zero cells at or
  behind parity. Suite gate 1517/123.
  **CURRENT BASELINE (2026-10-16 17:29, run_benchmarks.sh K=3, full-WMO
  EngineBench for Table 1, at `481cd3ce`; supersedes every AS table in
  this file). Full matrix in `Docs/21`.** One-decimal output (baselines
  before 2026-10-15 13:21 were truncated integers; do not compare them at
  the 1-ns level).
  Table 1, engine vs raw ICU C (ours/ICU): compare ascii 15.1/9.3
  (1.62×), latin 14.6/10.1 (1.45×), **cjk 25.4/40.5 = 0.63× and paths
  23.2/29.7 = 0.78× (we are FASTER)**, thai 257.9/173.8 (1.48×); sortKey
  ascii 157.2/104.5 (1.50×), latin 175.7/120.9 (1.45×), cjk 174.5/119.0
  (1.47×), paths 381.4/370.3 (1.03×), thai 209.5/155.5 (1.35×).
  Against 2026-10-15 13:21: compare ascii −9.6%, latin −6.4%, cjk −4.9%,
  paths −43.6% (all §50); sortKey flat.
  Table 2 (Foundation APIs vs system ICU): its lead comes mainly from the
  removed NSString → CoreFoundation → C++ bridge, so it is not evidence
  about the engine.
  **The ICU column is ICU 79.1 with Unicode 18 data** (the local checkout
  is on the CLDR 49 integration branch); its speed equals 79.0.1, so the
  ratios stay comparable.
  Machine state when recorded: load 10–17, on AC, 8 hours after a wake,
  under `caffeinate -i`. Two runs 7 minutes apart agree (ours: compare
  ≤1.4%, sortKey ≤2.1%). System-ICU control within 1.7% (run B, recorded).
  Sanity gates before recording a future run: system-ICU
  `localizedCompare` ~194/365/369/300/494; ICU C ~9.3/10.1/40.5/29.7/173.8
  compare and ~104.5/120.9/119.0/370.3/155.5 sortKey (check which ICU the
  checkout holds first). K=3 takes about 4–7 minutes. Suite gate 1529/124.
  Previous baselines: 2026-10-15 13:21 (decimal, post-§49) compare
  16.7/15.6/26.7/41.1/261.7, sortKey 158.6/175.4/175.1/392.2/211.4;
  2026-10-15 10:36 and 2026-08-12 (truncated integers). Details in the git
  history of `Docs/21`.
  **IN FLIGHT at the time of writing:** a workflow-orchestrated
  optimization hunt over the engine compare/sortKey paths (8 ideation
  lenses → adversarial verification → ranked plan), targeting the
  remaining 8 ns ascii-compare and 70 ns ascii-sortKey gaps. Its
  ranked output was not yet folded into this doc — check
  optimization-targets.md for a §46 or later, and if absent, the hunt
  did not land and the standing frontier is unchanged. Note for
  whoever picks it up: the sortKey writer design space has a THIRD
  point nobody has tried — (a) single-pass + heap level buffers was
  the old writer, (b) multi-pass + no buffers is shipped today, and
  **(c) single-pass + STACK level buffers is what ICU actually does
  and has never been measured here.** At default tertiary strength (b)
  traverses the CE array three times and re-runs the variable-CE skip
  per pass; (c) traverses once. This is NOT §15 (which fused CE
  *production* with the writer and regressed +11..44%) — it concerns
  only the writer's internal pass structure, CE array still
  materialized first.
  2026-08-03: **§46 — the in-flight hunt LANDED, four changes shipped**
  (machine 2). The writer's third design point was the right call:
  **(c) single-pass + region level buffers WINS** over both prior
  writers. `writeSortKeyUpToQuaternarySingle` traverses the CE array
  once, accumulating every level (primary included) into disjoint
  slices of ONE `withUnsafeTemporaryAllocation` region — ICU's
  MaybeStackArray semantics from the stdlib, stack at real string
  sizes, heap above — and assembles the key at the end, so the loop
  never touches `key` and pays no capacity/uniqueness/exclusivity cost
  per byte. Region sized from a PROVEN per-CE byte bound (primary
  ≤ 5N−5, secondary ≤ 2N−1, plus a flush-amortization theorem; N
  includes the NO_CE sentinel), asserted on every store so a wrong
  bound trips the debug suite instead of corrupting memory. **paths
  sortKey took back §43's accepted +5% residual.** Also shipped:
  **a CORRECTNESS BUG** — discontiguous contractions (UTS #10 S2.1.3)
  never counted the scalar `removeAhead` consumes, so `scalarsConsumed`
  under-counted cumulatively and EVERY search match reported after one
  was wrong (measured: 84 of 206k UCA lines fire it; 40 of 40 sentinel
  probes wrong, 27 of them nil = match MISSED; one increment fixes
  40/40). **`icuOptions` @inline(__always)** — it was an out-of-line
  28-instruction getter with a global switch-table load, called once
  per compare and once per sortKey; §2's "sub-nanosecond" estimate was
  read off source and was wrong (−1 ns on every compare row, symbol
  count 2→0). **Digit-resolved simple-CE tables** — §27 named the
  defect in passing and nobody tried it; two table variants selected
  at reset (never per scalar), paths sortKey −6.1%, +2 KB.
  **Gate is now 1527/124, zero known issues** (§46's two regression
  tests plus §47's position suite). New AS numbers in
  the baseline block below. **§47 — the position gate**: until now
  EVERY suite compared CE bytes or key bytes and NOTHING compared the
  offsets the search APIs report, which is why four bugs of one class
  (§39, §44/§45, §46(b), and §47's own find) all slipped through 1500
  tests. `PositionInvariantTests` closes it with an invariant that
  needs no reference implementation: the CE iterator must consume
  exactly as many scalars as the NFD front end produces, checked over
  both conformance corpora × {plain, table fast paths, numeric} —
  **252 mismatches per file on the unfixed source** — plus five
  oracle-free API-level position invariants (content round-trip,
  forward/backward agreement, self-search, Substring receiver).
  That suite immediately found a SECOND, pre-existing bug — and it is
  FIXED, not deferred: a match ENDING at a discontiguous contraction
  under-reported its end (the CE consumes a NON-CONTIGUOUS scalar set,
  so a running COUNT cannot say where it ends), landed
  mid-combining-sequence and was rejected → wrong nil / missed match.
  Probe committed: `build_disc_probe.sh` (finds the firing lines a
  corpus contains, prints per-CE spans, runs four position checks,
  exits non-zero on failure — 84 lines / 108 hits clean on the
  conformance corpus). Fixed by tracking NFD POSITIONS alongside the count (packed into the
  lookahead entries, one array) and taking min-start/max-end over a
  match's CEs in confirmedRange. Cost, measured: sortKey +1%, search
  end-match +2.4% with the absent control moving equally (so the cost
  is CE production, not confirmation) — accepted on the §44 precedent.
  The cheaper flag-gated variant was REJECTED for making position
  correctness opt-in. §47 has the trace, and warns against the tempting
  wrong fix (extending the end over trailing marks would break "e" not
  matching inside a decomposed "é"). **Suite gate 1527/124, ZERO known
  issues.**
  2026-08-06: **§48 — exclusivity scopes, ALL FOUR sites shipped**
  (`c272d6f` sortKey, `8134285` compare, `864edf3` search family,
  `ea2080f` identical-level drains). Headline: **thai compare 275→258
  (1.58× → 1.48× vs ICU, the worst engine row), search family
  −3.2..−3.6% on all three entries, `.identical` sortKey −22..−28%
  (~100 ns/call), sortKey −3.2..−5.4%.** Two mechanisms, and telling
  them apart is the lesson: call fusion merges repeated access to the
  SAME property (compare), but where the pairs come from DISTINCT
  properties (search) only BUNDLING them into one stored property
  helps — count the distinct properties an entry touches, that is the
  floor on its scope count. The `.identical` drains were a third shape:
  the same property touched once PER SCALAR in a loop, so hoisting the
  loop pays proportionally to input length (~100 ns) rather than a
  fixed per-call amount. Details in §48. `ScratchBuffers` is a class, so every mutating access to a stored
  property opens a dynamically-enforced scope. sortKey's two pairs
  (one around the out-of-line `reset`, one around the whole inlined
  `collectAll` loop) are now one, via a fused method over a static
  helper taking the iterator `inout` — the ONLY shape that works:
  fusing into a plain method on the class is a measured no-op, because
  the throwing `collectAll` blocks the optimizer's access merging.
  **sortKey ascii 167→159 (−5.4%), latin −3.7%, cjk −3.3%, thai −3.2%,
  paths no signal, compare flat**; symbol-verified 8/9 → 7/8 access
  relocations. **THE RECALIBRATION: one begin/end pair costs ~8–9 ns,
  not the ~2–3 ns §46 assumed**, which re-prices the three untouched
  sites — compare pipeline 4 pairs (thai-only), search family 5/5/4,
  and `.identical` drain loops 2 pairs PER SCALAR. All three take the
  same plain-Swift shape; reaching ZERO would need
  `@exclusivity(unchecked)` or unsafeAddress accessors, which have zero
  precedent in swift-foundation and are recorded-not-recommended.
  Same day (`15f5376`): the position suite gained a **data-derived sweep
  over every root discontiguous contraction** — 12 starters found by
  trie scan, their 14 real suffixes discovered by CE comparison, crossed
  with every lower-ccc mark; 2486 of 2490 triples reach the branch
  (99.8%, vs 100 of 14700 for a naive sweep), four oracle-free checks
  each, 0.113 s, with `#require` guards so a broken derivation fails
  loudly instead of silently covering nothing. **Gate 1528/124.**
  **2026-10-14 ROUND (§49 in `optimization-targets.md` — read it first).**
  The sk-ladder was refreshed onto the shipping writer (`36254566`; it
  supersedes the §43 table). Writer change "variant C" SHIPPED
  (`a6263dc7`): latin sortKey −4.3%, thai −3.2%, the other rows flat,
  with a new stress test against `compare()`. `gen_golden` lost its silent
  line-length and line-count limits (`d4c56e97`). The latin S0−S1 gap was
  a one-run outlier (`975929ac`). The two non-shipping sort key writers
  moved out of the product into
  `Collation/Tools/sk-ladder/ReferenceWriters.swift` (UPSTREAM-PREP item,
  done; SortKey.swift 1610 → 645 lines). **Gate 1529/124.** The round is
  complete. ICU reference answers for the stress strings (§49 item 1b)
  were dropped: 79.1 sorts the corpora in the same order as 79.0.1 but
  with different key bytes, so it cannot produce our golden keys, and the
  existing tests already cover the writer (§49).
  A/B baselines build in a git worktree (`../collation-baseline`), never
  from a stash. The tighter byte bounds were UNSAFE; do not redo them.
  **2026-10-16 (§50): the compare ladder.** `build_cmp_ladder.sh` split the
  ascii compare entry: the fast-Latin CORE is faster than ICU's whole
  call (8.4–9.0 against 9.3 ns); the gap is the ENTRY, ~5–6 ns (throws
  0.6, string access ~0, guard + field loads 2.7, interaction 1.6–2.8).
  Fix A3 (the default fast-Latin setup in one boxed pointer, RestartSafety
  kept in the storage object's `let`): ascii −0.4 ns, latin −0.6 ns, the
  other rows flat. Lesson: a 176-byte struct read through a raw pointer is
  copied before use — that variant cost paths +1.3 ns.
  **§50 (g), same day: an instruction count under lldb** (`Tools/insn-count/`)
  found two defects that timing could not separate: the restart-safety
  shortcut threshold was U+0034, not U+0300, so every letter took two binary
  searches (fix: a 768-byte table below U+0300); and the compiler loaded all
  of `RestartSafety` on EVERY call (fix: pass it by pointer to its own box).
  A/B vs `b31aeea6`: **paths compare −43% (1.38× → 0.78× of ICU), ascii −8.5%
  (1.76× → 1.61×), cjk −7%, latin −2%**, thai and sortKey flat. Next: a new
  baseline, then `icuOptions` (22 instructions) in the guard (§50 (g)).
  Technique log: `optimization-targets.md` — read THE ALLOCATION/
  RESOLUTION HUNT note at the top before any perf work, then §20
  (steps 6–8), §27, §29–§50 and the audit list;
  Apple Silicon numbers `21-foundation-api-benchmark.md`; Intel `Docs/25`.
  Previous sync (`f0dcec5`) added: inline collectAll (−12% Latin sortKey),
  bypass-refill for Latin precomposed chars (−11% Latin sortKey), ICU bench
  min-over-9 parity.
  Cross-machine confirmed on Intel/macOS 15 (2026-06-19/22 — see the Intel
  performance subsection below).
  Post-Span-revert optimizations:
  - Quick-primary CJK compare: bypasses CE pipeline for different CJK
    characters (−10% CJK).
  - Pre-baked fast-Latin setup: eliminates the per-call cache lock by
    storing primaries as UnsafeBufferPointer at init (−22% ASCII, −23%
    Latin, −16% paths). Full analysis in `Docs/18` §7-§8.
  - Scaling analysis confirmed: gap to ICU narrows with longer strings
    (~8-12 ns fixed per-call overhead dominates short strings).
  - Deletion experiments proved closures are zero-cost on Apple Silicon
    (compiler inlines them); the real cost was the cache lock.
  - Inline CE pipeline hot path: `@inline(__always)` on
    `NFDIterator.next()`, `CEIterator.popScalar()`, `appendMore()`.
    −5% CJK sortKey, −3% Latin/paths, −2% Thai/ASCII. Compare neutral
    for fast-Latin corpora.
  - Pre-computed `isUnsafe` safe threshold: scan at init finds the lowest
    unsafe code point (U+0300 for root). Short-circuits trie lookups on
    the prefix-skip safety check. −5% sorted ASCII 32, −4% sorted ASCII
    64 compare. Neutral on random corpora (no shared prefix to check).
  - Pre-computed ASCII CE table: 128-entry lookup of full 64-bit CEs,
    built at init. Sort key's `appendMore()` skips trie lookup + tag
    dispatch for simple ASCII characters. −14% ASCII, −6% Latin, −21%
    paths sortKey. Compare and CJK/Thai neutral.
  - NFDIterator carry-cascade fix: single inert carried scalar emitted
    directly instead of triggering a full refill chain. −14% Latin sortKey,
    −7% Thai sortKey, −8% Thai compare. ASCII/CJK neutral.
  - Quick decomposition for [starter, mark] pairs: `quickDecomp()` returns
    both scalars from one trie lookup, skipping the `decomposed` array.
    −7% Latin sortKey (stacks with carry fix). ASCII/CJK/paths neutral.
  - SortKey level-buffer memcpy (the `+appendTo` win): the sort
    key's write phase is ~56% of sortKey; `SortKeyLevel.appendTo`
    (`Array.replaceSubrange`) was its largest callee. Skip the copy for
    levels that compress to nothing, and copy the rest through an
    `UnsafeBufferPointer` (memcpy fast path). −3 to −6% sortKey on every
    corpus, compare unaffected.
  - Bypass `refill()` for Latin precomposed chars: for `c < 0x0300` with
    `quickDecomp` success and `leadCCC(following) == 0`, emit base + mark
    directly via `pendingMark` — no arrays, no loops, no carry. −11% Latin
    sortKey, per-accent cost 56→24 ns. ASCII/CJK/paths/Thai neutral.
  - Inline `collectAll()`: `@inline(__always)` gives the compiler full
    visibility into the CE loop from sortKey. −12% Latin sortKey (enables
    better register allocation for the refill/quickDecomp path).

### Current performance

Two machines, two CPU/OS regimes. **Keep each machine's numbers in its own
subsection** so cross-machine runs don't overwrite each other. Absolute ratios
differ by hardware (ICU is faster on Apple Silicon too); the *improvements* hold
on both. State the corpus, reps, and how the time was taken in each section.

#### Apple Silicon (macOS 26, quiet machine, 10000 reps, lower cluster) — HISTORICAL

> **SUPERSEDED by the 2026-08-12 baseline above (and `Docs/21`).** These
> predate §46–§48 entirely; kept only as the record of the June–July arc.
> Do not compare against them.

**Compare (ns/op, EngineBench full WMO):**

| corpus | ours | ICU 79 | ratio |
|--------|------|--------|-------|
| ASCII  | ~17  | ~9     | 1.9×  |
| Latin  | ~16  | ~10    | 1.6×  |
| CJK    | ~27  | ~42    | 0.6× (faster) |
| paths  | ~44  | ~30    | 1.5×  |

**Sort keys (inout API, buffer reused, EngineBench full WMO):**

| corpus | ours | ICU 79 | ratio |
|--------|------|--------|-------|
| ASCII  | ~202 | ~107   | 1.9×  |
| Latin  | ~218 | ~125   | 1.7×  |
| CJK    | ~213 | ~121   | 1.8×  |
| paths  | ~453 | ~372   | 1.2×  |

**Foundation API integration vs system ICU (ns/op, Apple Silicon):**

What users actually call — our collator through Foundation APIs vs the
system NSString → CoreFoundation → ICU bridge:

| API | corpus | ours | system ICU | speedup |
|-----|--------|------|-----------|---------|
| `localizedCompare` | ASCII | 47 | 201 | **4.3× faster** |
| `localizedCompare` | Latin | 45 | 368 | **8.2× faster** |
| `localizedCompare` | CJK | 66 | 377 | **5.7× faster** |
| `localizedCompare` | paths | 77 | 304 | **3.9× faster** |
| `localizedStdCmp` | ASCII | 52 | 201 | **3.9× faster** |
| `localizedStdCmp` | Latin | 53 | 355 | **6.7× faster** |
| `localizedStdCmp` | CJK | 79 | 368 | **4.7× faster** |
| `localizedStdCmp` | paths | 93 | 327 | **3.5× faster** |
| `compare(locale:)` | ASCII | 208 | 320 | **1.5× faster** |
| `compare(locale:)` | Latin | 193 | 493 | **2.6× faster** |
| `compare(locale:)` | CJK | 218 | 499 | **2.3× faster** |
| `compare(locale:)` | paths | 231 | 421 | **1.8× faster** |
| `localizedStdContains` | ASCII | 326 | 1015 | **3.1× faster** |
| `localizedStdContains` | Latin | 346 | 1478 | **4.3× faster** |
| `localizedStdContains` | CJK | 370 | 1309 | **3.5× faster** |
| `localizedStdContains` | paths | 377 | 995 | **2.6× faster** |
| `localizedStdRange` | ASCII | 338 | 1013 | **3.0× faster** |
| `localizedStdRange` | Latin | 361 | 1477 | **4.1× faster** |
| `localizedStdRange` | CJK | 397 | 1302 | **3.3× faster** |
| `localizedStdRange` | paths | 605 | 1011 | **1.7× faster** |
| `range(of:locale:)` | ASCII | 233 | 330 | **1.4× faster** |
| `range(of:locale:)` | Latin | 525 | 810 | **1.5× faster** |
| `range(of:locale:)` | CJK | 548 | 603 | **1.1× faster** |
| `range(of:locale:)` | paths | 296 | 322 | **1.1× faster** |
| `range(backwards)` | ASCII | 237 | 333 | **1.4× faster** |
| `range(backwards)` | Latin | 524 | 845 | **1.6× faster** |
| `range(backwards)` | CJK | 553 | 606 | **1.1× faster** |
| `range(backwards)` | paths | 331 | 523 | **1.6× faster** |

Every Foundation string API is faster than system ICU across all corpora.
`localizedCompare` is 4–8× faster. CJK engine compare beats raw ICU C.
Direct collation arithmetic is 1.2–1.9× behind ICU (down from 2–3×).

ICU bench built against `/Users/dragan/Projects/Unicode/icu-DraganBesevic-2/`:
```sh
cd Collation/Tools
clang bench_icu.c -O2 -o bench_icu \
  -I /Users/dragan/Projects/Unicode/icu-DraganBesevic-2/icu4c/source/common \
  -I /Users/dragan/Projects/Unicode/icu-DraganBesevic-2/icu4c/source/i18n \
  -L /Users/dragan/Projects/Unicode/icu-DraganBesevic-2/icu4c/source/lib \
  -licuuc -licui18n -licudata
DYLD_LIBRARY_PATH=/Users/dragan/Projects/Unicode/icu-DraganBesevic-2/icu4c/source/lib \
  ./bench_icu Tools/bench/bench-cjk.txt 200
```

#### Intel iMac (macOS 15, Swift 6.3.1 release) — HISTORICAL (through 2026-06-22)

> **Current Intel numbers live in `Docs/25` (re-baselined 2026-07-13,
> full-WMO EngineBench for Table 1).** Headline row there: compare ascii 36
> (2.25×), cjk 81 (1.11×), thai 637 (2.47×); sortKey 1.2–1.9×. The tables
> below predate the §29–§31 round AND the harness changes — keep them only
> as the record of the June optimization arc; do not compare against them.

min ns/op (best wall-clock pass; Bench takes the min over 9 internal passes,
interleaved across many invocations). One coherent run across all columns.
Three reference points: **`620be9d`** = fork point, before the optimization
run; **`86578c1`** = the post-Span optimization tip (cross-machine confirmed
here); **`+appendTo`** = `86578c1` plus the SortKey level-buffer memcpy (this
machine). Δ = `+appendTo` vs `620be9d`. Every metric improved over the fork
point; nothing regressed.

**Compare:**

| corpus | ICU 79 | `620be9d` | `86578c1` | `+appendTo` | Δ total |
|--------|-------:|-----------|-----------|-------------|--------:|
| ASCII  | 16  | 64 (4.00×)  | 50 (3.12×) | 51 (3.19×) | −20% |
| Latin  | 17  | 64 (3.76×)  | 50 (2.94×) | 50 (2.94×) | −22% |
| CJK    | 72  | 243 (3.38×) | 235 (3.26×)| 233 (3.24×)| −4%  |
| paths  | 48  | 133 (2.77×) | 109 (2.27×)| 108 (2.25×)| −19% |
| Thai (th) | 284 | 753 (2.65×) | 705 (2.48×)| 700 (2.46×)| −7% |

**Sort keys (inout API, buffer reused):**

| corpus | ICU 79 | `620be9d` | `86578c1` | `+appendTo` | Δ total |
|--------|-------:|-----------|-----------|-------------|--------:|
| ASCII  | 196 | 443 (2.26×)  | 375 (1.91×) | 359 (1.83×) | −19% |
| Latin  | 208 | 645 (3.10×)  | 470 (2.26×) | 453 (2.18×) | −30% |
| CJK    | 219 | 419 (1.91×)  | 403 (1.84×) | 384 (1.75×) | −8%  |
| paths  | 661 | 1237 (1.87×) | 994 (1.50×) | 961 (1.45×) | −22% |
| Thai   | 289 | 662 (2.29×)  | 581 (2.01×) | 566 (1.96×) | −15% |

The `+appendTo` step (sortKey write path) is −3 to −5% sortKey on every corpus
vs `86578c1`, compare unaffected — profiling showed `writeSortKeyUpToQuaternary`
is ~56% of sortKey, and `SortKeyLevel.appendTo` (Array.replaceSubrange) its
biggest callee. Next lever in the write phase: fuse CE production with key
writing to drop the intermediate `[Int64]` CE-array round-trip (bigger, riskier;
compare still needs the array).

ICU 79 built locally (machine 1):
```sh
cd Collation/Tools
ICU_SRC=~/Projects/claude/icu
ICU_BUILD=~/Projects/claude/collation/icu-build
clang bench_icu.c -O2 -o bench_icu \
  -I $ICU_SRC/icu4c/source/common -I $ICU_SRC/icu4c/source/i18n \
  -L $ICU_BUILD/lib -licuuc -licui18n -licudata
DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./bench_icu Tools/bench/bench-cjk.txt 300
```
Per-corpus reps equalize work (thai is ~33k lines vs ~200): ASCII/Latin/CJK 300,
paths 150, thai 3. Caveat: ICU's bench truncates input at 64 UTF-16 units, so the
**paths sortKey** ICU figure may be slightly optimistic (some paths are longer) —
the base→new improvement is ours-vs-ours and unaffected. These numbers used a
local min-of-9-passes tweak to `Sources/Bench/main.swift` (low measurement noise;
not committed).

## Key findings from round 14 (read before optimizing further)

1. **`isUniquelyReferenced` is hoisted out of loops.** The profiler shows it
   as ~9% of samples, but the compiler calls it once before the loop, not per
   byte. Replacing Array with raw `UnsafeMutablePointer` is **slower** (11
   instructions/byte vs Array's 7) because the compiler reloads pointer+capacity
   from memory every iteration due to aliasing uncertainty. Full assembly
   analysis in `Docs/16`.

2. **`Span<UInt8>` exists in this toolchain** (`String.utf8Span.span`, macOS
   26+, `#available`-gated). It gives closure-free byte access that compiles
   to identical assembly as `withContiguousStorageIfAvailable`. BUT: it's
   `~Escapable` (can't be stored in struct fields), and passing it to a
   non-inlined function is **3.3× slower** due to lifetime-check overhead.
   Must use `@inline(__always)` throughout. Detailed benchmarks in `Docs/16` §9.

3. **The residual gap is per-call overhead**, not per-byte arithmetic:
   - String-access cost (`withContiguousStorageIfAvailable` / iterator ARC)
   - The fast-Latin cache lock (~10 ns)
   - CE pipeline function-call boundaries
   The collation arithmetic itself runs at ICU's speed.

## Deliberate scope cuts (don't re-litigate without reading the docs)

- **Runtime rule builder NOT ported** — `12-rule-builder-decision.md` has the
  full reasoning, costs, and porting plan. Tailorings are compiled binaries
  extracted from ICU's build (`Tools/extract_tailoring.c`).
- **Normalization cannot be turned off** (architectural); **unpaired
  surrogates unsupported** (Swift String); **reorder-table generation
  unsupported** (data-supplied reordering only). (Fast-Latin was a cut on
  the ICU4X precedent, reversed by user decision in M7.5 round 9 — the
  tables were already in the bundled data.)

## Open backlog

- **Rule builder** (doc 12) — parked, awaiting decision.
- **M8 Foundation integration** — implemented, awaiting maintainer input
  before proposing upstream. Benchmarked: `localizedCompare` 1.5–2.8×
  faster than system ICU (same-module WMO, no `@inlinable` needed after
  refactor). Darwin opt-in feature flag added (defaults off, ready for
  Apple to flip).
- **`.widthInsensitive`** — NOT a collation feature. It's a scalar-level
  transformation (fullwidth U+FF00–U+FFEF → halfwidth) done before
  comparison. On Darwin, `_toHalfWidth()` calls `CFUniCharCompatibilityDecompose`;
  on non-Darwin, it's a `fatalError` TODO in FoundationEssentials
  (`Sources/FoundationEssentials/String/UnicodeScalar.swift:20`). ICU
  collation doesn't handle it either — it uses NFD, not NFKD. The fix is
  a simple offset table in FoundationEssentials, not in our collation module.
- **Span-based CE pipeline refactor** — the remaining Span opportunity:
  thread `Span<UInt8>` through the full `CEIterator.appendMore()` →
  `NFDIterator.next()` chain, replacing `String.UnicodeScalarView.Iterator`
  entirely. Requires `@inline(__always)` on the entire 5-call-deep chain.
  Potential −30–40% on CJK/Thai compare but high risk of regressions from
  inlining failures. Details in `Docs/16` §9.6 and §10.

## How to work

```sh
cd ~/Projects/dra8an/swift-foundation-collation  # repo root (machine 2)
# machine 1 (Intel iMac): cd ~/Projects/claude/collation/swift-foundation
swift test                      # full suite, ~30s (machine 1 reports 1514 tests / 121 suites)
swift build -c release          # build everything incl. BenchFoundation
```

### Benchmarking — run the script, DO NOT reconstruct it

This kept getting guessed wrong on cold starts. The procedure is a committed,
verified script. Run it; don't write a one-off harness or hand-build commands:

```sh
Collation/Tools/run_benchmarks.sh        # builds all 3 harnesses, prints the matrix
Collation/Tools/run_benchmarks.sh 3      # faster, K=3
```

Full explanation, per-machine ICU paths, and how to read the tables:
**`Docs/27-benchmark-runbook.md`**. Recorded numbers: `Docs/25` (Intel),
`Docs/21` (Apple Silicon).

> **MACHINE 1 (Intel iMac, Swift 6.3.1) gotcha** (the script already handles it):
> a release `BenchFoundation` built with whole-module optimization **SIGILLs at
> startup** — `Locale(identifier:)` → the `dynamic` `_localeICUClass()` whose
> `@_dynamicReplacement` isn't applied under WMO, so it jumps into data. Always
> build with `-Xswiftc -no-whole-module-optimization`. Not a collation bug, not
> stale artifacts; debug is fine. Root cause: `Docs/25`. (Machine 2 / newer
> toolchain doesn't hit this.)

Regenerating reference data (only when corpus/locales change; needs icu-build):

> **WARNING (2026-10-16): do NOT run this against `icu-DraganBesevic-2` as it
> is now.** That checkout holds ICU 79.1 with Unicode 18 data; our collator
> bundles 79.0.1 data, and all 42 key files differ (the order matrices match,
> which hides it). Golden files need an ICU build with the SAME data as the
> bundled `ucadata.icu`. See START HERE and technique log §49 (1b).

```sh
cd Tools
ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2
ICU_BUILD=$ICU_SRC/icu4c/source
clang gen_golden.c -o gen_golden -I $ICU_SRC/icu4c/source/common \
  -I $ICU_SRC/icu4c/source/i18n -L $ICU_BUILD/lib -licuuc -licui18n -licudata
DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./gen_golden \
  ../Tests/CollationTests/Golden/corpus.txt ../Tests/CollationTests/Golden
# fuzz keys: same with fuzz-corpus.txt + "--keys-only"; tailorings:
# extract_tailoring.c; norm data: swift run GenNormData <nfc.txt> <nfd.bin>
# test fixtures: extract_locale_suites.py / extract_regcoll.py /
#   extract_cmsccoll.py / extract_g7coll.py
```

## Code map (Sources/FoundationInternationalization/Collation/)

- `CollationConstants.swift` — CE32/CE bit layouts, tags, implicit/OFFSET
  primaries (renamed from `Collation` to avoid module/type name collision)
- `UTrie2.swift`, `UCharsTrie.swift` — read-side trie ports
- `CollationData.swift` — "UCol" v5 binary reader (root + tailorings +
  `Reordering`), bundled resources accessors
- `NormalizationData.swift` + `NFDIterator.swift` — nfd.bin reader (v2:
  single-trie, one lookup per scalar) + fused NFD front end (fast path for
  bare starters)
- `CollationElements.swift` — `CEIterator`: lazy CE production, contexts
  (contraction/prefix matching), numeric, base fallback
- `CollationCompare.swift` — level-by-level compare (lazy via `ce(at:)`)
- `CollationFastLatin.swift` — mini-CE fast path for Latin text (compare
  only; scalar and raw-UTF-8 variants; bails out to the regular pipeline)
- `SortKey.swift` — sort key writer + BOCSU identical level
- `CollationOptions.swift` — public options ↔ ICU options word
- `CollationSearch.swift` — collation-aware substring search: linear CE-space
  scan with strength masking, NFD position annotation, boundary validation
- `ScratchBuffers.swift` — thread-local buffer reuse (process-wide pthread
  key, monotonic collator IDs), `FastLatinCache`, `FastLatinSetup`
- `DataStorage.swift` — owns the allocated memory behind `UnsafeBufferPointer`
  views in `CollationData` and `NormalizationData`
- `RootCollator.swift` — public API: `compare`, `sortKey`, `sortKey(for:into:)`,
  `search(for:in:options:)`, `contains(pattern:in:options:)`,
  `init(tailoringNamed:)`, `defaultOptions`; Span-based fast-Latin bail path
  (`#available(macOS 26.0)`)

## Doc index (Docs/)

01 ICU4C investigation · 02 ICU4X strategy · 03 Swift strategy ·
04 **milestone plan + status table (the spine — keep it updated)** ·
05–10 milestone reports (2–7) · 11 milestone 7.5 report (tests + perf) ·
12 rule-builder decision record · 13 performance analysis (standalone,
covers rounds 1–13) · 14 **performance round 14** (thread-local, inout
sortKey, Span bail path; also records four reverted experiments) ·
15 ICU4C-to-Swift source mapping · 16 **Array vs UnsafePointer assembly
analysis + Span<UInt8> discovery and benchmarks** · 19 **Foundation
integration plan (implemented)** · 20 **Integration quick reference
(5-min pitch)** · 21 **Foundation API benchmark** (localizedCompare vs
system ICU) · 22 **Cross-module inlining** (the 10× improvement —
detailed analysis) · 23 **Refactoring plan** (move Collation into
FoundationInternationalization) · 30 **Side note: ICU4J fast-Latin
compare bug** (signed `pair` test; ICU4J only — ICU4C and our port are
correct; do not make our `pair` type signed) · HANDOFF (this file)

Convention: every milestone/round updates doc 04's table + outcome note and
gets a detailed report; decision records for surprising cuts. Commit
messages are ONE LINE (user decision, 2026-10-14); the details go into the
docs, not the commit message. No attribution line.
