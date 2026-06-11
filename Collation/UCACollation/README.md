# UCACollation

Pure-Swift prototype of UCA/CLDR root collation, ported from ICU4C's collation v2
design. Lives as a self-contained package under `Collation/` in this repo (branch
`port/collation`); it is intentionally NOT wired into the Foundation build — code
moves into `Sources/` at integration time (milestone 8). See
`../Docs/03-swift-strategy.md` for the strategy and `../Docs/04-milestone-plan.md`
for the plan.

## Status: milestone 1 complete

Primary-strength comparison against the CLDR root collation, validated by a
differential test against ICU 79 (175-string corpus, full pairwise matrix,
100% agreement — `Tests/UCACollationTests/DifferentialTests.swift`).

Implemented:
- `CollationData` — reader for the binary "UCol" v5 format (`ucadata.icu`)
- `UTrie2` — read-only code point → CE32 trie lookup
- `RootCollator` — primary-level compare; CE32 tag dispatch including
  expansions, digits, Hangul (arithmetic Jamo decomposition), OFFSET (Han),
  implicit (unassigned) primaries

Not yet implemented — see `../Docs/04-milestone-plan.md` for the numbered plan:
- fused NFD decomposition per the ICU4X model (milestone 2)
- secondary/case/tertiary/quaternary levels; settings (milestone 3)
- contraction/prefix context matching (milestone 4; currently resolves to
  default CE32s — correct unless the text actually forms a contraction)
- sort keys (5), conformance/perf (6), tailorings (7), Foundation integration (8)

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
