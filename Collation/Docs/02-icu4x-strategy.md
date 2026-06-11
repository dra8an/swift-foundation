# How ICU4X Solved the Collator's Normalization Dependency

> Investigation of the `icu_collator` crate (github.com/unicode-org/icu4x,
> components/collator) and the `icu4xMode` build paths in the local ICU4C clone at
> `~/Projects/claude/icu`. Conducted June 2026.
>
> Context: ICU4C's collator depends on `Normalizer2Impl` for FCD16 lookups inside contraction
> matching, NFD of FCD-failing segments, and NFD for the identical level. This was identified
> as the hardest dependency for any port. ICU4X did not port it — it dissolved it.

## 1. The core design inversion

ICU4C keeps text *as is*: it checks the FCD condition incrementally and only normalizes
segments that fail, which works because the collation data contains the **canonical closure**
(mappings for precomposed characters), so composed text can be looked up directly.

ICU4X inverted both halves:

- The data **omits the canonical closure entirely** — only NFD forms are mapped.
- The runtime **fuses incremental NFD decomposition into the collation element iterator**,
  using the icu_normalizer crate's data.

From the `icu_collator` design docs (`components/collator/src/docs.rs`):

> "The key design difference between ICU4C and ICU4X is that ICU4C puts the canonical closure
> in the data (larger data) to enable lookup directly by precomposed characters while ICU4X
> always omits the canonical closure and always normalizes to NFD on the fly."

> "Normalization cannot be turned off. There also isn't a separate 'Fast Latin' mode."

There is **no FCD anywhere in ICU4X**: no check, no FCD data, no segment-normalization
fallback. The normalizer's data layout was designed *backwards from the collator's needs* —
"a clean-slate design optimized for the concept of fusing the NFD decomposition into the
collator," optimized for the two dominant cases (starter decomposing to itself; starter
decomposing to a BMP starter + non-starter pair).

## 2. The runtime: `CollationElements` (components/collator/src/elements.rs)

- Adapts an iterator over `char` into an iterator over 64-bit collation elements (end signaled
  by `NO_CE`). Its fields show the fusion directly: `trie: &CodePointTrie<u32>` (the **NFD
  main trie**), `scalars16`/`scalars32` (NFD complex decompositions) — these are the
  *normalizer's* structures — plus collator-specific `jamo: &[u32; JAMO_COUNT]`,
  `diacritics: &ZeroSlice<u16>` (linear secondary-weight table for U+0300–U+034E),
  `lithuanian_dot_above: bool`, `numeric_primary: Option<u8>`.
- An `upcoming` SmallVec buffer holds read-but-unprocessed characters, kept normalized to NFD.
  Source comment: *"Betting that fusing the NFD algorithm into this one at the expense of the
  repetitiveness below, the common cases become fast."*
- **ccc comes from the same NFD trie value** (`ccc_from_trie_value`) — no separate combining
  class map lookup. Combining marks up to the next starter are collected into a buffer
  **sorted by ccc** (canonical reordering done inline).
- **Discontiguous contractions**: matching walks the suffix trie over the buffered, canonically
  ordered marks, tracking `most_recent_skipped_ccc` and only advancing when
  `most_recent_skipped_ccc < ccc` (UCA S2.1.3). Contractions whose suffixes contain
  **starters** don't fit the model — the docs admit "there's duplicated normalization code for
  normalizing the lookahead for contractions"; the `CONTRACT_HAS_STARTER` CE32 flag tells the
  iterator when that path is needed.
- **Hangul**: precomposed syllables detected via a trie-value marker and decomposed
  arithmetically; Jamo CEs come from a flat 256-entry table covering the U+1100 block, not the
  trie.
- **Prefix (precontext) matching**: ICU4X cannot iterate backwards; it keeps a buffer of the
  two most recent characters. Sufficient because CLDR data only contains two prefix shapes:
  a single starter, or a starter followed by U+3099/U+309A (kana voicing marks).
- **Identical-prefix optimization** (comparison.rs): with no FCD safety net, skipping a
  bit-identical prefix must verify the boundary is normalization-and-contraction safe using
  the **normalizer trie's markers** (`BACKWARD_COMBINING_MARKER`, `NON_ROUND_TRIP_MARKER`,
  `HANGUL_SYLLABLE_MARKER`) plus the CE32 Contraction/Prefix tags. ICU4C-style backing-up over
  unsafe characters is unimplemented but not architecturally precluded.
- Iterates Unicode scalar values, so unpaired surrogates sort as U+FFFD — no
  `LEAD_SURROGATE_TAG` machinery.
- **Lithuanian dot-above** is not data-driven closure; it's a hard-coded runtime path enabled
  by a metadata bit set by genrb when the locale is `lt`.

## 3. Data sharing between normalizer and collator

The `Collator` struct holds the **normalizer's own data payloads** alongside the collation
payloads: `decompositions` (NFD trie) and `tables` (scalars16/scalars24 supplements). One trie
lookup per character yields decomposition + ccc + safety markers. The trie-value format is
documented in `components/normalizer/trie-value-format.md`: bit 31 = first character of
decomposition can combine backwards; bit 30 = non-round-trip; value 1 = Hangul syllable;
non-starters carry ccc inline.

Collator-specific data markers (provider.rs): `CollationRootV1`, `CollationTailoringV1`,
`CollationDiacriticsV1`, `CollationJamoV1`, `CollationMetadataV1`, `CollationReorderingV1`,
`CollationSpecialPrimariesV1`.

## 4. The data is still built by ICU4C: `icu4xMode`

ICU4X did not rewrite the tailoring builder. Its data is produced by ICU4C's own builders
running in a special mode: **`genrb -X --ucadata …`** (genrb.cpp:118, 160-161) and
**`genuca -X`** (genuca.cpp:1153-1154), exporting TOML; normalizer tries come from
`icuexportdata`. All file references below are in the local ICU clone.

### No canonical closure / NFD-only mappings
- `collationbuilder.cpp:263-265`: skips `closeOverComposites()`; `:267-275` skips the
  ASCII/Latin-1 `optimize()` copy.
- `collationbuilder.cpp:748-759`: maps only the NFD prefix/string (`addIfDifferent` instead of
  `addWithClosure`).
- `collationdatabuilder.cpp:586-602`: non-NFD strings silently dropped — "s is not in NFD, so
  it cannot match in ICU4X, since ICU4X only does NFD lookups." Known cases (Unicode 16):
  Tibetan composite vowel precomposed forms, Kirat Rai vowel sequences (PRI 497), and the
  U+FDD1+U+AC00 AlphabeticIndex marker.
- `genuca.cpp:898-913`: root build skips every NFD-decomposable character, Hangul syllables
  (AC00–D7A3), and the surrogate range.
- `collationdatabuilder.cpp:810-814`: Latin mini-expansion CE32s disabled ("without the
  canonical closure these are so rare").

### Hangul / Jamo
- No `HANGUL_TAG` range written (`collationdatabuilder.cpp:339-355` skipped); syllables
  detected via normalizer trie marker instead.
- Jamo tailorings omitted (`:578-582`, "TODO(icu4x#1941)"); contractions containing modern
  Hangul/Jamo rejected (`:649-657`); Jamo block exported as a flat 256-entry table
  (genrb `writeCollationJamoTOML`, parse.cpp:915-939) and excluded from the exported trie.
- `U0000_TAG` special-casing skipped (`:1484-1488`).

### Prefix/contraction constraints (`collationdatabuilder.cpp:605-727`)
- Prefixes must be NFD, ≤ 2 code points, start with a starter; a second prefix char must be
  U+3099/U+309A.
- Prefix+contraction combined on one mapping is `U_UNSUPPORTED_ERROR` ("does not occur in the
  root or any tailorings in CLDR as of February 2025").

### `CONTRACT_HAS_STARTER` (collation.h:225, 302-303 — bit 11 of CONTRACTION CE32s)
- Set when any contraction suffix contains a starter (`collationdatabuilder.cpp:1643-1656`).
- The builder tracks "middle starters" (starters occurring mid-contraction,
  `collationdatabuilder.h:258-262`) and in `build()` (`:1422-1483`) forces each to carry a
  contraction CE32 with the flag — synthesizing, if needed, a dummy UCharsTrie containing only
  an unpaired surrogate that can never match — so the runtime can recognize these characters
  purely from the CE32.

### Trie/encoding/export details
- Tailoring trie fallback == default value to avoid extra blocks
  (`collationdatabuilder.cpp:334-337`; parse.cpp:969-971 "ICU4X never does out-of-range
  queries"). UTrie2 converted to a modern small 32-bit `UCPTrie` for export
  (parse.cpp:999-1003). Fast-Latin disabled (parse.cpp:1291-1292).
- Side tables written as TOML (parse.cpp:846-1143): diacritics secondaries
  (U+0300–U+034E linear table; U+0340/0341/0343/0344 excluded — "never occur in NFD data"),
  metadata bits (maxVariable, tailored, tailoredDiacritics, reordering,
  **lithuanianDotAbove = bit 6**, backward-secondary, shifted, case-first), reordering,
  special primaries (last primary per reorder group, compressible bytes, numeric primary),
  and the main data (contexts, ce32s, ces, trie).
- `icuexportdata.cpp` hard-codes the special non-starter decompositions
  (0x0340/0341/0343/0344, Tibetan 0x0F73/0F75/0F81, FF9E/FF9F) at `:822-832` and **errors if
  a new Unicode version introduces one** that "isn't already hard-coded into ICU4X."

## 5. Trade-offs accepted

**Gained:** smaller per-locale data (no closure), unconditional correctness on un-normalized
input, no FCD machinery, normalizer and collator share one trie lookup per character.

**Paid:** always-decompose runtime cost; no fast-Latin path; a handful of hard-coded special
cases instead of data-driven ones (Tibetan composite vowels, Kirat Rai, Lithuanian dot-above,
kana voicing prefixes); build-time constraints on prefix/contraction shapes; Unicode-version
assumptions enforced by export-time errors.

## 6. Why this matters for a Swift port

- The hardest ICU4C dependency (Normalizer2Impl/FCD) is avoidable by adopting the same fusion:
  design (or reuse) scalar-level NFD data the CE iterator consumes directly.
- The offline data pipeline **already exists in the local ICU checkout**: `genrb -X` /
  `genuca -X` / `icuexportdata` can generate ICU4X-shaped, NFD-only collation data today.
  A Swift runtime could consume the same exports (or a repackaged form of them).
- The shape constraints ICU4X enforces at build time (2-char prefixes, no prefix+contraction
  combos, etc.) are validated against all of CLDR — a Swift port inherits those guarantees by
  using the same builder.

Sources: local ICU tree as cited; icu_collator docs module (docs.rs/icu_collator), collator
source (elements.rs, comparison.rs, provider.rs, docs.rs), normalizer trie-value-format.md.
