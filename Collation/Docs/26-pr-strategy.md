# PR Strategy: Incremental Collation for swift-foundation

## The problem

Issue #284: locale-aware string comparison doesn't work on non-Darwin
platforms. `localizedCompare`, `localizedStandardCompare`, and
`compare(_:locale:)` need a collation engine.

## Why you can't fix #284 without UCA

Locale-aware string comparison IS the Unicode Collation Algorithm
(UTS #10). There's no subset or shortcut that correctly handles:

- Contractions (Slovak "ch" sorts as one unit)
- Accent ordering (French reverses secondary weights)
- Script reordering (Chinese puts Han before Latin)
- Case/accent insensitivity (requires weight-level masking)
- Expansion (German "ae" treated as "a" + "e" in phonebook order)
- Normalization (composed vs decomposed must compare equal)

The alternative (PR #1683) calls ICU directly via `ucol_open` /
`ucol_strcollUTF8` — which means swift-foundation can never be truly
self-contained on Linux/Windows. It also creates/destroys a collator
per call with no caching.

## What this is NOT

An ICU port. ICU4C's collation is ~33,000 lines of C/C++ (27,772 in
collation proper + 5,442 in usearch):

| Category | Lines | What |
|----------|-------|------|
| Rule builder + data builder | ~4,000 | `collationbuilder`, `collationdatabuilder`, `collationruleparser` |
| Public API / RuleBasedCollator | ~4,700 | `rulebasedcollator`, `coll`, `ucol`, `ucol_res`, `ucol_sit`, headers |
| Iterator variants (UTF-16, UTF-8, UCharIter) | ~2,500 | Three separate iterator implementations |
| Fast Latin + builder | ~2,200 | Runtime + builder (we only have the runtime) |
| Core runtime (data, compare, keys, settings) | ~3,500 | The part we actually implement |
| Collation element sets, weights, FCD | ~1,800 | FCD we don't need; sets/weights are for the builder |
| Search (usearch) | ~5,400 | Our 416 lines covers this |
| Headers (public + internal) | ~5,000 | API surface, documentation |

We implement the equivalent of their core runtime (~3,500) + fast latin
runtime (~1,100) + search (~5,400) = ~10,000 lines of ICU functionality
in 5,651 lines of Swift. The remaining ~23,000 lines are builder/parser,
API compat layers, FCD, and multiple iterator variants — none of which
we need.

## What this IS

5,651 lines of Swift implementing UTS #10 following the ICU4X
architectural model:

- Pre-compiled tailoring binaries (no runtime rule builder)
- Fused NFD decomposition (no FCD, no canonical closure in data)
- Read-only data structures (tries, no mutation)
- Purpose-built for Swift's String type

Proven correct: byte-identical sort keys to `ucol_getSortKey` across
52k test strings and 21 option sets. Passes the official UCA
conformance suite (433,000 lines). 941 tests.

## Minimum that fixes #284

The core that enables correct locale-aware `compare()`:

| Component | Lines | What it does |
|-----------|-------|--------------|
| Data readers (UTrie2, UCharsTrie, DataStorage) | ~420 | Read pre-compiled binary data |
| Constants + Options | ~320 | CE32/CE bit layouts, comparison options |
| NormalizationData + NFDIterator | ~420 | Fused NFD (required by Unicode for any comparison) |
| CollationData + CollationElements | ~970 | Load collation data, produce collation elements |
| CollationCompare | ~320 | Level-by-level comparison algorithm |
| Minimal RootCollator | ~200 | Public `compare()` API |
| **Total** | **~2,650** | |

Plus: root collation binary data (~800 KB).

This gives you a complete, correct Unicode collation `compare()` that
handles all strengths (primary through identical), case-first, numeric
mode, and the full UCA algorithm including contractions and expansions.

## Everything else is additive

Each subsequent PR adds one capability without touching the core:

| PR | Lines | What it adds | Why it can wait |
|----|-------|--------------|-----------------|
| Sort keys | ~620 | `sortKey(for:)` for pre-computed ordering | compare() works without it |
| Fast Latin + thread-local buffers | ~1,450 | 3-10x speedup on ASCII/Latin | Optimization, not correctness |
| Search | ~420 | `contains()`, `range(of:)` | Independent feature |
| Foundation API wiring | ~900 | `localizedCompare`, predicates, comparators | Integration layer |
| Locale tailorings | resources | 98 locales (th, zh, de, fr, ...) | Can start with root, add incrementally |

## Suggested PR sequence

**PR 1 (~2,650 lines + root data): Fix #284**
- Complete UCA compare with root collation
- A few essential tailorings (en, de, fr, es, zh, ja, ko, th)
- Tests: UCA conformance, collationtest.txt, basic locale tests
- Wires into `compare(_:locale:)` so #284 is actually fixed

**PR 2 (~620 lines): Sort keys**
- Enables efficient pre-sorted collections
- Byte-identical to `ucol_getSortKey`

**PR 3 (~1,450 lines): Performance**
- Fast Latin fast path
- Thread-local scratch buffers
- This is where we go from "correct" to "faster than system ICU"

**PR 4 (~420 lines): Search**
- `localizedStandardContains`, `range(of:locale:)`
- Collation-aware substring matching

**PR 5 (~900 lines): Full Foundation integration**
- `localizedCompare`, `localizedStandardCompare`
- `String.Comparator` with locale
- Predicate support (`#Predicate { $0.localizedStandardContains(...) }`)

**PR 6: Remaining tailorings**
- Full 98-locale coverage
- Thai dictionary tests (31k words)

## Performance

Even without the Fast Latin optimization (PR 3), the core compare
through Foundation APIs is faster than system ICU on non-ASCII text
because we avoid the ObjC bridge overhead:

| API | Latin | CJK | Paths |
|-----|-------|-----|-------|
| `localizedCompare` | **2.8x faster** | **1.5x faster** | **1.8x faster** |

With Fast Latin (PR 3), ASCII/Latin short-string comparisons also
get the fast path.

## Maintenance burden

- No runtime rule compilation (the hardest part of ICU to maintain)
- Tailorings are pre-compiled binaries extracted from CLDR via a
  build tool — updating to a new Unicode version means re-running
  the extractor against new CLDR data
- The core algorithm (UTS #10) hasn't changed in a decade
- Data format is stable (ICU's "v5" collation binary format, documented)
