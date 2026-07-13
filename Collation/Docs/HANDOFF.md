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
  Technique log: `optimization-targets.md` §20 (steps 6–8), §27, §29–§30;
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

**Compare (ns/op):**

| corpus | ours | ICU 79 | ratio |
|--------|------|--------|-------|
| ASCII  | ~24  | ~9     | 2.7×  |
| Latin  | ~25  | ~10    | 2.5×  |
| CJK    | ~130 | ~41    | 3.2×  |
| paths  | ~63  | ~30    | 2.1×  |
| Thai (th, sorted) | ~362 | ~190 | 1.9× |

**Sort keys (inout API, buffer reused):**

| corpus | ours | ICU 79 | ratio |
|--------|------|--------|-------|
| ASCII  | ~216 | ~103   | 2.1×  |
| Latin  | ~237 | ~123   | 1.9×  |
| CJK    | ~232 | ~124   | 1.9×  |
| paths  | ~546 | ~373   | 1.5×  |
| Thai   | ~316 | ~161   | 2.0×  |

**Foundation API integration vs system ICU (ns/op, Apple Silicon):**

What users actually call — our collator through Foundation APIs vs the
system NSString → CoreFoundation → ICU bridge:

| API | corpus | ours | system ICU | speedup |
|-----|--------|------|-----------|---------|
| `localizedCompare` | ASCII | 133 | 200 | **1.5× faster** |
| `localizedCompare` | Latin | 132 | 367 | **2.8× faster** |
| `localizedCompare` | CJK | 243 | 375 | **1.5× faster** |
| `localizedCompare` | paths | 172 | 304 | **1.8× faster** |
| `localizedCompare` | Thai | 483 | 496 | **1.0× (parity)** |
| `localizedStandardCompare` | ASCII | 141 | 201 | **1.4× faster** |
| `localizedStandardCompare` | Latin | 142 | 352 | **2.5× faster** |
| `localizedStandardCompare` | CJK | 251 | 366 | **1.5× faster** |
| `localizedStandardCompare` | paths | 194 | 326 | **1.7× faster** |
| `localizedStandardCompare` | Thai | 494 | 484 | **1.0× (parity)** |
| `compare(_:locale:)` | ASCII | 325 | 317 | **1.0× (parity)** |
| `compare(_:locale:)` | Latin | 309 | 484 | **1.6× faster** |
| `compare(_:locale:)` | CJK | 421 | 493 | **1.2× faster** |
| `compare(_:locale:)` | paths | 354 | 418 | **1.2× faster** |
| `compare(_:locale:)` | Thai | 671 | 642 | **1.0× (parity)** |
| `localizedStdContains` | ASCII | 444 | 999 | **2.2× faster** |
| `localizedStdContains` | Latin | 455 | 1445 | **3.2× faster** |
| `localizedStdContains` | CJK | 482 | 1280 | **2.7× faster** |
| `localizedStdContains` | paths | 492 | 963 | **2.0× faster** |
| `localizedStdContains` | Thai | 499 | 1367 | **2.7× faster** |
| `localizedCaseICmp` | ASCII | 137 | 198 | **1.4× faster** |
| `localizedCaseICmp` | Latin | 137 | 347 | **2.5× faster** |
| `localizedCaseICmp` | CJK | 244 | 364 | **1.5× faster** |
| `localizedCaseICmp` | paths | 176 | 308 | **1.8× faster** |
| `localizedCaseIContains` | ASCII | 445 | 1013 | **2.3× faster** |
| `localizedCaseIContains` | Latin | 455 | 1496 | **3.3× faster** |
| `localizedCaseIContains` | CJK | 483 | 1297 | **2.7× faster** |
| `localizedCaseIContains` | paths | 460 | 976 | **2.1× faster** |
| `localizedStdRange` | ASCII | 464 | 998 | **2.2× faster** |
| `localizedStdRange` | Latin | 479 | 1441 | **3.0× faster** |
| `localizedStdRange` | CJK | 504 | 1277 | **2.5× faster** |
| `localizedStdRange` | paths | 722 | 989 | **1.4× faster** |
| `range(of:locale:)` | ASCII | 361 | 323 | **0.9× (parity)** |
| `range(of:locale:)` | Latin | 655 | 790 | **1.2× faster** |
| `range(of:locale:)` | CJK | 687 | 585 | **0.9× (parity)** |
| `range(of:locale:)` | paths | 427 | 313 | **0.7× (behind)** |
| `range(backwards)` | ASCII | 361 | 324 | **0.9× (parity)** |
| `range(backwards)` | Latin | 663 | 830 | **1.3× faster** |
| `range(backwards)` | CJK | 682 | 596 | **0.9× (parity)** |
| `range(backwards)` | paths | 469 | 506 | **1.1× faster** |

Most Foundation string APIs are faster than system ICU. The two behind
are `range(of:locale:)` on CJK/paths (system uses Latin-1 byte encoding
advantage) and backward search (our implementation pre-produces all CEs
with no lazy bail-out). Direct collation arithmetic is 2–3× slower than
ICU's C code (Swift value-type overhead), but through Foundation APIs
we're faster because the system path pays the ObjC bridge cost.

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

#### Intel iMac (macOS 15, Swift 6.3.1 release) — confirmed 2026-06-19, updated 2026-06-22

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
swift test                      # full suite, ~5-20s (machine 1 reports 1488 tests / 119 suites)
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
