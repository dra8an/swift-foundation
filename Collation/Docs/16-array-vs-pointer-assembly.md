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
