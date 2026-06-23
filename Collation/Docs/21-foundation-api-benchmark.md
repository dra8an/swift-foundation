# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-06-23 on Apple Silicon (macOS 26), min of 9 passes, release
builds. **Updated after cross-module inlining fix (Docs/22).**

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: `swift -O bench_system_foundation.swift` (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 128   | 195       | **1.5× faster** |
| Latin  | 128   | 358       | **2.8× faster** |
| CJK    | 238   | 368       | **1.5× faster** |
| Paths  | 165   | 299       | **1.8× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 136   | 197       | **1.4× faster** |
| Latin  | 136   | 349       | **2.6× faster** |
| CJK    | 242   | 358       | **1.5× faster** |
| Paths  | 185   | 318       | **1.7× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 298   | 313       | **1.1× faster** |
| Latin  | 298   | 482       | **1.6× faster** |
| CJK    | 448   | 487       | **1.1× faster** |
| Paths  | 342   | 412       | **1.2× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 1383  | 1009      | 0.7× (slower) |
| Latin  | 1476  | 1437      | 1.0× (parity) |
| CJK    | 1174  | 1273      | **1.1× faster** |
| Paths  | 2963  | 972       | 0.3× (slower) |

## Analysis

**`localizedCompare` and `localizedStandardCompare`** are 1.4–2.8× faster
than system ICU across all corpora. Our collator avoids the ObjC bridge
overhead (NSString → CoreFoundation → ICU) that the system path pays.

**`compare(_:locale:)`** is 1.1–1.6× faster. Slightly less improvement
because this path goes through Foundation's `StringProtocol.compare`
generic dispatch which adds overhead on both sides.

**`localizedStandardContains`** is mixed — faster on CJK, slower on
ASCII/paths. Our v1 search implementation (linear CE scan with full
text pre-processing) is less optimized than ICU's `usearch` (ring buffer,
on-demand CE production). Search optimization is a separate effort.

## How to reproduce

```sh
# Swift Collator (via Foundation APIs):
cd swift-foundation-collation
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# System Foundation (NSString → ICU):
swift -O Collation/Tools/bench_system_foundation.swift Collation/Tools/bench/bench-ascii.txt 200
```
