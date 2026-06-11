# Proposed Strategy: Porting UCA Collation to Swift (swift-foundation)

> Portability assessment of ICU4C's collation v2 to Swift, targeting the swift-foundation
> project (local clone at `~/Projects/claude/swift-foundation`). Builds on
> `01-uca-icu4c-investigation.md` and `02-icu4x-strategy.md`. Conducted June 2026.

## 1. Overall verdict

The **runtime half of ICU4C collation is highly portable** — almost entirely integer
bit-twiddling over immutable flat data, no exotic C++ (no exceptions in hot paths, no deep
virtual hierarchies, no template metaprogramming). ICU4X proved the architecture ports to a
modern safe language; the ICU4C tree even carries the `icu4xMode` hooks for it. The real cost
is not C++→Swift translation; it is the **dependency closure** (tries, normalization) and the
**data pipeline**.

## 2. What ports cleanly (near-mechanical translation)

- **CE32/CE encoding** (`collation.h`): pure shifts/masks on `UInt32`/`UInt64`. Keep raw
  integers with static helpers — not enums with associated values — in the hot path.
- **Comparison loop** (`collationcompare.cpp`), **sort key writer** (`collationkeys.cpp`),
  **settings bitfield**, **weight-gap allocator** (`collationweights.cpp`): dependency-free
  integer code.
- **FCD quick-check tables** (`collationfcd.cpp`): self-contained generated bitsets — though
  under the recommended ICU4X-style design (below) these aren't needed.
- **BOCSU** (identical level): ~150 lines of delta encoding.
- **Binary data reader**: the `"UCol"` v5 format is stable (since ICU 53/2014) and documented
  in `collationdatareader.h`; or consume ICU4X-style exports instead.

## 3. The hard parts

1. **Normalization is the biggest hidden dependency** in ICU4C's design: `getFCD16()` inside
   discontiguous contraction matching, NFD of FCD-failing segments, NFD for the identical
   level. **Recommendation: don't port it — adopt the ICU4X inversion** (NFD-only data,
   decomposition fused into the CE iterator). See doc 02.
2. **The trie family**: read-side ports of **UTrie2/UCPTrie** (code point → CE32; ~50-line
   lookup, documented serialized format) and **UCharsTrie** (contraction/prefix matching;
   a few hundred lines; the save/restore state machine for discontiguous contractions is the
   fiddliest code in the whole port).
3. **The builder is half the codebase — skip it.** `CollationBuilder` + `CollationDataBuilder`
   + `CanonicalIterator` + rule parser ≈ 6–8k lines, dragging in writable tries and full
   canonical-closure machinery. ICU4X's answer: compile tailorings offline with ICU's own
   tools; the runtime only reads. Unless runtime `&a < x` rule parsing in pure Swift is a
   product requirement, cut it. Runtime-only port ≈ **8–10k lines of C++ → comparable Swift**.
4. **Swift-specific performance traps** (solvable; this is where tuning effort goes):
   - Work on `UTF8View`/raw code units, never `Character` — grapheme segmentation would
     destroy both performance and correctness (collation operates below grapheme level).
   - Index-based access over `UnsafeBufferPointer`/`Span` inside `withUnsafe…` scopes for
     bounds-check elimination; naive `Array` subscripting in `nextCE()` costs 2–3×.
   - `CEBuffer`'s stack allocation → `InlineArray` (Swift 6.2+) or fixed tuple; CEs as `Int64`
     in `ContiguousArray`; no ARC traffic in the hot loop.
   - Immutability is a gift: `CollationData` is read-only after load → natural `Sendable`.

## 4. What swift-foundation already has (and doesn't)

Explored June 2026; file references into the local clone.

**Architecture:** `FoundationEssentials` is intentionally ICU-free;
`FoundationInternationalization` depends on `_FoundationICU` (Package.swift:117-194).
README.md:52-54 states the philosophy: ICU is wrapped privately for internationalization;
Essentials clients avoid it.

**Present and useful:**
- A **streaming, scalar-level canonical decomposer**: `_decomposed()` in
  `Sources/FoundationEssentials/String/String+Internals.swift:246-367` — walks scalars,
  decomposes, collects combining marks, **sorts them by ccc** (line 307, via the stdlib's
  `Unicode.Scalar.properties.canonicalCombiningClass`). This is exactly the ICU4X-shaped
  idiom.
- Bitmap scalar sets (`BuiltInUnicodeScalarSet.swift`): `.canonicalDecomposable`,
  `.hfsPlusDecomposable`, `.graphemeExtend`, case sets — O(1) membership via embedded
  CF bitmap data.
- A pure-Swift options-based comparison engine (`String+Comparison.swift`): case-, diacritic-,
  width-insensitive, numeric, literal — scalar-transformation based, **no collation weights**.

**The catches:**
- The decomposition *mapping* inside `_decomposed` calls `String._nfd`, which is
  `FOUNDATION_FRAMEWORK`-only (CoreFoundation bridge); on non-Darwin it is TODO/`fatalError`.
  The architecture exists; the **decomposition data on Linux does not**.
- **No collation exists at all.** `localizedCompare`/`localizedStandardCompare` delegate to
  NSString on Darwin and are explicitly TODO elsewhere
  (`FoundationInternationalization/String/String+SortComparator.swift:60-64`; comment at
  ~line 154: "Until compare(_:options:locale:) is ported to FoundationInternationalization,
  only support unlocalized"). The only `ucol_*` calls in the repo are keyword/metadata
  enumeration (`Locale+Components_ICU.swift:473-495`) — none perform comparison.

## 5. Recommended strategy

**Follow the ICU4X playbook, adapted to Foundation:**

1. **Adopt the fused-NFD design, not ICU4C's FCD design.** Foundation's `_decomposed` proves
   the scalar-streaming idiom is already idiomatic there. This spares porting
   `Normalizer2Impl`, the FCD tables, and the canonical-closure builder — the three hardest
   pieces.
2. **Solve decomposition data once, for both features.** The collator needs scalar-level NFD
   data anyway. Building it as an embedded table — ideally modeled on ICU4X's trie-value
   format, where decomposition + ccc + safety markers share one lookup
   (`components/normalizer/trie-value-format.md`) — simultaneously fixes the existing
   non-Darwin `_nfd` TODO. That contribution is valuable to the project independent of
   collation.
3. **Generate collation data with existing tooling.** `genrb -X --ucadata` / `genuca -X` /
   `icuexportdata` from the local ICU checkout emit NFD-only, closure-free data with all
   ICU4X shape constraints validated at build time. Consume those exports (or a repackaged
   container) from Swift rather than re-deriving the format.
4. **Port the remaining runtime**: the CE iterator (modeled on ICU4X's `elements.rs` rather
   than ICU4C's `collationiterator.cpp`), level-by-level compare, sort keys, settings — the
   parts rated "ports cleanly" above are unchanged by this decision.
5. **Validate continuously against reference implementations**: ICU's UCA conformance files
   (`testdata/.../CollationTest_SHIFTED`, `CollationTest_NON_IGNORABLE`) and differential
   testing against `ucol_strcoll`.

### Effort/scoping options

| Option | Effort | Trade-off |
|---|---|---|
| Wrap system ICU (`ucol_*` via `_FoundationICU`) | days | No port; ties to platform ICU; matches current FoundationInternationalization philosophy; gets Linux `localizedCompare` working fastest |
| Runtime-only Swift port, offline data (recommended) | months | The ICU4X model: full UCA conformance, tailorings compiled offline, pure Swift |
| Full port including builder | many months | Only if runtime rule strings are a requirement |

### Open question to settle with Foundation maintainers first

Where does this live?
- **FoundationEssentials**: pure Swift, embedded root data, no locale tailorings — gives
  UCA-root-correct comparison without ICU; aligns with the Essentials "no ICU" rule but adds
  embedded data size.
- **FoundationInternationalization**: full CLDR tailorings — but then "why not just wrap
  `ucol_strcoll`?" must be answered. The honest pitch for pure Swift there is making
  `localizedStandardCompare` work on Linux without ICU, or as a staged path
  (wrap-ICU first, swap in the Swift engine behind the same API later).

## 6. Proposed first milestone

Prove the pipeline end-to-end (~a couple thousand lines):

1. Swift reader for the exported root data + code point trie lookup.
2. Simple-CE32 path + primary-level-only compare on NFD-safe ASCII.
3. Differential test vs `ucol_strcoll`.

Then grow outward: full level loop → fused NFD decomposition + combining-mark buffering →
contractions/prefixes (discontiguous matching last) → sort keys → tailoring data → settings
(strength/shifted/case/French/numeric) → Hangul/CODAN/implicits → conformance suite green.
