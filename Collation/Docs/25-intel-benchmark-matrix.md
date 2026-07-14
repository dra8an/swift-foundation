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

| corpus | compare ICU | compare ours | ratio | sortKey ICU | sortKey ours | ratio | skRet ours | ratio |
|--------|------------:|-------------:|------:|------------:|-------------:|------:|-----------:|------:|
| ascii  | 16  | 41   | 2.56× | 192 | 416  | 2.17× | 562  | 2.93× |
| latin  | 17  | 42   | 2.47× | 208 | 456  | 2.19× | 594  | 2.86× |
| cjk    | 73  | 92   | **1.26×** | 216 | 481  | 2.23× | 699  | 3.24× |
| paths  | 48  | 102  | 2.12× | 659 | 1109 | 1.68× | 1568 | 2.38× |
| thai   | 258 | 813  | 3.15× | 266 | 672  | 2.53× | 823  | 3.09× |

Pure-Swift vs hand-tuned C: 1.3–3.2× on compare, ~1.7–2.5× on sortKey.
(ascii/latin compare read ~2 ns higher than the 07-13 morning run purely
from -no-WMO code-layout shift after the search-box edit — under WMO, the
shipping config, the same change is neutral-to-better: ascii 35–36 ns.)
§29 decomposed the remainder: the fast-Latin loop core measures ~15 ns with
ICU's calling contract (vs ICU's ~16 total); ~10 ns is String→bytes
unwrapping (the safe-API floor on macOS 15). cjk is decided by the §31
quick-primary dispatch (1.26×). Thai — a real CE-pipeline workload
(contractions, marks) — is now the last row above 3× and the next engine
frontier; note its ratio ROSE with the honest root/root fix (ICU got
faster, ours barely moved).

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. **speedup = system-ICU ÷ ours: how many
times faster we are (>1 = ours faster).** (Flipped from the old ours÷system
convention on 2026-07-13; bench_matrix.py prints this orientation now.
Doc 21 on machine 2 still uses the old convention until it re-baselines.)

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`               | 1.56× | 2.59× | 2.22× | 1.74× | 1.07× |
| `localizedCompare`               | **3.50×** | **7.04×** | **5.09×** | **3.66×** | 1.23× |
| `localizedStandardCompare`       | 2.72× | 5.57× | 4.31× | 3.11× | 1.16× |
| `localizedCaseInsensitiveCompare`| 2.73× | 5.55× | 4.31× | 3.14× | 1.14× |
| `localizedStandardContains`      | 1.57× | 2.56× | 2.02× | 1.36× | 2.29× |
| `localizedCaseInsensitiveContains`| 1.59× | 2.66× | 2.01× | 1.47× | 2.44× |
| `localizedStandardRange`         | 1.45× | 2.33× | 1.84× | 0.96× | 1.63× |
| `range(of:options:locale:)`      | 1.29× | 1.18× | 0.80× | 1.00× | 0.92× |
| `range(of:.backwards,locale:)`   | 1.28× | 1.27× | 0.82× | 1.38× | 1.04× |

Raw ns/op behind the speedups (2026-07-13 evening run, §29–§31 + search box):

| API | corpus | sysICU | ours |
|-----|--------|-------:|-----:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 638 / 1056 / 1110 / 897 / 1318 | 408 / 408 / 499 / 517 / 1232 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 420 / 852 / 911 / 684 / 1087   | 120 / 121 / 179 / 187 / 883 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 422 / 852 / 923 / 709 / 1051   | 155 / 153 / 214 / 228 / 909 |
| localizedCaseICmp  | ascii/latin/cjk/paths/thai | 423 / 854 / 927 / 675 / 1052   | 155 / 154 / 215 / 215 / 920 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1409 / 2398 / 2179 / 1367 / 2314 | 897 / 936 / 1078 / 1002 / 1011 |
| localizedCaseICnt  | ascii/latin/cjk/paths/thai | 1427 / 2502 / 2193 / 1397 / 2426 | 896 / 942 / 1090 / 949 / 996 |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1404 / 2388 / 2188 / 1378 / 2442 | 971 / 1023 / 1188 / 1429 / 1495 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 588 / 1608 / 1332 / 601 / 1522   | 456 / 1366 / 1659 / 603 / 1662 |
| range(backwards)   | ascii/latin/cjk/paths/thai | 593 / 1682 / 1329 / 916 / 1625   | 462 / 1324 / 1619 / 662 / 1569 |

All but five cells beat system ICU, none is worse than 0.80×. The compare
family runs 1.1–7× faster than the system (`localizedCompare` latin: 121
vs 852 ns; cjk 179 vs 911 thanks to the §31 dispatch); search runs
1.3–2.7× faster nearly everywhere. The five remaining ≤1× cells are all
range-position reporting on CE-bound corpora (cjk 0.80–0.82×, paths/thai
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
