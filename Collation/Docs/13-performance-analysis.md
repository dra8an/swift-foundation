# Performance Analysis — Pure-Swift UCA Collation

> Written 2026-06-14. Consolidates the performance work tracked round-by-round
> in `11-milestone-7.5-report.md` into one standalone analysis: methodology,
> the full optimization journey, where the time goes today, what the residual
> gap to ICU4C is and why it is irreducible, and how to reproduce all of it.
>
> Scope: `RootCollator.compare` and `RootCollator.sortKey` against the CLDR
> root collation, release builds, ICU 79 as the reference. This document is
> descriptive of the *current* state; the per-round narrative (what changed
> and why, in order) lives in doc 11.

## 1. Executive summary

`compare()` is within **2.8–5×** of ICU4C across the corpora, after starting the
optimization effort **~75–94× slower**. Sort keys are within **2.2–4.4×**.
Every result is byte-identical to ICU's (sort keys) or verdict-identical
(comparisons), enforced by ~2.8M differential pairs per option set.

Representative figures (release, ns/op; this machine is a loaded multi-user
host, so these are the lower cluster of many runs — the floor that reflects
code cost rather than scheduler contention; see §2.4):

| corpus | compare (ours) | compare (ICU) | ratio | sortKey (ours) | sortKey (ICU) | ratio |
|---|---|---|---|---|---|---|
| ASCII  | ~79 ns  | ~16 ns | ~4.9× | ~720 ns  | ~205 ns | ~3.5× |
| Latin  | ~82 ns  | ~20 ns | ~4.1× | ~1040 ns | ~235 ns | ~4.4× |
| CJK    | ~350 ns | ~78 ns | ~4.4× | ~850 ns  | ~245 ns | ~3.5× |
| paths  | ~163 ns | ~52 ns | ~3.1× | ~1610 ns | ~720 ns | ~2.2× |

(CJK and other non-Latin compare improved ~12–35% after removing the
`left == right` canonical-`==` shortcut — see §6.6, which profiles where the
non-Latin gap actually goes. The sorted Thai dictionary improved further to
**2.8×** via prefix-skip iterator reuse — see §6.7, which also records two
levers that profiled well but failed a wall-clock A/B and were reverted.)

The headline: **ASCII compare went 7437 → ~79 ns over the effort — a 94×
speedup**, closing the gap to ICU from ~75× to ~4.9×.

The remaining gap is not algorithmic. It is per-call overhead intrinsic to a
value-type `String` API (contiguous-storage acquisition, a cache lock, closure
entry) plus the fact that ICU's benchmark hands its fast path raw `char*`
pointers while ours must reach inside `String`. The arithmetic itself — the
mini-CE comparison, the CE iteration, the trie lookups — runs at ICU's speed.

## 2. Methodology

### 2.1 The benchmark harness

`Sources/Bench` (Swift) and `Tools/bench_icu.c` (C, linked against the
machine-local ICU 79 build) are deliberately identical in shape: read a corpus
file (one string per line), then time two loops over `reps` passes —

- **compare**: every adjacent pair, `compare(lines[i-1], lines[i])`;
- **sortKey**: `sortKey(for: line)` over every line.

Both report `ns/op`. The Swift side calls `RootCollator.compare` /
`.sortKey`; the C side calls `ucol_strcollUTF8` / `ucol_getSortKey` — ICU's
UTF-8 entry points, the closest analogue to our `String`-based API. Default
`reps = 200`.

This harness is the same one used since milestone 6; the numbers are
comparable across the entire history.

### 2.2 The four corpora

A *corpus file* is a plain-text list of strings to sort — one string per line,
UTF-8, no header or other structure. It is simply the body of sample text the
collator is run against. The harness reads it into an array of strings; the
compare loop then walks adjacent pairs (`compare(line[i-1], line[i])`) and the
sortKey loop generates a key per line. A 200-line corpus yields 199
comparisons per pass.

All four live in the package's `Tools/bench/` directory (full path on this
machine:
`~/Projects/claude/collation/swift-foundation/Collation/Tools/bench/`), checked
into git alongside the other developer tooling. They are benchmark aids, not
bundled into the library. Both harnesses take the path as an argument, e.g.
`Tools/bench/bench-ascii.txt`.

The four bundled corpora and their first lines:

| file | lines | first lines (verbatim) |
|---|---|---|
| `Tools/bench/bench-ascii.txt` | 200 | `emubcrdl` · `bqgbcnnchcrn` · `sdh` · `bssmbhbrejne` |
| `Tools/bench/bench-latin.txt` | 200 | `bjqijćus` · `üxb` · `tunnø` · `ôep` · `bąabaslj` |
| `Tools/bench/bench-cjk.txt`   | 200 | `仝跱纹蛖` · `斔銸瓪悏` · `鞧繁顱殰奁` · `睴鯕洏瞴` |
| `Tools/bench/bench-paths.txt` | 439 | `icu4c/source/i18n/alphaindex.cpp` · `…/anytrans.cpp` · `…/anytrans.h` |

Provenance:

- The first three (`ascii`, `latin`, `cjk`) are **synthetic** — their contents
  are random-looking letter sequences, not real words, clearly built to stress
  character throughput without leaning on any language's vocabulary (ascii:
  A–Z; latin: seeded with Latin-1/Extended-A accents like ć/ø/ô; cjk: random
  Han). They were committed with the milestone-6 baseline (`0a74500`); the
  exact generator was not checked in, so the method isn't recoverable from the
  repo — only the files themselves. (Distinct from the *fuzz* corpus, which
  does ship its generator, `Tools/gen_fuzz_corpus.py`.) Because these are fixed
  files, the benchmark is reproducible regardless.
- `bench-paths.txt` is **real data**: source-file paths from the ICU tree
  (`icu4c/source/i18n/*.{cpp,h}`, path-prefixed and sorted), generated in the
  identical-prefix-skip round so adjacent lines share long prefixes
  (`anytrans.cpp` then `anytrans.h`) — the shape of a real sort-comparison
  workload. Regenerate with:
  `(cd <icu>/icu4c/source/i18n && ls *.cpp *.h | sed 's|^|icu4c/source/i18n/|') | sort > Tools/bench/bench-paths.txt`

Measured characteristics (the shape of the input governs which paths run):

| corpus | lines | avg length | avg shared prefix | within fast-Latin range |
|---|---|---|---|---|
| ASCII  | 200 | 7.3 scalars  | ~0.05 | 100% |
| Latin  | 200 | 6.1 scalars  | 0     | 100% (incl. precomposed accents ≤ U+017F) |
| CJK    | 200 | 4.0 scalars  | 0     | 0% |
| paths  | 439 | 33.5 scalars | 26.2  | 100% (sorted file paths) |

Why each matters:

- **ASCII / Latin** exercise the fast Latin path end to end; Latin adds
  two-byte (U+0080..U+017F) characters that test the UTF-8 lead+trail
  assembly. Neither has shared prefixes (unsorted), so they isolate
  per-character throughput.
- **CJK** is entirely outside the fast-Latin range and forces the regular
  CE-iterator pipeline on every character — the worst case, and the control
  showing that fast-Latin work doesn't regress non-Latin text (beyond the
  ~6% cost of *attempting* the byte path before bailing).
- **paths** (added in round 5) models the real workload the levers target:
  comparing adjacent rows of *sorted* data, where strings share long
  prefixes (26 of 33 scalars on average). This is where the identical-prefix
  skip pays off and where naive O(prefix) re-iteration would dominate.

Five further corpora are **large real-data** sets rather than throughput
micro-corpora, covered in §6: `bench-thai.txt` (32,895 Thai dictionary words,
`th`; §6) and three added later — `bench-cjk-dict.txt` (316k CJK words),
`bench-khmer.txt` (81k Khmer words), and `bench-uca.txt` (206k all-script
sequences from the UCA conformance data) — all in §6.8. Unlike the four
micro-corpora, these come straight from ICU's own test data; their provenance
and the fairness/licensing notes are in §6.8.

### 2.3 ICU as the reference

ICU 79.0.1, built machine-locally at `~/Projects/claude/collation/icu-build`
(outside the repo). It serves two roles: the **correctness oracle** (every
differential matrix and sort-key byte-comparison is judged against it) and the
**performance baseline**. Using the same Unicode/CLDR version on the same
machine makes the ratios meaningful.

A caveat on ICU's absolute numbers: `ucol_strcollUTF8` receives raw
NUL-terminated `char*`. Our API receives a Swift `String` and must acquire its
bytes. Part of our gap is this API-shape difference, not collation work — see
§5.

### 2.4 Measurement discipline

Two techniques used throughout:

- **Interleaved A/B.** For every round, the old and new release binaries were
  run back-to-back in the same loop (`/tmp/bench-base` vs `.build/release`).
  This controls for machine load: even when absolute numbers drift 2×, the
  *ratio* between two binaries on the same load is stable. The round-over-round
  deltas in §3 come from these interleaved runs and are far more trustworthy
  than any single absolute figure.
- **Deletion experiments.** To attribute cost, individual components were
  stubbed out (the `==` precheck, the cache lock, the prefix walk) and the
  binary re-benched. The delta is that component's cost. This is how §4's
  anatomy was derived — by measurement, not by reading the code.

The host runs at load average 5–9 with ~17 users. Single best-of-N runs
approach the true single-thread cost; the median drifts with contention.
Absolute figures here are the lower cluster of 3–6 runs and should be read as
"≈", accurate to maybe ±15%. The deltas and ratios are solid.

## 3. The optimization journey

Each row is the state *after* that round, ASCII compare unless noted. Deltas
are from interleaved A/B; absolutes are representative. Full narrative per
round: doc 11.

| round | change | ASCII compare | note |
|---|---|---|---|
| — | pre-lazy baseline | 7437 ns | full CE materialization, eager |
| (M6) | lazy CE generation | 2225 ns | compare pulls CEs on demand |
| 1 | NFD fast path + lookahead bypass + `==` shortcut | 1225 ns | bare starters skip buffering |
| 4 | buffer/iterator reuse (scratch pool) | ~690 ns | no per-call heap allocation |
| 5 | identical-prefix skip | ~697 ns | **paths 10532 → ~1060 (10×)** |
| 6 | trivial data access (ARC elimination) | ~239 ns | the single biggest lever |
| 8 | single-trie `nfd.bin` | ~239 ns | **Latin/CJK −11/−15%**; ASCII unaffected |
| 9 | fast Latin (scalar) | ~101 ns | mini-CE table compare |
| 10 | fast Latin (raw UTF-8) | **~79 ns** | byte feed, no scalar decode |
| 11 | remove `left == right` (canonical `==`) | ~79 ns | ASCII unaffected; **non-Latin −12…35%** (§6.6) |
| 12 | NFD front-end allocation cuts | ~79 ns | ASCII unaffected; **Thai sortKey −8%** (§6.7) |
| 13 | reuse prefix-skip iterators (ARC) | ~79 ns | ASCII unaffected; **Thai compare −13%** (§6.7) |

(Round 1 introduced the `if left == right` shortcut as an optimization;
round 11 removed it after profiling showed Swift's canonical `==` dominates
the non-Latin path — see §6.6. It never helped ASCII/Latin, which return from
the byte fast path before reaching it.)

Cumulative: **94× on ASCII compare**. The same levers moved the other corpora:

| corpus | start (M6 lazy) | today | speedup |
|---|---|---|---|
| ASCII compare  | 2225 ns | ~79 ns  | 28× (94× from pre-lazy) |
| Latin compare  | 2344 ns | ~82 ns  | 29× |
| CJK compare    | 2502 ns | ~395 ns | 6.3× |
| paths compare  | (≈10500) | ~163 ns | ~64× |

Sort keys, same journey (representative):

| corpus | round 1 | today | ICU |
|---|---|---|---|
| ASCII  | 2734 ns | ~720 ns  | ~205 ns |
| Latin  | 3499 ns | ~1040 ns | ~235 ns |
| CJK    | 2334 ns | ~850 ns  | ~245 ns |
| paths  | (n/a)   | ~1610 ns | ~720 ns |

### 3.1 What each lever actually bought

- **Lazy CE generation (M6).** The primary level usually decides a comparison
  after a few characters; materializing all CEs up front was pure waste. 3.3×
  on its own. This is structural — comparison pulls CEs through `ce(at:)` and
  stops at the first differing level.

- **Round 1 — NFD fast path.** Between reorderable units, a bare starter with
  no canonical decomposition is a hard boundary and is emitted with no unit
  buffer or marks handling. Covers all ASCII (`< 0xC0`) and most letters.

- **Round 4 — buffer reuse.** `compare` was allocating two full iterator
  stacks per call. A lock-guarded pool of reusable `ScratchBuffers` (the CE
  iterators, the sort-key byte buffer, the per-level buffers) reset with
  `removeAll(keepingCapacity:)` makes steady-state calls allocation-free —
  ICU's stack-buffer strategy, which Swift arrays can't express, approximated
  by reuse. ~1.8×.

- **Round 5 — identical-prefix skip.** Equal scalar prefixes produce identical
  CEs, so iteration starts at the first difference — when restarting there is
  provably safe (the unsafe-backward set, already serialized in ICU's data
  files, plus a lead-ccc check). On unsorted corpora this is ~0 (nothing
  shared); on sorted data (paths) it is **10×**, because it converts an
  O(prefix-length) re-scan into an O(1) skip. The lever real sorting
  workloads care about.

- **Round 6 — trivial data access (the biggest single win, 690 → 239 ns).**
  Profiling — not intuition — found the dominant cost was *reference counting*,
  not arithmetic. `CEIterator.lookup` returned its `CollationData` by value
  once per scalar, and with eight Swift arrays inside, every copy was eight
  retain/release pairs. Three fixes: (a) a `DataStorage` class owns all parsed
  memory and the data structs hold `UnsafeBufferPointer` views — one retain
  per copy, and bounds-check-free reads; (b) a fully trivial `CollationDataView`
  (pointers + ints, zero ARC) for the per-scalar dispatch; (c) `isEmpty`-guards
  before `removeAll`, because the empty-array singleton is never uniquely
  referenced and was taking the copy-on-write slow path every call. This 2.9×
  is the lesson of the whole effort: **in Swift, ARC traffic on a hot path
  can cost more than the work itself.**

- **Round 8 — single-trie `nfd.bin`.** Replaced two ~11-probe binary searches
  per scalar (ccc, decomposition) with one two-load trie lookup yielding
  ccc + lead-ccc + decomposition. Helps exactly where normalization runs —
  Latin −11%, CJK −15%; ASCII is untouched because `< 0xC0` short-circuits
  before the data is consulted.

- **Rounds 9–10 — fast Latin.** The precompiled mini-CE tables already ship in
  our bundled data (they were built by ICU from the same source). Round 9
  ported the comparison loop over scalars (239 → 101 ns); round 10 completed
  it with ICU's `compareUTF8`, reading characters as raw bytes from
  `String`'s contiguous UTF-8 storage (101 → 79 ns), so accented Latin costs
  the same as ASCII (a two-byte assembly is two ops). See §4 for why round 10
  also needed three Swift-specific structural fixes to not be *slower*.

## 4. Anatomy of a compare today

Where the ~79 ns of an ASCII `compare()` goes, by deletion experiment
(stub out a component, re-bench, take the delta):

| component | cost | notes |
|---|---|---|
| contiguous-storage acquisition | ~17 ns | `utf8.withContiguousStorageIfAvailable` × 2; small-string stack spill |
| setup-cache lock (`os_unfair_lock`) | ~10 ns | guards the per-options `FastLatinSetup` |
| identical-prefix byte scan + safety | ~6 ns | one memcmp-style loop; ~0 shared here |
| the `compareUTF8` mini-CE loop | ~30 ns | the actual collation work — ≈ ICU's core cost |
| closure entry, eligibility checks, options word | ~16 ns | calling convention + bookkeeping |

The collation arithmetic (~30 ns) is roughly ICU's own cost. The other ~49 ns
is the price of reaching collation *through a Swift `String` value*, where
ICU's bench starts from a raw pointer.

### 4.1 The round-10 lesson: ARC ambushes on the fast path

The first build of the UTF-8 path was *slower* than the scalar path it
replaced. Profiling found three Swift-specific traps, all now fixed and
documented because they will recur in any future fast path:

1. **Closures capturing `self` copy the struct.** The
   `withContiguousStorageIfAvailable` closures captured the collator;
   `RootCollator` holds several references, so each call did a struct copy
   (visible as `initializeWithCopy for RootCollator` in the profile). Fix:
   the byte path is a `static` function taking only trivial parameters.

2. **`base?.field` projections retain.** Rebuilding the fast-Latin table view
   or the safety view per call copied an optional's payload (+1 retain each).
   Fix: build them once at init (`RestartSafety`, `NormalizationDataView`,
   the stored `fastLatinTable`). `RootCollator` became `@unchecked Sendable`
   (immutable views into retained storage).

3. **Eager setup resolution taxes the bail path.** Resolving the per-options
   `FastLatinSetup` before the eligibility gate made every CJK compare pay the
   cache lock for a path that always bails. Fix: resolve lazily *inside* the
   gate, with a needs-setup sentinel retried once per options change.

The general principle: on a path measured in tens of nanoseconds, a single
retain (~5 ns) is a major line item. Trivial value types and stored views,
not convenience projections, are mandatory.

## 5. The residual gap on the fast (ASCII) path

This section dissects the *fast-Latin* ASCII gap, which is small in absolute
terms and mostly API-boundary cost. The much larger non-Latin gap (CJK, Thai)
is a different story — profiled separately in §6.6, where one big chunk turned
out reducible (Swift's canonical `==`) and the rest is value-type overhead.

ICU's ASCII compare is ~16 ns; ours is ~79. The ~63 ns difference breaks down
as:

- **~30 ns** — the collation loop, which we run at parity with ICU. Not
  recoverable without changing the algorithm (and it's already ICU's).
- **~17 ns** — contiguous-storage acquisition. ICU's benchmark is handed a
  `char*`; we hold a `String` value and must call into the stdlib to borrow
  its bytes (and small strings spill to the stack first). This is the cost of
  a *safe, value-type* string API. It would vanish only if the API took
  `UnsafeBufferPointer<UInt8>` directly — a different, lower-level contract.
- **~10 ns** — the setup-cache lock. ICU bakes options into the collator
  object at construction, so its compare reads a ready field; our API takes
  options per call, so we cache the computed setup behind a lock. Removable
  only by an API change (a "frozen options" / session object) — which is an
  **M8 API-design question**, to settle with swift-foundation maintainers, not
  a port-level optimization.
- **~6 ns** — the `==`/prefix bookkeeping that ICU also does, roughly at par.

So the honest conclusion: **the collation engine is at ICU's speed; the gap is
the API boundary.** Chasing it further means trading the current clean
value-type API (`compare(_ : String, _ : String, options:)`) for a
lower-level one. That trade belongs to the Foundation-integration discussion,
not here. Within the API we have, the engine is done.

### 5.1 CJK: a different gap

CJK compare is ~395 vs ICU's ~78 (~5×) and has no fast path on either side —
both run the full CE pipeline. Our gap here is the CE-iterator machinery: the
fused-NFD front end, the lazy CE buffer, and per-scalar trie dispatch, against
ICU's hand-tuned `UTF16CollationIterator`. This is closable with more
profiling (the iterator still allocates its growable CE array; ICU uses a
fixed CEBuffer with a stack tail), but with diminishing returns and real
complexity. It was judged a reasonable stopping point: 5× on the corpus that
is rarest in latency-sensitive sorting (CJK strings are short and primary
differences resolve fast in absolute terms).

## 6. Case study: the Thai dictionary (32k words)

A throughput test on a large, real, non-Latin, contraction-dense corpus, run
after the perf track closed (2026-06-14) to confirm the engine holds its ratio
under a demanding *tailored* workload — the first benchmark of a tailoring
rather than the root collator.

### 6.1 The corpus

`Tools/bench/bench-thai.txt` is the **32,895 Thai words of ICU's `riwords.txt`**
(the dictionary-order fixture also driving `ThaiDictionaryTests`), with the
comment header and BOM stripped. The words are in Thai dictionary order, so
adjacent pairs share ~3.3 scalars of prefix; average length 6.8 scalars,
longest 57. Regenerate from the bundled fixture:

```sh
python3 -c "import sys; \
print('\n'.join(l.strip() for l in \
open('Tests/CollationTests/Conformance/riwords.txt', encoding='utf-8-sig') \
if l.strip() and not l.startswith('#')))" > Tools/bench/bench-thai.txt
```

Both sides use Thai collation — ours via `RootCollator(tailoringNamed: "th")`,
ICU via `ucol_open("th")` — over the same word list. Both harnesses take an
optional locale/tailoring argument for this (added 2026-06-14):
`Bench <corpus> <reps> th` and `bench_icu <corpus> <reps> th`. (The ICU bench's
line cap was also raised 4096 → 40000 to hold the corpus.)

### 6.2 Results

Release, ns/op; medians of 3 runs (spreads were tight, ±3%):

| op | ours | ICU 79 | ratio |
|---|---|---|---|
| compare | ~820 ns | ~289 ns | **2.8×** |
| sortKey | ~950 ns | ~291 ns | **3.3×** |

Note: this compare figure is on dictionary-*adjacent* pairs — collation's
hardest case (minimal pairs; see §6.4). On random Thai pairs the absolute cost
roughly halves (~420 ns), though the ratio to ICU widens. Both are real; §6.4
explains the difference. (These are post-§6.7 numbers. The progression on
sorted-Thai compare: ~1255 ns before round 11 → ~975 (remove canonical `==`,
§6.6) → ~820 (reuse prefix-skip iterators, §6.7). sortKey: ~1130 → ~950 across
rounds 12–13.)

### 6.3 Why these numbers — the CJK story, not the Latin one

- Thai is **entirely outside the fast-Latin range** (the U+0E00 block), so
  every comparison runs the **full CE-iterator pipeline**, exactly like CJK,
  nowhere near ASCII/Latin's fast-path numbers — the fast-Latin win is
  Latin-specific and simply does not apply. Sorted-Thai compare (2.8×) now
  edges *below* the CJK compare ratio (~5×): the round-13 prefix-skip reuse
  pays off precisely on a sorted dictionary's long shared prefixes, which the
  CJK corpus does not have.
- Thai is **contraction-heavy**: prevowel+consonant pairs are contractions, so
  the iterator spends real time in the `UCharsTrie` contraction-matching path
  that ASCII/Latin never enter.
- The **identical-prefix skip is blunted** for Thai (the words share ~3.3
  scalars but Thai letters are contraction trailers in the unsafe-backward
  set, so the boundary is usually unsafe) — **but this is not why Thai is
  slow.** See §6.4: the cost is comparison *depth*, not the prefix. The skip
  being blunted is a side note, not the bottleneck.
- **Sort keys at 3.5×** are consistent with every other corpus (ASCII 3.5×,
  CJK 3.5×, Latin 4.4×): sortKey never had a fast path on either side, so it
  holds a uniform ratio regardless of script.

The conclusion: on heavy non-Latin, tailored, contraction-dense work the engine
is **~2.8–3.3× from ICU4C** (compare on a sorted dictionary now ahead of the
CJK ratio thanks to prefix-skip reuse; sortKey holds the uniform ~3.3×). The
fast-Latin gains were always Latin-specific; this 32k-word dictionary confirms
the rest of the engine holds — and improves — its ratio under a genuinely
demanding workload.

### 6.4 Sorted vs shuffled: minimal pairs, not the prefix skip

`riwords.txt` is in Thai dictionary order, so the §6.2 run compares adjacent
*dictionary-consecutive* words. Shuffling the corpus (`bench-thai-shuffled.txt`,
seed 42) makes adjacent pairs random instead. Compare, release, medians:

| Thai compare | ours | ICU 79 |
|---|---|---|
| sorted (dictionary-adjacent) | ~975 ns | ~289 ns |
| shuffled (random pairs) | ~465 ns | ~102 ns |

(Numbers post-§6.6; the ratio and mechanism below are unchanged from the
pre-fix ~1255 / ~715.) **Sorted is ~2× slower than shuffled — and ICU shows
the identical pattern (289 vs 102).** That ICU exhibits it too is the proof it
is a fundamental property of collation, not an artifact of our code.

The mechanism is **comparison depth**, established by instrumentation (CEs
generated per comparison):

| | CEs per compare | where the difference resolves |
|---|---|---|
| sorted (dictionary-adjacent) | **~8.9** | deep — primary-equal, decided at secondary/tertiary |
| shuffled (random pairs) | **~2.5** | shallow — a primary difference in the first scalar or two |

Dictionary-consecutive words are **minimal pairs**: `กง` / `ก่ง` / `ก้ง` — the
same base differing only by a tone mark. They are equal at the primary (and
often secondary) level, so the lazy comparison cannot stop early; it must
generate the *full* CE sequence for both words and walk every level to find the
difference (~9 CEs). Random pairs differ at the primary level in the first
character or two, so the comparison stops almost immediately (~2.5 CEs). 3.6×
the CE work → the slower time. Sorted-adjacent comparison is the *hardest* case
for any collator, which is exactly why ICU slows down on it too.

**This corrects an earlier, wrong explanation.** A previous version of this
section attributed sorted Thai's cost to the blocked identical-prefix skip
(the shared prefix being re-iterated). That was incorrect, and §6.5 records the
experiment that disproved it: the prefix skip contributes almost nothing here
(the skipped prefix averages well under one scalar), and skipping it does not
speed Thai up. The cost is generating and comparing ~9 CEs of a minimal pair,
which no prefix manipulation can avoid — it is the CE-iterator's per-element
cost (§5.1), the same lever as CJK.

(The contrast with `paths` still holds, but for a different reason than first
stated: paths adjacent pairs share long *prefixes* yet differ at the primary
level soon after — they are not minimal pairs — and the prefix is made of safe
characters, so the skip fires and removes it. Thai pairs are both unsafe-prefix
*and* minimal pairs; only the second property actually drives the cost.)

Regenerate the shuffled corpus deterministically:

```sh
python3 -c "import random; \
ws=[l for l in open('Tools/bench/bench-thai.txt',encoding='utf-8').read().split(chr(10)) if l]; \
random.Random(42).shuffle(ws); \
open('Tools/bench/bench-thai-shuffled.txt','w',encoding='utf-8').write(chr(10).join(ws)+chr(10))"
```

### 6.5 Bounded backward backup: implemented, measured, reverted (a wrong lever)

This subsection records a mistake and its correction, because the reasoning
error is instructive.

The hypothesis (an earlier §6.4) was that sorted Thai is slow because the
identical-prefix skip is blocked: on an unsafe boundary our code resets to
position 0 and re-iterates the shared prefix, whereas ICU backs up only to the
nearest *safe* character (`rulebasedcollator.cpp`: `while(--equalPrefixLength >
0 && isUnsafeBackward(c, numeric))`). The proposed fix — a bounded backward
walk to the nearest safe scalar — was estimated at ~285 ns on Thai. **It was
implemented, measured, and reverted with no gain (a slight regression).**

The failed experiment was itself the disproof. If the blocked skip were the
cost, skipping the prefix would have helped; it didn't. Instrumenting why
revealed two things:

- The shared prefix the skip could recover averages well under one scalar in
  effect (Thai letters are pervasively unsafe-backward, so the safe restart
  point is usually position 0), and the index-walk to find it costs about as
  much as it saves.
- More fundamentally — the §6.4 CE-count instrumentation — the cost is not the
  prefix at all but the **~9 CEs of a minimal pair** generated and compared
  across all levels. The prefix is a rounding error next to that.

So the prefix skip was a **red herring** for Thai. The §6.4 force-on
measurement that suggested a ~335 ns "opportunity" was misleading: forcing the
skip on truncates the strings (incorrectly skipping unsafe shared content),
which shortens the minimal-pair comparison — but that shared content is not a
removable prefix, it is the body of the words, and removing it changes the
result. No correct optimization can recover it.

**Outcome.** Reverted to the round-5 reset-to-0. Correctness was never in doubt
(the differential matrices and Thai dictionary test stayed green throughout);
the change was dropped because it does not earn its cost *and* because it
targeted the wrong thing. The real Thai/CJK lever is CE-iterator efficiency
(§5.1) — generating and comparing those ~9 CEs faster (ICU uses a fixed CE
buffer with a stack tail and no per-call allocation; we use a growable array).
That, not the prefix skip, is where the ~4× gap lives.

**Lesson.** Always instrument the actual work before theorizing about the
cause. "Sorted slower than shuffled" looked like a skip problem and was really
a comparison-depth property — one ICU shares (§6.4). A single CE-count
measurement would have prevented the whole detour.

### 6.6 Why ~4× when "it's just bitwise arithmetic" — a CE-pipeline profile

The mini-CE comparison, CE generation, and trie lookups are indeed integer/bit
work that should run at ICU's speed. So why is non-Latin compare ~4× slower?
Profiling sorted Thai (`sample`, leaf self-time) answers it: **the collation
arithmetic is the minority of the time.** Categorizing the samples:

| bucket | ~share | what it is |
|---|---|---|
| Swift `String ==` (canonical) | **~30%** | `_InternalNFC.Iterator`, `_slowCompare`, `getNormData` — see below |
| ARC (retain/release/uniref) | ~20% | refcounting `String`-backed iterators and `Array` storage |
| Array growth + `memmove` | ~13% | `replaceSubrange` from NFD-decomposition appends and the CE buffer |
| exclusivity enforcement | ~5% | `begin/endAccess` on `inout`-through-class buffer access |
| pool lock + contiguous-storage | ~4% | per-call `os_unfair_lock` + `withContiguousStorageIfAvailable` |
| **our CE/NFD/trie arithmetic** | the rest | `appendMore`, `NFDIterator`, `compareUpToQuaternary`, `UCharsTrie` |

So more than half the time was Swift-runtime overhead, not collation. The
single largest item was a self-inflicted one, now fixed:

**The `left == right` shortcut (removed).** We had an early `if left == right
{ return .same }`. Swift's `String ==` is *canonical equivalence*: for two
strings that are not binary-equal it must rule out canonical equivalence,
and on text containing combining marks (Thai tone marks, vowel signs) it drops
to a normalizing comparison (`_InternalNFC.Iterator` + `_slowCompare`). That
cost **~250–400 ns on every non-equal non-Latin compare**. The CE pipeline
already handles canonical equivalence correctly (the NFD front end produces
equal CEs for equivalent strings), so the shortcut was redundant — pure cost.
Removing it (verified: 61 tests green, ICU sort cross-check still
tie-only):

| corpus | before | after | saved |
|---|---|---|---|
| Thai sorted | ~1255 ns | **~975 ns** | ~280 (22%) |
| Thai shuffled | ~715 ns | **~465 ns** | ~250 (35%) |
| CJK | ~395 ns | **~350 ns** | ~45 (12%) |
| ASCII / Latin | ~80 / 78 ns | unchanged | — (byte path returns first) |

**The rest is structural.** Two smaller levers were measured and judged not
worth their cost or complexity: an early byte-path bail for non-Latin text
(the byte path always bails for Thai, duplicating the prefix scan + safety —
but worth only ~25 ns), and `-enforce-exclusivity=unchecked` (~50 ns, a
build-flag safety trade-off). What remains — ARC on `String`/`Array` storage
and growable-array reallocation — is the value-type cost §5 describes,
intrinsic to the current design. Closing it means ICU's model: fixed/stack CE
buffers instead of growable arrays, and fewer per-call iterator allocations to
cut the refcount traffic. That is a real refactor with diminishing returns, not
a one-line fix — but the headline answer to "why 4×" is now concrete: it was
~30% Swift canonical `==` (fixed) plus ~40% other Swift value-type overhead,
and only the remainder is the arithmetic, which does run at ICU's speed.

### 6.7 Chasing the residual: two wins and two honest negatives

§6.6 ended pointing at "the fixed/stack-buffer refactor ICU uses" as the next
lever. Pursuing it produced a result worth recording in full, because **half of
what looked promising under the profiler did not survive a wall-clock A/B.**

**The CE-buffer refactor (tried, neutral, reverted).** The headline candidate
from §6.6 was replacing the growable `[Int64]` CE buffer with a raw-pointer
fixed buffer (ICU's `int64_t ceBuffer[40]` + heap overflow), eliminating
copy-on-write probes, exclusivity checks, and bounds checks on every CE
append/index. It was implemented end-to-end and came out **neutral** — Thai
sorted compare ~947 → ~915 ns, inside the noise band. The reason: with the
scratch pool already reusing the array at steady-state capacity, `append` on a
uniquely-referenced buffer is cheap, and the "~13% Array growth + memmove" line
in §6.6's table was **not the CE buffer at all** — re-profiling traced it to
`NFDIterator.refill`. Reverted.

**NFD front-end allocation cuts (round 12, kept).** That re-profiling pointed
at the real allocator traffic, in the normalization front end:
- `flushMarks` sorted ≥2 combining marks by building a throwaway
  `[(ccc, scalar)]`, `insert`-ing into it (a `memmove` per insert), then
  materializing a *second* array via `.map`. Replaced with an in-place
  insertion sort on the existing `marks` buffer — zero temporaries.
- `refill` cleared and refilled a per-scalar `decomposed` scratch buffer for
  *every* scalar, including the overwhelming majority that map to themselves
  (bare consonants, marks, CJK). A `hasDecomposition` gate now sends those
  straight through with no buffer touch.

Both are output-identical (UCA conformance + the Thai dictionary suite stay
green). sortKey — which always fully decomposes — improved ~8–11%; compare
(which short-circuits before decomposing much) stayed roughly flat.

**Reuse the prefix-skip iterators (round 13, kept — the real ARC win).**
Attributing the per-compare ARC by caller showed it concentrated in `compare`
itself: the identical-prefix skip walks both inputs' scalars to find the shared
prefix, then **threw those iterators away** and built fresh
`String.UnicodeScalarView` iterators inside each `CEIterator.reset(skippingFirst:)`
— retaining `String` storage four times per compare and *re-walking the shared
prefix*. The skip walk already leaves each iterator positioned past the prefix
with the first unequal scalar in hand; handing that (pending scalar + iterator)
straight to the NFD front end via a new `reset(source:first:)` removes two of
the four iterator builds and the re-walk. Sorted-Thai compare **~947 → ~820 ns
(~13%)**, consistent across five sequential runs; this is the lever that scales
with shared-prefix length, i.e. with real sorting workloads. `takeScratch` ARC
also dropped ~6× in the profile as a side effect.

**The `isUnsafe` bitset (tried, no measurable gain, reverted).** The restart
check ran up to two binary searches over the unsafe-backward boundary sets per
compare; profiling put it at ~7% (≈188 leaf samples). A precomputed 8 KB BMP
bitset cut those samples to **zero** — and yet an interleaved A/B (with vs
without, run alternately so machine load hits both) showed the wall-clock delta
hovering at ±2% with the sign flipping between batches: **no reliable win.** The
binary search ran on small, cache-hot arrays — cheap in real nanoseconds even
though it sampled frequently — and trading it for an 8 KB (possibly cache-cold)
bitset is a wash. Reverted: 8 KB/collator + a 64K-iteration init for no gain.

**The meta-lesson.** This codebase fooled the profiler's *leaf self-time* twice
in the same way — once on the CE array (§6.6's "13%"), once on the
unsafe-backward search — both times overstating the wall-clock cost of
memory-latency code that overlaps with other work or lives in cache. The levers
that actually held removed **allocations** (round 12) and **redundant
algorithmic work plus real `String`-storage retains** (round 13), not sampled
hot-spots per se. Operational rule going forward: **A/B every lever before
trusting it; a sample count going to zero is a hypothesis, not a result.**

### 6.8 Three more large real-data corpora: CJK, Khmer, the full UCA repertoire

The Thai dictionary (§6) showed that real, large, non-Latin word lists tell a
different story than the 200-line micro-corpora. Three further corpora extend
that coverage, all drawn from ICU's own test data so the inputs are real and
the comparison is apples-to-apples (both engines read the same UTF-8 files):

| corpus | lines | source | run as |
|---|---|---|---|
| `bench-cjk-dict.txt` | 315,964 | ICU `brkitr/dictionaries/cjdict.txt`, word column (before the tab), header stripped | `zh` |
| `bench-khmer.txt` | 81,028 | ICU `brkitr/dictionaries/khmerdict.txt`, words | root |
| `bench-uca.txt` | 206,273 | ICU `CollationTest_NON_IGNORABLE_SHORT.txt` (already in-repo, `Tests/.../Conformance/`), hex sequences decoded to UTF-8, surrogate-bearing lines skipped | root |

Results (release, ns/op, 20 reps — enough for a stable read on these sizes;
see the rep-count note in §2.4):

| corpus | compare (ours) | compare (ICU) | ratio | sortKey (ours) | sortKey (ICU) | ratio |
|---|---|---|---|---|---|---|
| CJK dict (316k, `zh`)     | ~422 ns | ~93 ns  | **4.5×** | ~631 ns | ~164 ns | 3.8× |
| Khmer (81k, root)         | ~562 ns | ~120 ns | **4.7×** | ~976 ns | ~268 ns | 3.6× |
| UCA all-scripts (206k)    | ~236 ns | ~83 ns  | **2.8×** | ~591 ns | ~149 ns | 4.0× |

What they confirm:
- **CJK at 4.5×** matches the synthetic CJK micro-corpus (§5.1) on *real* Han
  vocabulary under the `zh` tailoring — the engine holds its ratio when the
  input stops being random and becomes a 316k-word dictionary.
- **Khmer at 4.7×** is a script class nothing else here benchmarks (no `km`
  tailoring is bundled, so it runs under root); it sits in the same ~4–5× band
  as CJK, evidence the regular pipeline's ratio is script-independent.
- **UCA all-scripts at 2.8×** is the broadest input — every script, in strict
  collation order, dominated by short 2–5-code-point sequences (many combining
  permutations). The low ratio reflects how often the primary level decides
  immediately on these short, distinct sequences; sortKey, which always runs
  the full pipeline, holds the usual ~4×.

**Sorted vs shuffled.** All three ship in sorted order — CJK and Khmer in
code-point order (their native dictionary order), UCA in *collation* order (the
conformance file lists sequences in sort order by construction). A seed-42
shuffled variant of each (`*-shuffled.txt`, same shuffle seed as
`bench-thai-shuffled`) collapses the shared prefix to ~0, isolating the
sorted-vs-shuffled effect:

| corpus | compare sorted | compare shuffled | direction |
|---|---|---|---|
| CJK (`zh`)  | ~411 ns | ~288 ns | sorted **slower** |
| Khmer (root)| ~542 ns | ~336 ns | sorted **slower** |
| UCA (root)  | ~234 ns | ~358 ns | sorted **faster** |

CJK and Khmer reproduce the Thai §6.4 result: sorted dictionary words are
minimal pairs that must be walked deep before a difference appears, so sorted is
*slower* than shuffled — and ICU shows the same direction (Khmer 120 → 61 ns),
confirming it is intrinsic to collation, not a Swift artifact. UCA inverts
because it is short combining-mark sequences in collation order, not words:
sorted-adjacent sequences are often primary-equal/near-equal and decide quickly,
while shuffling pairs arbitrary scripts that take longer to resolve (ICU agrees,
93 → 112 ns). Khmer, with the deepest shared prefix (4.5 scalars), is the
closest of the three to Thai's minimal-pair stress; CJK and UCA are dominated by
short strings, so the prefix-skip lever barely engages.

Regenerate (the dict files need the ICU source clone; the UCA file is derived
from in-repo data; shuffle with `python3 -c "import random,sys; \
L=open(f).read().splitlines(); random.seed(42); random.shuffle(L); \
open(f.replace('.txt','-shuffled.txt'),'w').write('\n'.join(L)+'\n')"`):
```sh
ICUDICT=<icu>/icu4c/source/data/brkitr/dictionaries
grep -vP '^\s*#' "$ICUDICT/cjdict.txt"   | sed '/^[[:space:]]*$/d' | cut -f1 > Tools/bench/bench-cjk-dict.txt
grep -vP '^\s*#' "$ICUDICT/khmerdict.txt" | sed '/^[[:space:]]*$/d' | cut -f1 > Tools/bench/bench-khmer.txt
python3 -c "
out=[]
for l in open('Tests/CollationTests/Conformance/CollationTest_NON_IGNORABLE_SHORT.txt', encoding='utf-8'):
    l=l.strip()
    if not l or l.startswith('#'): continue
    cps=[int(x,16) for x in l.split()]
    if any(0xD800<=c<=0xDFFF for c in cps): continue   # Swift String can't hold lone surrogates
    out.append(''.join(chr(c) for c in cps))
open('Tools/bench/bench-uca.txt','w',encoding='utf-8').write('\n'.join(out)+'\n')"
```

**Licensing note.** `bench-khmer.txt` and `bench-uca.txt` derive from
Unicode/IBM-licensed ICU data (same terms as the conformance fixtures already
shipped). `bench-cjk-dict.txt` derives from `cjdict.txt`, which carries a
**Google + IBM** copyright — fine as a local benchmark aid, but flagged here
because, unlike the others, it would need a license review before being bundled
toward any Foundation contribution. (To benchmark CJK without it, the synthetic
`bench-cjk.txt` of §2.2 remains.) `bench_icu.c`'s line cap was raised
40,000 → 320,000 to hold these corpora.

## 7. Data-format decisions that paid off

A recurring theme: **the data we needed was already in the bundled binaries;
the work was reading it, not building it.** Twice this turned a presumed-large
lever into a small one.

- **Unsafe-backward set (round 5).** The identical-prefix skip was expected to
  need the single-trie `nfd.bin` rework for "safety markers." Investigation
  showed ICU already serializes the unsafe-backward set into the data files
  (slot 14); we'd just been skipping it. The skip shipped without the trie
  work.

- **Fast-Latin tables (rounds 9–10).** "Fast-Latin not ported" had been a
  recorded scope cut on the ICU4X precedent. But the precompiled mini-CE
  tables (format version 2) already ship at slot 15 of every bundled binary
  (root: 960 bytes; Latin tailorings carry their own; others fall back to the
  base's, as ICU's reader does). No builder, no new CLDR tooling — a read-side
  port. The cut was reversed by user decision once the cost was understood.

- **Single-trie `nfd.bin` (round 8).** The one format we *do* generate
  (`GenNormData` from `nfc.txt`). Repacking the sorted-array container as a
  flat two-level trie (deduplicated 64-value blocks; ccc + lead-ccc +
  decomposition in one value) replaced two binary searches with one lookup.
  96 KB on disk vs 34 KB — the size/speed trade chosen deliberately, since the
  file is bundled once and read on every scalar.

## 8. Sort keys

Sort keys are 2.3–4× from ICU and were *not* a focus of the late rounds —
fast Latin is compare-only (it has no key-generation analogue in ICU either),
and the prefix skip doesn't apply (a key is always built whole). What helped
sort keys was the shared infrastructure: buffer reuse (round 4) and trivial
data access (round 6) cut allocation and ARC the same way they did for
compare, taking ASCII sortKey from 2734 → ~720 ns.

The remaining gap is the per-level `SortKeyLevel` byte assembly and the
compression state machines (faithful ports of `collationkeys.cpp`), plus the
same `String`-acquisition overhead as compare. The keys are **byte-identical**
to `ucol_getSortKey` — verified by the differential key tests and 52k fuzz
keys — so there is no correctness headroom being traded for speed; it is purely
the assembly cost. A profiling pass on `writeSortKeyUpToQuaternary` (it still
swaps growable level buffers) is the obvious next lever if sort-key throughput
ever becomes the priority.

## 9. Reproducing these measurements

```sh
cd ~/Projects/claude/collation/swift-foundation/Collation
swift build -c release

# Ours (compare + sortKey), one corpus, 200 reps:
.build/release/Bench Tools/bench/bench-ascii.txt 200
# corpora: bench-ascii.txt bench-latin.txt bench-cjk.txt bench-paths.txt

# ICU 79 reference (same harness, UTF-8 entry points):
DYLD_LIBRARY_PATH=~/Projects/claude/collation/icu-build/lib \
  Tools/bench_icu Tools/bench/bench-ascii.txt 200

# Tailored corpus (3rd arg = bundled tailoring / ICU locale). The Thai
# dictionary is large, so fewer reps suffice (see §6):
.build/release/Bench Tools/bench/bench-thai.txt 10 th
DYLD_LIBRARY_PATH=~/Projects/claude/collation/icu-build/lib \
  Tools/bench_icu Tools/bench/bench-thai.txt 10 th
```

The ICU bench must be rebuilt after the harness edit (locale arg, raised line
cap):

```sh
cd Tools
ICU_SRC=~/Projects/claude/icu ICU_BUILD=~/Projects/claude/collation/icu-build
clang bench_icu.c -O2 -o bench_icu -I $ICU_SRC/icu4c/source/common \
  -I $ICU_SRC/icu4c/source/i18n -L $ICU_BUILD/lib -licuuc -licui18n -licudata
```

For trustworthy numbers on a loaded machine: take the lower cluster of 5–6
runs with a `sleep` between them, and for round-over-round comparison run the
two binaries interleaved (old then new, repeatedly) rather than in separate
batches.

To attribute cost (deletion experiments): stub the component, rebuild release,
re-bench, `git checkout` to restore. To see the live hot path:

```sh
.build/release/Bench Tools/bench/bench-ascii.txt 80000 &
sample $! 2 -file /tmp/prof.txt   # narrow the window to hit compare, not sortKey
```

### 9.1 Sort-order cross-check against ICU

Both harnesses have a `sort` mode (and `Bench` a `keys` mode) for confirming
the collator orders text the same as ICU — collation is the ordering rule;
sorting is its main application, so this is the natural end-to-end check:

```sh
.build/release/Bench Tools/bench/bench-ascii.txt sort           > /tmp/ours.txt
DYLD_LIBRARY_PATH=$ICU_BUILD/lib \
  Tools/bench_icu Tools/bench/bench-ascii.txt sort              > /tmp/icu.txt
diff /tmp/ours.txt /tmp/icu.txt    # add a 3rd arg (th) to sort under a tailoring
```

Result (2026-06-14): **byte-identical** sorted output on `ascii`, `latin`,
`cjk`, and `paths`. On the 32,895-word shuffled Thai corpus under the `th`
tailoring the two sorts differ at 506 positions — **all of them ties**: the
words at those positions have identical sort keys, so the difference is only
how the two unstable sorts (`Array.sorted` / `qsort`) break ties among
collation-equal words, not a collation disagreement. Confirm with the `keys`
mode: dump `Bench <ours.txt> keys th` and `Bench <icu.txt> keys th`; the
key-sequences match position-for-position, and both lists are non-decreasing
by those keys (i.e. both are correct sorts of the same multiset). Zero genuine
ordering disagreements over 32k tailored, contraction-dense words.

## 10. Bottom line

The Swift collator runs comparison within ~2.8–4.9× of ICU4C and sort-key
generation within 2.2–4.4×, from a starting point of ~75–94× — with results
byte-/verdict-identical to ICU throughout. The collation *arithmetic* is at
ICU's speed; the residual gap is Swift value-type overhead — refcounting,
allocator traffic, and (until §6.6) a costly canonical `String ==`. Profiling,
not intuition, is what locates these: §6.6 found that ~30% of the non-Latin
compare was Swift's `==` doing normalization, removed it for a 12–35% non-Latin
speedup; §6.7 then cut the NFD front end's per-scalar allocations (sortKey −8%)
and reused the prefix-skip iterators to drop sorted-Thai compare another ~13%
(to 2.8×) by removing real `String`-storage retains and a redundant prefix
re-walk. The remaining gap is the fixed/stack-buffer territory ICU occupies — a
real effort with diminishing returns, partly an API-design question for
Foundation integration (M8).

Two structural lessons, both now confirmed more than once. First: on paths this
hot, **Swift value-type overhead — ARC and canonical `String` semantics — is the
enemy**, more than the arithmetic. Second, learned the harder way in §6.7:
**profiler leaf samples are a hypothesis, not a result.** Twice a sampled
hot-spot (a CE-array memmove, an unsafe-backward binary search) overstated its
real cost, and the "obvious" structural fix profiled to zero while moving
wall-clock not at all. The levers that held removed allocations and redundant
work; the ones that only made a sample count vanish were reverted. A/B every
lever before believing it.
