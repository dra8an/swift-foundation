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
> **Re-baselined 2026-07-13** after the §29–§30 engine-entry round: compare
> hot/cold split + prefix/safety wins (`ab7e953`) and the **RootCollator
> storage box** (`2eeb5cd` — collator values are one pointer; the ~768-byte
> per-call receiver copies are gone, including the CollatorCache fetch in
> every Foundation call). The engine rows also now hold the collator in a
> loop-local `let` (§30), so Table-1 rows are NOT comparable to pre-07-13
> recordings (~10–12 ns of receiver-copy artifact removed). Headlines:
> `localizedCompare` latin **7.3× faster** than system ICU;
> every Foundation API ≤1.21× on every corpus; engine compare ascii 2.4×,
> paths 2.0×.
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
  (thai uses the `th` tailoring / dictionary corpus).
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

| corpus | compare ICU | compare ours | ratio | sortKey ICU | sortKey ours | ratio | skRet ours | ratio |
|--------|------------:|-------------:|------:|------------:|-------------:|------:|-----------:|------:|
| ascii  | 16  | 39   | 2.44× | 204 | 416  | 2.04× | 567  | 2.78× |
| latin  | 17  | 38   | 2.24× | 208 | 463  | 2.23× | 600  | 2.88× |
| cjk    | 73  | 284  | 3.89× | 229 | 484  | 2.11× | 714  | 3.12× |
| paths  | 49  | 98   | 2.00× | 669 | 1152 | 1.72× | 1637 | 2.45× |
| thai   | 289 | 823  | 2.85× | 292 | 665  | 2.28× | 856  | 2.93× |

Pure-Swift vs hand-tuned C: ~2.0–3.9× on compare, ~1.7–2.3× on sortKey.
§29 decomposed the remainder: the fast-Latin loop core measures ~15 ns with
ICU's calling contract (vs ICU's ~16 total); ~10 ns is String→bytes
unwrapping (the safe-API floor on macOS 15); the rest is per-scalar CE
pipeline cost on cjk/thai. The cjk row is the CE-bound frontier (§28).

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. **speedup = system-ICU ÷ ours: how many
times faster we are (>1 = ours faster).** (Flipped from the old ours÷system
convention on 2026-07-13; bench_matrix.py prints this orientation now.
Doc 21 on machine 2 still uses the old convention until it re-baselines.)

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`               | 1.62× | 2.60× | 1.66× | 1.82× | 1.07× |
| `localizedCompare`               | **3.74×** | **7.31×** | 2.55× | **3.71×** | 1.24× |
| `localizedStandardCompare`       | 2.82× | 5.62× | 2.44× | 3.09× | 1.15× |
| `localizedCaseInsensitiveCompare`| 2.81× | 5.67× | 2.45× | 3.16× | 1.14× |
| `localizedStandardContains`      | 1.47× | 2.37× | 1.95× | 1.28× | 2.15× |
| `localizedCaseInsensitiveContains`| 1.52× | 2.53× | 2.01× | 1.37× | 2.28× |
| `localizedStandardRange`         | 1.28× | 2.19× | 1.79× | 0.97× | 1.56× |
| `range(of:options:locale:)`      | 1.10× | 1.13× | 0.83× | 0.91× | 0.88× |
| `range(of:.backwards,locale:)`   | 1.10× | 1.26× | 0.85× | 1.28× | 0.99× |

Raw ns/op behind the speedups (2026-07-13 post-§30 run):

| API | corpus | sysICU | ours |
|-----|--------|-------:|-----:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 654 / 1077 / 1140 / 918 / 1315 | 403 / 414 / 687 / 505 / 1232 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 438 / 863 / 931 / 676 / 1087   | 117 / 118 / 365 / 182 / 875 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 435 / 860 / 938 / 696 / 1053   | 154 / 153 / 385 / 225 / 918 |
| localizedCaseICmp  | ascii/latin/cjk/paths/thai | 432 / 868 / 945 / 679 / 1049   | 154 / 153 / 385 / 215 / 919 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1409 / 2424 / 2223 / 1379 / 2356 | 957 / 1023 / 1141 / 1080 / 1095 |
| localizedCaseICnt  | ascii/latin/cjk/paths/thai | 1447 / 2544 / 2267 / 1408 / 2440 | 954 / 1005 / 1128 / 1029 / 1068 |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1397 / 2432 / 2217 / 1410 / 2445 | 1093 / 1110 / 1239 / 1453 / 1567 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 602 / 1644 / 1328 / 614 / 1533   | 546 / 1458 / 1603 / 676 / 1734 |
| range(backwards)   | ascii/latin/cjk/paths/thai | 602 / 1726 / 1348 / 927 / 1637   | 549 / 1371 / 1582 / 725 / 1651 |

All but five cells beat system ICU, none is worse than 0.83×. The compare
family runs 1.1–7.3× faster than the system (`localizedCompare` latin:
118 vs 863 ns); search runs 1.3–2.3× faster nearly everywhere. The five
remaining <1× cells are all range-position reporting on the CE-bound
corpora (cjk 0.83–0.85×, paths/thai forward range 0.88–0.97×). Most of
the 07-13 jump in the compare family came from the §30 storage box: the
collator struct's ~8 reference fields made every per-call copy pay a
768-byte memcpy plus ~8 retain/release pairs, several times per Foundation
call (cache fetch, return, throwing-call receiver). Per-API history: this
file's git log plus §20/§27/§29/§30 of the technique log.

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
