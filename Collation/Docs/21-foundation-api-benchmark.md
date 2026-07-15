# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-07-15 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Includes all optimizations through §37 (allocation-free search).

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: pre-compiled `bench_system` binary (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 44    | 195       | **4.4× faster** |
| Latin  | 45    | 352       | **7.8× faster** |
| CJK    | 66    | 369       | **5.6× faster** |
| Paths  | 77    | 299       | **3.9× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 52    | 195       | **3.8× faster** |
| Latin  | 53    | 346       | **6.5× faster** |
| CJK    | 79    | 357       | **4.5× faster** |
| Paths  | 93    | 322       | **3.5× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 53    | 197       | **3.7× faster** |
| Latin  | 54    | 342       | **6.3× faster** |
| CJK    | 80    | 357       | **4.5× faster** |
| Paths  | 87    | 309       | **3.6× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 190   | 332       | **1.7× faster** |
| Latin  | 193   | 505       | **2.6× faster** |
| CJK    | 218   | 489       | **2.2× faster** |
| Paths  | 231   | 413       | **1.8× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 224   | 1006      | **4.5× faster** |
| Latin  | 242   | 1434      | **5.9× faster** |
| CJK    | 263   | 1280      | **4.9× faster** |
| Paths  | 245   | 983       | **4.0× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 223   | 1012      | **4.5× faster** |
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
| ASCII  | 210   | 344       | **1.6× faster** |
| Latin  | 407   | 817       | **2.0× faster** |
| CJK    | 429   | 581       | **1.4× faster** |
| Paths  | 275   | 318       | **1.2× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 210   | 349       | **1.7× faster** |
| Latin  | 416   | 846       | **2.0× faster** |
| CJK    | 429   | 593       | **1.4× faster** |
| Paths  | 312   | 514       | **1.6× faster** |

### Direct RootCollator (EngineBench, full WMO)

| Corpus | compare | ICU 79 | ratio | sortKey (inout) | ICU 79 | ratio | sortKey (alloc) |
|--------|---------|--------|-------|---------|--------|-------|---------|
| ASCII  | 17      | 9      | 1.9×  | 198     | 107    | 1.9×  | 265 |
| Latin  | 16      | 10     | 1.6×  | 218     | 125    | 1.7×  | 282 |
| CJK    | 27      | 42     | **0.6×** | 213  | 121    | 1.8×  | 296 |
| Paths  | 42      | 30     | 1.4×  | 450     | 372    | 1.2×  | 529 |
| Thai   | 286     | 192    | 1.5×  | 253     | 161    | 1.6×  | 324 |

## Analysis

**`localizedCompare` family** is 3.7–7.8× faster than system ICU.

**`compare(_:locale:)`** is 1.7–2.6× faster.

**Search APIs (contains, range)** are 1.2–6.2× faster. The §37
allocation-free refactor (2026-07-15) moved pattern/annotated/text CE
buffers into ScratchBuffers, eliminating per-call malloc/free. Contains
and localizedStandardRange improved 29–35% across all corpora.

**Direct engine compare** is 1.4–1.9× behind ICU on ASCII/Latin/paths,
**0.6× on CJK** (faster than ICU).

**Sort keys** are 1.2–1.9× behind ICU. Paths at 1.2× is our tightest.

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
# EngineBench/BenchFoundation: <corpus> 10
# bench_icu: bench/bench-thai.txt 10 th
```
