# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-07-20 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Includes all optimizations through §44 (locale-change revalidation).

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: pre-compiled `bench_system` binary (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 56    | 195       | **3.5× faster** |
| Latin  | 57    | 352       | **6.2× faster** |
| CJK    | 66    | 369       | **5.6× faster** |
| Paths  | 77    | 299       | **3.9× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 57    | 195       | **3.4× faster** |
| Latin  | 57    | 346       | **6.1× faster** |
| CJK    | 79    | 357       | **4.5× faster** |
| Paths  | 93    | 322       | **3.5× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 56    | 197       | **3.5× faster** |
| Latin  | 56    | 342       | **6.1× faster** |
| CJK    | 80    | 357       | **4.5× faster** |
| Paths  | 87    | 309       | **3.6× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 66    | 332       | **5.0× faster** |
| Latin  | 67    | 505       | **7.5× faster** |
| CJK    | 88    | 489       | **5.6× faster** |
| Paths  | 95    | 413       | **4.3× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 231   | 1006      | **4.4× faster** |
| Latin  | 242   | 1434      | **5.9× faster** |
| CJK    | 263   | 1280      | **4.9× faster** |
| Paths  | 245   | 983       | **4.0× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 227   | 1012      | **4.5× faster** |
| Latin  | 242   | 1496      | **6.2× faster** |
| CJK    | 263   | 1295      | **4.9× faster** |
| Paths  | 245   | 994       | **4.1× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 235   | 1009      | **4.3× faster** |
| Latin  | 255   | 1438      | **5.6× faster** |
| CJK    | 274   | 1284      | **4.7× faster** |
| Paths  | 478   | 993       | **2.1× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 82    | 344       | **4.2× faster** |
| Latin  | 276   | 817       | **3.0× faster** |
| CJK    | 294   | 581       | **2.0× faster** |
| Paths  | 143   | 318       | **2.2× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 80    | 349       | **4.4× faster** |
| Latin  | 289   | 846       | **2.9× faster** |
| CJK    | 299   | 593       | **2.0× faster** |
| Paths  | 185   | 514       | **2.8× faster** |

### Direct RootCollator (EngineBench, full WMO)

| Corpus | compare | ICU 79 | ratio | sortKey (inout) | ICU 79 | ratio | sortKey (alloc) |
|--------|---------|--------|-------|---------|--------|-------|---------|
| ASCII  | 17      | 9      | 1.9×  | 178     | 107    | 1.7×  | 240 |
| Latin  | 15      | 10     | 1.5×  | 190     | 125    | 1.5×  | 253 |
| CJK    | 28      | 42     | **0.7×** | 200  | 121    | 1.7×  | 273 |
| Paths  | 43      | 30     | 1.4×  | 433     | 372    | 1.2×  | 519 |
| Thai   | 281     | 192    | 1.5×  | 231     | 161    | 1.4×  | 299 |

## Analysis

**Every Foundation API is 2.0–7.8× faster than system ICU on every
corpus.** No cells at parity or behind.

**`localizedCompare` family** is 3.4–6.2× faster (slightly reduced from
3.7–7.8× by the §44 locale-change revalidation, which adds a generation-
counter check per call — accepted for correctness).

**`compare(_:locale:)`** is 4.3–7.5× faster.

**Search APIs (contains, range)** are 2.0–6.2× faster.

**Direct engine compare** is 1.4–1.9× behind ICU on ASCII/Latin/paths,
**0.7× on CJK** (faster than ICU), 1.5× on Thai.

**Sort keys** are 1.2–1.7× behind ICU (down from 1.9× before §43).
The direct multi-pass writer eliminates intermediate level buffers —
each level writes straight into the output key through the stack-batch
idiom. Paths at 1.2×, Thai at 1.4×.

## How to reproduce

```sh
cd swift-foundation-collation

# Engine (full WMO, true Table 1):
cd Collation && bash Tools/build_engine_bench.sh
# Run: .build/engine-bench/.build/out/Products/Release/EngineBench <corpus> 200

# Foundation APIs (Table 2):
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# System Foundation — compile once, reuse binary:
swiftc -O -o Collation/Tools/bench_system Collation/Tools/bench_system_foundation.swift
Collation/Tools/bench_system Collation/Tools/bench/bench-ascii.txt 200

# ICU 79 direct:
cd Collation/Tools && DYLD_LIBRARY_PATH=~/Projects/Unicode/icu-DraganBesevic-2/icu4c/source/lib \
  ./bench_icu bench/bench-ascii.txt 200

# Thai: use 10 reps (33k lines per rep)
```
