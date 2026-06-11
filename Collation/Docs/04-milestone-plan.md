# Milestone Plan: Pure-Swift UCA Collation

> Working plan for the port described in `03-swift-strategy.md`. Each milestone has a
> scope, a concrete deliverable, and verification criteria — "milestone N" in
> conversation refers to this document. Revise freely as reality intrudes.

## Status overview

| # | Milestone | Status |
|---|-----------|--------|
| 1 | Pipeline proof: primary-only root compare | **Done 2026-06-11** |
| 2 | Fused NFD decomposition + NFD-only data | not started |
| 3 | Full level loop + settings | not started |
| 4 | Contraction & prefix matching | not started |
| 5 | Sort keys | not started |
| 6 | Conformance & performance baseline | not started |
| 7 | Locale tailorings | not started |
| 8 | swift-foundation integration | not started |

Standing rule for every milestone: differential testing against ICU 79 (machine-local
build at `~/Projects/claude/collation/icu-build`, outside this repo) is the
acceptance gate. New functionality ships with new oracle coverage; existing golden
tests stay green.

---

## Milestone 1 — Pipeline proof (DONE)

**Scope.** Smallest vertical slice touching every layer: binary data → trie →
CE32 resolution → comparison → oracle validation.

**Delivered** (2026-06-11, `UCACollation/` package):
- `CollationData`: reader for the "UCol" v5 binary format (`ucadata.icu`)
- `UTrie2`: serialized-form reader and code-point lookup
- `RootCollator`: primary-strength compare; CE32 tag dispatch covering simple,
  long-primary/secondary, Latin/32/64-bit expansions, digit, U+0000, Hangul
  (arithmetic Jamo), OFFSET (Han), implicit (unassigned); contractions/prefixes
  resolve to default CE32s (no context matching yet)

**Verification (passed).** 175-string corpus (ASCII, accented Latin precomposed +
decomposed, Greek, Cyrillic, Han, Hangul, kana, expansions, emoji, plane 16,
unassigned); full 175×175 pairwise matrix vs `ucol_strcollUTF8` at
`UCOL_PRIMARY`: 100% agreement. Oracle and Swift read byte-identical data.

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
