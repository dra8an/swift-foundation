# Optimization Targets

> Living document. Ideas for further performance wins, tracked with status.

## Guiding principle

The pre-baked fast-Latin setup (−22% ASCII) showed the pattern: if something
is checked per-call but the answer is fixed at init, store the answer once and
skip the check. Look for more instances of this.

---

## Ideas

### 1. Skip `isUnsafe` backwards check for Latin-range prefixes

**Status:** shipped (−5% sorted ASCII 32, −4% sorted ASCII 64 compare)

Pre-compute at init the lowest code point that might be unsafe (`safeBelowCP`
for numeric=off, `safeBelowCPNumeric` for numeric=on). The hot-path
`isUnsafe()` short-circuits with `if c < threshold { return false }` — skips
binary searches + trie lookups for all ASCII/Latin characters.

For root collation: threshold is U+0300 (Latin Extended-B and below are all
safe). Benefits sorted/prefix-heavy text where the prefix scan finds a long
shared prefix and `isUnsafe` fires on the first differing character. Neutral
on random corpora (strings differ immediately, `i == 0`, guard skips the check
already).

---

### 2. Pre-resolve options dispatch at init

**Status:** try later

`compare()` checks the options word per call to decide which path to take
(strength, alternate handling, case-first, etc.). In practice the options
never change between calls on the same collator.

Pre-resolve at init: store an enum case or function pointer for "which compare
implementation to use" so the per-call branch is a direct call, not a
multi-field check.

**Expected gain:** 1–3 ns (branch prediction probably handles this well
already, so may be negligible). Analysis suggests the `icuOptions` computed
property is ~5 bitwise ops and the conditionals are perfectly predicted —
likely sub-nanosecond total. Low priority.

---

### 3. Store raw normalization trie pointer on the collator

**Status:** untried

Every `CEIterator` construction grabs a reference to `NormalizationData`. If
we store the raw trie base pointer directly on the collator (like we did with
fast-Latin primaries as `UnsafeBufferPointer`), iterator construction becomes
copying two integers instead of going through the struct.

**Expected gain:** 1–3 ns per call (iterator setup overhead).

---

### 4. Avoid CEIterator/NFDIterator reset cost

**Status:** investigated, partially confirmed, blocked

`CEIterator.reset()` clears 3 arrays + resets state, and `NFDIterator.reset()`
clears 3 more arrays + calls `String.UnicodeScalarView.makeIterator()`. The
`isEmpty` guards mean the array clears are cheap when buffers were never used,
but `makeIterator()` is a per-call cost.

**Deletion experiment (2026-06-18):** reset costs 22 ns per sort key call
(47 ns total for TLS+reset+key.clear vs 25 ns for TLS+key.clear alone).
Inlining the reset functions with `@inline(__always)` gives only ~1-2 ns
(borderline noise) — the compiler already inlines them with WMO. The 22 ns
is the actual work of `makeIterator()` + `ces.removeAll(keepingCapacity:)`.

**Byte-pointer experiment (2026-06-18):** Added a `useBytes` mode to
NFDIterator that decodes UTF-8 from an `UnsafeBufferPointer<UInt8>` instead
of using `String.UnicodeScalarView.Iterator`. Sort key path runs
`collectAll()` inside `withContiguousStorageIfAvailable` to keep the pointer
valid. Results:
  ASCII sortKey: 260→255 ns (−2%, ~5 ns)
  CJK sortKey: 240→237 ns (−1%, ~3 ns)
  Paths sortKey: 677→670 ns (−1%, ~7 ns)
The win is modest because: (1) the `if useBytes` branch in
`nextSourceScalar()` adds overhead per scalar, (2) the byte decoder does
the same UTF-8 decoding the iterator does internally. The theoretical 22 ns
ceiling isn't reached because we're replacing one decoding method with another
of similar cost — only saving the `makeIterator()` setup (~5 ns).

**Verdict:** ~5 ns gain is real but small. The byte-pointer approach works
today but adds complexity (dual-mode NFDIterator, closure wrapping). When
Span becomes storable (`~Escapable` lifted), the byte-pointer mode becomes
the ONLY mode and the `if useBytes` branch disappears — expected to recover
the full 22 ns. Until then, not worth the code complexity for 5 ns.

---

### 5. Closure capture overhead in real sorting (architectural)

**Status:** architectural (not actionable in collator)

In real sorting (`Array.sort`), Swift's sort algorithm calls the comparator
through a closure. That closure capture + indirect call is overhead ICU doesn't
pay (C `qsort` with a function pointer is cheaper). This affects the
function-call shell cost but isn't fixable inside the collator — it would
require Foundation-level API changes (e.g., a `SortComparator` protocol with
witness-table dispatch instead of closure indirection).

**Expected gain:** unknown, not actionable.

---

### 6. Inline CE pipeline hot path

**Status:** shipped (2278a07, −5% CJK sortKey, −3% Latin/paths)

`@inline(__always)` on `NFDIterator.next()`, `CEIterator.popScalar()`, and
`CEIterator.appendMore()`. Eliminates per-character function-call overhead
in the CE production chain.

---

### 7. Pre-baked fast-Latin setup

**Status:** shipped (afd645f, −22% ASCII, −23% Latin, −16% paths)

Store fast-Latin primaries as `UnsafeBufferPointer<UInt16>` at init. Eliminates
per-call cache lock, ARC, and Optional unwrap.

---

### 8. Pre-computed ASCII CE table for sort keys

**Status:** shipped (−14% ASCII, −6% Latin, −21% paths sortKey)

Build a 128-entry table of full 64-bit CEs for ASCII (0–127) at init. In
`appendMore()`, characters below 128 with a non-zero table entry skip the
trie lookup + `isSpecialCE32` check + tag dispatch entirely — one indexed
load + one array append. Characters that need full processing (digits in
numeric mode, U+0000, expansions) have a 0 sentinel and fall through.

Cost: 1 KB memory (128 × 8 bytes), one `DataStorage` allocation at init.
Only benefits sort keys (compare uses fast-Latin mini-CEs which already
bypass the CE pipeline). CJK/Thai neutral (all above 127).

---

### 9. CJK direct CE computation (skip trie for offset-tag characters)

**Status:** tried, reverted (neutral to slightly worse)

Pre-resolve the `dataCE` offset base at init for CJK Unified (U+4E00–U+9FFF)
and Extension A (U+3400–U+4DBF). In `appendMore()`, range-check and compute
the CE via `threeBytePrimaryForOffsetData()` directly — no trie lookup, no
tag dispatch.

**Result:** neutral on short CJK strings (4-char bench), slightly WORSE on
32-char sorted CJK (800→816 ns). The offset formula has two integer divisions
(mod 254, mod 251) which cost more than the trie lookup it replaces (one
indexed memory read). The trie is already a direct table for BMP characters.

**Lesson:** trie lookups for in-range characters are essentially free (one
indexed array read). Only worth bypassing the trie when the downstream
computation is cheaper than a table lookup — the ASCII CE table works
because it replaces trie + tag dispatch + ceFromCE32 with a single load.
For CJK, the offset math itself is the bottleneck. Pre-computing all CJK
CEs (20k+ entries, 160+ KB) is not acceptable memory-wise.

---

### 10. Break NFDIterator carried-scalar cascade

**Status:** shipped (−14% Latin sortKey, −7% Thai sortKey, −8% Thai compare)

After `refill()` processes a combining-mark sequence, the next starter gets
"carried" to the following refill call. Previously, that refill would absorb
the carried scalar, read the NEXT source scalar, see it starts a new unit,
carry IT over, and so on — cascading through all remaining characters.
One accented character could add ~110 ns to a 6-char sort key.

Fix: at the top of `refill(startingWith: nil)`, check if carried is a single
inert scalar. If so, emit it directly as a one-element unit — no source read,
no carry propagation, no cascade. Correct because an inert scalar is by
definition a complete reorderable unit (CCC=0, no decomposition).

Benefits any text with combining marks: Latin (accents), Thai (vowels/tones),
Khmer, Devanagari, etc. Pure ASCII/CJK neutral (carried is never populated).

---

### 11. Quick decomposition for simple [starter, mark] pairs

**Status:** shipped (−7% Latin sortKey on top of carry-cascade fix)

Inside `refill()`, the common Latin case (precomposed → [starter, one-mark])
previously went through: `hasDecomposition` trie lookup → `decomposed` array
clear → `appendDecomposition` (trie + buffer copy into array) → `for c in
decomposed { absorb(c) }`. Three trie lookups + array operations.

`quickDecomp(c)` does one trie lookup and returns both scalars directly from
the normalization buffer — no intermediate array, no clear, no copy loop.
Guarded by `ccc(base)==0 && ccc(mark)!=0` to ensure correctness (rejects
exotic decompositions like Tibetan U+0F73 → [non-starter, non-starter]).

Also applied in the while-loop decomposition path within `refill()` for
back-to-back accented characters.

Additionally, the `quickDecomp` fast path inside `refill()` inlines the
absorb logic: places base directly in `unit` and mark directly in `marks`,
skipping two `absorb()` function calls and their redundant `ccc` checks
(quickDecomp already verified CCC values). Saves ~5 ns per accent.

---

### 12. Combining mark CE table (extend simpleCEs to U+036F)

**Status:** tried, rejected (−2-3% Latin sortKey, but +6 KB memory)

Expanded the ASCII CE table from 128 entries to 880 (covering 0x000–0x36F)
to include combining marks (U+0300–U+036F). Each mark produces a single CE
with only secondary/tertiary weight — ideal for pre-computation.

**Result:** Latin sortKey 282→277 ns (−2%), one-accent 260→254 ns (−3%,
~7 ns per accent). The trie lookup for the mark costs ~7 ns; the table
eliminates it. But the table grows from 1 KB to 7 KB for a marginal win.

**Verdict:** not worth the memory. The remaining per-accent cost (~54 ns)
is dominated by the `refill()` structural overhead (entering the function,
array ops, while-loop peeking ahead), not the mark's trie lookup.

---
