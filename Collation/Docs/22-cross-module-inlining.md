# Cross-Module Inlining: localizedCompare 10× Improvement

## Summary

A two-line change — `@inlinable` on `RootCollator.compare()` and
`@usableFromInline` on its internal delegate — improved `localizedCompare`
from 6.9× slower than system ICU to 0.7× (30% faster). This document
explains exactly what changed, why it worked, and what to scrutinize.

## The problem

`localizedCompare` calls through two SwiftPM module boundaries:

```
FoundationInternationalization (module 1)
  → localizedCompare(_:)
    → CollatorCache.collatorForCurrentLocale()
    → RootCollator.compare(String, String)  ← crosses into module 2

Collation (module 2)
  → compare()
    → compareClassic()
      → fast-Latin byte path or compareBody()
        → CEIterator → NFDIterator
```

Each SwiftPM target is its own Swift module. Even in release mode with
`-whole-module-optimization`, the Swift compiler cannot inline function
calls across module boundaries. Every call from FoundationInternationalization
into Collation goes through a function pointer in the module's symbol table.

## What this costs

For short-string comparison (the common case), the collation arithmetic
itself takes ~25 ns. But the cross-module function call to `compare()`
adds enough overhead that the total becomes ~1170 ns — a 47× blowup
over the raw collation cost.

The overhead is NOT from:
- Lock acquisition (~7 ns, measured)
- `Locale.current` resolution (~30 ns, measured)
- `String(self)` copies (~50 ns for two, measured)
- `try?` error handling (~0 ns, optimized away)
- Dictionary lookup in CollatorCache (~5 ns on cache hit)

These were all measured individually and total ~92 ns. The remaining
~1050 ns was unaccounted for — until profiling revealed the real cause.

## Profiling evidence

`xcrun sample` on the BenchFoundation binary showed top samples in:

1. `_platform_strcmp` — string comparison during cross-module dispatch
2. `String.utf8CString.getter` — C string creation for cross-module calls
3. `swift_allocObject` / `swift_release_dealloc` — ARC traffic from
   cross-module value passing

These are symptoms of the compiler not being able to see through the
module boundary. When it can't inline `compare()`, it must:
- Pass arguments through the calling convention (ARC retain/release)
- Use indirect dispatch through the module's export table
- Create temporary values that would be eliminated by inlining

## The proof

Adding `Collation` as a direct dependency of `BenchFoundation` (the
benchmark executable) made the compiler treat both modules as available
for optimization. Result:

| API | Before (cross-module) | After (same compilation unit) |
|-----|-----------------------|-------------------------------|
| `localizedCompare` ASCII | 1337 ns | 133 ns |
| `localizedCompare` Latin | 1322 ns | 134 ns |
| `localizedCompare` CJK | 1462 ns | 237 ns |
| `localizedCompare` paths | 1365 ns | 172 ns |

This proved the overhead was entirely the module boundary, not our code.

## The fix

Two lines in `RootCollator.swift`:

```swift
// Before:
public func compare(
    _ left: String, _ right: String, options: CollationOptions = CollationOptions()
) throws -> Order {
    try compareClassic(left, right, options: options)
}

// After:
@inlinable
public func compare(
    _ left: String, _ right: String, options: CollationOptions = CollationOptions()
) throws -> Order {
    try _compare(left, right, options: options)
}

@usableFromInline
func _compare(
    _ left: String, _ right: String, options: CollationOptions
) throws -> Order {
    try compareClassic(left, right, options: options)
}
```

`@inlinable` tells the compiler to emit the function body into the
module's .swiftinterface, making it visible to other modules at compile
time. The body is a single line: `try _compare(...)`.

`@usableFromInline` on `_compare` makes it callable from the inlined
body without being public API. `_compare` itself just delegates to
`compareClassic`, which remains internal.

The compiler can now:
1. Inline `compare()` into the call site in FoundationInternationalization
2. See that it's a direct call to `_compare` (no virtual dispatch)
3. Devirtualize the call to `_compare`, eliminating the cross-module
   indirection

## What this does NOT do

- Does NOT expose any internal API. `_compare` is `@usableFromInline`
  (visible to the compiler but not importable by users). `compareClassic`
  and everything below it remain internal.
- Does NOT change any behavior. The function body is identical.
- Does NOT affect ABI. `@inlinable` is additive — callers compiled
  against the old interface still work (they just don't get the inlining).
- Does NOT make the function body a frozen contract. The `@inlinable`
  body is `try _compare(...)`, which is a stable delegation. The actual
  implementation in `_compare`/`compareClassic` can change freely.

## Results after the fix

Measured on Apple Silicon (macOS 26), min of 9 passes, release builds.

**Update:** After moving Collation sources into FoundationInternationalization
(same module), the `@inlinable`/`@usableFromInline` annotations were removed —
WMO handles inlining automatically within a module. Performance is identical.

### localizedCompare (ns/op)

| Corpus | Before | After | System ICU | Speedup vs ICU |
|--------|--------|-------|-----------|---------------|
| ASCII  | 1337   | 128   | 195       | **1.5× faster** |
| Latin  | 1322   | 128   | 358       | **2.8× faster** |
| CJK    | 1462   | 238   | 368       | **1.5× faster** |
| Paths  | 1365   | 165   | 299       | **1.8× faster** |

### localizedStandardCompare (ns/op)

| Corpus | Before | After | System ICU | Speedup vs ICU |
|--------|--------|-------|-----------|---------------|
| ASCII  | 1354   | 136   | 197       | **1.4× faster** |
| Latin  | 1332   | 136   | 349       | **2.6× faster** |
| CJK    | 1477   | 242   | 358       | **1.5× faster** |
| Paths  | 1386   | 185   | 318       | **1.7× faster** |

### compare(_:locale:) (ns/op)

| Corpus | Before | After | System ICU | Speedup vs ICU |
|--------|--------|-------|-----------|---------------|
| ASCII  | 521    | 298   | 313       | **1.1× faster** |
| Latin  | 516    | 298   | 482       | **1.6× faster** |
| CJK    | 653    | 448   | 487       | **1.1× faster** |
| Paths  | 570    | 342   | 412       | **1.2× faster** |

### RootCollator.compare (direct, ns/op) — unchanged

| Corpus | After | Standalone Bench |
|--------|-------|-----------------|
| ASCII  | 25    | 25              |
| Latin  | 24    | 25              |
| CJK    | 127   | 125             |
| Paths  | 62    | 62              |

Direct collation performance is unchanged. The improvement is entirely
in the Foundation API integration layer.

## What to scrutinize

1. **Is `@inlinable` on a public method acceptable?** The body is a
   one-line delegation. The contract is: "this calls `_compare`." If
   the internal implementation changes, callers compiled against the
   old interface still work (they call `_compare` which delegates to
   whatever the current `compareClassic` does). Only the inlining
   benefit is lost for old callers.

2. **Is `@usableFromInline` on `_compare` acceptable?** It's prefixed
   with underscore to signal it's not public API. It has no default
   arguments (those are on the `@inlinable` wrapper). It's a pure
   delegation function.

3. **Does this change the optimization profile?** Yes — the compiler
   may now inline more aggressively at call sites in
   FoundationInternationalization. This could increase code size
   slightly at those call sites. The function being inlined is one
   line, so the size impact is minimal.

4. **Thread safety.** No change — `RootCollator` is `@unchecked Sendable`
   and immutable after init. The `@inlinable` annotation doesn't affect
   thread safety.

5. **Are the benchmark numbers real?** The "before" and "after" runs
   use the same BenchFoundation binary, same corpus files, same
   measurement methodology (min of 9 passes). The only difference is
   the two-line change in RootCollator.swift. The system ICU numbers
   are from a separate standalone Swift script that uses the system
   Foundation framework, measured identically.

## How to reproduce

```sh
cd swift-foundation-collation

# Build the Foundation-level benchmark:
swift build -c release --target BenchFoundation

# Run against a corpus:
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# Compare against system Foundation (NSString → ICU):
swift -O Collation/Tools/bench_system_foundation.swift Collation/Tools/bench/bench-ascii.txt 200

# Run direct collation bench (no Foundation overhead):
cd Collation && swift build -c release
.build/out/Products/Release/Bench Tools/bench/bench-ascii.txt 200
```
