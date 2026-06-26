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
    `localizedCompare`, `localizedStandardCompare`, `localizedStandardContains`,
    `localizedStandardRange`, and `range(of:options:locale:)`.

## Table 1 — Pure collator engine

Our pure-Swift `RootCollator` vs ICU's C library. ratio = ours / ICU.

| corpus | compare ICU | compare ours | ratio | sortKey ICU | sortKey ours | ratio |
|--------|------------:|-------------:|------:|------------:|-------------:|------:|
| ascii  | 16  | 51   | 3.19× | 193 | 420  | 2.18× |
| latin  | 17  | 53   | 3.12× | 208 | 464  | 2.23× |
| cjk    | 72  | 288  | 4.00× | 219 | 501  | 2.29× |
| paths  | 49  | 122  | 2.49× | 662 | 1113 | 1.68× |
| thai   | 260 | 819  | 3.15× | 268 | 679  | 2.53× |

Pure-Swift vs hand-tuned C: ~2.5–3.9× on compare, ~1.7–2.5× on sortKey. This is
the expected gap for a from-scratch Swift implementation against ICU's C engine.

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. ratio = ours / system-ICU. **<1 = ours faster.**

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`          | 0.75× | 0.49× | 0.67× | 0.67× | 0.94× |
| `localizedCompare`          | 0.62× | 0.30× | 0.54× | 0.48× | 0.92× |
| `localizedStandardCompare`  | 0.67× | 0.33× | 0.56× | 0.54× | 0.98× |
| `localizedStandardContains` | 0.77× | 0.46× | 0.57× | 1.11× | 0.49× |
| `localizedStandardRange`    | 1.16× | 0.83× | 0.78× | 2.18× | 0.81× |
| `range(of:options:locale:)` | 0.96× | 1.50× | 1.46× | 1.13× | 1.30× |

Raw ns/op behind the ratios:

| API | corpus | sysICU | ours |
|-----|--------|-------:|-----:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 785 / 1206 / 1270 / 1042 / 1516 | 587 / 587 / 845 / 693 / 1426 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 426 / 866 / 932 / 682 / 1130   | 263 / 263 / 505 / 330 / 1039 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 425 / 867 / 933 / 704 / 1095   | 283 / 284 / 526 / 382 / 1074 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1411 / 2436 / 2218 / 1384 / 2468 | 1081 / 1125 / 1268 / 1538 / 1210 |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1400 / 2423 / 2216 / 1417 / 2611 | 1625 / 2001 / 1732 / 3094 / 2110 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 726 / 1769 / 1472 / 750 / 1777   | 697 / 2653 / 2147 / 846 / 2308 |

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

4. **Range-returning search is mixed, by API.** Both `search`/`searchBackwards`
   got the same scratch-iterator reuse (`a56b5a3`), and `range(of:locale:)`
   additionally got ASCII / UTF-8 byte-scan fast paths (`6e214ff` / `7c742c0`).
   - **`localizedStandardRange`** (strength `.primary`, numeric on → CE path, no
     byte-scan): Latin/CJK/Thai **beat** ICU (0.78–0.83×); ASCII (1.16×) and
     paths (2.18×) remain behind — these still build the index table + NFD map +
     `AnnotatedCE` buffer for position reporting, which iterator reuse doesn't
     remove (that's the next lever).
   - **`range(of:options:locale:)`** (default options → strength `.tertiary`,
     non-numeric → byte-scan fast path applies): ASCII **0.96×** (near parity,
     the byte-scan win) and paths 1.13×, but non-ASCII (Latin/CJK/Thai) falls
     through to the CE path and is 1.3–1.5× behind. The byte-scan fast path only
     fires for tertiary/non-numeric, so `localizedStandardRange` (primary+numeric)
     does not benefit from it.

## Cross-reference

- Apple Silicon (machine 2) Foundation-API numbers: `21-foundation-api-benchmark.md`,
  `HANDOFF.md` "Apple Silicon" perf subsection.
- Pure-engine Intel history (pre-module-move): `HANDOFF.md` "Intel iMac" perf subsection.
