# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-07-06 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Includes all search optimizations (scratch iterator reuse, byte-scan
fast path, lazy position reporting).

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: `swift -O bench_system_foundation.swift` (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 127   | 196       | **1.5× faster** |
| Latin  | 128   | 360       | **2.8× faster** |
| CJK    | 235   | 367       | **1.6× faster** |
| Paths  | 165   | 300       | **1.8× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 136   | 197       | **1.4× faster** |
| Latin  | 136   | 345       | **2.5× faster** |
| CJK    | 243   | 362       | **1.5× faster** |
| Paths  | 188   | 320       | **1.7× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 137   | 198       | **1.4× faster** |
| Latin  | 137   | 347       | **2.5× faster** |
| CJK    | 244   | 364       | **1.5× faster** |
| Paths  | 176   | 308       | **1.8× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 302   | 313       | **1.0× (parity)** |
| Latin  | 307   | 485       | **1.6× faster** |
| CJK    | 435   | 486       | **1.1× faster** |
| Paths  | 343   | 414       | **1.2× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 439   | 999       | **2.3× faster** |
| Latin  | 454   | 1445      | **3.2× faster** |
| CJK    | 483   | 1280      | **2.7× faster** |
| Paths  | 492   | 963       | **2.0× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 445   | 1013      | **2.3× faster** |
| Latin  | 455   | 1496      | **3.3× faster** |
| CJK    | 483   | 1297      | **2.7× faster** |
| Paths  | 460   | 976       | **2.1× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 457   | 998       | **2.2× faster** |
| Latin  | 469   | 1441      | **3.1× faster** |
| CJK    | 502   | 1277      | **2.5× faster** |
| Paths  | 722   | 989       | **1.4× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 361   | 323       | 0.9× (parity) |
| Latin  | 655   | 790       | **1.2× faster** |
| CJK    | 687   | 585       | 0.9× (near parity) |
| Paths  | 427   | 313       | 0.7× (behind) |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 361   | 324       | **0.9× (parity)** |
| Latin  | 663   | 830       | **1.3× faster** |
| CJK    | 682   | 596       | 0.9× (near parity) |
| Paths  | 469   | 506       | **1.1× faster** |

### Direct RootCollator (standalone, no Foundation overhead)

| Corpus | compare | ICU 79 | ratio | sortKey (inout) | ICU 79 | ratio | sortKey (alloc) |
|--------|---------|--------|-------|---------|--------|-------|---------|
| ASCII  | 25      | 9      | 2.8×  | 216     | 103    | 2.1×  | 270 |
| Latin  | 24      | 10     | 2.4×  | 232     | 123    | 1.9×  | 287 |
| CJK    | 126     | 41     | 3.1×  | 228     | 124    | 1.8×  | 318 |
| Paths  | 62      | 30     | 2.1×  | 534     | 373    | 1.4×  | 679 |

## Analysis

**`localizedCompare`, `localizedStandardCompare`, and
`localizedCaseInsensitiveCompare`** are 1.4–2.8× faster than system ICU
across all corpora. Our collator avoids the ObjC bridge overhead
(NSString → CoreFoundation → ICU) that the system path pays.

**`compare(_:locale:)`** is 1.0–1.6× faster. Slightly less improvement
because this path goes through Foundation's `StringProtocol.compare`
generic dispatch which adds overhead on both sides.

**`localizedStandardContains` and `localizedCaseInsensitiveContains`**
are 1.5–3.3× faster across all corpora. Key optimizations: scratch
iterator reuse eliminating per-call allocation, lazy CE production,
short-string reserveCapacity threshold.

**`localizedStandardRange(of:)`** is 1.1–3.0× faster. Lazy position
reporting (2026-07-04) was the decisive step: defer NFD→source mapping,
boundary validation, and String.Index construction to match time only.
No-match calls (the common case) now do zero position work.

**`range(of:locale:)`** is mixed. ASCII/Latin beat or match system ICU
(byte-scan fast path at tertiary strength). CJK is near parity (0.9×),
paths is 0.7× — the system's `NSString rangeOfString:locale:` uses
Latin-1 single-byte encoding advantage and pre-cached ICU `usearch`.

**`range(of:.backwards,locale:)`** is at parity or faster across all
corpora after the backward byte-scan fast path (2026-07-06). ASCII
0.9× (parity), Latin 1.3× faster, CJK 0.9× (near parity), paths 1.1×
faster. Previously our weakest API (0.4–0.5×).

**Allocating vs inout sortKey**: the allocating variant costs 24–39%
more — the per-call `[UInt8]` allocation + copy that `sortKey(for:into:)`
eliminates. Callers generating many keys should use the inout API.

**Direct collation arithmetic** is 1.8–3.1× slower than ICU's C (Swift
value-type + function-call overhead). Through Foundation APIs the ObjC
bridge cost offsets this entirely for most APIs.

## How to reproduce

```sh
# Swift Collator (via Foundation APIs):
cd swift-foundation-collation
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# System Foundation (NSString → ICU):
swift -O Collation/Tools/bench_system_foundation.swift Collation/Tools/bench/bench-ascii.txt 200
```
