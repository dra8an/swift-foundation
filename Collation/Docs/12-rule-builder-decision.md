# Decision Record: The Runtime Rule Builder Is Not Ported

> Written 2026-06-11, after the milestone 7.5 test-suite port made the absence
> visible (109 skipped `collationtest.txt` sections). This documents why the
> cut was made, what it costs, what would justify reversing it, and what a
> port would involve.

## What "the rule builder" is

ICU4C can construct a collator at runtime from a CLDR rule string —
`new RuleBasedCollator("&a < x <<< X")` — by parsing the rules, finding reset
positions among the root collation's weights, allocating new weights in the
gaps, computing the canonical closure of every tailored mapping, and building
the tailoring's trie and context data on the fly. This implementation does
not have that: tailorings are consumed as **compiled binaries** (the same
`%%CollationBin` format ICU's own build produces), and there is no API that
accepts rule strings.

## The three possible worlds

It helps to separate what "building collation data" can mean:

1. **Runtime building** (ICU4C's extra capability): rule strings compile to a
   collator on demand, inside the running app. *This is the only thing this
   implementation lacks.*
2. **Ahead-of-time, with ICU's compiler** (this implementation today, and
   ICU4X): ICU's build tools compile the rules; we ship and read their
   output. Note carefully: it is not *our* compile step that does the work —
   we borrow ICU's compiler output via `extract_tailoring`.
3. **Ahead-of-time, with our own builder**: the same shipped binaries,
   produced by Swift tooling directly from CLDR sources. This is what a
   builder port would actually serve — data-pipeline independence — not
   world 1.

## What is actually lost (and not)

| Scenario | Covered? |
|---|---|
| All current CLDR locales | yes — compiled, extracted, bundled |
| Future CLDR rule updates | yes — re-run the pipeline (requires ICU's toolchain each time) |
| New custom rules known at build time | yes — same pipeline (genrb on a dev machine, extract, bundle) |
| Rule strings supplied **at runtime** | **no — the only true functional loss** |

So "new rules" do not require the runtime builder — they require the offline
pipeline. The genuine loss is one scenario: an application accepting rule
strings dynamically (a `Collator(rules:)` API, Postgres-style user-defined
collations). No Foundation API wants that today. The *recurring* cost is
different in kind: every data refresh keeps ICU's toolchain in the loop,
which is the data-pipeline-independence argument below.

## Where and why the cut was made

The decision dates to the strategy phase (`02-icu4x-strategy.md`,
`03-swift-strategy.md`), before any code was written.

**1. It is roughly half of ICU4C's collation codebase.** The runtime we
ported is ~8–10k lines. The builder adds about as much again:

| Component | approx. size | Notes |
|---|---|---|
| `CollationRuleParser` | ~900 lines | CLDR rule syntax, `[settings]`, `[import]` |
| `CollationBuilder` | ~1,700 | node graph, reset navigation, temporary CEs, case bits |
| `CollationDataBuilder` | ~1,800 | mutable mappings → trie + contexts |
| `CollationWeights` | ~600 | gap allocation / weight lengthening (builder-only) |
| `CanonicalIterator` | ~700 | canonical closure |
| Writable UTrie2 + UCharsTrie builders | ~2,000 | we only ported the read sides |

**2. It needs a second data stack.** Canonical closure requires canonical
**composition** data and `CanonicalIterator`'s machinery. Our normalization
resource (`nfd.bin`) is deliberately decomposition-only; the entire runtime
never composes. The builder would be the only consumer of composition data.

**3. ICU4X set the precedent.** The Rust implementation shipped — and still
ships — without a runtime rule builder. Its tailorings are compiled offline
by ICU's tools. We adopted its architecture (fused NFD, no closure in data)
and its scope on this point.

**4. Rules exist to express locale tailorings, and those are served
offline.** ICU's build compiles every CLDR locale's rules into binaries this
implementation reads directly. Same data, same correctness, no builder.

**5. The integration target has no consumer for it.** No Foundation API
accepts ICU rule syntax: `localizedCompare`, `compare(_:options:locale:)`,
`SortDescriptor` are all locale-driven. A runtime builder would be capability
without a caller (as of the M8 design discussions).

## What the cut costs

- **Test coverage**: 109 of 124 `collationtest.txt` sections, 5 of 30
  regcoll cases, most of `cmsccoll.c`, and the rule-based parts of g7coll
  cannot run. This is the single largest hole in the otherwise-comprehensive
  test port — and the reason this document exists.
- **Data-pipeline dependence**: our tailorings exist only because ICU's
  build tools compiled them. The Swift implementation cannot today go from
  CLDR's rule sources to binary data on its own.
- **Completeness claim**: "full UCA port" arguably includes
  tailoring-from-rules. What we have is the complete *runtime*, not the
  *compiler*.

## What would justify reversing it

1. **Data-pipeline independence** — if Foundation wants to own its collation
   data story end-to-end (compile CLDR rules itself, track CLDR releases
   without an ICU toolchain), the builder is the missing piece. This is the
   strongest strategic argument.
2. A product decision to expose **custom collation rules as API** (no
   current Foundation precedent).
3. The desire to close the test-coverage hole for its own sake.

## What a port would involve, if undertaken

- Scope: the six components above (~7–8k lines), plus extending
  `GenNormData`/`nfd.bin` with composition data, in roughly this order:
  writable tries → `CollationWeights` → rule parser → `CollationDataBuilder`
  → `CanonicalIterator`/closure → `CollationBuilder`.
- Effort: the largest single milestone of the project — comparable to
  milestones 2–4 combined.
- **The verification story is unusually good**, which lowers the risk:
  - the 109 skipped data-driven sections become runnable the day it works —
    a ready-made acceptance suite;
  - a stronger oracle still: compile the same rule strings ICU compiled and
    require **byte-identical output binaries** (we already do byte-identical
    sort keys; the builder admits the same standard).

## Status

Recorded as a deliberate, reversible scope decision. Not currently scheduled;
revisit when M8's data-packaging discussion happens (the data-pipeline
argument naturally arises there), or earlier if priorities change.
