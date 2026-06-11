# Milestone 4 Report: Contraction & Prefix Matching

> Completed 2026-06-11. Companion to the outcome note in `04-milestone-plan.md`.
> Previous report: `06-milestone-3-report.md`.

## What this milestone was for

Until now, context-dependent mappings (CONTRACTION_TAG and PREFIX_TAG CE32s)
resolved to their default CE32 — correct only when the text didn't actually
form a contraction or meet a prefix condition. This milestone implements real
context matching, removing the last correctness caveat in the comparison
semantics. What remains before full conformance work (M6) is sort keys (M5).

## What was built

### 1. `UCharsTrie` (read side)

The collation contexts data is a sequence of serialized UCharsTries: compact
tries over UTF-16 unit strings with 32-bit values, mixing branch nodes
(binary-search + linear tail), linear-match nodes, and compact variable-length
values. Ported from `common/ucharstrie.{h,cpp}`: `first/next(ForCodePoint)`,
`branchNext`, the value/delta compact encodings, and `getValue`.

One Swift advantage shapes the whole port: **the trie handle is a value type**
(an offset pair into the shared contexts array). Copying the struct snapshots
the traversal state. ICU needs a `SkippedState` object that saves trie state
and replays partial matches for discontiguous contractions; we just keep a
copy from before the attempt.

### 2. Contraction matching (`CEIterator.contractionCE32`)

The CE iterator gained a normalized **lookahead buffer** (`scalarAhead(_:)` /
`consumeAhead` / `removeAhead`) over the NFD front end. Matching follows
UTS #10 S2.1 directly, which the always-normalized stream makes simple — ICU's
FCD16 lead/trail checks reduce to plain ccc lookups:

1. **Contiguous phase**: walk the suffix trie over following scalars; remember
   the longest match with a value (`bestCE32`, `bestLength`) and the trie
   state at that point.
2. **Discontiguous phase** (S2.1.1–S2.1.3), only when the data says some
   suffix ends in a non-starter (`CONTRACT_TRAILING_CCC`): scan the non-starters
   after the match. Because the stream is canonically ordered, candidate C is
   blocked exactly when the previously skipped mark's ccc >= ccc(C). An
   unblocked C that extends the match to a value is consumed — removed from
   the lookahead per S2.1.3 — while skipped marks stay in the buffer and
   produce their own CEs afterwards (same CE order as ICU's replay machinery).
3. `CONTRACT_NEXT_CCC` (all suffixes start with a non-starter → a following
   starter can't match) and `CONTRACT_SINGLE_CP_NO_MATCH` (discontiguous only
   extends an existing match) are honored.

### 3. Prefix matching (`CEIterator.prefixCE32`)

Prefix tries store the preceding characters last-first; the iterator keeps the
two most recently processed scalars and feeds them to the trie in that order.
Two is sufficient for all CLDR prefixes (single starter, or starter + kana
voicing mark — see `02-icu4x-strategy.md`); the limitation is documented in
code. Scalars consumed as contraction suffixes or digit runs enter the history
in text order.

## Root-data findings

- **Root contains exactly 4 prefix entries** (`FractionalUCA.txt`):
  `l|·`, `L|·`, `l|U+0387`, `L|U+0387` — the Catalan `l·l` middle dot (and its
  Greek ano-teleia lookalike), which becomes a **secondary-only CE** after l/L
  and keeps its punctuation primary otherwise.
- The vowel-dependent katakana prolonged sound mark (ー) that I expected to be
  a root prefix is actually part of the **Japanese tailoring** — a useful
  reminder of the root/tailoring split for milestone 7. (The first version of
  the targeted prefix test assumed kana and failed against both our code and
  ICU; the corpus matrices had been passing all along because root genuinely
  gives ー a fixed CE.)
- Tibetan vowel contractions (U+0F71 + U+0F72/0F74/0F80) are the main root
  contractions with non-starter suffixes; the composite vowels U+0F73/75/81
  decompose to exactly those pairs, so contraction matching is what makes the
  decomposed forms sort identically to the composites.

## Verification

- Corpus grown 239 → 287: kana length/iteration marks, voiced kana
  (precomposed vs combining), Tibetan contraction pairs including the
  **equal-ccc blocking case** (`0F71 0F80 0F72` must NOT discontiguously match
  `0F71+0F72`), Thai, Cyrillic, and the Catalan middle-dot strings.
- Full differential: 13 option sets × 2 data variants × 287² =
  **2.36M comparisons, 100% agreement with ICU 79**.
- New `ContextTests` prove the paths *fire* rather than merely default-agree:
  `l·` vs `x·` CE difference (prefix), CE-identity of `0F73` vs `0F71+0F72`
  (contraction), CE-difference of blocked vs unblocked mark orders (S2.1.2),
  and kana/Tibetan canonical-equivalence classes at identical strength.
- The ICU4X data variant — with its rewritten contexts encoding,
  `CONTRACT_HAS_STARTER` bit, and dummy lone-surrogate tries for middle
  starters — passes everything unmodified.

## Limitations carried forward

- The truly discontiguous *skip* case (unblocked lower-ccc mark between base
  and matching mark) is implemented and blocking-verified, but root data
  offers no natural positive instance; tailoring data (M7) will exercise it.
- Prefix history is two scalars deep — fine for CLDR, would need revisiting
  for hypothetical longer tailored prefixes.
- Per-compare allocations (lookahead buffer, CE arrays) remain; M6 owns
  performance.
