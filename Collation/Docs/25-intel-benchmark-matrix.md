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
    `localizedCompare`, `localizedStandardCompare`, `localizedStandardContains`,
    `localizedStandardRange`, and `range(of:options:locale:)`.

## Table 1 — Pure collator engine

Our pure-Swift `RootCollator` vs ICU's C library. ratio = ours / ICU.

| corpus | compare ICU | compare ours | ratio | sortKey ICU | sortKey ours | ratio |
|--------|------------:|-------------:|------:|------------:|-------------:|------:|
| ascii  | 16  | 50   | 3.12× | 192 | 421  | 2.19× |
| latin  | 16  | 50   | 3.12× | 202 | 473  | 2.34× |
| cjk    | 73  | 284  | 3.89× | 217 | 495  | 2.28× |
| paths  | 49  | 124  | 2.53× | 659 | 1136 | 1.72× |
| thai   | 284 | 844  | 2.97× | 288 | 671  | 2.33× |

Pure-Swift vs hand-tuned C: ~2.5–3.9× on compare, ~1.7–2.5× on sortKey. This is
the expected gap for a from-scratch Swift implementation against ICU's C engine.

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. ratio = ours / system-ICU. **<1 = ours faster.**

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`          | 0.90× | 0.54× | 0.77× | 0.76× | 1.12× |
| `localizedCompare`          | 0.62× | 0.31× | 0.56× | 0.50× | 0.99× |
| `localizedStandardCompare`  | 0.66× | 0.33× | 0.59× | 0.57× | 1.06× |
| `localizedStandardContains` | 0.76× | 0.48× | 0.59× | 1.14× | 0.52× |
| `localizedStandardRange`    | 0.86× | 0.52× | 0.64× | 1.46× | 0.74× |
| `range(of:options:locale:)` | 1.18× | 1.05× | 1.40× | 1.37× | 1.32× |

Raw ns/op behind the ratios (2026-07-06 run), with the 2026-06-26 "ours"
rows kept for the ours-vs-ours comparison across the lazy-position change:

| API | corpus | sysICU | ours | ours 06-26 |
|-----|--------|-------:|-----:|-----------:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 648 / 1089 / 1106 / 915 / 1306 | 582 / 587 / 852 / 691 / 1462 | 587 / 587 / 845 / 693 / 1426 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 424 / 847 / 906 / 676 / 1089   | 263 / 262 / 506 / 338 / 1081 | 263 / 263 / 505 / 330 / 1039 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 428 / 849 / 913 / 694 / 1050   | 284 / 283 / 537 / 395 / 1108 | 283 / 284 / 526 / 382 / 1074 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1401 / 2416 / 2148 / 1396 / 2346 | 1062 / 1152 / 1263 / 1586 / 1214 | 1081 / 1125 / 1268 / 1538 / 1210 |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1391 / 2430 / 2177 / 1416 / 2430 | 1190 / 1271 / 1403 / 2072 / 1787 | 1625 / 2001 / 1732 / 3094 / 2110 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 585 / 1618 / 1308 / 603 / 1524   | 690 / 1702 / 1825 / 828 / 2009 | 697 / 2653 / 2147 / 846 / 2308 |

Ours-vs-ours, the lazy-position change (07-06 vs 06-26 "ours" columns):
`localizedStandardRange` −15 to −36% on every corpus (ascii 1625→1190,
paths 3094→2072); `range(of:locale:)` −1 to −36% (latin 2653→1702,
thai 2308→2009). Compare and contains within noise of unchanged.

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
     (latin 2653→1702), but the precompiled bench_system also lowered the
     system reference, so ratios read 1.05–1.40× — ASCII/Latin at parity, the
     non-ASCII CE fall-through still the frontier.

## Cross-reference

- Apple Silicon (machine 2) Foundation-API numbers: `21-foundation-api-benchmark.md`,
  `HANDOFF.md` "Apple Silicon" perf subsection.
- Pure-engine Intel history (pre-module-move): `HANDOFF.md` "Intel iMac" perf subsection.
