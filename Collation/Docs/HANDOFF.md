# HANDOFF — Cold-Start Guide for the Collation Project

> Written 2026-06-12, last updated 2026-06-22, for a fresh session with no
> conversation context. Read this first, then `04-milestone-plan.md` for
> status, then the numbered docs as needed.

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
  Technique log: `optimization-targets.md` — read THE ALLOCATION/
  RESOLUTION HUNT note at the top before any perf work, then §20
  (steps 6–8), §27, §29–§45 and the audit list;
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

#### Apple Silicon (macOS 26, quiet machine, 10000 reps, lower cluster)

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
FoundationInternationalization) · HANDOFF (this file)

Convention: every milestone/round updates doc 04's table + outcome note and
gets a detailed report; decision records for surprising cuts; commit
messages carry the full summary (no attribution line!).
