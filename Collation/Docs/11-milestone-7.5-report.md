# Milestone 7.5 Report: ICU Test-Suite Port + Performance Round 1

> Round 1 completed 2026-06-11; milestone complete 2026-06-12. Companion to
> the outcome note in `04-milestone-plan.md`. Previous report:
> `10-milestone-7-report.md`. For a standalone, consolidated performance
> analysis (methodology, the full journey, cost anatomy, the residual gap),
> see `13-performance-analysis.md`; this report keeps the per-round narrative.

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

## Round 6: trivial data access (2026-06-12)

The lever the plan called "Span-based data access". Profiling (macOS
`sample` over the bench) showed the dominant cost was not bounds checks but
**reference counting**: `CEIterator.lookup` returns its `CollationData` by
value once per scalar, and because the struct held eight Swift arrays, every
copy was eight retains + eight releases. Three fixes, in impact order:

1. **One storage owner, raw views** (`DataStorage.swift`): a final class
   owns the parsed memory (allocated/copied once at parse time, freed in
   deinit); `CollationData`, `NormalizationData`, `UTrie2`, and `UCharsTrie`
   now hold `UnsafeBufferPointer` views into it. Copying a data struct costs
   one retain instead of eight, `UCharsTrie` state snapshots (discontiguous
   contraction matching) are fully trivial, and buffer reads lose their
   bounds checks in release builds — the data files are version-pinned,
   parse-validated, and exercised by the conformance suites, the same trust
   ICU4C places in its own arrays. The structs become `@unchecked Sendable`
   (immutable after init).
2. **`CollationDataView`**: even one retain per lookup survived, because
   passing `self.data` alongside the iterator's `inout self` forces a
   defensive copy that the optimizer cannot elide. The per-scalar dispatch
   (`appendCEs` and friends) now works on a fully trivial view struct
   (pointers + ints, zero ARC); the iterator's strong references keep the
   memory alive.
3. **Empty-singleton `removeAll`**: arrays initialized from `[]` share the
   global empty-array singleton, which is never uniquely referenced — so
   `removeAll(keepingCapacity:)` on a never-grown buffer took the
   copy-on-write slow path every time, including once per scalar in
   `appendMore`. All reset-path `removeAll`s are now guarded by `isEmpty`.
   Also: `ScratchPool` uses `os_unfair_lock` on Darwin (NSLock elsewhere).

**Numbers** (release, medians of repeated runs; "before" = round 5):

| corpus | compare before → after | ICU | sortKey before → after | ICU |
|---|---|---|---|---|
| ASCII | 697 → **~239 ns** | 16 ns | ~2100 → **~785 ns** | 202 ns |
| Latin | 768 → **~346 ns** | 27 ns | ~2400 → **~1266 ns** | 221 ns |
| CJK | 863 → **~407 ns** | 74 ns | ~1650 → **~895 ns** | 227 ns |
| paths | 1057 → **~603 ns** | 48 ns | ~7800 → **~1560 ns** | 672 ns |

ASCII compare gap to ICU: ~44× → **~15×**; ASCII sortKey ~4×, paths sortKey
~2.3×. Cumulative compare since the pre-lazy baseline: 7437 → 239 ns (31×).
Remaining known levers, both currently out of scope: the single-trie nfd.bin
(one lookup per scalar instead of two binary searches) and fast-Latin
(a deliberate cut, ICU4X precedent — reversing it is a decision, not a task).

## Round 7: the last test scraps — g7coll + apicoll (2026-06-12)

**g7coll** (`G7CollationTests.swift`; `Tools/extract_g7coll.py` →
g7coll.json): TestG7Locales checks the pairwise order of 15 fixed strings
for the eight G7 locales (en×3 / fr_FR / de / it → root; fr_CA, ja →
bundled tailorings). The demo tests and remaining result rows are
rule-based — out of scope (doc 12). Two findings, both courtesy of the
investigate-before-fixing rule:

1. ICU's per-character comments disagree with its code units in places —
   the test strings are really "blabkbirds"/"blabk-bird" etc. Mechanical
   extraction is faithful to the values ICU tests; hand transcription from
   the comments would have produced wrong fixtures.
2. The first port attempt set quaternary strength + alternate=shifted, as
   the test body appears to do — and every locale failed on exactly one
   pair ("blabk-birds" vs "blabkbird", whose order depends on whether the
   hyphen is primary-visible). Reading further: after setting those
   attributes, ICU *replaces* the collator with one rebuilt from its rule
   string, silently resetting the attributes to defaults — the known issue
   ICU-10671 ("TestG7Locales does not test ignore-punctuation") annotated in
   the test itself. The expected orders encode default options; the port
   runs them that way and matches ICU's effective behavior.

**apicoll** (`ApicollTests.swift`): the behavioral fraction of
CollationAPITest, inlined (a handful of literals, cited per source
function): TestProperty's comparisons, TestCompare's strength behavior
("Abcda"/"abcda": tertiary > / secondary = / primary =), TestCollationKey +
TestSortKey key properties — the empty string's tertiary key is exactly
`01 01 00`, a completely-ignorable string (U+0001, U+034F) keys equal to
empty, lower-strength keys prefix higher-strength keys — and
TestMaxVariable's currency behavior under shifted. Everything else in
apicoll exercises C++ API surface with no counterpart in this port
(constructors, clone/operators, registry, display names, rule access,
element iterators, subclassing).

## Round 8: single-trie nfd.bin (2026-06-12)

The normalization container planned since M2 ("the ICU4X single-trie design
remains the target"), now decided and done. nfd.bin v2:

- GenNormData packs one 32-bit value per scalar — ccc (bits 0..7), lead ccc
  (8..15), decomposition length (16..18, with 7 as the Hangul sentinel) and
  decomposition-buffer offset (19..31) — into a flat two-level trie:
  17408 index entries (scalar >> 6) pointing at deduplicated 64-value
  blocks (186 blocks). 96 KB on disk (was 34 KB); the sorted-array +
  binary-search container and its three lookup paths are gone.
- One lookup (two loads) replaces two ~11-probe binary searches per scalar.
  Value 0 means inert (ccc 0, no decomposition), so the NFD bare-starter
  fast path is a single read (`isInert`); lead-ccc — added in round 5 for
  the identical-prefix skip — comes from the same read.
- The reader validates the index entries and every value's offset/length
  once at parse time, keeping the unchecked buffer reads in bounds for any
  scalar 0...0x10FFFF.

Numbers (release, medians): compare latin 346 → **~308 ns** (-11%), cjk
407 → **~345 ns** (-15%); sortKey latin ~1266 → **~1038 ns**, cjk ~895 →
**~723 ns** (both ≈ -18%). ASCII and the paths corpus are unchanged within
noise — scalars below U+00C0 never touch the normalization data. Full suite
green after regeneration; same 968 ccc entries and 2081 decompositions feed
the new format.

## Round 9: fast Latin (2026-06-12) — a scope-cut reversal

"Fast-Latin not ported (ICU4X precedent)" had been a recorded cut since the
strategy phase. Reversed by user decision once investigation showed the
balance had changed: the precompiled mini-CE tables (CollationFastLatin
format version 2) already ship inside our bundled binaries — index slot 15,
the same situation as the unsafe-backward set in round 5 — so no builder
and no new CLDR tooling is involved; the work is a read-side port.

**What was ported** (`CollationFastLatin.swift`, from
i18n/collationfastlatin.{h,cpp}):
- `getOptions`: precomputes 384 primaries for one options word, applying
  variable-top (from the table header) and script reordering; returns
  unsupported (-1) for reorderings that disturb the groups below Latin.
- `compare`: the multi-level loop over 16-bit mini CEs — primaries with
  variable handling, secondaries, optional case level, tertiaries
  (caseFirst transforms), quaternaries — walking the scalar streams once
  per level. Bail-outs route to the regular pipeline: out-of-range
  characters, mappings the table cannot encode (it supports one-character
  contraction suffixes and two-CE expansions), digits under numeric
  collation, secondary differences under backwards-secondary.

**Integration**: after the identical-prefix skip, when both remainders
start within U+0000..U+017F (ICU's same gate). Adaptations for our
options-per-call API: `icuOptions` now encodes numeric and maxVariable
(completing the word — it is the cache key), and the per-options setup is
cached as an immutable snapshot (`FastLatinSetup`) behind a tiny lock on
the collator, so a bail-free compare never touches the scratch pool.
Reader: data files without a table or with a different format version get
an empty table (never an error); tailorings fall back to the base's table,
as in CollationDataReader.

**Verification**: every existing compare-based suite now exercises the
integrated fast path — the differential matrices (~2.8M pairs × 13 option
sets vs ICU verdicts), key-agreement tests, conformance, locale suites.
New `FastLatinTests` pin the machinery itself: the path engages (real
results, not bail-outs) for plain text, bails exactly where required
(numeric digits, backwards-secondary differences, out-of-range), and
shifted-variable punctuation behaves at tertiary and quaternary strengths.
**59 tests / 19 suites green.**

**Numbers** (release, medians):

| corpus | compare before → after | ICU | gap |
|---|---|---|---|
| ASCII | 239 → **~101 ns** | 16 ns | ~6.3× |
| Latin | 308 → **~114 ns** | 27 ns | ~4.2× |
| paths | 603 → **~412 ns** | 48 ns | ~8.6× |
| CJK | ~345 ns (unchanged) | 74 ns | ~4.7× |

sortKey is unchanged (fast Latin is compare-only, as in ICU). Cumulative
ASCII compare since the pre-lazy baseline: 7437 → ~101 ns (74×).

## Round 10: fast Latin over raw UTF-8 (2026-06-12)

Round 9 left ASCII compare at ~101 ns vs ICU's 16. Deletion experiments
showed the remaining cost was not the mini-CE arithmetic but the character
feed and per-call glue: reading scalars through
String.UnicodeScalarView.Iterator (a UTF-8 decoder with representation
branches) where ICU's ucol_strcollUTF8 reads raw bytes. The fix is the rest
of the same ICU file: **compareUTF8**.

- `compare()` first tries `utf8.withContiguousStorageIfAvailable` on both
  strings (native Swift strings qualify; small strings are spilled to the
  stack by the stdlib). On the bytes: binary equality and the
  identical-prefix scan are one memcmp-style loop, the restart boundary
  backs up over trail bytes (ICU's UTF-8 doCompare), the safety check
  decodes just the two boundary scalars, and `CollationFastLatin.compareUTF8`
  reads characters as raw bytes — ASCII one load, U+0080..U+017F a
  0xC2..0xC5 lead+trail pair, punctuation a three-byte sequence. Identical
  strength and non-contiguous strings keep the scalar paths; every bail-out
  still lands in the regular pipeline.
- Three profile-driven structural lessons, recorded because they are
  Swift-specific and will matter to future fast paths:
  1. **Closures must not capture the collator.** The contiguous-storage
     closures capturing `self` copied the struct per call — one retain per
     stored reference, visible as `initializeWithCopy for RootCollator`.
     The byte path is a static function taking trivial parameters.
  2. **Views are stored, not rebuilt.** `base?.field` projections copy the
     optional's payload (+1 retain each); the fast-Latin table and the
     restart-safety views (RestartSafety, NormalizationDataView) are built
     once at collator init.
  3. **Per-options setup resolves lazily, inside the eligibility gate.**
     Resolving it eagerly made every CJK compare pay the cache lock for a
     path that always bails; the closure returns a needs-setup sentinel on
     a cache miss (once per options change) and the caller retries.

Numbers (release, medians; ICU 79 re-measured side by side):

| corpus | compare round 9 → 10 | ICU | gap |
|---|---|---|---|
| ASCII | 101 → **~79 ns** | 16 ns | ~4.9× |
| Latin | 114 → **~79 ns** | 21 ns | ~3.8× |
| paths | 412 → **~158 ns** | 58 ns | ~2.7× |
| CJK | 345 → ~365 ns | 79 ns | ~4.6× |

Latin now costs the same as ASCII (the two-byte assembly is two ops). CJK
pays ~6% for attempting the byte path before bailing. What remains is
irreducible per-call cost for a value-type String API: the small-string
stack spill that contiguous access requires (~17 ns), the setup-cache lock,
and the closure entries. Cumulative ASCII compare across the whole effort:
7437 → ~79 ns (94×).

## Status

**Milestone 7.5 complete.** Rounds 1–10: every portable ICU collation test
suite is ported — **61 tests / 19 suites green** — and the perf track is
finished: compare within 2.7–4.9× of ICU4C on every corpus (ASCII ~79 ns
vs 16), sort keys 2.3–4× — all byte-identical to ICU's. The runtime rule
builder remains the one deliberate cut (doc 12). Next milestone: M8 (on
hold, awaiting maintainer/community input).
