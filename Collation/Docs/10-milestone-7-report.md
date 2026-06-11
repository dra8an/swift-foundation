# Milestone 7 Report: Locale Tailorings & Script Reordering

> Completed 2026-06-11. Companion to the outcome note in `04-milestone-plan.md`.
> Previous report: `09-milestone-6-report.md`.

## What this milestone was for

Everything so far was root collation. Real-world sorting is locale-specific:
Swedish puts ö after z, German phonebook order equates ü with ue, Turkish
distinguishes dotless ı, Chinese pinyin moves Han characters before other
scripts. This milestone adds tailoring support — per-locale data layered over
root — plus the script reordering that was deferred from milestone 3.

## Design: consume compiled tailorings

The strategy docs considered two data paths; this milestone took the
lower-risk one: ICU's build already compiles every locale's collation rules
into `%%CollationBin` binaries in the **same "UCol" v5 format** the package
reads for root data. `Tools/extract_tailoring.c` pulls them out of the
compiled resource bundles (`ures_getBinary`), and 8 are bundled:

| name | size | exercises |
|---|---|---|
| de-phonebook | 9.5 KB | ä/ö/ü ≡ ae/oe/ue expansions |
| sv, da | 10.8 / 13 KB | å/ä/ö/æ/ø after z; da: aa contraction, caseFirst=upper default |
| fr_CA | 32 B | settings-only (backwards secondary), no mappings at all |
| tr, lt | 9.6 / 9.9 KB | dotless-ı case pairs; Lithuanian dot-above interplay |
| ja | 102 KB | kana prefixes (prolonged sound mark!), quaternary kana distinctions |
| zh | 131 KB | pinyin Han ordering + script reordering with split bytes |

The `genrb -X` TOML path (NFD-only tailorings matching the icu4x data
variant) remains future work; the compiled regular tailorings work with our
always-NFD runtime because tailoring mappings include NFD forms (the builder
normalizes rules before adding closure).

## Runtime changes

- **Base fallback** (`CEIterator.lookup`): a tailoring's trie maps untouched
  characters to `FALLBACK_CE32`; lookup switches to the root trie, and the
  *owning* data is threaded through all CE32 resolution (expansions, context
  tries, digit indirections) — the `d` parameter that ICU's
  `appendCEsFromCE32` carries. Jamo CE32s come from whichever data has them.
- **Settings-only tailorings**: fr_CA's 32-byte binary has no trie; the
  collator then uses root data directly with the tailoring's options — the
  same shortcut as `CollationDataReader` ("Use the base data. Only the
  settings are tailored.").
- **Per-locale defaults**: `IX_OPTIONS & 0xffff` decodes into
  `CollationOptions` (`init(icuOptionsWord:)`); `RootCollator.defaultOptions`
  exposes them and `compare`/`sortKey` use them via the test suites.
  Verified: fr-CA → backwardSecondary, da → caseFirst=.upperFirst.
- **Script reordering** (`Reordering` in CollationData.swift): the 256-entry
  primary-lead-byte permutation with the split-byte range table
  (`CollationSettings::aliasReordering`/`reorder`/`reorderEx` ports;
  `minHighNoReorder` short-circuit). Applied at primary and quaternary
  differences in `CollationCompare` and in the sort key writer (after the
  compressibility test on the un-reordered primary, exactly like ICU).
  Exercised for real by zh-pinyin, which reorders Han ahead of other scripts.

## Verification

- Reference matrices **and** byte-identical sort keys per locale, generated
  by `gen_golden` with locale collators using their default settings, over
  the corpus (grown to 328 strings: Turkish ı/i/İ/I quadruple, sv/da/de
  umlaut classics, Müller/Mueller, lt forms, pinyin Han, ja kana). All 8
  locales: 100% matrix agreement, 100% key byte-identity — including zh's
  reordered keys, which fail loudly if reordering is wrong or missing.
- All previous suites (root option sets, conformance, fuzz) unchanged and
  green — the fallback refactor is behavior-neutral for root collation.
- One bug found by the locale data: the "UCol" parser indexed past short
  index arrays (tailorings carry fewer indexes than root); fixed to treat
  out-of-range parts as absent like ICU's `getIndex`.
- A note on hand-written expectations: "aa ≡ å" (da) and "Müller ≡ Mueller"
  (de-phonebook) hold at *primary* strength — at the locales' default
  tertiary strength ICU orders them, and our matrices agreed with ICU before
  the human did. The classic-orderings test now asserts the primary-level
  claims.

## Limitations carried forward

- Tailorings are bundled for 8 locales as proof; a full locale set is a data
  packaging decision for Foundation integration (M8).
- No `[import]`-chain resolution at runtime (compiled binaries are already
  flattened — only relevant if we later compile rules ourselves).
- ICU4X-style (NFD-only) tailoring data via `genrb -X` TOML: future work.
