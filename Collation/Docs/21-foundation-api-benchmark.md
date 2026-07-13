# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-07-13 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Includes boxed RootCollator storage, hot/cold compare split,
word-wise prefix scan, all search optimizations.

Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: `swift -O bench_system_foundation.swift` (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 44    | 196       | **4.5× faster** |
| Latin  | 44    | 360       | **8.2× faster** |
| CJK    | 150   | 367       | **2.4× faster** |
| Paths  | 75    | 300       | **4.0× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 51    | 197       | **3.9× faster** |
| Latin  | 52    | 345       | **6.6× faster** |
| CJK    | 159   | 362       | **2.3× faster** |
| Paths  | 91    | 320       | **3.5× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 51    | 198       | **3.9× faster** |
| Latin  | 52    | 347       | **6.7× faster** |
| CJK    | 158   | 364       | **2.3× faster** |
| Paths  | 85    | 308       | **3.6× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 196   | 313       | **1.6× faster** |
| Latin  | 203   | 485       | **2.4× faster** |
| CJK    | 309   | 486       | **1.6× faster** |
| Paths  | 226   | 414       | **1.8× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 352   | 999       | **2.8× faster** |
| Latin  | 365   | 1445      | **4.0× faster** |
| CJK    | 401   | 1280      | **3.2× faster** |
| Paths  | 398   | 963       | **2.4× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 349   | 1013      | **2.9× faster** |
| Latin  | 367   | 1496      | **4.1× faster** |
| CJK    | 398   | 1297      | **3.3× faster** |
| Paths  | 380   | 976       | **2.6× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 364   | 998       | **2.7× faster** |
| Latin  | 380   | 1441      | **3.8× faster** |
| CJK    | 410   | 1277      | **3.1× faster** |
| Paths  | 626   | 989       | **1.6× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 255   | 323       | **1.3× faster** |
| Latin  | 552   | 790       | **1.4× faster** |
| CJK    | 579   | 585       | **1.0× (parity)** |
| Paths  | 323   | 313       | **1.0× (parity)** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  | 255   | 324       | **1.3× faster** |
| Latin  | 554   | 830       | **1.5× faster** |
| CJK    | 577   | 596       | **1.0× (parity)** |
| Paths  | 361   | 506       | **1.4× faster** |

### Direct RootCollator (standalone, no Foundation overhead)

| Corpus | compare | ICU 79 | ratio | sortKey (inout) | ICU 79 | ratio | sortKey (alloc) |
|--------|---------|--------|-------|---------|--------|-------|---------|
| ASCII  | 16      | 9      | 1.8×  | 200     | 103    | 1.9×  | 259 |
| Latin  | 15      | 10     | 1.5×  | 220     | 123    | 1.8×  | 277 |
| CJK    | 116     | 41     | 2.8×  | 215     | 124    | 1.7×  | 303 |
| Paths  | 42      | 30     | 1.4×  | 520     | 373    | 1.4×  | 669 |

## Analysis

**`localizedCompare`, `localizedStandardCompare`, and
`localizedCaseInsensitiveCompare`** are 2.3–8.2× faster than system ICU.
The boxed RootCollator storage (2026-07-13) eliminated a 768-byte struct
memcpy per Foundation API call; the hot/cold compare split removed the
`throws` error ABI overhead from the fast path. Together these halved
the compare APIs on short strings.

**`compare(_:locale:)`** is 1.6–2.4× faster. Previously at parity on
ASCII; the storage boxing benefits this path equally.

**`localizedStandardContains` and `localizedCaseInsensitiveContains`**
are 2.4–4.1× faster across all corpora.

**`localizedStandardRange(of:)`** is 1.6–3.8× faster.

**`range(of:locale:)` and `range(of:.backwards,locale:)`** are at parity
or faster across all corpora. The byte-scan fast path handles ASCII/paths;
non-ASCII corpora reach parity through lazy position reporting and
scratch iterator reuse.

**Direct collation arithmetic** is 1.4–2.8× slower than ICU's C (down
from 2–3× before the entry-cost optimizations). The remaining gap is
per-byte Swift value-type overhead vs C — the hard floor.

## How to reproduce

```sh
# Swift Collator (via Foundation APIs):
cd swift-foundation-collation
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# System Foundation (NSString → ICU):
swift -O Collation/Tools/bench_system_foundation.swift Collation/Tools/bench/bench-ascii.txt 200
```
