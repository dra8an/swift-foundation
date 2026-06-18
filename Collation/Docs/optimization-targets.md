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

**Status:** untried

`compare()` checks the options word per call to decide which path to take
(strength, alternate handling, case-first, etc.). In practice the options
never change between calls on the same collator.

Pre-resolve at init: store an enum case or function pointer for "which compare
implementation to use" so the per-call branch is a direct call, not a
multi-field check.

**Expected gain:** 1–3 ns (branch prediction probably handles this well
already, so may be negligible).

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

**Status:** untried

`CEIterator.reset()` clears 3 arrays + resets state, and `NFDIterator.reset()`
clears 3 more arrays + calls `String.UnicodeScalarView.makeIterator()`. The
`isEmpty` guards mean the array clears are cheap when buffers were never used,
but `makeIterator()` is a per-call cost.

Where it matters:
- **Sort keys:** every call hits full `reset(scalars:)` with `makeIterator()`.
- **CJK/Thai compare:** when fast-Latin bails, reset fires before entering
  the CE pipeline. (The non-`fellBack` path already avoids this by reusing
  the prefix-scan iterator via `reset(source:first:)`.)
- **ASCII/Latin compare:** fast-Latin succeeds → reset never runs.

Possible approaches:
- Store a "rewound" iterator state at init or at closure entry so sort keys
  can reset without rebuilding from `String.UnicodeScalarView`.
- For the CJK compare bail path: pass the byte pointer directly instead of
  reconstructing a scalar iterator (ties into the Span pipeline refactor).
- Measure `makeIterator()` cost in isolation via deletion experiment (return
  immediately after reset, before any CE work).

**Expected gain:** 2–5 ns on sort keys and CJK compare (the `makeIterator()`
portion; array clears are already guarded).

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
