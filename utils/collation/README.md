# Collation data tools

The collation engine (`Sources/FoundationInternationalization/Collation/`) ships ICU's collation data,
compiled into the library by the C target `_FoundationCollationData`. These tools regenerate that data,
for example after a new Unicode or ICU version.

| tool | what it makes | needs |
|---|---|---|
| `extract_tailoring.c` | the 98 compiled tailorings (`Collation/Resources/tailorings/*.bin`) from ICU's resource bundles | an ICU4C build |
| `gen_norm_data.swift` | the normalization data `Collation/Resources/nfd.bin` from ICU's `norm2/nfc.txt` | Swift |
| `gen_golden.c` | the reference answers of the tests (sort keys and compare matrices, `Tests/FoundationInternationalizationTests/Collation/Golden/`) | an ICU4C build of the same version as the data |
| `gen_collation_data.py` | `Sources/_FoundationCollationData/` (the data as C byte arrays) from `Collation/Resources/` | Python 3 |

The root data `ucadata.icu` is ICU's `icu4c/source/data/in/coll/ucadata-unihan.icu`, copied as is. (Checked 2026-11-09: the bundled file is byte for byte that file of ICU tag `release-78.3`, plus 12 bytes of `0xAA` at the end — the fill of ICU's packaged data build, from which it was taken; the parser reads only up to the data's own end.)

## A data update, in order

1. Copy the new `ucadata.icu` into `Sources/FoundationInternationalization/Collation/Resources/`.
2. Build `extract_tailoring.c` against the new ICU (see its header) and extract the tailorings into `Resources/tailorings/`.
3. Run `swift utils/collation/gen_norm_data.swift <icu>/icu4c/source/data/unidata/norm2/nfc.txt Sources/FoundationInternationalization/Collation/Resources/nfd.bin`.
4. Build `gen_golden.c` against the same ICU (see its header) and regenerate the reference answers.
5. Run `python3 utils/collation/gen_collation_data.py`.
6. Run the tests (`swift test`).

Check: for an unchanged Unicode version, `gen_norm_data.swift` must reproduce the old `nfd.bin` byte for byte
(on 2026-11-09, ICU's `nfc.txt` of tag `release-78.3`, Unicode 17.0.0, gave the bundled file exactly).
