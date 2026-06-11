# UCACollation

Pure-Swift prototype of UCA/CLDR root collation, ported from ICU4C's collation v2
design. Lives as a self-contained package under `Collation/` in this repo (branch
`port/collation`); it is intentionally NOT wired into the Foundation build — code
moves into `Sources/` at integration time (milestone 8). See
`../Docs/03-swift-strategy.md` for the strategy and `../Docs/04-milestone-plan.md`
for the plan.

## Status: milestone 4 complete

Full multi-level comparison against the CLDR root collation, with incremental
NFD decomposition fused into the iterator (the ICU4X model — normalization is
always on). All strengths (primary..quaternary + identical) and settings:
alternate=shifted with maxVariable, case-first, case-level, French backwards
secondary, numeric (CODAN). Validated by differential tests against ICU 79:
13 option sets (named combinations of collator settings) × 2 bundled data variants × a 239×239 corpus
matrix = 1.49M comparisons, 100% agreement. The ICU reference answers are generated with
`UCOL_NORMALIZATION_MODE=UCOL_ON` to match the always-normalizing design.

Implemented:
- `CollationData` — reader for the binary "UCol" v5 format incl. scripts data
  (variableTop derivation); two bundled variants: `ucadata.icu` (regular,
  canonical closure) and `ucadata-icu4x.icu` (genuca -X: NFD-only)
- `UTrie2` — read-only code point → CE32 trie lookup
- `NormalizationData` + `NFDIterator` — full canonical decomposition with
  canonical reordering (UAX #15), arithmetic Hangul; data generated from ICU's
  `norm2/nfc.txt` by the `GenNormData` tool into `nfd.bin` (34 KB)
- `UCharsTrie` — read-side trie for the contexts data
- `CEIterator` — full 64-bit collation elements over the NFD front end:
  contraction matching (incl. discontiguous per UTS #10 S2.1), prefix
  matching, numeric (CODAN) digit-run CEs
- `CollationCompare` — faithful port of `compareUpToQuaternary`
  (level-by-level, variable shifting, case level, case-first, French)
- `CollationOptions` — public options mirroring ICU's settings word
- `RootCollator` — `compare(_:_:options:)`, identical-level NFD tiebreaker

Not yet implemented — see `../Docs/04-milestone-plan.md` for the numbered plan:
- sort keys (5), conformance/perf (6), tailorings + script reordering (7),
  Foundation integration (8)

## Regenerating the normalization data

```sh
swift run GenNormData \
  ~/Projects/claude/icu/icu4c/source/data/unidata/norm2/nfc.txt \
  Sources/UCACollation/Resources/nfd.bin
```

## Regenerating the golden data

The bundled `Sources/UCACollation/Resources/ucadata.icu` is copied from a local
ICU 79 build (machine-local, outside this repo:
`~/Projects/claude/collation/icu-build/data/out/build/icudt79l/coll/ucadata.icu`,
unihan variant; source clone at `~/Projects/claude/icu`) so the oracle and the
Swift reader use byte-identical data.

```sh
cd Tools
ICU_SRC=~/Projects/claude/icu ICU_BUILD=~/Projects/claude/collation/icu-build
clang gen_golden.c -o gen_golden \
  -I $ICU_SRC/icu4c/source/common -I $ICU_SRC/icu4c/source/i18n \
  -L $ICU_BUILD/lib -licuuc -licui18n -licudata
DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./gen_golden \
  ../Tests/UCACollationTests/Golden/corpus.txt \
  ../Tests/UCACollationTests/Golden/matrix.txt
```
