# HANDOFF — Cold-Start Guide for the Collation Project

> Written 2026-06-12 for a fresh session with no conversation context.
> Read this first, then `04-milestone-plan.md` for status, then the numbered
> docs as needed.

## What this project is

A pure-Swift implementation of the Unicode Collation Algorithm (UTS #10 /
CLDR root + tailorings), ported from ICU4C's "collation v2" design following
the ICU4X architectural model (always-on fused NFD decomposition, no FCD, no
canonical closure in data). Target: eventual contribution to swift-foundation
(milestone 8, ON HOLD awaiting maintainer/community input — do not start it
unprompted).

## Where everything is

| Path | What |
|---|---|
| `~/Projects/claude/collation/swift-foundation/` | git worktree, branch `port/collation`, based on `upstream/release/6.3` |
| `.../swift-foundation/Collation/` | **the SwiftPM package root** (name: `Collation`) and these docs (`Docs/`) |
| `~/Projects/claude/swift-foundation/` | user's MAIN checkout — calendars project on `port/buddhist` / `port/hebrew`. **Never touch.** |
| `~/Projects/claude/icu/` | ICU4C 79.0.1 source clone (reference for porting; test data source) |
| `~/Projects/claude/collation/icu-build/` | local ICU build: differential-reference library + data tools. Machine-local, not in git. Rebuild: `mkdir build && cd build && <icu>/icu4c/source/runConfigureICU MacOSX && make -j8` |

Remotes: `origin` = github.com/dra8an/swift-foundation (user's fork, push
target), `upstream` = swiftlang (never push). Branch tracks origin.

## Hard rules (user-mandated)

1. **NEVER add "Co-Authored-By: Claude" or any Claude/Anthropic reference to
   commits.** History was rewritten once to purge them. Before every push:
   verify messages (`git log --format=%B | grep -ci 'claude\|co-authored\|anthropic'`
   must be 0) and author/committer identity (must be dra8an), and show the
   user the verification.
2. Push only when the user says push (they always ask explicitly).
3. Plain terminology: no testing jargon — "ICU reference answers" not
   "oracle", "option set" not "configuration".
4. Swift 6.4 does NOT compile on this machine; everything bases on
   `upstream/release/6.3` (toolchain: Swift 6.3.1).
5. Transient `.git/worktrees/swift-foundation/index.lock` collisions happen
   (likely Atom's git polling). Wait a few seconds, re-check for live git
   processes, remove the zero-byte lock only if stale, retry.
6. The user values: decision records for surprising scope cuts, honest
   skip-counting in tests, investigating failing imported expectations
   against ICU source before "fixing" our code (twice the expectations were
   wrong, not the implementation).

## Current state (2026-06-12)

- **Milestones 1–7 complete** (plan + per-milestone reports in `Docs/`):
  full UCA runtime — fused NFD, all strengths/settings, contractions
  (incl. discontiguous S2.1) and prefixes, sort keys **byte-identical to
  ucol_getSortKey**, 15 locale tailorings incl. zh script reordering.
- **Milestone 7.5 complete** (rounds 1–7): every portable ICU test suite is
  ported, plus perf rounds. **54 tests / 18 suites, all green.** Suites: official UCA
  conformance (433k lines), collationtest.txt data-driven, Thai dictionary
  (31k words), 9 classic locale suites, regcoll (13 cases), cmsccoll
  (20 cases + extreme compression), g7coll locale rows, apicoll behavioral
  parts, differential matrices + byte-identical keys (21 option sets × 2
  data variants), 52k fuzz keys.
- Pushed through commit `83f085b` (round 6); round 7 may be committed but
  unpushed — check `git log origin/port/collation..HEAD`.

## Deliberate scope cuts (don't re-litigate without reading the docs)

- **Runtime rule builder NOT ported** — `12-rule-builder-decision.md` has the
  full reasoning, costs, and porting plan. Tailorings are compiled binaries
  extracted from ICU's build (`Tools/extract_tailoring.c`).
- **Fast-Latin not ported** (ICU4X precedent); **normalization cannot be
  turned off** (architectural); **unpaired surrogates unsupported** (Swift
  String); **reorder-table generation unsupported** (data-supplied
  reordering only).

## Open backlog

**M7.5 is complete; nothing is actionable without a new decision.** Parked:
- Rule builder (doc 12); M8 Foundation integration (await user).
- Perf levers needing a decision: single-trie nfd.bin; fast-Latin
  (deliberate cut, ICU4X precedent). Current: ASCII compare ~239 ns vs
  ICU 16 ns (~15×), sortKey ~785 vs 202 ns; analysis in
  `11-milestone-7.5-report.md`.

## How to work

```sh
cd ~/Projects/claude/collation/swift-foundation/Collation
swift test                      # full suite, ~40s
swift build -c release && .build/release/Bench Tools/bench/bench-ascii.txt 200
```

Regenerating reference data (only when corpus/locales change; needs icu-build):
```sh
cd Tools
ICU_SRC=~/Projects/claude/icu ICU_BUILD=~/Projects/claude/collation/icu-build
clang gen_golden.c -o gen_golden -I $ICU_SRC/icu4c/source/common \
  -I $ICU_SRC/icu4c/source/i18n -L $ICU_BUILD/lib -licuuc -licui18n -licudata
DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./gen_golden \
  ../Tests/CollationTests/Golden/corpus.txt ../Tests/CollationTests/Golden
# fuzz keys: same with fuzz-corpus.txt + "--keys-only"; tailorings:
# extract_tailoring.c; norm data: swift run GenNormData <nfc.txt> <nfd.bin>
# test fixtures: extract_locale_suites.py / extract_regcoll.py /
#   extract_cmsccoll.py / extract_g7coll.py
```

## Code map (Sources/Collation/)

- `CollationConstants.swift` — CE32/CE bit layouts, tags, implicit/OFFSET
  primaries (renamed from `Collation` to avoid module/type name collision)
- `UTrie2.swift`, `UCharsTrie.swift` — read-side trie ports
- `CollationData.swift` — "UCol" v5 binary reader (root + tailorings +
  `Reordering`), bundled resources accessors
- `NormalizationData.swift` + `NFDIterator.swift` — nfd.bin reader + fused
  NFD front end (fast path for bare starters)
- `CollationElements.swift` — `CEIterator`: lazy CE production, contexts
  (contraction/prefix matching), numeric, base fallback
- `CollationCompare.swift` — level-by-level compare (lazy via `ce(at:)`)
- `SortKey.swift` — sort key writer + BOCSU identical level
- `CollationOptions.swift` — public options ↔ ICU options word
- `RootCollator.swift` — public API: `compare`, `sortKey`,
  `init(tailoringNamed:)`, `defaultOptions`

## Doc index (Docs/)

01 ICU4C investigation · 02 ICU4X strategy · 03 Swift strategy ·
04 **milestone plan + status table (the spine — keep it updated)** ·
05–10 milestone reports (2–7) · 11 milestone 7.5 report (tests + perf) ·
12 rule-builder decision record · HANDOFF (this file)

Convention: every milestone/round updates doc 04's table + outcome note and
gets a detailed report; decision records for surprising cuts; commit
messages carry the full summary (no attribution line!).
