# The Unicode Collation Algorithm and its ICU4C Implementation

> Investigation of the local ICU4C clone at `~/Projects/claude/icu` (paths below are relative to
> `icu4c/source/i18n` unless noted). Conducted June 2026.

## 1. UCA in brief, and how ICU diverges from it

UTS #10 defines collation conceptually as four steps: normalize the input (NFD), map each code
point/contraction to one or more **collation elements** (triples of primary/secondary/tertiary
weights from the DUCET table), build a **sort key** by concatenating weights level by level with
level separators, and compare keys byte-wise. ICU4C implements this faithfully in behavior but
almost nowhere literally:

- **The data isn't DUCET.** The root is the **CLDR root collation**, built from
  `FractionalUCA.txt` — weights are already "fractional" variable-length byte sequences
  (1–4 bytes per primary), not the 16-bit DUCET weights. The `genuca` tool
  (`tools/unicode/c/genuca/genuca.cpp`) compiles it into `ucadata.icu` (format `"UCol"`,
  version 5).
- **It never builds full sort keys to compare.** `compare()` interleaves CE generation and
  comparison level by level, with multiple fast paths before any CE is ever computed.
- **It doesn't NFD the input.** It uses incremental **FCD** checking, normalizing only the rare
  segments that need it.

## 2. The data model: CE32s, the trie, and fallback

The heart of the design is in `collation.h` and `collationdata.h`. A `UTrie2` maps every code
point to a 32-bit **CE32** (`collationdata.h:171`). Most characters resolve in one trie hit.

### CE32 encoding (`collation.h:154-276`)

- **Simple CE32** (`ppppsstt`, low byte < 0xc0): 16-bit primary + 8-bit secondary + 8-bit
  tertiary, expanded on demand to a 64-bit CE `pppp0000 ss00tt00` (`collation.h:423`).
- **Special CE32** (low byte ≥ 0xc0): a 4-bit tag selects among 16 cases:

| Tag | Name | Meaning |
|----:|------|---------|
| 0x0 | FALLBACK | Fall back to base (root) data |
| 0x1 | LONG_PRIMARY | 3-byte primary, common sec/ter (`ppppppC1`) |
| 0x2 | LONG_SECONDARY | Primary-ignorable, 16-bit sec + 8-bit ter |
| 0x4 | LATIN_EXPANSION | Two CEs packed into one word |
| 0x5 | EXPANSION32 | index+length into `ce32s[]` (≤31 CEs) |
| 0x6 | EXPANSION | index+length into 64-bit `ces[]` |
| 0x7 | BUILDER_DATA | Builder-only, never serialized |
| 0x8 | PREFIX | index into `contexts[]` (serialized UCharsTrie) |
| 0x9 | CONTRACTION | index into `contexts[]` + flag bits 8–11 |
| 0xa | DIGIT | numeric collation (CODAN) |
| 0xb | U0000 | NUL special case (`ce32s[0]`) |
| 0xc | HANGUL | decompose syllable to Jamo arithmetically |
| 0xd | LEAD_SURROGATE | bulk handling of supplementary planes |
| 0xe | OFFSET | code-point-ordered primary range (e.g. Han) |
| 0xf | IMPLICIT | computed unassigned-implicit primary |

Contraction flag bits (`collation.h:297-303`): `CONTRACT_SINGLE_CP_NO_MATCH` (0x100),
`CONTRACT_NEXT_CCC` (0x200), `CONTRACT_TRAILING_CCC` (0x400), and `CONTRACT_HAS_STARTER`
(0x800, **ICU4X only** — see the ICU4X strategy doc).

Key constants: `COMMON_WEIGHT16 = 0x0500`, `NO_CE = 0x101000100`,
`MERGE_SEPARATOR_PRIMARY = 0x02000000`, `UNASSIGNED_IMPLICIT_BYTE = 0xfe`,
`TRAIL_WEIGHT_BYTE = 0xff`, `FFFD_PRIMARY = 0xffe00000`.

### CollationData (`collationdata.h:40-254`)

Immutable container per collator: the `UTrie2`, `ce32s[]`, 64-bit `ces[]`, `contexts[]`
(serialized UCharsTries for prefixes/contractions), `jamoCE32s[67]` (19 L + 21 V + 27 T),
`numericPrimary` (default `0x12000000`), `compressibleBytes[256]`, `unsafeBackwardSet`,
optional `fastLatinTable`, script-reordering tables (`scriptsIndex`/`scriptStarts`), and —
root only — `rootElements`.

Two especially elegant pieces:

- **Tailoring fallback is a single sentinel.** A tailored locale's trie stores `FALLBACK_CE32`
  (0xc0) for untouched characters; lookup just switches to `base->getCE32(c)`
  (`collationdata.cpp:59-65`). Tailorings are tiny deltas over the shared root.
- **Implicit weights are computed, not stored.** Unassigned code points get a synthesized
  4-byte primary under lead byte 0xfe via base-254/251/18 arithmetic in
  `Collation::unassignedPrimaryFromCodePoint()` (`collation.cpp:124-137`); Han and other huge
  ordered ranges use `OFFSET_TAG`, storing one "data CE" (base primary + per-code-point
  increment) per range.

### Root elements (`collationrootelements.h`)

A compact sorted list of every root CE (primaries, with sec/ter deltas flagged by
`SEC_TER_DELTA_FLAG = 0x80`; ranges compressed to first/last + step). Used **only by the
tailoring builder** to answer "what weight comes before/after X".

### Binary format (`collationdatareader.h:35-100`)

`"UCol"` format version 5 (stable since ICU 53, 2014). An `indexes[]` array of byte offsets to:
reorder codes/table, trie, ces, ce32s, root elements, contexts, unsafe-backward set, fast-Latin
table, scripts, compressible bytes. Locale tailorings are embedded in `.res` bundles as
`%%CollationBin` blobs.

## 3. Runtime: CE iteration and comparison

`CollationIterator::nextCE()` (`collationiterator.h:117-159`) has an inline fast path for
simple CE32s; everything else goes through `appendCEsFromCE32()`
(`collationiterator.cpp:251-445`), the big tag-dispatch switch that fills a `CEBuffer`
(40-element initial stack allocation).

Notable conformance machinery:

- **Discontiguous contractions (UTS #10 S2.1)**: `nextCE32FromDiscontiguousContraction()`
  (`collationiterator.cpp:556-684`) implements the blocking rule (`prevCC < leadCC`) exactly,
  with a `SkippedState` that snapshots `UCharsTrie` state so skipped combining marks can be
  backtracked and their CEs appended after the match.
- **FCD instead of NFD**: `FCDUTF16CollationIterator` (`utf16collationiterator.cpp:373-409`)
  checks combining-class ordering incrementally and only decomposes the offending segment when
  the check fails (with forced decomposition for Tibetan composite vowels U+0F73/0F75/0F81).
  The check uses compact standalone bitset tables in `collationfcd.cpp`, not the full FCD trie.
  This works because the data contains the **canonical closure** (composed forms are mapped
  directly).
- **Hangul** is decomposed to Jamo arithmetically at lookup time using the fixed 67-entry
  `jamoCE32s` array — no Hangul syllable mappings are stored.
- **Numeric collation (CODAN)**: `DIGIT_TAG` + `appendNumericCEs()`
  (`collationiterator.cpp:687-839`) encodes whole digit runs as length-prefixed primaries so
  "item10" sorts after "item9".

`CollationCompare::compareUpToQuaternary()` (`collationcompare.cpp:28-352`) runs the level loop
directly on two iterators: primaries first (applying script reordering and shifting variable
CEs — those below `variableTop` — down to quaternary), then secondaries (backwards within
segments for French), optional case level, tertiary (case-first via XOR 0xc000), quaternary.
The identical level is a separate NFD code-point comparison
(`rulebasedcollator.cpp:937`, `compareNFDIter`).

## 4. Sort keys

`CollationKeys::writeSortKeyUpToQuaternary()` (`collationkeys.cpp:230-674`) is the literal
UTS #10 sort-key step, with byte-level engineering on top:

- Levels separated by `0x01`, terminated by `0x00`; `0x02` is the merge separator.
- **Primary compression**: for "compressible" lead bytes (per-script flags in
  `compressibleBytes[256]`), the lead byte is written once per run, with `0x03`/`0xff` as
  ordering terminators.
- **Common-weight run compression** at secondary/tertiary/quaternary: runs of common weight
  0x05 collapse into one byte encoding run length, biased low/high depending on what follows
  (secondaries: 0x05–0x45, max run 33; quaternaries: 0x1c–0xfc, max run 113).
- The identical level appends the NFD string compressed with **BOCSU** delta encoding
  (`bocsu.h`): code-point-order-preserving, avoids bytes 0–2, ~1 byte/char for same-script text.
- `ucol_getBound()` (`ucol.cpp:247-309`) builds prefix-range bounds by truncating a key at a
  level boundary and appending `0x02` or `0xff 0xff`.

Settings live in a 16-bit options word in `CollationSettings` (`collationsettings.h:34-95`):
strength (bits 12–15), shifted/non-ignorable (bits 2–3), maxVariable (bits 4–6), case-first/
upper-first (bits 8–9), case-level (bit 10), French secondary (bit 11), numeric (bit 1),
check-FCD (bit 0). Script **reordering** is a 256-entry permutation of primary lead bytes with
a range-table escape (`reorderEx`, `collationsettings.cpp:261`) for lead bytes split between
two reordered scripts.

## 5. Tailoring: from `&a < x` to a trie

The build pipeline is shared by `RuleBasedCollator(rules)` at runtime and `genrb` at ICU build
time — locale rules in `data/coll/*.txt` are compiled to binary `%%CollationBin` resources
(`tools/genrb/parse.cpp:1295`):

1. **`CollationRuleParser`** tokenizes CLDR syntax: `&` resets (including `[before n]` and
   logical positions like `[last variable]`), `< << <<< <<<< =` relations, `|` prefixes,
   `/` extensions, and `[settings]` including `[import de-u-co-phonebk]`.
2. **`CollationBuilder`** keeps a doubly-linked node graph ordered by collation order. Reset
   positions are found by navigating `rootElements`; tailored nodes initially carry
   **temporary CEs** that encode a node index (so insertions never invalidate anything);
   case bits are harvested from the base collator's CEs (`setCaseBits`,
   `collationbuilder.cpp:1019`).
3. **Canonical closure** (`addWithClosure`, plus `closeOverComposites`) maps every canonical
   equivalent of each tailored string via `CanonicalIterator`, satisfying UTS #10's
   canonical-equivalence requirement at build time rather than compare time.
   (Loop-limited to 3000 iterations per ICU-22517.)
4. **`CollationWeights`** (`collationweights.cpp`) does gap allocation: it decomposes the
   space between two neighboring root weights into up to 7 byte-ranges and, if too few slots
   exist, *lengthens* weights (3-byte primaries become 4-byte) — this is why arbitrarily many
   `&a < x1 < x2 …` insertions always fit.
5. **`CollationDataBuilder`** assembles the final `UTrie2`, expansion arrays, and context
   `UCharsTrie`s; `CollationDataWriter` serializes the binary.

## 6. The performance story

A stack of escape hatches, each falling through to the next:

1. **Identical-prefix skip** in `doCompare()` (`rulebasedcollator.cpp:975`) — compare raw code
   units first, backing up over "unsafe" characters (contraction/combining-mark territory,
   tracked in `unsafeBackwardSet`).
2. **Fast Latin** (`collationfastlatin.cpp`) — a precomputed 16-bit mini-CE table covering
   U+0000–U+017F plus general punctuation, doing the full multi-level comparison on packed
   words; returns `BAIL_OUT` for anything it can't prove correct (digits under numeric mode,
   French secondary, unsupported chars).
3. **Full iterator comparison**, itself with the simple-CE32 inline path, choosing
   FCD-checking vs. plain iterators once per collator.
4. Sort keys are only materialized when explicitly requested (databases, indexing).

## 7. Pointers for going deeper

Best in-tree documentation: comment blocks at `collation.h:154-276` (CE32 encoding),
`collationrootelements.h:232-268` (root elements layout), `collationbuilder.h:314-405`
(node graph), `collationkeys.h:103-164` (sort key format).

This design is the "collation v2" rewrite (ICU 53, 2014). ICU4J mirrors it class-for-class;
ICU4X consumes a variant of the same data — the tree contains `icu4xMode` flags and the
ICU4X-only `CONTRACT_HAS_STARTER` bit (see `02-icu4x-strategy.md`).

Conformance oracle for any port: the UCA test files under `testdata`
(`CollationTest_SHIFTED`, `CollationTest_NON_IGNORABLE`) and ICU's own `CollationTest`.
