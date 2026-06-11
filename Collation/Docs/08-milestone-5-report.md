# Milestone 5 Report: Sort Keys

> Completed 2026-06-11 (commit `cb4553a`). Companion to the outcome note in
> `04-milestone-plan.md`. Previous report: `07-milestone-4-report.md`.

## What this milestone was for

Comparison answers "which of these two strings comes first"; sort keys answer
"give me bytes I can store and `memcmp`" — what databases and indexes need.
This is the last functional piece of UTS #10's main algorithm; with it, the
collator's root-collation feature set is complete (conformance/perf, tailored
locales, and Foundation integration remain).

## What was built

- **`CollationKeys.writeSortKeyUpToQuaternary`** (`SortKey.swift`): faithful
  port. Levels are accumulated in per-level buffers while walking the CE
  array once, then appended with `01` separators:
  - **Primary**: written directly, with lead-byte compression — runs under a
    compressible lead byte write the lead once, with `03`/`FF` as
    low/high terminators on runs that break order. This needed
    `compressibleBytes[256]` from the data file (part 17, now parsed).
  - **Secondary/tertiary/quaternary**: runs of the common weight (0x0500)
    collapse into single count-encoded bytes, biased low or high depending on
    what follows (e.g. secondaries 05..25..45, max run 33; tertiaries get
    three different transforms depending on caseFirst, with lead-byte range
    remapping like 06..3F → C6..FF).
  - **Case level**: nibble-packed pairs, different compression for
    lowerFirst (1..7..13, mixed=14, upper=15) vs upperFirst (3..15, 2, 1).
  - **Backwards secondary**: weights appended byte-reversed, each
    merge-separated segment reversed in place at its boundary.
  - **Shifted variables**: their primaries go to the quaternary level,
    prefixed with `1B` when a lead byte would collide with the common range.
- **BOCSU identical level**: the slope-detection delta encoder
  (`u_writeDiff`, with the Unihan-window `prev` adjustment) over the NFD
  scalar stream, appended after a `01` separator at identical strength.
- **`RootCollator.sortKey(for:options:)`**: CEs → levels → optional identical
  level → `00` terminator.

## Verification

Two independent checks, both exact on the first run:

1. **Byte-for-byte identity with ICU.** `gen_golden.c` now also emits
   `keys-<option-set>.txt` (hex `ucol_getSortKey` output). All
   13 option sets × 2 data variants × 287 corpus strings = **7,462 keys,
   byte-identical**. This is the strongest possible cross-check: every
   compression scheme, separator, and transform must agree exactly, and it
   also re-confirms that both data variants carry identical weights.
2. **The defining invariant**: byte-wise key comparison equals `compare()`
   with the same options, over all 13 × 287² ≈ **1.07M pairs**.

## Notes

- ICU's key for strength=identical includes the BOCSU level; matching it
  byte-for-byte confirms our NFD stream is exactly ICU's NFD (a second,
  independent check on the milestone-2 normalizer).
- `ucol_getSortKey`'s returned length includes the `00` terminator; ours does
  too.
- Sort keys reuse the CE array from the comparison pipeline; the one-pass
  level-buffer structure is the same as ICU's, so the M6 perf work (CE
  streaming instead of materialized arrays) will apply to both paths.

## Limitations carried forward

- No `getBound`/`mergeSortkeys` equivalents yet (not in the milestone scope;
  add if Foundation API needs them).
- Script reordering still pending (M7); reorder hooks in the key writer are
  omitted like in the comparison.
