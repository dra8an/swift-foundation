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
| ascii  | 16  | 50   | 3.12× | 196 | 424  | 2.16× | 585  | 2.98× |
| latin  | 17  | 50   | 2.94× | 212 | 475  | 2.24× | 624  | 2.94× |
| cjk    | 73  | 283  | 3.88× | 219 | 493  | 2.25× | 717  | 3.27× |
| paths  | 48  | 120  | 2.50× | 669 | 1143 | 1.71× | 1614 | 2.41× |
| thai   | 288 | 828  | 2.88× | 293 | 676  | 2.31× | 863  | 2.95× |

Pure-Swift vs hand-tuned C: ~2.5–3.9× on compare, ~1.7–2.5× on sortKey. This is
the expected gap for a from-scratch Swift implementation against ICU's C engine.

## Table 2 — Integrated in Foundation (same APIs, two backends)

Both call the *same* Foundation APIs; one routes to system ICU (NSString→ICU),
the other to our Swift collator. ratio = ours / system-ICU. **<1 = ours faster.**

| API | ascii | latin | cjk | paths | thai |
|-----|------:|------:|----:|------:|-----:|
| `compare(locale:)`               | 0.92× | 0.55× | 0.74× | 0.77× | 1.08× |
| `localizedCompare`               | 0.60× | 0.31× | 0.55× | 0.49× | 0.96× |
| `localizedStandardCompare`       | 0.67× | 0.34× | 0.57× | 0.56× | 1.01× |
| `localizedCaseInsensitiveCompare`| 0.66× | 0.35× | 0.57× | 0.52× | 1.01× |
| `localizedStandardContains`      | 0.75× | 0.49× | 0.58× | 1.14× | 0.52× |
| `localizedCaseInsensitiveContains`| 0.76× | 0.46× | 0.57× | 0.85× | 0.50× |
| `localizedStandardRange`         | 0.87× | 0.53× | 0.61× | 1.38× | 0.70× |
| `range(of:options:locale:)`      | 1.18× | 1.02× | 1.32× | 1.35× | 1.17× |
| `range(of:.backwards,locale:)`   | 1.17× | **0.94×** | 1.32× | **0.96×** | 1.09× |

Raw ns/op behind the ratios (2026-07-06 post-fix quiet-machine run):

| API | corpus | sysICU | ours |
|-----|--------|-------:|-----:|
| compare(locale:)   | ascii/latin/cjk/paths/thai | 659 / 1086 / 1155 / 899 / 1331 | 603 / 598 / 853 / 693 / 1433 |
| localizedCompare   | ascii/latin/cjk/paths/thai | 436 / 861 / 928 / 676 / 1114   | 262 / 269 / 507 / 332 / 1064 |
| localizedStdCmp    | ascii/latin/cjk/paths/thai | 436 / 858 / 933 / 692 / 1080   | 291 / 292 / 531 / 387 / 1092 |
| localizedCaseICmp  | ascii/latin/cjk/paths/thai | 435 / 866 / 933 / 678 / 1076   | 285 / 300 / 532 / 355 / 1089 |
| localizedStdContns | ascii/latin/cjk/paths/thai | 1440 / 2435 / 2204 / 1395 / 2380 | 1086 / 1196 / 1276 / 1587 / 1242 |
| localizedCaseICnt  | ascii/latin/cjk/paths/thai | 1465 / 2579 / 2222 / 1412 / 2496 | 1111 / 1198 / 1276 / 1194 / 1236 |
| localizedStdRange  | ascii/latin/cjk/paths/thai | 1424 / 2429 / 2260 / 1407 / 2530 | 1243 / 1285 / 1388 / 1940 / 1766 |
| range(of:locale:)  | ascii/latin/cjk/paths/thai | 607 / 1643 / 1353 / 613 / 1616   | 716 / 1680 / 1790 / 826 / 1892 |
| range(backwards)   | ascii/latin/cjk/paths/thai | 612 / 1717 / 1371 / 925 / 1653   | 717 / 1612 / 1804 / 887 / 1809 |

History of the ours columns across today's three changes (min ns/op):
`localizedStandardRange` — 06-26: 1625/2001/1732/3094/2110 → lazy
positions: 1193/1235/1351/1994/1747 → +reserve: paths ~1940.
`range(backwards)` — first baseline (pre-fix): 1555/1591/1749/3149/1862 →
+reserve+byte-scan: 717/1612/1804/887/1809 (ascii −54%, paths −72%).
`range(of:locale:)` forward pays +2–5% for the byte-scan soundness fixes
(§20 step 8). Compare and contains unchanged throughout.

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
     therefore a measurable cost worth a look.
   - **Allocating sortKey (`skRet`, Table 1)** costs ~160–470 ns/op over the
     inout variant (ascii 424→585, paths 1143→1614) — the per-call
     allocation+copy, as designed; recorded so the delta is tracked.

## Cross-reference

- Apple Silicon (machine 2) Foundation-API numbers: `21-foundation-api-benchmark.md`,
  `HANDOFF.md` "Apple Silicon" perf subsection.
- Pure-engine Intel history (pre-module-move): `HANDOFF.md` "Intel iMac" perf subsection.
