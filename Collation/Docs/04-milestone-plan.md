# Milestone Plan: Pure-Swift UCA Collation

> Working plan for the port described in `03-swift-strategy.md`. Each milestone has a
> scope, a concrete deliverable, and verification criteria — "milestone N" in
> conversation refers to this document. Revise freely as reality intrudes.

## Status overview

| # | Milestone | Status |
|---|-----------|--------|
| 1 | Pipeline proof: primary-only root compare | **Done 2026-06-11** |
| 2 | Fused NFD decomposition + NFD-only data | **Done 2026-06-11** |
| 3 | Full level loop + settings | **Done 2026-06-11** |
| 4 | Contraction & prefix matching | **Done 2026-06-11** |
| 5 | Sort keys | **Done 2026-06-11** |
| 6 | Conformance & performance baseline | **Done 2026-06-11** |
| 7 | Locale tailorings | **Done 2026-06-11** |
| 7.5 | ICU test-suite port + performance round | **In progress** (2026-06-11) |
| 8 | swift-foundation integration | on hold (awaiting input) |

Standing rule for every milestone: differential testing against ICU 79 (machine-local
build at `~/Projects/claude/collation/icu-build`, outside this repo) is the
acceptance gate. New functionality ships with new ICU-reference coverage; existing golden
tests stay green.

---

## Milestone 1 — Pipeline proof (DONE)

**Scope.** Smallest vertical slice touching every layer: binary data → trie →
CE32 resolution → comparison → validation against ICU reference answers.

**Delivered** (2026-06-11, `Collation/` package):
- `CollationData`: reader for the "UCol" v5 binary format (`ucadata.icu`)
- `UTrie2`: serialized-form reader and code-point lookup
- `RootCollator`: primary-strength compare; CE32 tag dispatch covering simple,
  long-primary/secondary, Latin/32/64-bit expansions, digit, U+0000, Hangul
  (arithmetic Jamo), OFFSET (Han), implicit (unassigned); contractions/prefixes
  resolve to default CE32s (no context matching yet)

**Verification (passed).** 175-string corpus (ASCII, accented Latin precomposed +
decomposed, Greek, Cyrillic, Han, Hangul, kana, expansions, emoji, plane 16,
unassigned); full 175×175 pairwise matrix vs `ucol_strcollUTF8` at
`UCOL_PRIMARY`: 100% agreement. ICU and our Swift reader use byte-identical data.

---

## Milestone 2 — Fused NFD decomposition + NFD-only data

The architectural centerpiece, done early because every later milestone depends on
the iterator's shape (see `02-icu4x-strategy.md`). Adopts the ICU4X model:
decompose-as-you-iterate, no FCD, no canonical closure in data.

**Scope.**
- Offline data step: generate NFD-only root collation data (`genuca -X`; the repo
  also ships prebuilt `ucadata-*-icu4x.icu`) and normalization data
  (`icuexportdata` NFD tries, or an equivalent repackaging) from the local ICU
  checkout. Decide the container format here (raw ICU binaries vs repackaged).
- Runtime: rework the iterator front end into scalar stream → incremental NFD
  decomposition → ccc-ordered combining-mark buffer → CE lookup. One
  normalization-trie lookup should yield decomposition + ccc (+ safety markers),
  per the ICU4X trie-value design.
- Keep default-CE32 resolution for contexts (full matching is milestone 4).

**Deliverable.** `RootCollator` correct on arbitrary (including non-NFD) input;
normalization data reader usable independently of collation.

**Verification.**
- Canonical-equivalence property tests: NFC/NFD/mixed forms of the same text
  compare equal (Latin accents, Hangul, Tibetan composite vowels U+0F73/75/81,
  CJK compatibility ideographs).
- Differential matrix vs ICU regenerated with a corpus heavy in non-NFD text.
- Carry-over: milestone-1 suite still green on the new data.

**Open decision to settle first:** consume ICU's binary/TOML exports directly vs
define our own container. (Leaning: parse `genrb -X` TOML offline with a small
tool, emit a compact Swift-friendly binary; revisit when Foundation integration
nears.)

**Outcome (2026-06-11).** Delivered as planned, with these decisions:
- Normalization data is generated from ICU's `norm2/nfc.txt` (the gennorm2
  source format) by the `GenNormData` tool into `nfd.bin` (34 KB: full
  recursively-expanded decompositions + ccc; sorted arrays + binary search).
  This is a *provisional* container — the ICU4X single-trie design
  (decomposition + ccc + safety markers in one lookup) remains the target for
  the perf pass (M6). Hangul stays arithmetic.
- `NFDIterator` decomposes and canonically reorders (stable insertion sort by
  ccc per reorderable unit) in front of CE lookup; normalization cannot be
  turned off, matching ICU4X.
- BOTH data variants are bundled and continuously tested: regular
  `ucadata.icu` (closure) and `ucadata-icu4x.icu` (prebuilt genuca -X, NFD-only,
  no Hangul mappings — Jamo resolve via the trie after our decomposition). The
  icu4x variant passed the full differential matrix unmodified, empirically
  confirming the closure-free model. Default stays `ucadata.icu` until M4
  settles context matching against the icu4x contexts data.
- Verification: 205-string corpus (30 non-NFD/equivalence forms added),
  205×205 matrix vs ICU at primary strength, 100% on both variants; normalizer
  differentially tested against Foundation's NFD over ~13k scalars in
  normalization-stable blocks plus 432 combining-mark sequences.

---

## Milestone 3 — Full level loop + settings

**Scope.**
- Port `CollationSettings` (options word: strength, alternate shifted +
  maxVariable, case-first, case-level, backwards-secondary, numeric).
- Extend the iterator to full 64-bit CEs; port `CollationCompare`'s level loop:
  secondary (incl. French backwards within segments), case, tertiary (case-first
  transforms), quaternary (variable shifting).
- Numeric collation (CODAN digit-run CEs).

**Deliverable.** `compare()` honoring all strengths and the settings above
(API: an options struct on `RootCollator`).

**Verification.** Differential matrices vs ICU at each strength
PRIMARY→QUATERNARY and for each setting toggled (shifted, case-first upper/lower,
case-level, French, numeric with digit-heavy corpus, e.g. "item9" < "item10").
Script reordering is *out of scope* until tailorings (M7) unless trivially cheap.

**Outcome (2026-06-11).** Delivered as planned (commit history has details):
- `CollationOptions` mirrors the ICU options word; `CEIterator` produces full
  64-bit CEs (incl. CODAN numeric digit runs with one-scalar pushback);
  `CollationCompare` is a faithful port of `compareUpToQuaternary` over
  NO_CE-terminated CE arrays; identical strength adds an NFD code-point
  tiebreaker. Scripts data is now parsed for maxVariable→variableTop
  derivation (present in both data variants). Script reordering deferred to M7.
- Verification: 13 option sets checked against ICU reference answers (5 strengths, shifted ×2, case
  level ×2, case-first ×2, French, numeric) × 2 data variants × 239×239
  corpus = 1.49M comparisons, 100% agreement with ICU 79.
- Two findings worth recording: (1) ICU's root collator defaults to
  normalization OFF; since our implementation always normalizes (ICU4X
  model), the ICU reference run must set UCOL_NORMALIZATION_MODE=UCOL_ON or
  non-canonically-ordered marks compare differently. (2) A transcription
  error in CASE_AND_TERTIARY_MASK (0xc03f vs the correct 0xff3f =
  CASE_MASK|ONLY_TERTIARY_MASK) masked the NO_CE terminator to zero and ran
  the case-first tertiary loop off the array — caught by the caseFirst
  differential configs; masks are now derived, not transcribed.

---

## Milestone 4 — Contraction & prefix matching

The conformance-critical, fiddly one.

**Scope.**
- Port read-side `UCharsTrie` (the context data structure).
- Contraction matching over the M2 combining-mark buffer, including
  discontiguous contractions per UTS #10 S2.1 (ccc-based skipping with
  `most_recent_skipped_ccc` blocking, ICU4X-style) and `CONTRACT_HAS_STARTER`
  lookahead normalization.
- Prefix matching with the two-recent-characters back buffer (sufficient for all
  CLDR prefixes: single starter, or starter + kana voicing mark).
- Identical-prefix fast path *safety* rules if we add that optimization here
  (may defer the optimization itself to M6).

**Verification.**
- Targeted S2.1 cases: kana + U+3099/309A voicing, Tibetan, discontiguous
  combining-mark sequences with blocking and non-blocking ccc patterns.
- Differential matrix vs ICU on a context-heavy corpus.
- Remove the milestone-1 "default CE32" caveat from the code.

**Outcome (2026-06-11).** Delivered; details in `07-milestone-4-report.md`:
- Read-side `UCharsTrie` ported; being a Swift value type, copying the struct
  snapshots traversal state, replacing ICU's SkippedState save/replay.
- `CEIterator` gained a normalized lookahead buffer; contraction matching
  (contiguous longest-match + discontiguous per S2.1 with ccc blocking over
  the already-canonically-ordered stream) and prefix matching over the two
  preceding scalars (all CLDR prefixes fit). CONTRACT_NEXT_CCC /
  CONTRACT_TRAILING_CCC / CONTRACT_SINGLE_CP_NO_MATCH flags honored.
- Root data findings: exactly 4 prefix entries exist in root (Catalan/Greek
  middle dot after l/L); the vowel-dependent kana prolonged sound mark is the
  Japanese tailoring, not root. Tibetan 0F71+0F72/0F74/0F80 contractions and
  the equal-ccc blocking case are exercised and ICU-verified.
- Verification: corpus 239 -> 287 (kana, voiced kana, Tibetan incl. blocking,
  Thai, Cyrillic, Catalan l-middle-dot); 13 option sets x 2 data variants x
  287^2 = 2.36M comparisons, 100% agreement; targeted ContextTests prove the
  context paths fire (not just default-agree).

---

## Milestone 5 — Sort keys

**Scope.** Port `CollationKeys::writeSortKeyUpToQuaternary`: level buffers,
`0x01` separators, primary lead-byte compression, common-weight run compression
(sec/ter/quat), case level, shifted quaternaries, BOCSU identical level,
`0x00` terminator. Merge separator (U+FFFE) handling.

**Deliverable.** `sortKey(for:) -> [UInt8]` with the invariant
`memcmp(key(a), key(b)) == compare(a, b)`.

**Verification.**
- Property test of the invariant over all corpora (every pair, every strength).
- Byte-level comparison vs `ucol_getSortKey` where the data variants permit
  (same weights → keys should match byte-for-byte; investigate any divergence).

**Outcome (2026-06-11).** Delivered; ICU-exact:
- `SortKey.swift`: faithful port of writeSortKeyUpToQuaternary (level buffers,
  01 separators, primary lead-byte compression via compressibleBytes [now
  parsed from the data], common-weight run compression on sec/case/ter/quat
  with all three caseFirst tertiary variants, backwards-secondary segment
  reversal, shifted quaternaries) + BOCSU identical level over the NFD stream.
- `RootCollator.sortKey(for:options:)` public API.
- Verification: byte-for-byte identity with ucol_getSortKey for 13 option
  sets x 2 data variants x 287 corpus strings (reference keys generated by
  gen_golden.c into keys-<option-set>.txt), plus the defining invariant
  (byte-wise key order == compare()) over all 13 x 287^2 pairs. All exact on
  the first run.

---

## Milestone 6 — Conformance & performance baseline

**Scope.**
- Run the official UCA/CLDR conformance files
  (`CollationTest_SHIFTED`, `CollationTest_NON_IGNORABLE`) to green, plus a
  randomized fuzz harness (random scalar sequences, differential vs ICU).
- Benchmarks vs ICU (`ucol_strcoll`, `ucol_getSortKey`) on representative
  corpora (ASCII, Latin-1, mixed-script, CJK); first profiling pass
  (bounds-check elimination, buffer strategy, identical-prefix fast path).

**Deliverable.** Conformance suite in CI-runnable form; benchmark numbers
recorded in the docs; no conformance regressions tolerated afterward.

**Outcome (2026-06-11).** Delivered; details in `09-milestone-6-report.md`:
- Official UCA/CLDR conformance suite green: CollationTest_CLDR_SHIFTED_SHORT
  + NON_IGNORABLE_SHORT (433k lines, UCA 17), strength=identical, both data
  variants; compare() and sort keys agree on every adjacent pair. Lines with
  unpaired surrogates are skipped (Swift Strings cannot represent them; same
  property as ICU4X).
- Fuzz harness: seeded 2000-string corpus weighted toward trouble spots
  (Tools/gen_fuzz_corpus.py); ICU reference keys via gen_golden --keys-only;
  all 13 option sets x 2 variants byte-identical (52k keys).
- Benchmarks (Tools/bench, Sources/Bench vs Tools/bench_icu.c, release,
  this machine): after making compare() lazy (CEs generated on demand,
  3x gain), Swift compare ~2.2-2.4 us/op vs ICU 16-73 ns/op; sortKey
  ~3.1-3.7 us/op vs ICU ~200 ns/op. Remaining gap: per-compare allocations
  (iterator buffers) and no identical-prefix/fast-Latin paths -- deferred to
  M8 hardening with Span/InlineArray work.

---

## Milestone 7 — Locale tailorings

**Scope.**
- Offline: per-locale data via `genrb -X` from `data/coll/*.txt`; package
  root + tailorings in the chosen container.
- Runtime: tailoring data with base-fallback lookup (`FALLBACK_CE32` → root),
  per-locale default settings, metadata bits (e.g. Lithuanian dot-above,
  backwards-secondary for fr-CA), script reordering if deferred from M3.

**Verification.** Differential vs ICU with locale collators: de-phonebook (ä=ae),
sv (å/ä/ö after z), fr-CA (backwards secondary), tr (dotless i), ja, zh-pinyin.

**Outcome (2026-06-11).** Delivered; details in `10-milestone-7-report.md`:
- Offline: extract_tailoring.c pulls compiled %%CollationBin blobs (same
  "UCol" v5 format) from ICU's resource bundles; 8 locales bundled:
  de-phonebook, sv, da, fr_CA (settings-only, 32 bytes), tr, lt, ja, zh
  (pinyin, 131 KB incl. reordering).
- Runtime: base-fallback CE lookup (FALLBACK_CE32 -> root) threaded through
  the CE iterator (expansions/contexts/digits resolve in the owning data);
  per-locale default options decoded from IX_OPTIONS (fr-CA backwards
  secondary, da caseFirst=upper); script reordering (table + split-byte
  ranges, CollationSettings::reorder/reorderEx port) applied in compare and
  sort keys.
- Verification: per-locale ICU reference matrices + byte-identical sort keys
  over the corpus (grown to 328 strings with tr/sv/da/de/lt/pinyin/kana
  additions), all 8 locales 100%; locale defaults asserted; classic
  orderings (z < ö in sv, aa primary-equal a-ring in da, Mueller/Mueller
  phonebook, Turkish dotless i, fr-CA backwards accents) green.
- The genrb -X TOML path (NFD-only tailorings for the icu4x data variant)
  remains future work; compiled regular tailorings + the always-NFD runtime
  are verified equivalent against ICU.

---

## Milestone 7.5 — ICU test-suite port + performance round

Added at the user's request while M8 awaits external input. Two goals: port
ICU4C's own collation test suites (the ultimate confidence builder), and do
the performance hardening that M6 deferred.

**Round 1 delivered (2026-06-11; details in `11-milestone-7.5-report.md`):**
- Data-driven suite: runner for test/testdata/collationtest.txt
  (CollationTest::TestDataDriven semantics: relations =, <, <1..<4, <c, <i;
  both directions; sort-key difference-level verification; NFD-input
  re-checks). 300 lines run; skipped with counts: 109 @rules sections (need
  the rule builder), reorder-attribute sections, unbundled locales,
  unpaired-surrogate lines. FOUND A REAL BUG: U+FFFE must rank between
  end-of-string and all code points on the identical level (compareNFDIter:
  end=-2, FFFE=-1); fixed.
- Thai dictionary order test (CollationThaiTest::TestDictionary): all ~31k
  riwords.txt adjacent pairs in order under the th tailoring.
- Tailorings grown to 15 (added th, fi, es, ko, fr, zh-stroke).
- Performance: NFD fast path (bare starters with no decomposition bypass all
  buffering), CE-iterator lookahead bypass, canonical-equality shortcut.
  compare: ascii 2225->1225ns, cjk 2502->1410ns (6x/3.2x vs pre-lazy
  baseline); sortKey ascii 3640->2734ns, cjk 2959->2334ns. ICU is still
  ~75x faster on ASCII compare (identical-prefix + fast-Latin paths, zero
  allocation) — remaining gap documented in the report.

**Round 2 delivered (2026-06-11):**
- Classic locale suites ported: encoll (en/root), cdetst (de/root), cestst
  (es), cfrtst (fr-CA), cjaptst (ja), cturtst (tr), ficoll (fi), lcukocol
  (ko), currcoll (currency/root). Test arrays extracted mechanically
  (Tools/extract_locale_suites.py -> locale-suites.json); per-suite loop
  logic (case ranges per strength, pairwise/adjacency/matrix expectations,
  caseLevel for ja) reimplemented from the C sources. All 9 green; doTest
  semantics (both directions + sort-key order) preserved.
- regcoll.cpp regression port: 13 portable cases extracted
  (Tools/extract_regcoll.py -> regcoll.json) incl. the fr-CA and da_DK
  cases; 17 skipped with reasons (rule-string collators x5, CE-iterator
  API, object identity/clone, normalization-off phase). All 13 green.
- Parser fix found by ko.bin: tailorings can end their indexes[] early
  (ko has 13 slots); the minimum-indexes guard was too strict.
- Tailorings: ko reordering exercised; suite total 39 tests / 14 suites.

**Round 3 delivered (2026-06-12): cmsccoll.c non-rule cases.**
- 20 cases extracted (Tools/extract_cmsccoll.py -> cmsccoll.json): pinyin
  ordering (TestBeforePinyin, TestPinyinProblem), da upper-first, fr, ko
  Hangul data, ja quaternary/shifted kana (TestNewJapanese, 76+32 strings),
  the six TestNumericCollation sets (incl. 32-bit boundaries, long numbers,
  foreign + supplementary digits), upper-first quaternary, J4960
  primary+caseLevel, J5232 Thai; TestExtremeCompression reimplemented
  programmatically (primary-compression stress, lengths 20..500).
- Two extraction lessons: ICU test strings are double-escaped ("\\u4e8c" is
  decoded by u_unescape at runtime, requiring a two-stage unescape), and
  dead #if 0 code must be stripped (TestJ784 is disabled in ICU, superseded
  by TestBeforePinyin — its stale expectations are correctly absent).
- The remaining ~88 cmsccoll call sites are rule-based
  (see 12-rule-builder-decision.md). Suite total: 41 tests / 15 suites.

**Round 4 delivered (2026-06-12): performance round 2 — buffer reuse.**
- RootCollator keeps a small thread-safe pool of reusable buffer sets
  (both CE iterators with their NFD front ends, the sort key bytes, the four
  per-level buffers); compare()/sortKey() check one out per call and reset it
  keeping capacity, so steady-state calls run without heap allocation. Public
  API and thread safety unchanged.
- compare: ascii 1247->~690ns, latin 1652->~735ns, cjk 1399->~870ns
  (1.6–2.3x); sortKey ascii 2686->~2000ns, latin 3550->~2400ns,
  cjk 2262->~1620ns. Gap to ICU on ASCII compare: ~78x -> ~43x.

**Round 5 delivered (2026-06-12): identical-prefix skip.**
- The planned single-trie nfd.bin rework turned out unnecessary: ICU's data
  files already serialize the unsafe-backward set (contraction trailers
  etc.), which our reader now parses; lead-ccc comes from the existing
  normalization data at runtime, digits from the CE32 tag. compare() skips
  the equal scalar prefix when restarting there is safe, falling back to a
  full comparison on an unsafe boundary (ICU backs up partially instead;
  skipping less is always sound). Prefix-context characters are unsafe here
  (ICU's iterator can read back into the skipped prefix; ours cannot).
- New PrefixSkipTests pin the boundary cases (digit runs under numeric, ja
  prolonged sound mark, combining marks, Thai prevowel contractions, Hangul,
  supplementary plane) against sort keys, which never skip; disabling the
  safety check makes them fail. Suite total: 48 tests / 16 suites.
- New prefix-heavy corpus Tools/bench/bench-paths.txt (sorted file paths,
  avg 26-scalar shared prefix — the sort-verification workload): compare
  10532 -> ~1060ns (10x; ICU 48ns). Zero-sharing corpora pay the walk:
  ascii ~697, latin ~768 (+4%), cjk ~863ns.

**Backlog for next rounds:**
- apicoll behaviors where applicable; g7coll rule-free parts.
- The runtime rule builder remains a deliberate, reversible cut — reasoning,
  costs, and a porting plan are documented in `12-rule-builder-decision.md`.
- Perf: Span-based data access; fast-Latin remains unported (ICU4X
  precedent) — the dominant remaining gap on no-sharing ASCII compares.

---

## Milestone 8 — swift-foundation integration

**Scope.**
- Settle placement with maintainers (FoundationEssentials root-only vs
  FoundationInternationalization with tailorings — see `03-swift-strategy.md` §5)
  and pitch on the Swift forums.
- Adapt code to Foundation conventions in the `port/collation` worktree; wire
  into `String.compare(_:options:locale:)` / `localizedStandardCompare` (the
  existing non-Darwin TODO); share the M2 normalization data with Foundation's
  `_nfd` gap.
- Production hardening: `Span`/`InlineArray` hot paths, `Sendable` audit,
  data-size budget, UTF-8 code-unit front end.

**Verification.** Foundation's existing test suite + ours, ported into the
project's test style; benchmarks acceptable to maintainers.

---

## Cross-cutting open decisions

1. **Data container** (decide in M2): ICU binary/TOML exports vs custom compact
   format. Affects M7 packaging and the Foundation data-size conversation.
2. **Placement in Foundation** (decide before M8, ideally discuss early):
   Essentials (root-only, ICU-free) vs Internationalization (full tailorings).
3. **UTF-8 front end**: prototype iterates `String.UnicodeScalarView`; switching
   to UTF-8 code units is a perf decision for M6/M8, not a correctness one.
