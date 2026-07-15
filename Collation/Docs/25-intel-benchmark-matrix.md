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
> range cells all ≥1.07×. The two cjk range cells (0.84–0.86×) remain the
> only sub-parity numbers. Remember §34's alignment band when comparing
> paths sortKey across builds.
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

2026-07-15 round-end run (`9b1d62b`, §33–§35 included):

| corpus | compare ICU | compare ours | ratio | sortKey ICU | sortKey ours | ratio | skRet ours | ratio |
|--------|------------:|-------------:|------:|------------:|-------------:|------:|-----------:|------:|
| ascii  | 16  | 35   | 2.19× | 195 | 333  | 1.71× | 484  | 2.48× |
| latin  | 17  | 35   | 2.06× | 208 | 376  | 1.81× | 515  | 2.48× |
| cjk    | 72  | 80   | **1.11×** | 222 | 361  | 1.63× | 568  | 2.56× |
| paths  | 49  | 86   | 1.76× | 663 | 777  | **1.17×** | 983  | 1.48× |
| thai   | 261 | 534  | **2.05×** | 268 | 443  | 1.65× | 607  | 2.26× |

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

2026-07-15 round-end run (`9b1d62b`):

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`               | 1.50× | 2.56× | 2.32× | 1.76× | 1.22× |
| `localizedCompare`               | **3.59×** | **7.15×** | **5.24×** | **3.66×** | **1.53×** |
| `localizedStandardCompare`       | 2.74× | 5.61× | 4.31× | 3.00× | 1.45× |
| `localizedCaseInsensitiveCompare`| 2.76× | 5.62× | 4.38× | 3.15× | 1.46× |
| `localizedStandardContains`      | 1.57× | 2.57× | 2.06× | 1.36× | **2.81×** |
| `localizedCaseInsensitiveContains`| 1.59× | 2.68× | 2.10× | 1.46× | **2.91×** |
| `localizedStandardRange`         | 1.40× | 2.31× | 1.92× | 1.02× | 1.79× |
| `range(of:options:locale:)`      | 1.26× | 1.19× | 0.84× | 1.01× | 1.07× |
| `range(of:.backwards,locale:)`   | 1.26× | 1.25× | 0.86× | 1.42× | 1.18× |

Raw ns/op behind the speedups (2026-07-15 round-end run):

| API | corpus | sysICU | ours |
|-----|--------|-------:|-----:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 640 / 1076 / 1119 / 900 / 1310 | 428 / 420 / 482 / 510 / 1074 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 427 / 858 / 932 / 673 / 1092   | 119 / 120 / 178 / 184 / 714 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 427 / 859 / 917 / 680 / 1059   | 156 / 153 / 213 / 227 / 731 |
| localizedCaseICmp  | ascii/latin/cjk/paths/thai | 425 / 855 / 933 / 675 / 1060   | 154 / 152 / 213 / 214 / 728 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1415 / 2422 / 2184 / 1369 / 2362 | 902 / 941 / 1060 / 1007 / 841 |
| localizedCaseICnt  | ascii/latin/cjk/paths/thai | 1435 / 2516 / 2203 / 1397 / 2452 | 902 / 938 / 1050 / 956 / 843 |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1403 / 2423 / 2203 / 1390 / 2454 | 1003 / 1049 / 1148 / 1364 / 1369 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 594 / 1621 / 1312 / 596 / 1516   | 470 / 1363 / 1563 / 590 / 1422 |
| range(backwards)   | ascii/latin/cjk/paths/thai | 600 / 1691 / 1331 / 920 / 1632   | 478 / 1356 / 1546 / 647 / 1388 |

All but two cells beat system ICU, none is worse than 0.84×. The compare
family runs 1.2–7× faster than the system (`localizedCompare` latin: 120
vs 858 ns; cjk 178 vs 932 thanks to the §31 dispatch; thai 714 vs 1092
after §34/§35); search runs 1.3–2.9× faster nearly everywhere. The two
remaining <1× cells are cjk range-position reporting (0.84–0.86×); the
former paths/thai sub-parity range cells crossed to 1.01–1.18× (paths/thai
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
