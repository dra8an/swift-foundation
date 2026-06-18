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
