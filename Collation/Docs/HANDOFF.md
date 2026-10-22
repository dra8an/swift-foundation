# HANDOFF — Cold-Start Guide for the Collation Project

## START HERE (current as of 2026-10-21 — everything below this section is history)

**If anything in the history below contradicts this section, this section
wins.** The history has stale rules and numbers on purpose; it is the record.

**What this is.** A Swift implementation of the Unicode Collation Algorithm
(ICU4C collation v2 design, ICU4X model) inside swift-foundation:
`Sources/FoundationInternationalization/Collation/`. Repo
`~/Projects/dra8an/swift-foundation-collation`, branch `port/collation`,
remote `origin` = `git@github-personal:dra8an/swift-foundation.git` (an SSH
alias to ssh.github.com:443 — see "Network" below; never push `upstream`,
which this repo does not even have). The tools and docs live under
`Collation/`.

**State at the time of writing (VERIFY WITH GIT — do not trust this
paragraph).** Expected: HEAD = a docs commit (the late-evening matrix:
Docs/21, Docs/27, this file, optimization-targets.md) on top of `6d0d26f9`
(§51 (t)). If it is missing, those four files are modified — say so and
give the add/commit lines. Tree clean otherwise; about 13 commits ahead of
`origin` (not pushed: `d3c9eed9` … through §51 (t) and this docs commit). The A/B worktree is now at `c84d0ca1` (before (t)) with its own
`main.swift` (the probe copy was restored). The
first-collator probe packages are `.build/first-collator/` (base engine
sources, all probe modes) and `.build/first-collator-new/`. The worktree holds EngineBench builds in `.build/engine-bench/` (plain
and, in `.build-al/`, with every function aligned to 64 bytes) and older
WMO BenchFoundation builds in `.build-bf/` and `.build-bfg/` (from
`4c24d059` with the §51 (p) probe rows; rebuild them before a Table 2
A/B). The §51 (p) probe `main.swift` is in the main tree at
`.build/insn-wrappers/main-probe.swift`, with the count runner `run.sh`,
`classify.py` and the A/B row list `foundation_ab_wrappers.py`. Remove the
worktree with `git worktree remove ../collation-baseline` when the A/B work
ends.

**What is routine and needs no question:** builds and A/Bs of up to about 10
minutes; the full test suite (`swift test`, about 1–2 minutes; the Thread
Sanitizer run of the concurrency tests about 5 minutes the first time);
moving the worktree and rebuilding there; temporary probe rows in
`Collation/Sources/BenchFoundation/main.swift` — in BOTH trees when an A/B
needs them (keep a copy of the original in `.build/`, restore it after,
restore the worktree's copy before its next checkout, never commit them;
row names may contain only letters, spaces and `().:_`, no digits, or the
A/B parser skips them); `git fetch`. Ask before anything longer or with
wider effect.
Suite gate: **1549 tests in 132 suites** — `swift test` prints three summary
lines (45/5, 563/87, 941/40); add them up.

**Read next, in this order:**
1. The memory index (loaded automatically) and ALL its feedback files — the
   user's working rules. New or changed on 2026-10-20:
   `feedback-no-silent-wait-loops`, `feedback-no-foundationessentials-changes`,
   `project-array-vs-pointer`, `project-next-steps-2026-10-20`,
   `reference-github-ssh-443`.
2. `Collation/Docs/optimization-targets.md` **§51, all of it, (a)–(p)** — the
   technique log of the 2026-10-16…21 round (every change, every rejected
   variant, every measurement). Then §50 (g) (the instruction-count method)
   and the ALLOCATION/RESOLUTION HUNT note at the top of the file.
3. `Collation/Docs/21-foundation-api-benchmark.md` — the current baseline
   (2026-10-21 late evening, run A), including "The sort rows, split".
4. `Collation/Docs/27-benchmark-runbook.md` — how to measure, the harness
   cost, the gates.
5. `Collation/Docs/30-icu4j-fastlatin-signed-pair-bug.md` — a side note (an
   ICU4J bug we do NOT have; do not make our fast-Latin `pair` type signed).

**Current engine numbers (Table 1, EngineBench vs ICU C, 2026-10-21 late
evening run A at `6d0d26f9`, ns per call, ours / ICU):**

| corpus | compare | ratio | sortKey | ratio |
|---|---|---|---|---|
| ascii | 10.6 / 9.4 | 1.13× | 80.0 / 105.9 | 0.76× |
| latin | 11.2 / 10.3 | 1.09× | 105.6 / 123.1 | 0.86× |
| cjk | 20.1 / 40.8 | 0.49× | 114.8 / 119.4 | 0.96× |
| paths | 18.8 / 29.8 | 0.63× | 200.4 / 371.8 | 0.54× |
| thai | 194.7 / 174.7 | 1.11× | 153.0 / 156.5 | 0.98× |

At the start of the round (2026-10-16) the ranges were compare 0.63–1.62×
and sortKey 1.03–1.50×; now compare 0.49–1.13×, sortKey 0.54–0.98×. Runs A
and B agree within 1.8%. In this `-no-WMO` matrix the `range(of:)` rows
read 1–9% above the morning baseline (ascii 108 → 116, backwards 109 →
119): code placement — one call executes exactly the same instructions as
in the morning (§51 (t)), and the WMO A/B showed ascii −5%.

Table 2 (Foundation APIs vs system ICU, now 14 API families including an
options compare and four sort APIs, floor 1.58×) is ahead everywhere, but
mostly because it skips the system NSString → CoreFoundation → C++ bridge.
**Never use Table 2 as evidence about the engine; never cite it as
consolation for a Table 1 gap.**

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
  under load. Guideline: for an A/B, run at any load and give the load in
  one line (direction is what it measures). For a matrix, up to a 1-minute
  load of about 25, just run; between about 25 and 50, run only if the
  5-minute value is not far above the 1-minute one, and let the system-ICU
  control decide afterwards (more than ~3% drift: do not record); above
  about 50, or during a burst (the 5-minute value far above the 1-minute
  one), say so in one line, do load-independent work (instruction counts,
  code reading) and re-check ONCE before you start it. Run unavoidable waits
  in the background.
- **Work solo** (no Workflow tool, no multi-agent fan-out) unless the user
  asks for it.
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
  | tail -3`). Run under `caffeinate -i`. Record two matrix runs that agree.
- **Precision means removing OUR harness overhead — never making the ICU
  reference slower.**
- **Fix bugs you find in the same pass** — never park them behind a
  known-issue marker; report the cost and let the user judge.
- **Writing:** ASD-STE100 Simplified Technical English for all user-facing
  text, docs and comments. Say "Swift implementation", never "pure Swift".
  Plain terms ("ICU reference answers", not "oracle"). Report failures and
  wrong conclusions plainly, and correct your own wrong numbers at once.

**How to measure:**
- **Full matrix:** `ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2
  ICU_BUILD=$ICU_SRC/icu4c/source caffeinate -i /Users/dragan/Projects/dra8an/swift-foundation-collation/Collation/Tools/run_benchmarks.sh 3`
  (about 6–8 minutes with the 14 Table 2 APIs). Run it in the MAIN tree: it
  builds BenchFoundation with `-no-whole-module-optimization`, which works
  there only because the swift-syntax objects are cached (see below). Gates
  (2026-10-21, run B): system-ICU `localizedCompare` about
  194/365/369/300/494 (the long-term reference; run B read 196/363/370/301/505);
  ICU C compare about 9.5/10.1/40.8/29.7/172.0 and
  sortKey about 106.1/122.1/119.3/369.6/154.7. Record run B in Docs/21 (and
  START HERE, the runbook ratio line, §51). **Start every build script with
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
- **Foundation (Table 2) A/B:** `python3 Collation/Tools/ab/foundation_ab.py
  <base BenchFoundation> <variant> 5` (edit its `rows` list for the rows you
  need). A FRESH release build with `-no-whole-module-optimization` fails in
  swift-syntax ("unable to open dependencies file") — so for an A/B, build
  BOTH sides with normal WMO into fresh scratch paths (`swift build -c release
  --product BenchFoundation --scratch-path .build-wmo` here, `--scratch-path
  .build-bf` in the worktree; the runbook allows WMO on this machine). For a
  placement check, add `-Xswiftc -Xllvm -Xswiftc -align-all-functions=6` and
  other fresh scratch paths on both sides (a full build, ~5 minutes each).
- **Two build modes, and why both matter for Table 2 work:** the matrix and
  the instruction counts of §51 (o) used the `-no-WMO` BenchFoundation (main
  tree, `.build/out/Products/Release/BenchFoundation`); the A/Bs use WMO
  builds. With WMO and SwiftPM's cross-module optimization, a generic
  non-`@inlinable` function MAY be specialized for the bench's types, so a
  cost seen in the `-no-WMO` count may be smaller or absent in the WMO A/B.
  Real clients of the shipping framework (library evolution) do NOT get such
  specialization, so the `-no-WMO` build is the closer model of them. Count
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
- **Ladders** (`build_sk_ladder.sh`, `build_cmp_ladder.sh`, thai-ladder,
  disc-probe): they copy the engine sources and widen private members in the
  copy. **Build all four after any change to an internal signature** — C4
  broke two of them unnoticed until the next round (§51 (h)).

**The ICU checkout is not 79.0.1.** `~/Projects/Unicode/icu-DraganBesevic-2`
is on the CLDR 49 integration branch with ICU 79.1 and Unicode 18 data. Its
speed equals 79.0.1, so Table 1 stays comparable, but its KEYS differ from
our bundled 79.0.1 data. **Never generate golden files from it.** In that
checkout, build and test in-source only, never `build/icuhost` (see
`~/CLAUDE.md`).

**The code as it is now (details in §51):**
- **compare:** `compare(_:_:options:)` with `compareFastPath` force-inlined
  (§51 (i), ascii/latin −22%). The guard compares the options as one 64-bit
  pattern (`bits(of:)`, `optionBitsAreExact`; §51 (g)). `fastLatinUTF8` does
  the prefix scan and calls `CollationFastLatin.compareUTF8`; on a bail,
  `quickCJKDispatch`, then `restartScalarCount` (ICU's backup rule on the
  pinned bytes, §51 (l)) hands a restart count to `compareSlowPath` →
  `compareBody(restart:)`. Identical strength first tries
  `identicalStrengthTertiaryPass` (§51 (o)). `RestartSafety` has a 768-byte
  table below U+0300 and a two-level BMP table above it; pointer callers use
  the static `isUnsafe(_:_:numeric:)` (no struct copy; §51 (d)).
- **sortKey:** `ScratchBuffers.resetCollectAndWriteKey` runs reset, CE
  production and the writer under ONE access scope; the writer builds the
  whole key in its region and writes it with one `replaceSubrange` (§51 (j)).
  CEs live in `CEBuffer` (a `~Copyable` buffer with an explicit count; §51
  (h)); `ScratchBuffers.left/right` are `UnsafeMutablePointer<CEIterator>`,
  reached through `.pointee` — no dynamic exclusivity checks (§51 (k)).
- **Creation and caches:** `CollationData.root()`, `rootICU4X()` and
  `NormalizationData.standard()` are parsed once per process (`static let`);
  `RootCollator()` and `RootCollator(tailoringNamed:)` share one Storage per
  name (§51 (e)). `FastLatinCache` is lock-free for readers, keyed by
  `CollationFastLatin.primariesKey` (at most 10 keys; §51 (e), (g)).
- **Tests added this round:** RestartSafetyTests, CollationConcurrencyTests
  (also run under `swift test --sanitize=thread --scratch-path .build/tsan`),
  CollationOptionsBitsTests, RestartBackupTests, IdenticalStrengthTests.
  Tests that read the current locale heavily must run on the preferences
  actor (`usingCurrentInternationalizationPreferences`): the test-only
  `LocaleCache.resetCurrent(to:)` races with concurrent readers (§51 (o)).

**DONE 2026-10-21 (the task agreed on 2026-10-20): the generic String
conversion in the `localized*` String methods — §51 (p).** The eight
collation wrappers in `StringProtocol+Locale.swift` convert their arguments
with `_collationString` (the stdlib's `_specialize(_:for:)`: a metatype
compare, no generic `String.init`) and call fileprivate non-generic `String`
methods; the range rebase skips String receivers and maps UTF-8 offsets for
the others. The cost was present in the WMO build too (cross-module
optimization did not specialize the methods). Counts: −11..−27% per call
(compare and range methods), −3..−8% (contains, `localizedStandardRange`).
A/B against `4c24d059` (WMO pair): compare rows −12..−28%, search rows
−4..−16%, a matched `range(of:)` −53% (String) / −31% (Substring), all 5/5;
sort controls flat. Suite 1544/129.

**Open items, in order:**
1. ~~Run the full matrix to record (l), (o) and (p).~~ DONE 2026-10-21
   (Docs/21, run B; runs A and B agree).
2. ~~The FIRST `RootCollator()` in a process takes 7–22 ms — split it.~~
   DONE 2026-10-21, §51 (q): ~4.5 ms of it is the process's one-time
   CFBundle and localization setup (an app pays it at launch), ~1.3 ms our
   bundle open and lookup, ~0.9 ms our data work. The resources are now
   found by path (`collationResourceURL`): cold 6.8 → 3.7 ms, after an
   app's launch 2.3 → 2.2 ms. Left: the bundle open (~0.9 ms, SwiftPM's
   accessor) and the data read and parse (~0.75 ms; mapping the file is
   the next candidate).
3. ~~§51 (o) left about +1 ns on two Table 2 rows~~ CLOSED 2026-10-21: in
   the new matrix `localizedStandardCompare` latin (65 ns) equals
   `localizedCaseInsensitiveCompare` latin (65), and the options compare
   latin (91) has the same latin/ascii step as the other rows.
4. Writer and CE-production instructions. DONE 2026-10-21 for the writer
   (§51 (r) level cursors, (s) a specialization for the default options)
   and for ASCII in CE production (§51 (t): runs of simple ASCII scalars in
   one loop; sortKey ascii −14%, paths −26%, others within ±1–2%). Thai in
   the same run was REJECTED (§51 (u)). CJK: a fast path for computed Han
   primaries (§51 (v), sortKey cjk −8%). Combining marks: a fast-path
   table (§51 (w), sortKey latin −5%; thai compare +0.5..+0.8%). Left: NFD's
   decomposition of precomposed letters (~119 per accented letter), and
   the run-time writer path for non-default options. A/B every variant; the
   counts pointed the wrong way in (r).
5. A non-throwing `compare` (~0.5 ns per call) changes the public API — the
   user's decision.
6. A Substring argument still pays its copy into a String (~293
   instructions per argument pair plus ~90 of reference counting; in the
   A/B a Substring compare took 76–81 ns against 40 ns for Strings, ascii)
   because the engine entries take `String`; removing it needs engine
   entries for Substring or UTF-8 buffers — the user's decision (§51 (p)).

**Do not redo (measured and rejected; details in §51 and §49/§50):** tighter
per-CE byte bounds (UNSAFE); `RestartSafety` by value out of a raw pointer;
the `takeScratch` hot/cold split; golden keys from ICU 79.1; adding cost to
the ICU harness; the writer specialized for default options (W3a, worse);
inlining `compareUTF8` into the entry (worse); a forward single-pass restart
count (worse); Fix B (dropped); a one-slot or locked `FastLatinCache`; a cache
key of the whole options word (fills up); merging the identical-strength pass
into the options byte pass (+1–3% on common rows); Thai scalars in the
ASCII bulk run (§51 (u): no thai gain, ascii/latin/paths +2–5%); any
FoundationEssentials change.

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
