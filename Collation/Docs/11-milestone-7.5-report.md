# Milestone 7.5 Report: ICU Test-Suite Port + Performance Round 1

> In progress; round 1 completed 2026-06-11. Companion to the outcome note in
> `04-milestone-plan.md`. Previous report: `10-milestone-7-report.md`.

## Why this milestone exists

M8 (Foundation integration) is on hold awaiting external input. Two
high-value tracks remain fully in our control: porting ICU4C's own collation
test suites — so the port is validated by the tests ICU itself must pass, not
only by differential agreement — and the performance hardening M6 deferred.

## Track 1: ICU's test suites

### Inventory (what ICU4C has)

| Suite | Kind | Status here |
|---|---|---|
| `ucaconf.cpp` + CollationTest_*_SHORT | UCA conformance | **ported (M6)** |
| `collationtest.cpp` + collationtest.txt | curated data-driven | **ported (this round)** |
| `thcoll.cpp` TestDictionary + riwords.txt | exhaustive Thai dictionary | **ported (this round)** |
| `mnkytst.cpp` (monkey) | randomized vs ICU | equivalent already (fuzz keys, M6) |
| `regcoll.cpp`, `cmsccoll.c` | regression cases | backlog (non-rule cases) |
| `encoll/decoll/escoll/ficoll/frcoll/jacoll/trcoll/lcukocol/currcoll/g7coll` (+ c variants) | classic locale suites | backlog (mechanical array extraction) |
| `apicoll`, `itercoll`, `svccoll`, `ssearch` | API/iterator/service/search | mostly out of scope (different API surface) |
| rule-based sections everywhere | need runtime rule builder | out of scope until a builder exists |

### The data-driven runner (`DataDrivenTests.swift`)

Ports `CollationTest::TestDataDriven` over `collationtest.txt` (bundled):
section directives (`@ root`, `@ locale`, `@ rules`, `% attribute=value`,
`* compare`), relations `=`, `<`, `<1`, `<2`, `<c`, `<3`, `<4`, `<i`, ICU
string unescaping (`\\uXXXX`, `\\UXXXXXXXX`, `\\xHH`, surrogate-pair
combining). Checks per line, mirroring `checkCompareTwo`:
- `compare(prev, cur)` and the reverse direction;
- sort keys order identically, and for `<N` relations the **level of the
  first key difference** (count of 01 separators, with the case slot skipped
  when caseLevel is off) equals N;
- NFD-normalized inputs produce the same results and identical keys.

Coverage: 300 relation lines run. Skipped, with counts asserted in the test
output: 109 `@ rules` sections (no runtime rule builder — deliberate), 5
`% reorder` sections (reorder-table *generation* unsupported; data-supplied
reordering is supported), locales not bundled or with unsupported keywords
(`kk-false` cannot be honored: normalization can't be turned off in this
design), 6 unpaired-surrogate lines (unrepresentable in Swift Strings).

To serve the file's locale sections, the bundled tailorings grew to 15:
added th, fi, es, ko, fr (settings-only), zh-stroke (228 KB).

### The bug it found

`<i` relations among strings containing U+FFFE failed: on the **identical
level**, U+FFFE must rank as a merge separator — between end-of-string and
all real code points (`compareNFDIter`: end = −2, U+FFFE = −1) — not at its
code point value. Our identical-level tiebreaker compared raw scalar values.
Fixed in `RootCollator.compare`. Notably: 2.36M differential comparisons, the
conformance files, and 52k fuzz keys had never hit this case — the curated
file found it in 300 lines. That is exactly why porting ICU's own tests
matters.

### Thai dictionary (`ThaiDictionaryTests`)

`riwords.txt` (~31k Thai words in dictionary order, bundled): every adjacent
pair must compare ascending under the th tailoring, by `compare()` and by
sort keys. Passes.

## Track 2: Performance round 1

Three changes, all behavior-neutral (full suite green after each):

1. **NFD fast path**: between reorderable units, a bare starter with no
   canonical decomposition is a hard reordering boundary and is emitted
   directly — no unit buffer, no marks handling. Covers ASCII (`< 0xC0`
   unconditionally) and, via ccc + decomposition lookups, CJK and most
   letters. Also hoisted the per-refill decomposition scratch buffer into the
   iterator.
2. **CE-iterator lookahead bypass**: the lookahead buffer is only needed
   during contraction/digit matching; the common path now pops scalars
   straight from the NFD iterator.
3. **Canonical-equality shortcut**: Swift `String ==` is canonical
   equivalence, which implies equal CEs and equality at every strength —
   `compare` returns `.same` immediately for equal strings.

Numbers (release, same harness as M6; ICU 79 for reference):

| corpus | compare before → after | ICU | sortKey before → after | ICU |
|---|---|---|---|---|
| ASCII | 2225 → **1225 ns** | 16 ns | 3716 → **2734 ns** | 198 ns |
| Latin | 2344 → **1571 ns** | 17 ns | 3697 → **3499 ns** | 210 ns |
| CJK | 2502 → **1410 ns** | 73 ns | 3137 → **2334 ns** | 229 ns |

Cumulative since the first (pre-lazy) baseline: ASCII compare 7437 → 1225 ns
(6.1×). The remaining ~75× gap to ICU on ASCII compare is structural and
known: ICU's identical-prefix skip and fast-Latin table compare code units
with zero allocation, while we still construct two iterators (a handful of
array allocations) per compare. Next levers, in expected-impact order:
buffer/iterator reuse across compares (API shape question), the
identical-prefix skip (needs normalization safety markers from the planned
trie-value data format), Span-based data access to eliminate bounds checks.

## Round 2: classic locale suites + regression cases (same day)

- **Locale suites** (`LocaleSuiteTests.swift`): encoll, cdetst, cestst,
  cfrtst, cjaptst, cturtst, ficoll, lcukocol, currcoll. The case arrays are
  extracted mechanically from the C sources
  (`Tools/extract_locale_suites.py` -> `locale-suites.json`) — no hand
  transcription; the loop logic (which case indexes at which strength,
  pairwise bug lists, full expected-order matrices, ja's caseLevel) is
  reimplemented per suite from the C code. ICU's `doTest` semantics are
  preserved: both directions plus sort-key order. All 9 suites pass; the
  cdetst "doubt in primary here" cases and the fr-CA acute matrix (backwards
  secondary) behave exactly as ICU expects.
- **Regression cases** (`RegressionTests.swift`): 13 portable
  CollationRegressionTest cases extracted (`Tools/extract_regcoll.py` ->
  `regcoll.json`), including the fr-CA (4062418, 4066696) and da_DK
  (4087241) cases that an earlier extractor draft misattributed to root —
  the failures were the port working correctly against wrong expectations.
  17 cases skipped with recorded reasons: 5 build collators from rule
  strings, others exercise the CollationElementIterator API, clone/identity
  behavior, or a normalization-off phase (4114077's OFF array is excluded;
  its ON array runs).
- **Another data-format fix**: ko.bin ends its indexes[] at slot 13 (no
  contexts entry); the parser's minimum-indexes guard was too strict.
  Korean — with its 232 KB tailoring and script reordering — now loads and
  passes.

## Round 4: performance round 2 — buffer/iterator reuse (2026-06-12)

(Round 3 — cmsccoll.c non-rule cases — is summarized in the outcome note in
`04-milestone-plan.md`.)

Round 1 left compare() building two full iterator stacks per call: each side
allocates the CE buffer and, off the ASCII fast path, the NFD unit/marks
buffers; sortKey() additionally grows the key and four per-level buffers from
empty every call. ICU4C avoids all of this with stack buffers, which Swift
arrays cannot express — the equivalent is reuse.

**Design.** `RootCollator` keeps a `ScratchPool`: a small lock-guarded pool
(capacity 4) of `ScratchBuffers` sets, each holding two `CEIterator`s (with
their fused-NFD front ends), the sort key byte buffer, the four
`SortKeyLevel` buffers, and the identical-level scalar buffer. A call checks
a set out, `reset(...)`s it — `removeAll(keepingCapacity:)` throughout — and
returns it on exit, so steady-state calls run without heap allocation once
the buffers reach working size. Properties preserved:

- public API unchanged; `RootCollator` stays `Sendable` (the pool is
  lock-guarded, and copies of a collator share it);
- concurrent calls beyond the pool capacity just allocate a fresh set;
- the sort key level buffers are *swapped* in and out of
  `writeSortKeyUpToQuaternary` (not copied) so appends never copy-on-write;
- `sortKey` builds into the reused buffer and copies out right-sized — one
  exact-size allocation instead of a grow-realloc chain.

**Numbers** (release, same harness; ICU 79 re-measured the same day):

| corpus | compare before → after | ICU | sortKey before → after | ICU |
|---|---|---|---|---|
| ASCII | 1247 → **~690 ns** | 16 ns | 2686 → **~2000 ns** | 202 ns |
| Latin | 1652 → **~735 ns** | 27 ns | 3550 → **~2400 ns** | 221 ns |
| CJK | 1399 → **~870 ns** | 74 ns | 2262 → **~1620 ns** | 227 ns |

ASCII compare gap to ICU: ~78× → ~43×. Cumulative since the pre-lazy
baseline: 7437 → ~690 ns (10.8×). The remaining gap is compute, not
allocation: per-scalar trie lookups with bounds checks, and no
identical-prefix skip. Next levers unchanged: identical-prefix skip (needs
normalization safety markers from the planned trie-value data format),
Span-based data access.

## Round 5: identical-prefix skip (2026-06-12)

The plan expected this lever to wait for the single-trie nfd.bin rework
("normalization safety markers"). Investigating ICU4C's actual mechanism
(`RuleBasedCollator::doCompare` + `CollationData::isUnsafeBackward`) showed
the data is already in hand:

- ICU's "UCol" binaries serialize the **unsafe-backward set** (USerializedSet
  wire format at indexes slot 14): characters in contraction suffixes and
  other restart hazards, computed by ICU's builder. Our reader now parses it
  into a sorted boundary list (`CollationData.unsafeBackward`); tailoring
  files carry a delta over the root set, so lookups check both.
- ICU folds `[:^lccc=0:]` into the set at load time; we query lead-ccc at
  runtime from the existing normalization data (`NormalizationData.leadCCC`).
- Digits under numeric collation are recognized by their CE32 tag, like
  `CollationData::isDigit`.

**The skip** (in `compare()`): walk both scalar streams while equal; if the
first differing scalar on either side is a safe restart point, both CE
iterators start there (`reset(skippingFirst:)` fast-forwards the source
iterator), and the identical level — like ICU's — also runs from the skip
position. On an *unsafe* boundary we compare from the start: ICU instead
backs up partially, but it can do so because its iterators read the full
string — prefix (precontext) matches reach back into the skipped prefix,
which our streaming iterator cannot. Hence one deliberate strengthening:
characters whose mapping carries a PREFIX_TAG are themselves unsafe restart
points here. Skipping less than ICU is always sound; skipping differently
*more* than ICU would not be.

**Verification.** The differential matrices (every ordered pair of the
328-string corpus × 13 option sets × 2 data variants ≈ 2.8M comparisons vs
ICU's verdicts) and the full ported suites all pass unchanged. New
`PrefixSkipTests` pin the dangerous boundaries — digit runs under numeric
("a12" vs "a2"), the ja prolonged sound mark (precontext), combining marks
incl. canonically-equivalent mark order, Thai prevowel contractions, Hangul
and supplementary-plane prefixes, ignorable tails — against sort keys, which
never skip and are byte-identical to ICU's. Sensitivity-checked: disabling
the safety predicate makes these tests fail (52 failures). Suite total:
**48 tests / 16 suites**.

**Numbers** (release; medians of repeated runs on a loaded machine). New
corpus `bench-paths.txt`: 439 sorted file paths, average 26-scalar shared
prefix — adjacent-pair comparison of sorted data, the workload this lever
targets:

| corpus | compare before → after | ICU |
|---|---|---|
| paths (prefix-heavy) | 10532 → **~1060 ns** | 48 ns |
| ASCII | ~690 → ~697 ns | 16 ns |
| Latin | ~735 → ~768 ns | 27 ns |
| CJK | ~870 → ~863 ns | 74 ns |

10× where prefixes are shared; ≤4% walk overhead where none are. sortKey is
unaffected (it never skips). The dominant remaining gap on no-sharing ASCII
is fast-Latin (unported, ICU4X precedent) and per-scalar data access — the
Span lever is next.

## Status

Rounds 1–5 done: 48 tests / 16 suites green, all perf work verified against
the full suite. Remaining backlog in the plan: apicoll where applicable,
g7coll rule-free parts, Span-based data access.
