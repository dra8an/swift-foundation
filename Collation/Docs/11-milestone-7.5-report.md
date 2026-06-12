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

## Status

Round 1 done. Backlog for subsequent rounds is listed in the plan: regcoll +
cmsccoll regression cases, the classic locale suites via mechanical array
extraction, and the deeper perf levers above.
