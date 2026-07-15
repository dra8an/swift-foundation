# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-07-14 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Includes boxed RootCollator + CollationSearch storage, hot/cold
compare split, word-wise prefix scan, quick-primary CJK dispatch, primary
byte batching, all search optimizations.

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: `swift -O bench_system_foundation.swift` (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 47    | 201       | **4.3× faster** |
| Latin  | 45    | 368       | **8.2× faster** |
| CJK    | 66    | 377       | **5.7× faster** |
| Paths  | 77    | 304       | **3.9× faster** |
| Thai   | 314   | 499       | **1.6× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 52    | 201       | **3.9× faster** |
| Latin  | 53    | 355       | **6.7× faster** |
| CJK    | 79    | 368       | **4.7× faster** |
| Paths  | 93    | 327       | **3.5× faster** |
| Thai   | 329   | 483       | **1.5× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 52    | 203       | **3.9× faster** |
| Latin  | 54    | 355       | **6.6× faster** |
| CJK    | 80    | 370       | **4.6× faster** |
| Paths  | 87    | 315       | **3.6× faster** |
| Thai   | 330   | 485       | **1.5× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 208   | 320       | **1.5× faster** |
| Latin  | 193   | 493       | **2.6× faster** |
| CJK    | 218   | 499       | **2.3× faster** |
| Paths  | 231   | 421       | **1.8× faster** |
| Thai   | 473   | 634       | **1.3× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 326   | 1015      | **3.1× faster** |
| Latin  | 346   | 1478      | **4.3× faster** |
| CJK    | 370   | 1309      | **3.5× faster** |
| Paths  | 377   | 995       | **2.6× faster** |
| Thai   | 329   | 1395      | **4.2× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 324   | 1022      | **3.2× faster** |
| Latin  | 343   | 1533      | **4.5× faster** |
| CJK    | 374   | 1317      | **3.5× faster** |
| Paths  | 356   | 1007      | **2.8× faster** |
| Thai   | 330   | 1442      | **4.4× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 338   | 1013      | **3.0× faster** |
| Latin  | 361   | 1477      | **4.1× faster** |
| CJK    | 397   | 1302      | **3.3× faster** |
| Paths  | 605   | 1011      | **1.7× faster** |
| Thai   | 536   | 1443      | **2.7× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 233   | 330       | **1.4× faster** |
| Latin  | 525   | 810       | **1.5× faster** |
| CJK    | 548   | 603       | **1.1× faster** |
| Paths  | 296   | 322       | **1.1× faster** |
| Thai   | 524   | 719       | **1.4× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 237   | 333       | **1.4× faster** |
| Latin  | 524   | 845       | **1.6× faster** |
| CJK    | 553   | 606       | **1.1× faster** |
| Paths  | 331   | 523       | **1.6× faster** |
| Thai   | 528   | 769       | **1.5× faster** |

### Direct RootCollator (EngineBench, full WMO)

| Corpus | compare | ICU 79 | ratio | sortKey (inout) | ICU 79 | ratio | sortKey (alloc) |
|--------|---------|--------|-------|---------|--------|-------|---------|
| ASCII  | 17      | 9      | 1.9×  | 202     | 107    | 1.9×  | 265 |
| Latin  | 16      | 10     | 1.6×  | 218     | 125    | 1.7×  | 282 |
| CJK    | 27      | 42     | **0.6×** | 213  | 121    | 1.8×  | 296 |
| Paths  | 44      | 30     | 1.5×  | 453     | 372    | 1.2×  | 534 |
| Thai   | 286     | 192    | 1.5×  | 253     | 161    | 1.6×  | 324 |

## Analysis

**`localizedCompare` family** is 3.9–8.2× faster than system ICU.
The boxed storage (2026-07-13) eliminated the 768-byte struct memcpy;
the hot/cold compare split removed throws overhead; the quick-primary
CJK dispatch resolves Han comparisons at the byte-scan mismatch point
without entering the CE pipeline.

**`compare(_:locale:)`** is 1.5–2.6× faster. The generic dispatch path
through `StringProtocol.compare` adds overhead vs the direct localized*
methods.

**Search APIs (contains, range)** are 1.1–4.5× faster. Scratch iterator
reuse, lazy position reporting, byte-scan fast paths, backward byte-scan,
and CollationSearch storage boxing all stack.

**Direct engine compare** is 1.5–1.9× behind ICU on ASCII/Latin/paths
(per-call String-unwrapping overhead), but **0.6× on CJK** (faster than
ICU) thanks to the quick-primary dispatch resolving CJK in the byte path.

**Sort keys** are 1.2–1.9× behind ICU. The primary byte batching brought
paths to 1.2×. The remaining gap is the per-CE secondary/tertiary/case
level processing and the `collectAll()` intermediate array.

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
