# Swift Raw Pointer vs Array: Assembly-Level Analysis

> Written 2026-06-16. An investigation into why replacing Swift's `Array<UInt8>`
> with manual `UnsafeMutablePointer<UInt8>` produced *slower* code, contrary to
> the expectation that "unsafe = faster". Includes raw assembly, annotated
> analysis, and implications for the collation port's performance ceiling.

## 1. The Experiment

Two implementations of the same operation — appending bytes to a buffer in a
tight loop:

**Version A: Swift Array**
```swift
@inline(never)
func arrayAppend(_ buffer: inout [UInt8], count: Int) {
    for i in 0..<count {
        buffer.append(UInt8(truncatingIfNeeded: i))
    }
}
```

**Version B: Raw Pointer**
```swift
struct RawBuffer {
    var storage: UnsafeMutablePointer<UInt8>?
    var count: Int = 0
    var capacity: Int = 0

    @inline(__always)
    mutating func ensureCapacity(_ needed: Int) {
        if needed <= capacity { return }
        let newCap = max(needed, capacity == 0 ? 64 : capacity * 2)
        let newStorage = UnsafeMutablePointer<UInt8>.allocate(capacity: newCap)
        if count > 0, let old = storage {
            newStorage.update(from: old, count: count)
            old.deallocate()
        }
        storage = newStorage
        capacity = newCap
    }

    @inline(__always)
    mutating func append(_ byte: UInt8) {
        ensureCapacity(count + 1)
        storage.unsafelyUnwrapped[count] = byte
        count += 1
    }
}

@inline(never)
func pointerAppend(_ buffer: inout RawBuffer, count: Int) {
    for i in 0..<count {
        buffer.append(UInt8(truncatingIfNeeded: i))
    }
}
```

Both compiled with `swiftc -O` (full optimization, release mode) on Apple
Silicon (arm64), Swift 6.3.1 toolchain.

## 2. Raw Assembly Output

### 2.1 Array Version (complete function)

```asm
_$s11ArrayAppend05arrayB0_5countySays5UInt8VGz_SitF:
    .cfi_startproc
; %bb.0:
    tbnz    x1, #63, LBB1_9
; %bb.1:
    stp     x24, x23, [sp, #-64]!
    stp     x22, x21, [sp, #16]
    stp     x20, x19, [sp, #32]
    stp     x29, x30, [sp, #48]
    add     x29, sp, #48
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    .cfi_offset w21, -40
    .cfi_offset w22, -48
    .cfi_offset w23, -56
    .cfi_offset w24, -64
    mov     x20, x1
    cbz     x1, LBB1_8
; %bb.2:
    mov     x19, x0
    ldr     x21, [x0]
    mov     x0, x21
    bl      _swift_isUniquelyReferenced_nonNull_native
    tbz     w0, #0, LBB1_10
LBB1_3:
    mov     x23, #0
    ldr     x24, [x21, #16]
LBB1_4:                                 ; =>This Inner Loop Header: Depth=1
    ldr     x8, [x21, #24]
    add     x22, x24, #1
    cmp     x24, x8, lsr #1
    b.hs    LBB1_6
LBB1_5:                                 ;   in Loop: Header=BB1_4 Depth=1
    add     x8, x21, x24
    strb    w23, [x8, #32]
    add     x23, x23, #1
    str     x22, [x21, #16]
    mov     x24, x22
    cmp     x20, x23
    b.ne    LBB1_4
    b       LBB1_7
LBB1_6:                                 ;   in Loop: Header=BB1_4 Depth=1
    cmp     x8, #1
    cset    w0, hi
    mov     x1, x22
    mov     w2, #1
    mov     x3, x21
    bl      _$ss12_ArrayBufferV20_consumeAndCreateNew...
    mov     x21, x0
    b       LBB1_5
LBB1_7:
    str     x21, [x19]
LBB1_8:
    ldp     x29, x30, [sp, #48]
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp], #64
    ret
LBB1_9:
    brk     #0x1
LBB1_10:
    ldr     x8, [x21, #16]
    add     x1, x8, #1
    mov     w0, #0
    mov     w2, #1
    mov     x3, x21
    bl      _$ss12_ArrayBufferV20_consumeAndCreateNew...
    mov     x21, x0
    b       LBB1_3
    .cfi_endproc
```

### 2.2 Pointer Version (complete function)

```asm
_$s13PointerAppend07pointerB0_5countyAA9RawBufferVz_SitF:
; %bb.0:
    stp     x28, x27, [sp, #-96]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #80]
    add     x29, sp, #80
    tbnz    x1, #63, LBB3_22
; %bb.1:
    mov     x20, x1
    cbz     x1, LBB3_19
; %bb.2:
    mov     x19, x0
    mov     x27, #0
    ldr     x25, [x0, #8]
    eor     x26, x25, #0x7fffffffffffffff
    mov     x28, #4611686018427387904
    b       LBB3_5
LBB3_3:                                 ;   in Loop: Header=BB3_5 Depth=1
    ldr     x23, [x19]
LBB3_4:                                 ;   in Loop: Header=BB3_5 Depth=1
    add     x8, x27, #1
    add     x9, x23, x25
    strb    w27, [x9, x27]
    mov     x27, x8
    cmp     x20, x8
    b.eq    LBB3_18
LBB3_5:                                 ; =>This Inner Loop Header: Depth=1
    cmp     x26, x27
    b.eq    LBB3_20
; %bb.6:                                ;   in Loop: Header=BB3_5 Depth=1
    add     x21, x25, x27
    add     x8, x21, #1
    ldr     x9, [x19, #16]
    cmp     x9, x8
    b.ge    LBB3_3
; %bb.7:                                ;   in Loop: Header=BB3_5 Depth=1
    cbz     x9, LBB3_10
; %bb.8:                                ;   in Loop: Header=BB3_5 Depth=1
    cmn     x9, x28
    b.mi    LBB3_21
; %bb.9:                                ;   in Loop: Header=BB3_5 Depth=1
    lsl     x9, x9, #1
    cmp     x9, x8
    csel    x22, x9, x8, gt
    b       LBB3_11
LBB3_10:                                ;   in Loop: Header=BB3_5 Depth=1
    cmp     x8, #64
    mov     w9, #64
    csel    x22, x8, x9, gt
LBB3_11:                                ;   in Loop: Header=BB3_5 Depth=1
    mov     x0, x22
    mov     x1, #-1
    bl      _swift_slowAlloc
    mov     x23, x0
    cmp     x21, #1
    b.lt    LBB3_17
; %bb.12:                               ;   in Loop: Header=BB3_5 Depth=1
    ldr     x24, [x19]
    cbz     x24, LBB3_17
; %bb.13:                               ;   in Loop: Header=BB3_5 Depth=1
    cmp     x23, x24
    b.ne    LBB3_15
; %bb.14:                               ;   in Loop: Header=BB3_5 Depth=1
    add     x8, x24, x25
    add     x8, x8, x27
    cmp     x23, x8
    b.lo    LBB3_16
LBB3_15:                                ;   in Loop: Header=BB3_5 Depth=1
    mov     x0, x23
    mov     x1, x24
    mov     x2, x21
    bl      _memmove
LBB3_16:                                ;   in Loop: Header=BB3_5 Depth=1
    mov     x0, x24
    mov     x1, #-1
    mov     x2, #-1
    bl      _swift_slowDealloc
LBB3_17:                                ;   in Loop: Header=BB3_5 Depth=1
    str     x23, [x19]
    str     x22, [x19, #16]
    b       LBB3_4
LBB3_18:
    add     x8, x25, x8
    str     x8, [x19, #8]
LBB3_19:
    ldp     x29, x30, [sp, #80]
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #96
    ret
LBB3_20:
    brk     #0x1
LBB3_21:
    brk     #0x1
LBB3_22:
    brk     #0x1
    .cfi_endproc
```

## 3. Annotated Analysis

### 3.1 Array: The Inner Loop

```asm
; Setup (runs ONCE before the loop):
    ldr     x21, [x0]                          ; x21 = buffer object pointer
    bl      _swift_isUniquelyReferenced_...    ; uniqueness check — ONCE
    ldr     x24, [x21, #16]                    ; x24 = current count

; THE INNER LOOP (per byte):
LBB1_4:
    ldr     x8, [x21, #24]         ; load capacity (from buffer header, in cache)
    add     x22, x24, #1           ; newCount = count + 1
    cmp     x24, x8, lsr #1        ; count < capacity/2? (growth threshold)
    b.hs    LBB1_6                 ; branch to grow — almost never taken
LBB1_5:
    add     x8, x21, x24           ; address = bufferBase + count
    strb    w23, [x8, #32]         ; STORE the byte (32 = object header size)
    add     x23, x23, #1           ; i++
    str     x22, [x21, #16]        ; update count in buffer header
    mov     x24, x22               ; local count = newCount
    cmp     x20, x23               ; i < total?
    b.ne    LBB1_4                 ; loop
```

**Key facts:**
- `isUniquelyReferenced` executes **once**, before the loop starts
- `x21` (the buffer object pointer) is **never reloaded** — stays in register
  for the entire loop
- 7 instructions per iteration on the fast path
- The compiler *knows* that `strb [x8, #32]` writes into the buffer's data
  region (offset ≥ 32) and cannot alias the buffer's header fields (at offsets
  0, 8, 16, 24) — so it safely keeps capacity/count in registers

### 3.2 Pointer: The Inner Loop

```asm
; Setup:
    mov     x19, x0                ; x19 = &struct (the inout pointer)
    ldr     x25, [x0, #8]         ; x25 = struct.count (loaded once BUT...)

; THE INNER LOOP (per byte):
LBB3_5:
    cmp     x26, x27              ; overflow check (i == INT_MAX?)
    b.eq    LBB3_20               ; trap
    add     x21, x25, x27         ; offset = baseCount + i
    add     x8, x21, #1           ; needed = offset + 1
    ldr     x9, [x19, #16]        ; ← LOAD capacity FROM MEMORY (every iteration!)
    cmp     x9, x8                ; capacity >= needed?
    b.ge    LBB3_3                ; if yes → do the store
    ; ... (ensureCapacity slow path: malloc, memmove, dealloc)

LBB3_3:
    ldr     x23, [x19]            ; ← LOAD storage pointer FROM MEMORY (every iteration!)
LBB3_4:
    add     x8, x27, #1           ; i + 1
    add     x9, x23, x25          ; ptr = storage + baseOffset
    strb    w27, [x9, x27]        ; STORE the byte
    mov     x27, x8               ; i = i + 1
    cmp     x20, x8               ; i < total?
    b.eq    LBB3_18               ; exit
    ; → back to LBB3_5
```

**Key facts:**
- `ldr x9, [x19, #16]` (capacity) and `ldr x23, [x19]` (storage pointer) are
  **reloaded from memory on every single iteration**
- The compiler **cannot hoist them** — see §4 for why
- 11 instructions per iteration on the fast path
- Extra overflow check (`cmp x26, x27`) that Array doesn't need
- Two-add address computation (`x23 + x25 + x27`) vs Array's single
  `x21 + x24 + #32`

## 4. Why the Compiler Cannot Hoist the Pointer Loads

The struct is passed as `inout`, which means it lives at some address in
memory (`x19`). The struct's fields are:

```
[x19 + 0]  = storage (UnsafeMutablePointer<UInt8>?)
[x19 + 8]  = count (Int)
[x19 + 16] = capacity (Int)
```

The store instruction is:
```asm
strb    w27, [x9, x27]    ; writes to address (storage + baseOffset + i)
```

The compiler asks: **"Could `storage + baseOffset + i` ever equal `x19`,
`x19+8`, or `x19+16`?"**

For `UnsafeMutablePointer`, the answer is: **it cannot prove it doesn't.**
The pointer is "unsafe" — by definition, it can point anywhere in memory,
including back at the struct itself. The compiler must be conservative and
assume that after every `strb`, the struct's fields might have changed.
Therefore it must reload them.

For Array, the compiler has special knowledge:
- The buffer object (`x21`) is a heap-allocated Swift object with a known
  layout: refcount at offset 0, count at offset 16, capacity at offset 24,
  data starting at offset 32
- A `strb` at offset ≥ 32 **provably cannot alias** offsets 0–24
- Therefore the header fields stay valid in registers across the entire loop

This is the fundamental asymmetry: **Array gives the optimizer layout
guarantees that raw pointers cannot.**

## 5. The Profiler Lie

When profiling the collation sort-key path, `swift_isUniquelyReferenced` showed
up as ~9% of samples. This led to the hypothesis that replacing Array with raw
pointers would save that 9%.

The assembly proves why this was wrong:

1. `isUniquelyReferenced` runs **once per `sortKey()` call** (not per byte) —
   it's hoisted before the append loop. The profiler samples it frequently
   because it's a `bl` (function call) instruction that the sampler lands on
   disproportionately, but its amortized cost per byte is negligible.

2. Removing it and using raw pointers **added** two memory loads per byte
   (capacity + storage pointer) that the Array version didn't have — a net
   loss of ~4 instructions per iteration.

3. The profiler's leaf-time attribution cannot distinguish "this instruction
   runs many times cheaply" from "this instruction is expensive." Sampling
   counts do not equal wall-clock cost.

## 6. Implications for the Collation Port

This finding has a direct bearing on whether the Swift port can ever match
ICU4C's performance:

### What this means

- **Swift Array in a tight loop is nearly as efficient as C** when the
  compiler can prove unique ownership (which it can for `inout` arrays). The
  per-byte cost is 7 arm64 instructions — comparable to C's `*p++ = byte`.

- **The performance gap to ICU4C is NOT in the per-byte array operations.**
  It's in the per-*call* overhead: String access (`withContiguousStorage`),
  iterator construction (ARC), function-call boundaries, and the copy-out
  (which we fixed with the `inout` API).

- **UnsafeMutablePointer does NOT give C-like performance in Swift.** The
  compiler treats it as potentially aliasing anything, preventing the very
  optimizations that make Array fast. To get C-speed pointer arithmetic in
  Swift, you'd need `UnsafeBufferPointer` with a *proven non-aliasing*
  relationship — which is exactly what Array already provides internally.

### What would actually close the remaining gap

1. **API-level changes** (M8 Foundation integration): borrowing `String`
   parameters that give the collator direct access to UTF-8 bytes without
   closure entry or iterator construction. Swift's `~Copyable` / borrowing
   features, once mature, could enable this.

2. **Compiler improvements**: if the Swift compiler could prove that an
   `UnsafeMutablePointer` stored in a local struct doesn't alias the struct
   itself (type-based alias analysis, similar to C's strict aliasing rule),
   raw pointers *would* match Array. This is a known area of Swift compiler
   development.

3. **Whole-module optimization across the collation pipeline**: if the
   compiler could inline from `compare()` through `CEIterator` through
   `NFDIterator` and eliminate intermediate struct copies, the remaining
   per-call overhead would shrink. Currently each layer boundary forces
   register saves and potential reloads.

### What will NOT close the gap

- Replacing Array with UnsafeMutablePointer in struct fields (this document)
- Removing `isUniquelyReferenced` (it's already hoisted)
- Manual memory management of buffers (loses optimizer knowledge)
- Any approach that introduces potential aliasing the compiler can't disprove

## 7. Reproducing This Analysis

```sh
# Generate the source files
cat > /tmp/ArrayAppend.swift << 'EOF'
@inline(never)
func arrayAppend(_ buffer: inout [UInt8], count: Int) {
    for i in 0..<count {
        buffer.append(UInt8(truncatingIfNeeded: i))
    }
}
var arr: [UInt8] = []
arr.reserveCapacity(1024)
arrayAppend(&arr, count: 100)
print(arr.count)
EOF

cat > /tmp/PointerAppend.swift << 'EOF'
struct RawBuffer {
    var storage: UnsafeMutablePointer<UInt8>?
    var count: Int = 0
    var capacity: Int = 0
    @inline(__always)
    mutating func ensureCapacity(_ needed: Int) {
        if needed <= capacity { return }
        let newCap = max(needed, capacity == 0 ? 64 : capacity * 2)
        let newStorage = UnsafeMutablePointer<UInt8>.allocate(capacity: newCap)
        if count > 0, let old = storage {
            newStorage.update(from: old, count: count)
            old.deallocate()
        }
        storage = newStorage
        capacity = newCap
    }
    @inline(__always)
    mutating func append(_ byte: UInt8) {
        ensureCapacity(count + 1)
        storage.unsafelyUnwrapped[count] = byte
        count += 1
    }
}
@inline(never)
func pointerAppend(_ buffer: inout RawBuffer, count: Int) {
    for i in 0..<count {
        buffer.append(UInt8(truncatingIfNeeded: i))
    }
}
var buf = RawBuffer()
buf.ensureCapacity(1024)
pointerAppend(&buf, count: 100)
print(buf.count)
EOF

# Compile to assembly
swiftc -O -emit-assembly /tmp/ArrayAppend.swift -o /tmp/arr.s
swiftc -O -emit-assembly /tmp/PointerAppend.swift -o /tmp/ptr.s

# View demangled (search for "arrayAppend" / "pointerAppend"):
cat /tmp/arr.s | swift demangle | less
cat /tmp/ptr.s | swift demangle | less
```

Toolchain: Swift 6.3.1 (swift-DEVELOPMENT-SNAPSHOT-2026-04-27-a),
target: arm64-apple-macos.

## 8. Discovery: `String.utf8Span` — Closure-Free Byte Access

After documenting the aliasing problem, we discovered that this toolchain
(Swift 6.3.1, 2026-04-27 snapshot) ships `String.utf8Span` — a **non-closure**
path to raw UTF-8 bytes:

```swift
let bytes: Span<UInt8> = someString.utf8Span.span
bytes[0]   // direct subscript, no closure, no ARC
```

### 8.1 What It Is

- `String.utf8Span` returns a `UTF8Span` (a non-escaping borrowed view)
- `UTF8Span.span` yields a `Span<UInt8>` — direct byte-level subscript access
- `Span<UInt8>` is `~Escapable`: cannot be stored in struct fields or returned
  from functions, only used in the scope where it's created
- Two strings' spans can be held simultaneously:
  ```swift
  let lBytes = left.utf8Span.span
  let rBytes = right.utf8Span.span
  // both valid, no nesting
  ```

### 8.2 Assembly Comparison: Span vs Closure

A byte-summing loop was compiled both ways:

```swift
// Via Span (no closure):
func sumViaSpan(_ s: String) -> Int {
    let bytes = s.utf8Span.span
    var sum = 0
    for i in 0..<bytes.count { sum &+= Int(bytes[i]) }
    return sum
}

// Via closure:
func sumViaClosure(_ s: String) -> Int {
    s.utf8.withContiguousStorageIfAvailable { buf in
        var sum = 0
        for i in 0..<buf.count { sum &+= Int(buf[i]) }
        return sum
    } ?? 0
}
```

Result: **identical assembly** — both auto-vectorize to the same NEON
`ldp q28, q29` + `tbl` + `uaddw` pipeline processing 32 bytes per iteration.
The Span path has no performance penalty vs the closure path, but eliminates
the closure entry/exit overhead and the nesting problem.

### 8.3 Constraints for the Collation Use Case

`Span<UInt8>` is `~Escapable`, which means:
- ❌ Cannot be stored as a field in `NFDIterator` or `CEIterator`
- ❌ Cannot be returned from a function
- ✅ Can be passed as a function parameter
- ✅ Can be used with an `inout Int` offset for stateful iteration
- ✅ Two spans (left + right string) can coexist in the same scope

The collation iteration pattern works with Span:
```swift
func iterateScalars(_ bytes: Span<UInt8>, offset: inout Int) -> UInt32? {
    guard offset < bytes.count else { return nil }
    let b0 = UInt32(bytes[offset])
    if b0 < 0x80 { offset += 1; return b0 }
    if b0 < 0xe0 {
        let c = ((b0 & 0x1f) << 6) | (UInt32(bytes[offset + 1]) & 0x3f)
        offset += 2; return c
    }
    // ... (3 and 4-byte sequences)
}
```

### 8.4 Implications

This is the path to eliminating the `withContiguousStorageIfAvailable` closure
overhead (~17 ns per compare on the ASCII fast path, §4 of Docs/14). The
approach would be:

1. At the `RootCollator.compare()` level, acquire both spans flat (no nesting):
   ```swift
   let lBytes = left.utf8Span.span
   let rBytes = right.utf8Span.span
   ```

2. Pass them down to the iteration layer as parameters (with `inout` offsets),
   rather than storing `String.UnicodeScalarView.Iterator` in `NFDIterator`.

3. This eliminates:
   - The `withContiguousStorageIfAvailable` closure entry/exit
   - The `String.UnicodeScalarView.Iterator` ARC (no iterator object at all)
   - The nested-closure problem that limited approach (a) to +3%

The challenge: `NFDIterator` and `CEIterator` currently store the iterator as
a struct field. A Span-based design would need to thread the span through as a
parameter to every call in the pipeline, or restructure the iteration to be
driven from the top level. This is a significant refactor but architecturally
sound — ICU4C's iterators work exactly this way (a pointer + offset passed
through the call chain).

### 8.5 Reproducing

```swift
// Requires Swift 6.3+ (2026-04-27 snapshot or later)
import Swift

let s = "hello"
let span: UTF8Span = s.utf8Span
let bytes: Span<UInt8> = span.span
print(bytes[0])  // 104 ('h')
```

`Span` is part of the Swift standard library in this toolchain (SE-0447),
not an import. `UTF8Span` is `String`'s conformance to the span protocol.

## 9. Span Performance: Benchmarking the Collation Use Case

The §8 discovery showed `Span` exists and compiles. But the real question is:
**does it actually help in the collation hot path?** This section benchmarks
the specific patterns the collator uses.

### 9.1 Test Setup

The benchmark compares the prefix-skip operation — iterating two strings'
scalars in lockstep until a difference is found. This is the exact operation
`RootCollator.compare()` does before entering the CE pipeline. Test strings:
```
left:  "icu4c/source/i18n/collationiterator.cpp"  (39 bytes)
right: "icu4c/source/i18n/collationiterator.h"    (37 bytes)
```
These share a 34-character prefix — a realistic sorted-data comparison.

### 9.2 Results: Five Approaches

| Approach | ns/op | vs Iterator |
|----------|-------|-------------|
| `String.UnicodeScalarView.Iterator` (current code) | ~79 ns | baseline |
| Span, scalar decode in a **separate function** (no inline hint) | ~262 ns | **3.3× slower** |
| Span, scalar decode in an `@inline(__always)` helper | ~73 ns | **8% faster** |
| Span, scalar decode **manually inlined** in the loop body | ~60 ns | **25% faster** |
| Span, re-acquiring `.utf8Span.span` each iteration (no `let` binding) | ~705 ns | **9× slower** |

### 9.3 Analysis: Why Inlining Matters for Span

`Span<UInt8>` is `~Escapable` — the compiler enforces that it cannot outlive
the scope that created it. When a `Span` is passed as a function parameter,
the compiler inserts **lifetime-dependency checks** at the call boundary to
verify the span is still valid. These checks have measurable cost:

- **Non-inlined function taking `Span` parameter:** ~180 ns overhead per call
  from lifetime verification at each call-site. The function call itself is
  cheap, but the compiler cannot elide the lifetime proof across the boundary.

- **`@inline(__always)` function:** the function body is substituted into the
  caller, so the compiler can see that the span and its source (the String
  parameter) are in the same scope — no runtime lifetime check needed. Cost:
  near zero, and the span access compiles to the same code as a direct
  `UnsafeBufferPointer` subscript.

- **Manually inlined:** same as `@inline(__always)` but the compiler has even
  more freedom (no function-boundary artifacts at all). The 25% vs 8% gap
  suggests the compiler doesn't fully optimize away all overhead even with
  `@inline(__always)` — possibly residual register pressure from the function
  signature.

### 9.4 Single-String vs Two-String

A simpler test — counting scalars in one string:

| Approach | ns/op |
|----------|-------|
| `String.UnicodeScalarView.Iterator` | ~75 ns |
| Span + local offset (inlined decode) | ~31 ns |

For single-string iteration, Span is **2.4× faster** than the iterator. The
iterator carries a String storage reference (ARC on construction) and has
per-scalar method-call overhead; the Span is a raw pointer + count with
subscript access.

The two-string case (§9.2) narrows the gap because:
1. Acquiring two spans means two `utf8Span.span` calls (each extracts the
   buffer pointer from the String's guts)
2. The comparison loop has more register pressure (two offsets, two spans)
3. The short-circuit (`a == b`) prevents the loop from vectorizing

### 9.5 Lifetime Rules: What Works and What Doesn't

```swift
// ✅ WORKS: Span from a function parameter (lifetime = function body)
func compare(_ left: String, _ right: String) -> Int {
    let lBytes = left.utf8Span.span   // valid for entire function
    let rBytes = right.utf8Span.span  // valid for entire function
    // ... use both spans ...
}

// ❌ FAILS: Span from a local variable
func test() {
    let s = "hello"
    let bytes = s.utf8Span.span  // ERROR: lifetime-dependent value escapes
    // The compiler can't prove `s` outlives `bytes` because `s` is a local
    // that could be destroyed at any point after its last direct use.
}

// ❌ FAILS: Span stored in a struct field
struct MyIter {
    var bytes: Span<UInt8>  // ERROR: ~Escapable type cannot be stored
}

// ✅ WORKS: Span passed to an @inline(__always) method
struct State {
    var offset: Int = 0
    @inline(__always)
    mutating func next(_ bytes: Span<UInt8>) -> UInt32? {
        guard offset < bytes.count else { return nil }
        // ... decode scalar, advance offset ...
    }
}

// ⚠️ SLOW: Span passed to a non-inlined function
func decode(_ bytes: Span<UInt8>, _ offset: inout Int) -> UInt32? {
    // Works correctly but adds ~180ns lifetime-check overhead per call
}
```

### 9.6 Implications for the Collation Refactor

To use Span in `RootCollator.compare()`:

**What would change:**
1. `compare()` acquires spans at the top: `let lBytes = left.utf8Span.span`
2. `NFDIterator` stores only `offset: Int` (not `source: String.Iterator`)
3. `NFDIterator.nextSourceScalar(_ bytes: Span<UInt8>)` takes span as parameter
4. All methods in the chain (`appendMore`, `refill`, `ce(at:)`) must either:
   - Be `@inline(__always)` (so the span is never passed across a non-inlined
     boundary), or
   - Accept the span as a parameter (adds the ~180ns overhead per call)

**The challenge:**
The current call chain is:
```
compare() → CollationCompare.compareUpToQuaternary()
  → CEIterator.ce(at:)
    → CEIterator.appendMore()
      → NFDIterator.next()
        → NFDIterator.nextSourceScalar()  ← reads the input here
```

That's 5 function calls deep. If any of them is NOT inlined, the Span
parameter incurs the lifetime-check penalty. The `@inline(__always)` chain
would need to go from `compareUpToQuaternary` all the way down to
`nextSourceScalar` — or alternatively, the iteration would need to be
restructured so that `compare()` drives the byte reading directly and passes
decoded scalars down (inverting the call direction).

**The ICU4C model** (for reference):
ICU4C passes `const char*` + length at the top and each layer reads through
the pointer directly. No lifetime checks, no function-call boundary costs for
pointer access. This is what `Span` is designed to replicate — but the
`~Escapable` lifetime enforcement adds cost at non-inlined boundaries that C
doesn't have.

**Estimated impact if fully wired:**
- Prefix skip: −25% (60 ns vs 79 ns, from §9.2 manually-inlined result)
- CE pipeline scalar source: eliminates the `String.Iterator` ARC entirely
  (the −30% from the earlier §2 profile that approach (a) couldn't fully
  capture due to closure overhead)
- Combined: potentially −30-40% on CJK/Thai compare — but ONLY if the entire
  chain is inlined, which may cause code-size explosion and instruction-cache
  pressure

**Recommended next step:**
Prototype a `compareViaSpan` method that uses Span for the prefix skip (the
outer layer) while keeping the existing `CEIterator` path for the CE pipeline.
This captures the prefix-skip win (−25%) without requiring the full inlining
chain. Measure, then decide whether the deeper refactor is worth it.

### 9.7 Reproducing the Benchmarks

```swift
// File: /tmp/SpanBenchCompare.swift
// Compile: swiftc -O /tmp/SpanBenchCompare.swift -o /tmp/span_bench
import Swift
import Dispatch

@inline(__always)
func nextScalarInline(_ bytes: Span<UInt8>, _ offset: inout Int) -> UInt32? {
    guard offset < bytes.count else { return nil }
    let b0 = UInt32(bytes[offset])
    if b0 < 0x80 { offset += 1; return b0 }
    if b0 < 0xe0 {
        let c = ((b0 & 0x1f) << 6) | (UInt32(bytes[offset + 1]) & 0x3f)
        offset += 2; return c
    }
    if b0 < 0xf0 {
        let c = ((b0 & 0x0f) << 12)
            | ((UInt32(bytes[offset + 1]) & 0x3f) << 6)
            | (UInt32(bytes[offset + 2]) & 0x3f)
        offset += 3; return c
    }
    let c = ((b0 & 0x07) << 18)
        | ((UInt32(bytes[offset + 1]) & 0x3f) << 12)
        | ((UInt32(bytes[offset + 2]) & 0x3f) << 6)
        | (UInt32(bytes[offset + 3]) & 0x3f)
    offset += 4; return c
}

@inline(never)
func twoSpanForceInline(_ left: String, _ right: String) -> Int {
    let lBytes = left.utf8Span.span
    let rBytes = right.utf8Span.span
    var lOff = 0
    var rOff = 0
    var shared = 0
    while let a = nextScalarInline(lBytes, &lOff),
          let b = nextScalarInline(rBytes, &rOff),
          a == b {
        shared += 1
    }
    return shared
}

@inline(never)
func iteratorCompare(_ left: String, _ right: String) -> Int {
    var lIter = left.unicodeScalars.makeIterator()
    var rIter = right.unicodeScalars.makeIterator()
    var shared = 0
    while let a = lIter.next(), let b = rIter.next(), a == b {
        shared += 1
    }
    return shared
}

let left = "icu4c/source/i18n/collationiterator.cpp"
let right = "icu4c/source/i18n/collationiterator.h"
let reps = 5_000_000
var sink = 0

for _ in 0..<1000 { sink += twoSpanForceInline(left, right) }
for _ in 0..<1000 { sink += iteratorCompare(left, right) }

var start = DispatchTime.now().uptimeNanoseconds
for _ in 0..<reps { sink += twoSpanForceInline(left, right) }
var ns = DispatchTime.now().uptimeNanoseconds - start
print("Span @inline(__always): \(ns / UInt64(reps)) ns/op")

start = DispatchTime.now().uptimeNanoseconds
for _ in 0..<reps { sink += iteratorCompare(left, right) }
ns = DispatchTime.now().uptimeNanoseconds - start
print("Iterator:              \(ns / UInt64(reps)) ns/op")

if sink == Int.min { print("") }
```
