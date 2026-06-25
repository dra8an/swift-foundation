# Benchmark Matrix — Intel iMac (machine 1)

> **Platform: Intel iMac, macOS 15, Swift 6.3.1 release.** These numbers are
> **machine 1 only** — do not compare them directly against the Apple Silicon
> (machine 2) numbers in `21-foundation-api-benchmark.md` / `HANDOFF.md`.
> Absolute ns differ by hardware (ICU is faster on Apple Silicon too); read the
> *ratios* within this doc, not cross-machine deltas.
>
> Measured 2026-06-24, at `port/collation` (`78729ac`) — after the
> FoundationInternationalization module move and the four stacked search
> optimizations: lazy CE production (`7648b1d`), buffer `reserveCapacity` on the
> range path (`e1cd576`), the `contains()` Bool fast path (`c683653`), and
> `reserveCapacity` on that fast path too (`78729ac`).

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
  ASCII/Latin/CJK 300, paths 150, thai 3.
- Corpora: `Collation/Tools/bench/bench-{ascii,latin,cjk,paths,thai}.txt`
  (thai uses the `th` tailoring / dictionary corpus).
- Harnesses:
  - **Pure ICU:** `Collation/Tools/bench_icu.c` → `ucol_strcollUTF8` / `ucol_getSortKey`
    (ICU 79, local build at `~/Projects/claude/collation/icu-build`).
  - **Pure ours:** `BenchFoundation` measures `RootCollator.cmp` / `RootCollator.sk`
    (direct engine, no Foundation API).
  - **System ICU via Foundation:** `Collation/Tools/bench_system_foundation.swift`
    (`swift -O`, NSString → system ICU).
  - **Ours via Foundation:** `BenchFoundation` measures `compare(locale:)`,
    `localizedCompare`, `localizedStandardCompare`, `localizedStandardContains`.

## Table 1 — Pure collator engine

Our pure-Swift `RootCollator` vs ICU's C library. ratio = ours / ICU.

| corpus | compare ICU | compare ours | ratio | sortKey ICU | sortKey ours | ratio |
|--------|------------:|-------------:|------:|------------:|-------------:|------:|
| ascii  | 16  | 51   | 3.19× | 193 | 424  | 2.20× |
| latin  | 17  | 51   | 3.00× | 208 | 464  | 2.23× |
| cjk    | 72  | 284  | 3.94× | 217 | 487  | 2.24× |
| paths  | 49  | 120  | 2.45× | 659 | 1146 | 1.74× |
| thai   | 258 | 816  | 3.16× | 267 | 663  | 2.48× |

Pure-Swift vs hand-tuned C: ~2.5–3.9× on compare, ~1.7–2.5× on sortKey. This is
the expected gap for a from-scratch Swift implementation against ICU's C engine.

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. ratio = ours / system-ICU. **<1 = ours faster.**

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`          | 0.76× | 0.49× | 0.66× | 0.67× | 1.00× |
| `localizedCompare`          | 0.61× | 0.30× | 0.54× | 0.49× | 0.97× |
| `localizedStandardCompare`  | 0.66× | 0.33× | 0.55× | 0.56× | 1.02× |
| `localizedStandardContains` | 1.49× | 0.93× | 0.96× | 2.00× | 0.92× |

Raw ns/op behind the ratios:

| API | corpus | sysICU | ours |
|-----|--------|-------:|-----:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 779 / 1198 / 1254 / 1016 / 1422 | 591 / 583 / 829 / 684 / 1418 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 434 / 881 / 921 / 669 / 1076   | 263 / 263 / 496 / 329 / 1042 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 432 / 871 / 933 / 681 / 1045   | 284 / 285 / 517 / 382 / 1067 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1410 / 2428 / 2189 / 1365 / 2318 | 2099 / 2249 / 2097 / 2727 / 2127 |

## Findings

1. **The engine is slower than raw ICU** (Table 1) — pure Swift vs C on the core
   algorithm, as expected.
2. **But integrated in Foundation, ours wins the compare family** by 1.0–3.3×
   (Table 2): system Foundation pays `ucol_open`/`ucol_close` + bridging *per
   call*; our cached collator does not. End users calling `localizedCompare` /
   `compare(locale:)` get faster results from the Swift collator despite the
   slower engine. Latin is the standout — **3.3× faster** on `localizedCompare`.
   Thai is ≈ parity (the dictionary corpus is the heaviest case for both).
3. **`localizedStandardContains` — at or near ICU parity after four stacked
   search optimizations.** (a) lazy CE production (`7648b1d`, return on first
   match); (b) buffer `reserveCapacity` on the range path (`e1cd576`, kill the
   per-call Array-growth realloc that profiling showed was ~44% of the time);
   (c) a dedicated `contains()` Bool fast path (`c683653`) that skips the index
   table, NFD map, `AnnotatedCE` structs, and boundary validation entirely —
   `contains` needs only yes/no, not the range; (d) `reserveCapacity` on the fast
   path's own buffers (`78729ac`, the same realloc fix — the fast path grew fresh
   buffers from empty too). Result vs the pre-optimization matrix:

   | corpus | before (×ICU) | now (×ICU) | ours ns: before → now |
   |--------|--------------:|-----------:|----------------------:|
   | ascii  | 2.80× | 1.49× | 3951 → 2099 |
   | latin  | 1.71× | **0.93×** | 4125 → 2249 |
   | cjk    | 1.51× | **0.96×** | 3325 → 2097 |
   | paths  | 5.88× | 2.00× | 8252 → 2727 |
   | thai   | 1.71× | **0.92×** | 3993 → 2127 |

   **Latin, CJK, and Thai now match or beat system ICU** on contains; ASCII
   (1.49×) and paths (2.00×) remain behind. Step (d) was a clear Intel win on
   ASCII/Latin/CJK/Thai (−12 to −21% on top of the fast path) but ~neutral on
   paths — paths' benchmark needle (a prefix of line 1) matches many same-prefixed
   lines *early*, so the fast path returns before the buffer grows and the reserve
   slightly over-allocates. The deeper remaining lever (mainly for ASCII/paths) is
   reusing CE buffers across calls (scratch-pool, like the main collator) or
   CE-space skipping (ICU's ring-buffer `usearch` model).

## Cross-reference

- Apple Silicon (machine 2) Foundation-API numbers: `21-foundation-api-benchmark.md`,
  `HANDOFF.md` "Apple Silicon" perf subsection.
- Pure-engine Intel history (pre-module-move): `HANDOFF.md` "Intel iMac" perf subsection.
