# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-06-25 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Includes all search optimizations (lazy CE production, buffer
capacity reservation with short-string threshold, fast-path contains).

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: `swift -O bench_system_foundation.swift` (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 133   | 200       | **1.5× faster** |
| Latin  | 132   | 367       | **2.8× faster** |
| CJK    | 243   | 375       | **1.5× faster** |
| Paths  | 172   | 304       | **1.8× faster** |
| Thai   | 483   | 496       | **1.0× (parity)** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 141   | 201       | **1.4× faster** |
| Latin  | 142   | 352       | **2.5× faster** |
| CJK    | 251   | 366       | **1.5× faster** |
| Paths  | 194   | 326       | **1.7× faster** |
| Thai   | 494   | 484       | **1.0× (parity)** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 325   | 317       | **1.0× (parity)** |
| Latin  | 309   | 484       | **1.6× faster** |
| CJK    | 421   | 493       | **1.2× faster** |
| Paths  | 354   | 418       | **1.2× faster** |
| Thai   | 671   | 642       | **1.0× (parity)** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 453   | 1011      | **2.2× faster** |
| Latin  | 458   | 1474      | **3.2× faster** |
| CJK    | 483   | 1292      | **2.7× faster** |
| Paths  | 618   | 991       | **1.6× faster** |
| Thai   | 499   | 1367      | **2.7× faster** |

### Direct RootCollator (standalone, no Foundation overhead)

| Corpus | compare | ICU 79 | ratio | sortKey | ICU 79 | ratio |
|--------|---------|--------|-------|---------|--------|-------|
| ASCII  | 24      | 9      | 2.7×  | 216     | 103    | 2.1×  |
| Latin  | 25      | 10     | 2.5×  | 237     | 123    | 1.9×  |
| CJK    | 130     | 41     | 3.2×  | 232     | 124    | 1.9×  |
| Paths  | 63      | 30     | 2.1×  | 546     | 373    | 1.5×  |
| Thai   | 362     | 190    | 1.9×  | 316     | 161    | 2.0×  |

## Analysis

**`localizedCompare` and `localizedStandardCompare`** are 1.4–2.8× faster
than system ICU across all corpora. Our collator avoids the ObjC bridge
overhead (NSString → CoreFoundation → ICU) that the system path pays.

**`compare(_:locale:)`** is 1.0–1.6× faster. Slightly less improvement
because this path goes through Foundation's `StringProtocol.compare`
generic dispatch which adds overhead on both sides.

**`localizedStandardContains`** is 1.6–3.2× faster across all corpora.
Four stacked optimizations: lazy CE production for forward search
(7648b1d), buffer capacity reservation on the range-returning path
(e1cd576), a short-string threshold (≤32 UTF-8 bytes) on the Bool fast
path, and thread-local scratch iterator reuse that eliminates per-call
CEIterator allocation entirely (b93b549).

**Direct collation arithmetic** is 1.9–3.2× slower than ICU's C (Swift
value-type + function-call overhead). Through Foundation APIs the ObjC
bridge cost offsets this entirely.

## How to reproduce

```sh
# Swift Collator (via Foundation APIs):
cd swift-foundation-collation
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# System Foundation (NSString → ICU):
swift -O Collation/Tools/bench_system_foundation.swift Collation/Tools/bench/bench-ascii.txt 200
```
