# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-06-23 on Apple Silicon (macOS 26), min of 9 passes, release
builds. Same Foundation APIs, two backends:

- **Swift Collator**: `swift run -c release BenchFoundation` (SwiftPM build,
  routes through CollatorCache → RootCollator)
- **System ICU**: `swift -O bench_system_foundation.swift` (system Foundation,
  routes through NSString → CoreFoundation → ICU)

## Results (ns/op)

### compare(_:locale:)

| Corpus | Swift | System ICU | Ratio |
|--------|-------|-----------|-------|
| ASCII  | 521   | 311       | 1.7×  |
| Latin  | 516   | 482       | 1.1×  |
| CJK    | 653   | 487       | 1.3×  |
| Paths  | 570   | 409       | 1.4×  |

### localizedCompare(_:)

| Corpus | Swift | System ICU | Ratio |
|--------|-------|-----------|-------|
| ASCII  | 1337  | 195       | 6.9×  |
| Latin  | 1322  | 364       | 3.6×  |
| CJK    | 1462  | 366       | 4.0×  |
| Paths  | 1365  | 298       | 4.6×  |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Ratio |
|--------|-------|-----------|-------|
| ASCII  | 1354  | 196       | 6.9×  |
| Latin  | 1332  | 351       | 3.8×  |
| CJK    | 1477  | 361       | 4.1×  |
| Paths  | 1386  | 321       | 4.3×  |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Ratio |
|--------|-------|-----------|-------|
| ASCII  | 2596  | 994       | 2.6×  |
| Latin  | 2688  | 1441      | 1.9×  |
| CJK    | 2398  | 1287      | 1.9×  |
| Paths  | 4141  | 980       | 4.2×  |

## Analysis

**`compare(_:locale:)`** is the best ratio (1.1–1.7×). The caller provides the
Locale directly, so there's no `Locale.current` resolution per call.

**`localizedCompare` and `localizedStandardCompare`** are much worse (3.6–6.9×).
The per-call overhead comes from:

1. **`Locale.current`** — resolved every call (~36 ns standalone, but may be
   higher under contention with the collator cache lock)
2. **`CollatorCache.shared.collator(for:)`** — LockedState lock + dictionary
   lookup every call
3. **`String(self)` / `String(aString)`** — creates String copies from the
   StringProtocol generic parameters
4. **`try?`** — existential error boxing overhead

The system ICU path for `localizedCompare` is faster because NSString's
`localizedCompare:` is a single ObjC message send → direct C function call
into ICU, with no intermediate allocations or lock acquisition.

## Optimization opportunities

- **Cache `Locale.current` resolution** — resolve once per sort operation
  rather than per comparison
- **Avoid String copies** — accept StringProtocol directly in the collator,
  or use `withContiguousStorageIfAvailable` to avoid allocation
- **Lock-free cache hit** — the common case (same locale, same collator) could
  use an atomic read rather than acquiring the LockedState lock
- **Inline the collator call** — the `localizedCompare` → `CollatorCache` →
  `RootCollator.compare()` call chain has several layers that could be
  flattened for the hot path

## How to reproduce

```sh
# Swift Collator (via Foundation APIs):
cd swift-foundation-collation
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# System Foundation (NSString → ICU):
swift -O Collation/Tools/bench_system_foundation.swift Collation/Tools/bench/bench-ascii.txt 200
```
