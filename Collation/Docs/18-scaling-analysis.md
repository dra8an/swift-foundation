# Performance Scaling Analysis: Per-Call Overhead vs Per-Character Cost

> Written 2026-06-18. Investigates the hypothesis that the performance gap
> to ICU narrows with longer strings (suggesting a fixed per-call setup cost),
> and that the NFD decomposition strategy costs differently depending on
> character composition.

## 1. Hypothesis

Two theories from cross-machine discussion:

1. **The gap closes with longer words** — suggesting a fixed per-call overhead
   in our setup phase (String access, iterator construction, thread-local
   checkout, fast-Latin cache lock) that gets amortized over more characters.

2. **Our fused-NFD strategy costs more for accented text** — because we
   decompose on the fly for every character, while ICU's FCD approach only
   normalizes when it detects non-FCD segments.

## 2. Experimental Design

Generated sorted corpora with shared prefixes of varying lengths:
- **Sorted ASCII**: strings share (length−2) prefix, differ on last 2 chars
- **Sorted CJK**: strings share (length−1) prefix, differ on last char
- **Sorted accented**: strings share (length−2) prefix with accented chars,
  differ on last 2

Sorted data forces the comparison to scan the full shared prefix before
finding the difference — this exercises the per-character cost, not just
the per-call setup. Adjacent pairs in sorted order are "minimal pairs"
that resolve late.

## 3. Results (Apple Silicon, 5000 reps)

### ASCII (sorted, shared prefix)

| length | ours (ns) | ICU (ns) | ratio | Δ ours/char | Δ ICU/char |
|--------|-----------|----------|-------|-------------|------------|
| 4      | 55        | 17       | 3.2×  | —           | —          |
| 8      | 57        | 18       | 3.2×  | 0.5         | 0.25       |
| 16     | 62        | 21       | 3.0×  | 0.6         | 0.4        |
| 32     | 67        | 25       | 2.7×  | 0.3         | 0.25       |
| 64     | 77        | 36       | 2.1×  | 0.3         | 0.3        |

### CJK (sorted, shared prefix)

| length | ours (ns) | ICU (ns) | ratio | Δ ours/char | Δ ICU/char |
|--------|-----------|----------|-------|-------------|------------|
| 4      | 198       | 60       | 3.3×  | —           | —          |
| 8      | 229       | 62       | 3.7×  | 7.8         | 0.5        |
| 16     | 268       | 70       | 3.8×  | 4.9         | 1.0        |
| 32     | 327       | 88       | 3.7×  | 3.7         | 1.1        |

### Accented (sorted, shared prefix, needs NFD decomposition)

| length | ours (ns) | ICU (ns) | ratio | Δ ours/char | Δ ICU/char |
|--------|-----------|----------|-------|-------------|------------|
| 4      | 67        | 24       | 2.8×  | —           | —          |
| 8      | 71        | 28       | 2.5×  | 1.0         | 1.0        |
| 16     | 78        | 31       | 2.5×  | 0.9         | 0.4        |
| 32     | 84        | 40       | 2.1×  | 0.4         | 0.6        |

## 4. Analysis

### Theory 1: CONFIRMED (ASCII and accented)

The ratio drops clearly as strings get longer:
- ASCII: 3.2× at len=4 → 2.1× at len=64
- Accented: 2.8× at len=4 → 2.1× at len=32

The per-character marginal cost **converges** between us and ICU:
- ASCII long strings: ~0.3 ns/char (ours) vs ~0.3 ns/char (ICU) — **at parity**
- Accented long strings: ~0.4 ns/char (ours) vs ~0.6 ns/char (ICU) — **we're
  actually cheaper per-char for accented text at length 32+**

The fixed per-call overhead (extrapolating to len=0):
- Ours: ~50 ns
- ICU: ~15 ns
- **Fixed gap: ~35 ns per compare call**

This 35 ns is the "preparation phase": `withContiguousStorageIfAvailable`
closure entry, `FastLatinCache` lock acquisition, thread-local scratch
take/give, and scalar iterator construction. It's not recoverable without
API-level changes (Span for the full pipeline, or direct pointer access).

### Theory 2: PARTIALLY CONFIRMED (CJK stays flat)

CJK ratio stays at 3.3–3.8× regardless of length — the per-character cost
doesn't converge:
- Ours: ~4–8 ns/char (CJK, CE pipeline)
- ICU: ~0.5–1.1 ns/char

This is NOT the NFD front end (CJK characters don't decompose). It's the
CE-iterator overhead: our `appendMore()` → `NFDIterator.next()` →
`popScalar()` → trie lookup chain costs ~4–8 ns per scalar, while ICU's
`UTF8CollationIterator::nextCE()` does it in ~1 ns with inline buffer access
and no virtual dispatch.

For **accented** text (which DOES decompose), our per-character cost is
actually lower than expected (~0.4–1.0 ns/char) because the fast-Latin path
handles precomposed accented characters directly from the mini-CE table
without entering the NFD pipeline at all. The NFD cost only appears when
fast-Latin bails — which for Latin-range accented text (≤ U+017F), it doesn't.

### Key Insight

The gap has two distinct components:

1. **Fixed per-call overhead: ~35 ns** (ours: ~50, ICU: ~15)
   - Not in any loop — pure setup cost
   - Dominates short strings (4-char: 35 of 55 ns = 64% of our time)
   - Amortized away on long strings (64-char: 35 of 77 ns = 45%)
   - Sources: String byte access, cache lock, TLS checkout, iterator build

2. **Per-character CE pipeline cost: ~4–8 ns vs ICU's ~1 ns** (CJK path)
   - Dominates long non-Latin strings
   - Sources: `NFDIterator` struct overhead, `CEIterator.appendMore()` call
     chain, Array-based CE buffer append, `UCharsTrie` contraction matching
   - The fast-Latin path (ASCII/accented) bypasses this entirely — that's why
     ASCII per-char cost converges to parity

## 5. Implications for Further Optimization

### What to target for short strings (the common case)

The ~35 ns fixed overhead. Components (from Docs/14 §4):
- ~17 ns: contiguous-storage acquisition (2× nested closures)
- ~10 ns: fast-Latin cache lock
- ~6 ns: prefix skip + safety check
- ~2 ns: thread-local take/give (already optimized)

The closures compile to the same code as Span (proven in this session), so
the ~17 ns is the cost of *reaching into the String's guts to get a pointer*,
not the closure syntax. This is irreducible without Foundation-level changes
(e.g., a `borrowing` String parameter that exposes bytes directly).

### What to target for long non-Latin strings

The ~4–8 ns per-character CE pipeline cost. The full pipeline refactor
(replacing `String.UnicodeScalarView.Iterator` with direct byte decoding
inside the CE loop) would reduce this toward ICU's ~1 ns. But it requires
Span threading through 5 layers of `@inline(__always)` calls — the deep
refactor documented in Docs/16 §9.6.

### What's NOT a problem

The NFD decomposition strategy. For Latin-range text, fast-Latin handles
accented characters without decomposing. For CJK, there's nothing to
decompose. The NFD cost is only material for non-Latin text with combining
marks (Thai, Khmer) — and there it's part of the CE pipeline cost, not
a separate overhead.

## 6. Reproducing

```sh
cd ~/Projects/dra8an/swift-foundation-collation/Collation

# Generate the corpora (one-time):
python3 /tmp/gen_sorted_corpora.py   # or re-run the script in this doc

# Benchmark:
swift build -c release
.build/out/Products/Release/Bench Tools/bench/bench-sorted-ascii-32.txt 5000
DYLD_LIBRARY_PATH=.../icu4c/source/lib \
  Tools/bench_icu Tools/bench/bench-sorted-ascii-32.txt 5000
```

The corpus files are:
- `bench-sorted-ascii-{4,8,16,32,64}.txt`
- `bench-sorted-cjk-{4,8,16,32}.txt`
- `bench-sorted-accented-{4,8,16,32}.txt`

## 7. Deletion Experiments: Per-Component Cost (Apple Silicon)

Measured on this machine by stubbing out components one at a time in release
builds. Each experiment returns a fixed result at a different point in the
`compare()` → `compareClassic()` → `fastLatinUTF8()` chain. The delta between
successive experiments isolates each component's cost.

Test corpus: `bench-ascii.txt` (200 random 7-char ASCII strings), 10000 reps.
Baseline: 32 ns/op. All runs rock-stable (±0 ns across 5 iterations).

### 7.1 Results

| Experiment | What runs | ns/op |
|---|---|---|
| **Full baseline** | Everything | **32** |
| **Exp 1**: Return -1 before closures | Function-call shell only | **14** |
| **Exp 2b**: Enter closures, return -1 inside | Shell + closure entry/exit | **14** |
| **Exp 3**: Closures + byte prefix scan, then return | Shell + closures + scan | **15** |
| **Exp 4**: Closures + scan + safety + cache, then return | Everything except compareUTF8 | **27** |
| **Baseline**: Full path including compareUTF8 | Everything | **32** |

### 7.2 Per-Component Breakdown

| Component | Cost (ns) | % of total | Notes |
|-----------|-----------|-----------|-------|
| Function-call shell | ~14 | 44% | `compare()` → `compareClassic()`, options check, `for` loop, result mapping |
| `withContiguousStorageIfAvailable` closures | ~0 | 0% | Compiler inlines them completely — zero runtime cost |
| Byte prefix scan | ~1 | 3% | One byte comparison (random ASCII, differs immediately) |
| Safety check + cache lock + cache lookup | ~12 | 38% | `isUnsafe` trie lookup + `os_unfair_lock` + word match |
| `compareUTF8` mini-CE loop | ~5 | 16% | The actual collation comparison (2-3 characters before difference) |

### 7.3 Key Corrections from Intel Analysis

The Docs/14 §4 analysis (Intel iMac, 79 ns baseline) attributed ~17 ns to
"contiguous-storage acquisition (closures)". **This was wrong.** On Apple
Silicon the closures are provably zero-cost — the compiler inlines them
completely. The ~17 ns on Intel was likely the safety + cache component that
was mis-attributed.

The ~10 ns "setup-cache lock" from Docs/14 is confirmed here as part of the
~12 ns safety + cache block. The lock itself is ~5 ns (`os_unfair_lock`
uncontended); the remaining ~7 ns is the `isUnsafe` trie lookup and the
cache word comparison.

### 7.4 Implications

1. **Span cannot help the fast-Latin path.** The closures cost zero — replacing
   them with Span produces identical code (confirmed in the neutral A/B in
   Docs/16 §10). There is nothing to save here.

2. **The function-call shell (14 ns, 44%) is irreducible** without merging
   `compare()` and `compareClassic()` into one function. The other machine's
   split refactor made this worse on Intel by adding a call frame; on Apple
   Silicon it's neutral. This is the cost of having a `public func compare()`
   that dispatches to an internal implementation.

3. **The safety + cache block (12 ns, 38%) is the remaining target.** The
   `isUnsafe` check runs even on ASCII (where it always returns false), and
   the cache lock runs even when the setup never changes. These could be
   addressed by:
   - Skip `isUnsafe` when `i == 0` (no prefix was found, nothing to check) —
     but on random ASCII, `i` IS 0 almost always, so the check is
     already short-circuited by the `if i > 0` guard. The 12 ns cost must be
     predominantly in the cache lookup path (lock + word check + setup access).
   - Pre-compute the setup at init (attempted, +3 ns regression from
     extra parameter passing into the closure).

4. **The `compareUTF8` loop itself (5 ns, 16%) is near ICU's speed.** ICU's
   full ASCII compare is ~9 ns, of which most is the same mini-CE comparison
   loop. Our 5 ns for the loop portion is comparable — the gap is entirely
   in the shell + cache overhead.

### 7.5 Reproducing

```swift
// In fastLatinUTF8(), add `return -1` at the desired point:
// After the function signature = Exp 2b (closure cost)
// After the prefix scan loop = Exp 3
// After the cache lookup = Exp 4
// No modification = Baseline

// Build release, run:
// .build/out/Products/Release/Bench Tools/bench/bench-ascii.txt 10000
```

## 8. Pre-Baked Fast-Latin Setup: Eliminating the Cache Lock (−22% ASCII)

### 8.1 The Problem

The deletion experiments (§7) identified ~12 ns in "safety + cache lock"
on the ASCII fast path. The `FastLatinCache` is a class holding a locked
`FastLatinSetup?`:

```swift
// Per-call path (inside the closures):
guard let setup = cache.setup(for: word) else { return needsSetupResult }
// cache.setup does: lock → check word → return → unlock = ~10 ns
```

In practice, the options word NEVER changes between calls (the benchmark and
real sorting always use the same options). The cache always hits. The lock
always succeeds uncontended. We're paying ~10 ns per call to confirm something
that's been true since the first call.

### 8.2 The Fix

Pre-compute the fast-Latin setup (primaries + packedOptions) at `init` and
store it directly on the collator as trivial fields:

```swift
private let defaultFLPrimaries: UnsafeBufferPointer<UInt16>  // owned by defaultFLStorage
private let defaultFLPackedOptions: Int32
private let defaultFLWord: Int32
private let defaultFLStorage: DataStorage  // owns the primaries memory
```

The fast path checks `word == defaultFLWord` (one integer compare, ~0 ns)
and uses the stored primaries directly — **no lock, no class reference, no
ARC, no Optional unwrap**.

Key design choices:
- Primaries stored as `UnsafeBufferPointer<UInt16>` (not `[UInt16]`) so the
  closure capture is trivial (pointer + count, no Array ARC). This was
  critical: an `[UInt16]` capture added +4% CJK regression; the
  UnsafeBufferPointer capture is zero-cost.
- Owned by a dedicated `DataStorage` instance (same pattern as the trie data).
- Fallback for non-default options still goes through the locked cache
  (rare path — non-default options are uncommon in real sorting).
- `CollationFastLatin.compareUTF8` signature changed to take
  `UnsafeBufferPointer<UInt16>` instead of `[UInt16]` to match.

### 8.3 Results

| corpus | before | after | delta | ICU | new ratio |
|--------|--------|-------|-------|-----|-----------|
| ASCII compare | 32 ns | 25 ns | **−22%** | 9 ns | **2.8×** |
| Latin compare | 31 ns | 24 ns | **−23%** | 10 ns | **2.4×** |
| paths compare | 75 ns | 63 ns | **−16%** | 33 ns | **1.9×** |
| CJK compare | 128 ns | 127 ns | neutral | 41 ns | 3.1× |
| Thai compare | 401 ns | 399 ns | neutral | 191 ns | 2.1× |
| All sort keys | — | — | neutral | — | — |

The saving is a constant ~8-12 ns regardless of string length (confirmed via
sorted corpora at lengths 4–64). It's a fixed per-call saving that benefits
short strings proportionally more.

### 8.4 Why This Works (and why earlier attempts failed)

Previous attempt: resolve setup before closures and pass `[UInt16]` primaries
into the closure. Result: −9% ASCII but +5% CJK — the Array capture triggered
a retain/release in the closure, adding ARC cost for CJK text that bails
before using the primaries.

This version: store primaries as `UnsafeBufferPointer<UInt16>` (trivial value
type — just a pointer + count). The closure captures it as two integers,
zero ARC. CJK text that bails from fast-Latin pays nothing extra because
the UnsafeBufferPointer capture doesn't retain anything.

### 8.5 Architectural Lesson

ICU bakes everything at `ucol_open()` — options, primaries, setup are all
pre-resolved once and stored as struct fields on the collator. Our API takes
`options:` per call, so we previously needed a per-call cache lookup. But
since the common case is always the same options, pre-baking the default
options' setup at init is the Swift equivalent of ICU's model: pay once at
init, read for free on every call.

