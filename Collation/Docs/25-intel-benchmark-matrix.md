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
> The same day, the harness gained **four previously unmeasured metrics** —
> the allocating sortKey variant (`skRet`, Table 1), the case-insensitive
> compare/contains pair, and **backward search** (`range(backwards)`) — and
> the tables below are from the full run including them. Backward search is
> the standout: 2.6×/3.5× behind system ICU on ascii/paths (finding #5).

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
| ascii  | 16  | 51   | 3.19× | 195 | 421  | 2.16× | 569  | 2.92× |
| latin  | 17  | 50   | 2.94× | 209 | 463  | 2.22× | 598  | 2.86× |
| cjk    | 73  | 285  | 3.90× | 226 | 485  | 2.15× | 708  | 3.13× |
| paths  | 48  | 120  | 2.50× | 668 | 1133 | 1.70× | 1583 | 2.37× |
| thai   | 284 | 836  | 2.94× | 288 | 668  | 2.32× | 854  | 2.97× |

Pure-Swift vs hand-tuned C: ~2.5–3.9× on compare, ~1.7–2.5× on sortKey. This is
the expected gap for a from-scratch Swift implementation against ICU's C engine.

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. ratio = ours / system-ICU. **<1 = ours faster.**

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`               | 0.90× | 0.55× | 0.76× | 0.76× | 1.11× |
| `localizedCompare`               | 0.61× | 0.31× | 0.55× | 0.49× | 0.98× |
| `localizedStandardCompare`       | 0.67× | 0.33× | 0.56× | 0.55× | 1.06× |
| `localizedCaseInsensitiveCompare`| 0.66× | 0.33× | 0.56× | 0.53× | 1.01× |
| `localizedStandardContains`      | 0.76× | 0.46× | 0.57× | 1.13× | 0.51× |
| `localizedCaseInsensitiveContains`| 0.75× | 0.45× | 0.56× | 0.81× | 0.48× |
| `localizedStandardRange`         | 0.85× | 0.51× | 0.62× | 1.42× | 0.71× |
| `range(of:options:locale:)`      | 1.15× | 1.04× | 1.35× | 1.37× | 1.31× |
| `range(of:.backwards,locale:)`   | 2.61× | 0.95× | 1.30× | 3.45× | 1.13× |

Raw ns/op behind the ratios (2026-07-06 run), with the 2026-06-26 "ours"
rows kept for the ours-vs-ours comparison across the lazy-position change
(the case-insensitive and backwards rows are first-time baselines — no
06-26 numbers exist):

| API | corpus | sysICU | ours | ours 06-26 |
|-----|--------|-------:|-----:|-----------:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 642 / 1069 / 1114 / 895 / 1302 | 579 / 585 / 843 / 684 / 1441 | 587 / 587 / 845 / 693 / 1426 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 426 / 846 / 918 / 669 / 1085   | 261 / 262 / 501 / 327 / 1058 | 263 / 263 / 505 / 330 / 1039 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 420 / 846 / 927 / 688 / 1052   | 281 / 282 / 521 / 379 / 1115 | 283 / 284 / 526 / 382 / 1074 |
| localizedCaseICmp  | ascii/latin/cjk/paths/thai | 423 / 849 / 932 / 673 / 1072   | 281 / 282 / 521 / 354 / 1087 | — |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1408 / 2415 / 2181 / 1372 / 2373 | 1072 / 1112 / 1248 / 1544 / 1200 | 1081 / 1125 / 1268 / 1538 / 1210 |
| localizedCaseICnt  | ascii/latin/cjk/paths/thai | 1429 / 2512 / 2214 / 1398 / 2461 | 1077 / 1125 / 1238 / 1136 / 1186 | — |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1403 / 2409 / 2185 / 1408 / 2467 | 1193 / 1235 / 1351 / 1994 / 1747 | 1625 / 2001 / 1732 / 3094 / 2110 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 591 / 1620 / 1320 / 599 / 1518   | 681 / 1684 / 1784 / 818 / 1982 | 697 / 2653 / 2147 / 846 / 2308 |
| range(backwards)   | ascii/latin/cjk/paths/thai | 595 / 1682 / 1349 / 912 / 1644   | 1555 / 1591 / 1749 / 3149 / 1862 | — |

Ours-vs-ours, the lazy-position change (07-06 vs 06-26 "ours" columns):
`localizedStandardRange` −17 to −38% on every corpus (ascii 1625→1193,
paths 3094→1994); `range(of:locale:)` −2 to −37% (latin 2653→1684,
thai 2308→1982). Compare and contains within noise of unchanged.

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
     ascii 0.86×, latin 0.52×, cjk 0.64×, thai 0.74×; paths 1.46× (was
     2.18×). The residual paths gap vs `contains` (1.14×) is the
     `AnnotatedCE` buffer itself (24 B/element, unreserved growth on long
     strings).
   - **`range(of:options:locale:)`** (default options → strength `.tertiary`,
     non-numeric → byte-scan applies): our raw ns improved on every corpus
     (latin 2653→1684), but the precompiled bench_system also lowered the
     system reference, so ratios read 1.04–1.37× — ASCII/Latin at parity, the
     non-ASCII CE fall-through still the frontier.

5. **First-time baselines (2026-07-06) expose backward search as the worst
   API and confirm the numeric-mode cost.**
   - **`range(of:.backwards,locale:)`: 2.61× (ascii) / 3.45× (paths) behind
     system ICU** — by far the weakest numbers in the matrix. The backward
     search has no byte-scan fast path and no lazy early exit: it pre-produces
     *all* of the text's annotated CEs, then scans candidates from the end.
     The system side presumably runs a reverse literal scan for these corpora.
     Latin (0.95×), thai (1.13×), cjk (1.30×) are close because CE production
     dominates there for both sides. Clear next optimization target.
   - **`localizedCaseInsensitiveContains` beats system ICU on all five
     corpora** (0.45–0.81×) — including paths (0.81×), where
     `localizedStandardContains` is 1.13×. Same search machinery; the
     difference is numeric mode (`localizedStandard*` turns it on): digits
     leave the pre-computed ASCII CE table and take the slow numeric path,
     and the paths corpus is digit-heavy. The numeric-mode digit path is
     therefore a measurable cost worth a look.
   - **Allocating sortKey (`skRet`, Table 1)** costs ~150–450 ns/op over the
     inout variant (ascii 421→569, paths 1133→1583) — the per-call
     allocation+copy, as designed; recorded so the delta is tracked.

## Cross-reference

- Apple Silicon (machine 2) Foundation-API numbers: `21-foundation-api-benchmark.md`,
  `HANDOFF.md` "Apple Silicon" perf subsection.
- Pure-engine Intel history (pre-module-move): `HANDOFF.md` "Intel iMac" perf subsection.
