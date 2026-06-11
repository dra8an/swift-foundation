# Milestone 2 Report: Fused NFD Decomposition

> Completed 2026-06-11 (commit `e47c6e1`). Companion to the brief outcome note in
> `04-milestone-plan.md`. Milestone 1 background: `04-milestone-plan.md` §M1.

## What this milestone was for

ICU4C's collator never normalizes whole input. It checks the FCD condition and
relies on the **canonical closure** baked into its data (every precomposed form
has its own mapping). Our strategy (`02-icu4x-strategy.md`, `03-swift-strategy.md`)
bets on the ICU4X inversion instead: ship **NFD-only data** and **fuse
incremental NFD decomposition into the collation iterator**. Everything later —
contraction matching over combining-mark buffers (M4), the perf model (M6), the
data pipeline (M7) — depends on that iterator shape, so it had to land before
levels, contexts, or sort keys.

Milestone 2 delivered the fused front end and produced the project's most
important empirical result so far (§ "The headline finding").

## What was built

### 1. Normalization data: `GenNormData` → `nfd.bin`

Source: ICU's `icu4c/source/data/unidata/norm2/nfc.txt` — the human-readable
input to ICU's own `gennorm2` tool. It carries complete canonical data for
Unicode 17 (matching the UCA 17 collation data): ccc assignments
(`0300..0314:230`) and canonical mappings, both round-trip (`00C0=0041 0300`)
and one-way (`212B>0041 030A`). Both kinds are NFD decompositions.

The `GenNormData` executable target parses this, **recursively expands**
mappings to full decompositions (`1E08 → 00C7 0301 → 0043 0327 0301`), asserts
Hangul is absent (it is algorithmic), and writes `nfd.bin`:

```
u32 magic "SNFD" | u32 version=1
u32 cccCount;     u32[(scalar<<8)|ccc]                     sorted by scalar
u32 decompCount;  u64[(scalar<<32)|(bufferOffset<<8)|len]  sorted by scalar
u32 bufferCount;  u32[decomposition scalars]
```

Resulting size: **34,340 bytes** (968 ccc entries, 2,081 decompositions, 3,450
buffer scalars). Lookup is binary search with fast paths (`c < 0x300` → ccc 0;
`c < 0xC0` → no decomposition).

**This container is explicitly provisional.** The end-state design is ICU4X's
single normalization trie whose value packs decomposition + ccc + safety
markers into one lookup (`components/normalizer/trie-value-format.md`). That
swap is scheduled with the perf work (M6); `NormalizationData`'s API
(`ccc(_:)`, `appendDecomposition(of:to:)`) isolates the format so the swap
won't ripple.

### 2. Runtime: `NFDIterator`

Adapts a `String.UnicodeScalarView` into its NFD form, incrementally:

- Each **refill** produces one *reorderable unit*: a starter plus all following
  combining marks (or the string-initial run of non-starters).
- When the next input scalar's decomposition begins with a starter, the current
  unit is finished and the decomposed scalars are carried into the next refill
  (`carried`) — the pushback that keeps the iterator single-pass.
- Combining marks are reordered by a **stable insertion sort on ccc** (the
  Canonical Ordering Algorithm, UAX #15). Stability matters: equal-ccc marks
  must keep input order. Mark runs are short in practice, so insertion sort is
  the right tool.
- Hangul syllables decompose arithmetically to L V (T) Jamo at this layer, so
  the CE pipeline below never sees a syllable.

Like ICU4X, **normalization cannot be turned off**. There is no FCD check, no
"already normalized" fast path yet (an identical-prefix/ASCII fast path is M6
work and needs the safety markers from the trie-value design).

`PrimaryIterator` (the CE-producing layer from milestone 1) is unchanged except
that it now pulls scalars from `NFDIterator` instead of the raw string.

### 3. Data: both root variants bundled and tested

| Resource | Origin | Properties |
|---|---|---|
| `ucadata.icu` | ICU 79 build (unihan) | canonical closure, `HANGUL_TAG` mappings |
| `ucadata-icu4x.icu` | `genuca -X` prebuilt, shipped in the ICU repo | NFD-only: no closure, no Hangul syllable or precomposed mappings |

`CollationData.root()` / `.rootICU4X()` select the variant; every differential
and equivalence test runs against **both**. Default remains `ucadata.icu` until
M4 settles contraction matching against the icu4x contexts encoding
(`CONTRACT_HAS_STARTER` etc.).

## The headline finding

**The closure-free ICU4X data variant passed the complete differential matrix
unmodified, on the first run.** No code branches on the data variant; the same
fused-NFD runtime is simply handed different data.

Why this matters: it is the empirical confirmation of the central bet from the
strategy docs — that

> NFD-only data + always-decompose runtime ≡ closure data + FCD runtime

holds in practice, on real CLDR root data, for everything the corpus exercises
(precomposed Latin/Greek/Vietnamese in all spellings, out-of-order combining
marks, NFD and precomposed Hangul, Tibetan composite vowels, CJK compatibility
ideographs, supplementary-plane decompositions). Hangul works with zero
syllable mappings because our front end emits Jamo, which the icu4x trie maps
normally. The two failure modes we were watching for — missing Jamo mappings
and divergent default-CE32s in the rewritten contexts — did not materialize at
primary strength.

## Verification inventory

All 14 tests green:

1. **Differential vs ICU 79** (`DifferentialTests`): corpus grown 175 → 205
   strings (30 adversarial normalization forms added, e.g. `ậ` in five
   spellings, `a+◌̂+◌̣` in both mark orders, `Å`/`A+◌̊`/U+212B, `0F73` vs
   `0F71 0F72`, `F900` vs `8C48`, `1D15E` vs its decomposition). Full 205×205
   matrix at `UCOL_PRIMARY`, ×2 data variants = **84,050 comparisons, 100%
   agreement**. The reference generator (`gen_golden.c`) is unchanged: ICU's verdict does
   not depend on which data *we* read.
2. **Normalizer vs Foundation** (`NormalizationTests`): our `nfd()` against
   `decomposedStringWithCanonicalMapping` for ~13k single scalars across
   normalization-stable blocks (deliberately excluding blocks newer than the
   system ICU's Unicode version, e.g. Kirat Rai) plus 432 base+two-marks
   sequences exercising reordering. Exact string equality.
3. **Canonical-equivalence properties** (`CanonicalEquivalenceTests`): 12
   equivalence classes, all ordered pairs compare `.same`, both variants.
4. **Milestone-1 suite**: unchanged and green on the new front end.

## Limitations carried forward

- Contexts (prefix/contraction CE32s) still resolve to their default CE32 — no
  suffix matching until M4. Correct for all corpus content; not correct for
  text that genuinely forms contractions (e.g. Cyrillic ⟨ѐ⟩ handled via
  decomposition, but kana voicing prefixes await M4).
- Primary strength only; settings ignored (M3).
- Per-scalar array allocations in the decomposition path; no fast path for
  already-NFD text. Acceptable: M2's gate was correctness, M6 owns performance.
- `nfd.bin` container is provisional (see §1).

## Pointers

- Code: `Sources/UCACollation/{NormalizationData,NFDIterator}.swift`,
  `Sources/GenNormData/main.swift`
- Tests: `Tests/UCACollationTests/{NormalizationTests,DifferentialTests}.swift`
- Regenerate data: `swift run GenNormData <nfc.txt> Sources/UCACollation/Resources/nfd.bin`
- Next: milestone 3 (full level loop + settings), `04-milestone-plan.md`
