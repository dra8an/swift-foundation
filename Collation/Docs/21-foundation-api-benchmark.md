# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-07-23 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Includes all optimizations through §45 (tailoring default options)
plus correctness fixes (§44 locale-change revalidation, §45 fr_CA defaults).

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: pre-compiled `bench_system` binary (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 55    | 195       | **3.5× faster** |
| Latin  | 57    | 352       | **6.2× faster** |
| CJK    | 77    | 369       | **4.8× faster** |
| Paths  | 80    | 299       | **3.7× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 55    | 195       | **3.5× faster** |
| Latin  | 57    | 346       | **6.1× faster** |
| CJK    | 82    | 357       | **4.4× faster** |
| Paths  | 95    | 322       | **3.4× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 55    | 197       | **3.6× faster** |
| Latin  | 56    | 342       | **6.1× faster** |
| CJK    | 82    | 357       | **4.4× faster** |
| Paths  | 88    | 309       | **3.5× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 73    | 332       | **4.5× faster** |
| Latin  | 73    | 505       | **6.9× faster** |
| CJK    | 92    | 489       | **5.3× faster** |
| Paths  | 100   | 413       | **4.1× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 226   | 1006      | **4.5× faster** |
| Latin  | 242   | 1434      | **5.9× faster** |
| CJK    | 264   | 1280      | **4.8× faster** |
| Paths  | 239   | 983       | **4.1× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 227   | 1012      | **4.5× faster** |
| Latin  | 242   | 1496      | **6.2× faster** |
| CJK    | 263   | 1295      | **4.9× faster** |
| Paths  | 221   | 994       | **4.5× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 239   | 1009      | **4.2× faster** |
| Latin  | 255   | 1438      | **5.6× faster** |
| CJK    | 278   | 1284      | **4.6× faster** |
| Paths  | 320   | 993       | **3.1× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 87    | 344       | **4.0× faster** |
| Latin  | 276   | 817       | **3.0× faster** |
| CJK    | 302   | 581       | **1.9× faster** |
| Paths  | 156   | 318       | **2.0× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 84    | 349       | **4.2× faster** |
| Latin  | 289   | 846       | **2.9× faster** |
| CJK    | 303   | 593       | **2.0× faster** |
| Paths  | 193   | 514       | **2.7× faster** |

### Direct RootCollator (EngineBench, full WMO)

| Corpus | compare | ICU 79 | ratio | sortKey (inout) | ICU 79 | ratio | sortKey (alloc) |
|--------|---------|--------|-------|---------|--------|-------|---------|
| ASCII  | 17      | 9      | 1.9×  | 177     | 107    | 1.7×  | 241 |
| Latin  | 16      | 10     | 1.6×  | 193     | 125    | 1.5×  | 249 |
| CJK    | 28      | 42     | **0.7×** | 195  | 121    | 1.6×  | 272 |
| Paths  | 43      | 30     | 1.4×  | 435     | 372    | 1.2×  | 523 |
| Thai   | 283     | 192    | 1.5×  | 231     | 161    | 1.4×  | 302 |

## Analysis

**Every Foundation API is 1.9–6.9× faster than system ICU on every
corpus.** No cells at parity or behind.

**`localizedCompare` family** is 3.5–6.2× faster. The §44 locale-change
revalidation adds ~12 ns per call (generation-counter check); the §45
tailoring-defaults fix adds a few ns in the -no-WMO bench build (WMO
folds it). Both accepted for correctness.

**`compare(_:locale:)`** is 4.1–6.9× faster.

**Search APIs (contains, range)** are 1.9–6.2× faster.

**Direct engine compare** is 1.4–1.9× behind ICU on ASCII/Latin/paths,
**0.7× on CJK** (faster than ICU), 1.5× on Thai. Engine is unaffected
by the correctness fixes.

**Sort keys** are 1.2–1.7× behind ICU. Direct multi-pass writer (§43).

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
