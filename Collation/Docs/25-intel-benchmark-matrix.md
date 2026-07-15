# Benchmark Matrix — Intel iMac (machine 1)

> **Platform: Intel iMac, macOS 15, Swift 6.3.1 release.** These numbers are
> **machine 1 only** — do not compare them directly against the Apple Silicon
> (machine 2) numbers in `21-foundation-api-benchmark.md` / `HANDOFF.md`.
> Absolute ns differ by hardware (ICU is faster on Apple Silicon too); read the
> *ratios* within this doc, not cross-machine deltas.
>
> Measured 2026-06-26, at `port/collation` (`7c742c0`) — after the
> FoundationInternationalization module move and the full search-optimization
> stack: lazy CE production (`7648b1d`), buffer `reserveCapacity` (`e1cd576`),
> the `contains()` Bool fast path (`c683653` / `78729ac` / `843b4d8`),
> **thread-local scratch-iterator reuse** for `contains` (`b93b549`) and the
> range-returning search (`a56b5a3`), and **ASCII / UTF-8 byte-scan fast paths**
> for `range(of:locale:)` (`6e214ff` / `7c742c0`).
>
> **Re-measured 2026-07-06** — one coherent K=3 run (thai at 10 reps) after
> **lazy position reporting** in the range search (`optimization-targets.md`
> §20 step 6). This run also uses the reworked harness (bench_system compiled
> once with `swiftc -O`; see Methodology): the *system* reference got faster
> across several APIs versus the 06-26 script-mode numbers, so ratios are not
> comparable across the harness change — ours-vs-ours raw ns are (the 06-26
> "ours" rows are preserved below for that comparison).
>
> **Re-baselined 2026-07-13 (evening)**, one coherent run containing the
> full 07-12/13 round: compare hot/cold split (`ab7e953`), **RootCollator
> storage box** (`2eeb5cd` — the §29–§30 receiver-copy discovery), the
> **quick-primary CJK dispatch + longPrimary coverage** (`4acac0b`, §31),
> the **CollationSearch storage box** from machine 2 (`67594f8`), thai
> measured **root vs root** for the first time (ICU ref ~258, was ~289
> with a "th" collator), and Table 2 as **speedup = system ÷ ours** (>1 =
> we're faster). Table-1 rows are NOT comparable to pre-07-13 recordings
> (~10–12 ns receiver-copy artifact removed; §30). Headlines: engine cjk
> compare **1.26× vs ICU C** (was 3.9× a week ago); `localizedCompare`
> 3.5–7× faster than system ICU on every non-Thai corpus; all Foundation
> APIs within 0.80× of the system, all but five cells ahead.
>
> **Re-baselined 2026-07-15 (round end)**, one coherent K=3 run at
> `9b1d62b`, containing the full §34/§35 thai round: NFD lone-mark
> pass-through (`2e6c961`), Thai-block simple-CE table (`4a73ada`),
> walk-skip at the byte-scan mismatch (`26e340f`), plus machine 2's
> borrowing reconciliation (`44c9497`, §33). Headlines: **thai engine
> compare 534 (2.05× vs ICU root/root, was 637 / 2.47× at round start),
> thai sortKey 443 (1.65×, was 513 / 1.93×)**; thai `localizedCompare`
> 1.53× faster than system (was 1.23×), thai contains 2.8–2.9×; thai
> range cells all ≥1.07×. The two cjk range cells (0.84–0.86×) remained
> the only sub-parity numbers at that point. Remember §34's alignment band
> when comparing paths sortKey across builds.
>
> **Re-baselined 2026-07-16**, one coherent K=3 run at `1b43bbc`,
> containing **§37 allocation-free search** (`43c5c84`: reusable
> pattern/window/text CE buffers on ScratchBuffers, scratch passed as ONE
> reference) plus both machine-2 confirmations (§33 borrowing neutral on
> 6.4; §37 carries to Apple Silicon, −29..35% there). Headlines: **the
> last two sub-parity cells flipped** — cjk range fwd/back now
> 1.19×/1.06× ahead; contains 2.4–4.2× on every corpus (thai contains
> 577 ns vs system 2317); stdRange 1.5–3.6×. **Zero Foundation-API cells
> (Table 2) behind system ICU on either machine**; the only ≤1× Table-2
> number is paths range(of:) at 0.99× — byte-scan-bound, oscillating ±1%
> around parity across runs, untouched by §37 by design. The pure-engine
> rows (Table 1 — raw ICU C calls, no API overhead on either side) are a
> separate comparison and still trail hand-tuned C on this machine:
> compare 1.12–2.25×, sortKey 1.17–1.78× (Apple Silicon's cjk engine
> compare is the one engine row ahead of ICU C). Engine rows certified
> unchanged by §37 (compare ±2 mixed-sign; paths sortKey moves inside
> the §34 band with writer instructions byte-identical).
>
> **CAVEAT (2026-07-16 late): the tables below predate §38–§40** — the
> one-slot locale cache (explicit-locale rows −190..250 ns; paths
> range(of:) now 1.50× ahead), the §39 Substring rebase fix, and the §40
> comparator fix all shipped after this run. Their A/B numbers live in
> the technique-log sections; fold everything into the next coherent
> re-baseline.
>
> The same day (07-06), the harness gained **four previously unmeasured metrics** —
> the allocating sortKey variant (`skRet`, Table 1), the case-insensitive
> compare/contains pair, and **backward search** (`range(backwards)`).
> Their first baselines exposed backward search at 2.6×/3.45× behind system
> ICU on ascii/paths; the same day it got the **backward byte-scan**
> (`16d0322`, §20 step 8) plus the capped buffer reserve (`48338d4`, step
> 7), and the tables below are from the post-fix quiet-machine run:
> backward search now **beats** system ICU on latin and paths and is within
> 1.2× everywhere. Finding #5 records the pre-fix numbers.

## Build note — the `-no-WMO` workaround (required on this machine)

A normal `swift run -c release BenchFoundation` **crashes with SIGILL** at
startup on this machine, before any measurement. Root cause: `Locale(identifier:)`
goes through `LocaleCache.fixed` → the `dynamic` `_localeICUClass()`, whose
`@_dynamicReplacement` (supplied by FoundationInternationalization to return
`_LocaleICU`) **is not applied** in a release **whole-module-optimized executable**
on this Swift 6.3.1 toolchain. The call falls back to `_LocaleUnlocalized` and
the init dispatch jumps into data → SIGILL. It is **not** a collation bug (the
collator is never even constructed yet) and **not** stale artifacts (reproduces
on a clean build). Debug builds work because they don't run the WMO pass that
defeats the dynamic dispatch.

**Workaround:** keep `-O` but disable whole-module optimization:

```sh
swift run -c release -Xswiftc -no-whole-module-optimization \
  BenchFoundation Collation/Tools/bench/bench-ascii.txt 200
```

Consequence: our numbers below are built **without WMO**, so they are *slightly
pessimistic* versus a true full-release (WMO) build — the compare-family wins in
Table 2 would likely be a bit larger with WMO. ICU (C) and system-Foundation are
unaffected. (Apple Silicon / machine 2 uses a newer toolchain where this does not
trip, so its numbers there are full-WMO.)

## Methodology

- **min ns/op** over repeated runs (min = least-OS-perturbed pass). BenchFoundation's
  `measure()` additionally takes the min over 9 internal passes per invocation.
- Per-corpus reps equalize work (thai is ~33k lines vs ~200–440 for the rest):
  ASCII/Latin/CJK 300, paths 150, thai 10.
- Corpora: `Collation/Tools/bench/bench-{ascii,latin,cjk,paths,thai}.txt`
  (thai is the dictionary corpus; since 07-13 BOTH sides use the root
  collator on it — earlier runs gave ICU a `th`-tailored one).
- Harnesses:
  - **Pure ICU:** `Collation/Tools/bench_icu.c` → `ucol_strcollUTF8` / `ucol_getSortKey`
    (ICU 79, local build at `~/Projects/claude/collation/icu-build`).
  - **Pure ours:** `BenchFoundation` measures `RootCollator.cmp` / `RootCollator.sk`
    (direct engine, no Foundation API).
  - **System ICU via Foundation:** `Collation/Tools/bench_system_foundation.swift`
    (NSString → system ICU). Since 2026-07-04, `run_benchmarks.sh` compiles it
    once with `swiftc -O` instead of `swift -O` per invocation — the per-run
    recompiles dominated the matrix's wall time. The compiled binary also runs
    `range(of:locale:)` measurably faster on the system side (~600 vs ~750
    ns/op ASCII), so that API's ratios shifted against us across the change
    with no change in our code.
  - **Ours via Foundation:** `BenchFoundation` measures `compare(locale:)`,
    `localizedCompare`, `localizedStandardCompare`,
    `localizedCaseInsensitiveCompare`, `localizedStandardContains`,
    `localizedCaseInsensitiveContains`, `localizedStandardRange`,
    `range(of:options:locale:)`, and `range(of:options:.backwards,locale:)`;
    plus the engine-only allocating sortKey variant (`RootCollator.skRet`).

## Table 1 — Pure collator engine

Our pure-Swift `RootCollator` vs ICU's C library. ratio = ours / ICU.

`sortKey` is the inout API (caller-supplied buffer, the ICU
`ucol_getSortKey` model); `skRet` is the allocating variant returning a
fresh `[UInt8]` per call — the difference (~150–450 ns) is the per-call
allocation+copy the inout API avoids. Both are measured against the same
ICU reference.

**Since 2026-07-13 late, Table 1 measures the FULL-WMO engine** — the
shipping optimization level — via the engine-only EngineBench
(`Tools/build_engine_bench.sh`; no Locale, so machine 1's WMO SIGILL never
trips). The old -no-WMO engine rows carried a 10–26% build-workaround
handicap and were sensitive to code-layout luck.

2026-07-16 re-baseline (`1b43bbc`, §37 included — engine rows unchanged
from 07-15 within the certification bands):

| corpus | compare ICU | compare ours | ratio | sortKey ICU | sortKey ours | ratio | skRet ours | ratio |
|--------|------------:|-------------:|------:|------------:|-------------:|------:|-----------:|------:|
| ascii  | 16  | 36   | 2.25× | 194 | 342  | 1.76× | 487  | 2.51× |
| latin  | 17  | 36   | 2.12× | 208 | 371  | 1.78× | 505  | 2.43× |
| cjk    | 72  | 81   | **1.12×** | 218 | 366  | 1.68× | 561  | 2.57× |
| paths  | 48  | 83   | 1.73× | 661 | 813  | **1.23×** | 1013 | 1.53× |
| thai   | 258 | 528  | **2.05×** | 265 | 444  | 1.68× | 609  | 2.30× |

Previous (07-13) row set for the arc: ascii 36/338/497, latin 35/369/518,
cjk 81/368/574, paths 87/805/1017, **thai 637/513/678** — the §34/§35
round moved thai compare −16% and sortKey −14% with everything else
neutral (paths sortKey differences sit in the §34 alignment band).
(07-13 numbers included machine 2's sortKey primary-byte batching,
`68156e1` — paths sortKey −18% on Intel, matching their −15% on AS.)

> **Alignment band (2026-07-14, §34):** on this machine the paths sortKey
> row moves ±6–7% from pure code placement — any size change in a file
> earlier in the WMO emission order shifts `writeSortKeyUpToQuaternary`'s
> loop alignment (its instruction stream can be byte-identical while the
> row reads +50 ns). Do not convict a paths sortKey delta inside that band
> without an instruction-stream diff of the writer (`otool -tv`, addresses
> stripped). WMO builds of identical sources are not bit-identical either;
> whole-binary hashes prove nothing.
>
Pure-Swift vs hand-tuned C: 1.1–2.2× on compare, 1.2–1.8× on sortKey.
§29 decomposed the remainder: the fast-Latin loop core measures ~15 ns with
ICU's calling contract (vs ICU's ~16 total); ~10 ns is String→bytes
unwrapping (the safe-API floor on macOS 15). cjk is decided by the §31
quick-primary dispatch; thai by the §34/§35 round (mark pass-through,
simple-CE table, walk-skip) — its remaining gap is the NFD per-scalar
floor (the parked Span refactor, §35).

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. **speedup = system-ICU ÷ ours: how many
times faster we are (>1 = ours faster).** (Flipped from the old ours÷system
convention on 2026-07-13; bench_matrix.py prints this orientation now.
Doc 21 on machine 2 still uses the old convention until it re-baselines.)

2026-07-16 re-baseline (`1b43bbc`, §37 allocation-free search included):

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`               | 1.55× | 2.56× | 2.22× | 1.74× | 1.24× |
| `localizedCompare`               | **3.55×** | **7.05×** | **5.11×** | **3.66×** | **1.53×** |
| `localizedStandardCompare`       | 2.74× | 5.54× | 4.34× | 3.03× | 1.45× |
| `localizedCaseInsensitiveCompare`| 2.75× | 5.60× | 4.39× | 3.13× | 1.44× |
| `localizedStandardContains`      | **2.57×** | **4.05×** | **3.17×** | **2.37×** | **4.02×** |
| `localizedCaseInsensitiveContains`| **2.58×** | **4.21×** | **3.18×** | **2.61×** | **4.16×** |
| `localizedStandardRange`         | **2.27×** | **3.57×** | **2.97×** | 1.48× | **2.42×** |
| `range(of:options:locale:)`      | 1.31× | 1.61× | **1.19×** | 0.99× | 1.41× |
| `range(of:.backwards,locale:)`   | 1.30× | 1.49× | **1.06×** | 1.43× | 1.35× |

Raw ns/op behind the speedups (2026-07-16 re-baseline):

| API | corpus | sysICU | ours |
|-----|--------|-------:|-----:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 633 / 1061 / 1106 / 885 / 1292 | 409 / 415 / 499 / 508 / 1038 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 419 / 846 / 905 / 666 / 1074   | 118 / 120 / 177 / 182 / 701 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 419 / 847 / 912 / 681 / 1042   | 153 / 153 / 210 / 225 / 718 |
| localizedCaseICmp  | ascii/latin/cjk/paths/thai | 420 / 851 / 917 / 669 / 1039   | 153 / 152 / 209 / 214 / 721 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1398 / 2389 / 2170 / 1354 / 2317 | 543 / 590 / 685 / 572 / 577 |
| localizedCaseICnt  | ascii/latin/cjk/paths/thai | 1414 / 2503 / 2196 / 1396 / 2431 | 548 / 595 / 691 / 535 / 584 |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1389 / 2386 / 2169 / 1375 / 2408 | 613 / 668 / 731 / 926 / 994 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 586 / 1620 / 1303 / 587 / 1500   | 447 / 1005 / 1092 / 593 / 1062 |
| range(backwards)   | ascii/latin/cjk/paths/thai | 593 / 1673 / 1320 / 907 / 1613   | 455 / 1126 / 1248 / 636 / 1193 |

**Every cell beats system ICU** except paths range(of:) at 0.99× —
byte-scan-bound, ±1% around parity across runs, unaffected by §37 by
design. The compare family runs 1.2–7× faster; after §37 the search
family runs 1.3–4.2× faster everywhere (contains: thai 577 vs 2317 ns;
the former cjk sub-parity range cells now 1.19×/1.06× ahead — the §37
allocator elimination was worth −30..45% on every buffered-search row,
and machine 2 confirmed the same shape on Apple Silicon). Before §37 the
cjk range cells read 0.84–0.86× (paths/thai
forward range 0.92–1.00×). The 07-13 jumps came from the §30 storage
boxes (the collator and searcher structs carried reference fields, so
every per-call copy paid a large memcpy plus retain/release pairs —
several times per Foundation call) and the §31 CJK dispatch. Per-API
history: this file's git log plus §20/§27/§29–§31 of the technique log.

## Findings

1. **The engine is slower than raw ICU** (Table 1) — pure Swift vs C on the core
   algorithm, as expected.
2. **But integrated in Foundation, ours wins the compare family** by 1.0–3.3×
   (Table 2): system Foundation pays `ucol_open`/`ucol_close` + bridging *per
   call*; our cached collator does not. End users calling `localizedCompare` /
   `compare(locale:)` get faster results from the Swift collator despite the
   slower engine. Latin is the standout — **3.3× faster** on `localizedCompare`.
   Thai is ≈ parity (the dictionary corpus is the heaviest case for both).
3. **`localizedStandardContains` — now beats system ICU on 4 of 5 corpora.**
   The optimization chain: lazy CE production (`7648b1d`) → buffer
   `reserveCapacity` (`e1cd576`) → a dedicated `contains()` Bool fast path that
   skips the index table, NFD map, `AnnotatedCE` structs, and boundary validation
   (`c683653`, since `contains` needs only yes/no) → fast-path `reserveCapacity`
   with a short-string threshold (`78729ac` / `843b4d8`) → **thread-local
   scratch-iterator reuse** (`b93b549`). The last step was decisive: profiling
   showed ~half the time was per-call allocation/ARC — every call built two fresh
   `CEIterator`s (one re-deriving the *same* pattern's CEs) plus their arrays.
   Reusing one scratch iterator for pattern + text, across calls, removed it.

   | corpus | before (×ICU) | now (×ICU) | ours ns: before → now |
   |--------|--------------:|-----------:|----------------------:|
   | ascii  | 2.80× | **0.77×** | 3951 → 1081 |
   | latin  | 1.71× | **0.46×** | 4125 → 1125 |
   | cjk    | 1.51× | **0.57×** | 3325 → 1268 |
   | paths  | 5.88× | 1.11× | 8252 → 1538 |
   | thai   | 1.71× | **0.49×** | 3993 → 1210 |

   ASCII/Latin/CJK/Thai now **beat** system ICU (0.46–0.77×); paths is at near
   parity (1.11×), down from 5.9×.

4. **Range-returning search: position reporting is now lazy** (2026-07-04,
   `optimization-targets.md` §20 step 6). The range paths used to build three
   upfront O(n) arrays per call — `[String.Index]` table, NFD→source map,
   plus `unicodeScalars.count` passes — consumed only at match time; pure
   waste on no-match calls. Now CEs carry raw NFD offsets and `confirmMatch`
   converts/validates/builds indices only for CE-equal candidates; when the
   NFD front end never decomposed (`sawDecomposition == false` — always for
   ASCII/paths/CJK), NFD offsets *are* source offsets and no map is ever
   built.
   - **`localizedStandardRange`** (strength `.primary`, numeric on → CE path,
     no byte-scan): now **beats system ICU on every corpus except paths** —
     ascii 0.87×, latin 0.53×, cjk 0.61×, thai 0.70×; paths 1.38× (was
     2.18×; the buffer reserve of §20 step 7 trimmed it further). The
     residual paths gap tracks `contains` (1.14×) plus the annotation
     bookkeeping; the numeric digit path (finding #5) is the shared cost.
   - **`range(of:options:locale:)`** (default options → strength `.tertiary`,
     non-numeric → byte-scan applies): our raw ns improved on every corpus
     (latin 2653→1684), but the precompiled bench_system also lowered the
     system reference, so ratios read 1.04–1.37× — ASCII/Latin at parity, the
     non-ASCII CE fall-through still the frontier.

5. **First-time baselines (2026-07-06) exposed backward search as the worst
   API — fixed the same day — and confirm the numeric-mode cost.**
   - **`range(of:.backwards,locale:)` was 2.61× (ascii) / 3.45× (paths)
     behind system ICU** — it had no byte-scan fast path and no lazy early
     exit (full CE pre-production, then a scan from the end). Fixed by the
     backward byte-scan + buffer reserve (`16d0322`/`48338d4`, §20 steps
     7–8): now **0.94×/0.96× (beats system ICU) on latin/paths**, 1.09×
     thai, 1.17× ascii, 1.32× cjk. The same commit fixed three soundness
     holes in the *forward* byte-scan (ignorable ASCII controls, missing
     alternate=shifted gate, byte-match-past-dirty-bytes not provably
     first) and taught the search CE path alternate=shifted semantics.
   - **`localizedCaseInsensitiveContains` beats system ICU on all five
     corpora** (0.46–0.85×) — including paths, where
     `localizedStandardContains` is 1.14×. Same search machinery; the
     difference is numeric mode (`localizedStandard*` turns it on): digits
     leave the pre-computed ASCII CE table and take the slow numeric path,
     and the paths corpus is digit-heavy. The numeric-mode digit path is
     therefore a measurable cost worth a look. **Addressed the same day**
     (`optimization-targets.md` §27, dense digit-run fast path): contains
     paths 1597→1238 ns (now ~0.89×, ahead of system ICU), range paths
     1965→1644.
   - **Allocating sortKey (`skRet`, Table 1)** costs ~160–470 ns/op over the
     inout variant (ascii 424→585, paths 1143→1614) — the per-call
     allocation+copy, as designed; recorded so the delta is tracked.

## Cross-reference

- Apple Silicon (machine 2) Foundation-API numbers: `21-foundation-api-benchmark.md`,
  `HANDOFF.md` "Apple Silicon" perf subsection.
- Pure-engine Intel history (pre-module-move): `HANDOFF.md` "Intel iMac" perf subsection.
