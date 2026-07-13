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

**Further:** bypass `refill()` entirely (shipped separately, see §16 below).

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

### 13. Remove `throws` from CE pipeline hot path

**Status:** tried, neutral

Made `appendMore()`, `appendCEs()`, `appendHangulCEs()`, `appendNumericCEs()`
non-throwing by storing errors in a field and checking after `collectAll()`.
Only 3 throw sites exist (all for malformed data that never occurs).

**Result:** no measurable difference on any corpus. The compiler with WMO
already proves the throw sites are dead code on the hot path and optimizes
the `try` to zero cost.

---

### 14. Sort key writer (`writeSortKeyUpToQuaternary`) optimization

**Status:** partially shipped (appendTo memcpy fix: −6% ASCII/CJK, −3% paths)

**Deletion experiment (2026-06-22):** skipping the writer entirely shows it
accounts for 58% of ASCII sort key time and 59% of paths:

| Component | ASCII (ns) | CJK (ns) | Paths (ns) |
|-----------|-----------|----------|------------|
| TLS + reset + key.clear | 25 | 25 | 25 |
| collectAll (CE generation) | 69 | 102 | 194 |
| **writeSortKeyUpToQuaternary** | **131** | **114** | **322** |
| Total | 225 | 241 | 541 |

**Shipped (3e6caf2):** `SortKeyLevel.appendTo` was the largest callee — 
`key.append(contentsOf: bytes.dropLast())` forced slice iteration instead of
memcpy. Fix: skip empty levels entirely, and copy through UnsafeBufferPointer
for the memcpy fast path. −6% ASCII/CJK, −3% paths on Apple Silicon.

**Tried, reverted:** Specialized `writeSortKeyTertiary` for default options
(eliminate all flag/variable/quaternary/case branches). Hit correctness issues
with the NO_CE termination flush — the common-weight compression uses "low"
vs "high" flush variants depending on whether the terminator is below or above
the common value. Needs careful parity study with ICU's writer before retrying.

Remaining potential: the per-CE loop still has ~10 ns/CE overhead from
branching + multiple key.append calls. A batch approach (accumulate primary
bytes in a stack buffer, flush once) could help.

---

### 15. Fuse CE production with the sort-key writer (REJECTED — regresses)

**Status:** tried, reverted (Intel) — significant regression on every corpus.

Distinct from §14's "batch primary bytes" idea: this attacked the intermediate
`[Int64]` CE array itself. Instead of `collectAll()` materializing all CEs and
the writer reading them back, a streaming `CEIterator.nextCE()` (produces on
demand, compacts `ces` so it never grows past one character's batch) fed the
writer directly. Byte-identical output (61 tests green), so the experiment is
valid — and clearly slower:

| corpus | sortKey vs two-pass |
|--------|--------------------:|
| ASCII  | +20% |
| Latin  | +15% |
| CJK    | +11% |
| paths  | **+44%** |
| Thai   | +11% |

**Why the two-pass design wins:**
1. **Inlining blow-up.** `appendMore()` is `@inline(__always)`. Two-pass: it
   inlines into `collectAll()`'s tight loop while the writer stays lean. Fused:
   the writer pulls `nextCE()` → `appendMore()`, so the *entire* CE pipeline
   (tag dispatch, contraction/prefix/expansion, numeric) inlines into the
   already-large writer body → register spills + i-cache pressure slow both
   halves. The +44% on paths (most CEs) is exactly this.
2. **The round-trip was already nearly free.** The `ces` array is reused across
   calls (scratch, `keepingCapacity`) and stays L1-resident at these string
   lengths, so reading it back costs almost nothing — while streaming *adds*
   per-CE overhead (the refill/compact branch in `nextCE`).

Two tight, independently-optimized loops with a small hot buffer between them
beat one fat fused loop. The writer's remaining wins are inside its own loop
(§14), not in removing the CE array.

---

### 16. Bypass refill() for Latin precomposed characters

**Status:** shipped (−11% Latin sortKey, per-accent cost 56→24 ns)

For precomposed characters below U+0300, when `quickDecomp` succeeds AND the
following source character has `leadCCC == 0` (its NFD starts with a starter),
emit base directly and stash mark in `pendingMark` — bypassing `refill()`
entirely. No arrays, no loops, no carry, no flushMarks.

The `leadCCC` check is the critical safety guard: it catches characters like
U+0F73 (own CCC=0 but decomposes to [CCC=129, CCC=130]) whose NFD lead could
reorder with the emitted mark. The `< 0x300` fast test for `following` is safe
because all characters below U+0300 are guaranteed `leadCCC == 0`.

This stacks with §10 (carry-cascade fix), §11 (quickDecomp), and the inline
absorb optimization. Together they reduced per-accent overhead from +110 ns
(start of session) to +24 ns (now). ICU pays +11 ns.

---

### 17. CJK compare path investigation (3.1× — worst ratio)

**Status:** under investigation

Random CJK compare is 130 ns (vs ICU 42 ns = 3.1×). Deletion experiments:
- Return `.ascending` at top of compareBody: **20 ns** (shell + bail)
- Return at quickPrimaryCompare exit: **36 ns** (shell + iterators + quickPrimary)

This suggests quickPrimary resolves at ~36 ns total. But the full path is
130 ns, implying 94 ns is spent AFTER quickPrimary. Debug prints confirmed
quickPrimary IS firing and resolving (no fallback prints). The discrepancy
is likely a **codegen artifact**: when compareBody is small (deletion
experiment), the compiler inlines it into compareClassic, eliminating the
function-call boundary. At full size, compareBody is a separate call frame
and the overhead compounds.

The real cost breakdown is likely:
- Shell + fast-Latin bail: 20 ns
- compareBody function-call overhead: ~30 ns (non-inlined entry/exit)
- Iterator construction (2× makeIterator): ~40 ns
- quickPrimary (2 trie lookups + offset math): ~30 ns
- Result mapping + return: ~10 ns

The function-call boundary + iterator construction dominate. Moving the
quickPrimary check BEFORE iterators (into the byte path where we already
have the UTF-8 bytes) could save ~70 ns — but requires byte-level scalar
decode + trie lookup inside fastLatinUTF8 (see §18).

---

### 18. Quick-primary in the byte path for CJK (avoid compareBody entirely)

**Status:** tried, neutral (−2 ns, not worth the code)

Moved quickPrimaryCompare into the `withContiguousStorageIfAvailable` closure
right after fastLatinUTF8 bails. Decoded CJK scalars from raw bytes, did the
trie lookup + offset math inline.

**Result:** 130→127 ns (noise-level). The offset math (`threeBytePrimaryForOffsetData`
with 2 integer divisions per character) costs ~40 ns and dominates regardless
of where it's called from. Moving it into the byte path saves ~3 ns of
function-call overhead but doesn't reduce the math cost.

**Lesson:** CJK compare at 3.1× is bottlenecked on the offset formula's
integer divisions, not on the function-call structure. Same finding as §9.
Without pre-computing primaries (rejected — 160 KB) or changing the data
encoding (breaking change), this ratio is a hard floor.

---

### 19. Sort key: fast collectAll for ASCII (bypass NFDIterator)

**Status:** tried, reverted (−4% ASCII but +4-9% Latin/CJK/paths)

Inside `sortKey(for:into:)`, added a fast path using
`withContiguousStorageIfAvailable` to read UTF-8 bytes and build the ces
array directly from the simpleCE table — no NFDIterator, no appendMore().
Bails at the first non-ASCII byte or missing table entry.

**Result:** ASCII sortKey 211→202 ns (−4%, ~9 ns saved from avoiding
makeIterator + NFDIterator overhead). But Latin (+6%), CJK (+4%), paths
(+9%) all regressed — the added code bloats the function body and disrupts
the compiler's inlining decisions for non-ASCII paths. Even with an
early-bail guard, the closure entry adds measurable overhead.

**Lesson:** at this stage, adding any code to the sort key hot path risks
regressing other corpora through codegen butterfly effects. Future
improvements need to either: (a) make existing code cheaper without adding
branches, or (b) use separate compilation units (@_silgen_name or similar)
to isolate codegen.

---

### 20. Collation-aware search (`contains` / `range`) optimization chain

**Status:** shipped. `localizedStandardContains` went from 1.5–5.9× *slower*
than system ICU to **beating it on most corpora**; the range APIs are partway
there. Full Intel numbers and per-API breakdown: `Docs/25-intel-benchmark-matrix.md`.

The starting point (`CollationSearch`) produced *all* text CEs into arrays with
position annotations, built a `[String.Index]` table + NFD source map, then did
a linear CE-space scan — fine for correctness, heavy per call. The chain that
fixed it:

1. **Lazy CE production** (`7648b1d`): produce CEs incrementally and match as
   each arrives; return on first match. Avoids processing the whole text when
   the pattern hits early.
2. **`contains()` Bool fast path** (`c683653`): `localizedStandardContains`
   returns Bool, not a range — so skip the index table, NFD map, `AnnotatedCE`
   structs, and boundary validation entirely. Produce only masked `Int64` CEs
   and match. (Boundary validation isn't needed without range reporting.)
3. **`reserveCapacity`** on the CE/match buffers (`e1cd576` range path;
   `78729ac` fast path), gated on `utf8.count <= 32` (`843b4d8`) — short strings
   get the realloc-avoidance win; long strings (where search bails early) skip
   the over-allocation.
4. **Thread-local scratch-iterator reuse** (`b93b549` contains, `a56b5a3`
   range) — **the decisive step.** Profiling `localizedStandardContains` showed
   ~half the time was per-call allocation/ARC: every call built two fresh
   `CEIterator`s (one re-deriving the *same* pattern's CEs) plus their arrays,
   then freed them. Route `RootCollator.contains`/`search`/`searchBackwards`
   through `takeScratch()` and reuse `scratch.left`/`scratch.right` (reset per
   call). Searching one pattern over many strings now allocates no per-call
   iterator or CE buffer. Intel: contains −37 to −46%, range −26 to −39%.
5. **ASCII / UTF-8 byte-scan fast path** for `range(of:options:locale:)`
   (`6e214ff`, `7c742c0`): at strength ≥ tertiary with numeric off, byte
   equality implies collation equality, so do a direct byte scan (mirrors
   CoreFoundation's `CFStringFindWithOptionsAndLocale`). ASCII near-parity with
   ICU. Does **not** apply to `localizedStandardRange` (primary + numeric).

6. **Lazy position reporting** (2026-07-04): the range paths built three
   upfront O(n) arrays *per call* — a `[String.Index]` table, the NFD→source
   map (one trie probe per scalar plus decomposition scratch arrays), and
   `unicodeScalars.count` passes — all consumed only *at match time*; pure
   waste on no-match calls. Now `AnnotatedCE` carries raw NFD offsets
   (free — read off `iter.scalarsConsumed`), and `confirmMatch` does the
   NFD→source conversion, boundary validation, and `String.Index`
   construction only for candidates whose CEs already matched. Two things
   make the conversion cheap: a `sawDecomposition` flag on `NFDIterator`
   (set only in the four decomposition branches; while false the NFD stream
   is 1:1 with the source, so offsets carry over with no map at all — always
   true for ASCII/paths/CJK; mark reordering permutes scalars within a unit
   but never changes counts, so it doesn't need the flag), and building the
   map lazily, cached across candidates, when decomposition did happen.
   `String.Index`es come from one `index(offsetBy:limitedBy:)` walk at match
   time — O(match position) once instead of O(n) always. Same treatment on
   forward and backward search; the index-table builder is deleted. Intel:
   `localizedStandardRange` −17 to −39% (ascii 1736→1190, now **beats**
   system ICU at 0.85×; paths 3269→2020, 2.28×→~1.4×), `range(of:locale:)`
   non-ASCII −10 to −40% (latin 2755→1656). Compare/contains unchanged.

**Results.** `contains`: Apple Silicon 1.6–3.2× faster than system ICU
(`2268a0e`); Intel beats ICU on ASCII/Latin/CJK/Thai (0.46–0.77×), paths near
parity (1.11×). `localizedStandardRange` now beats system ICU on every corpus
except paths (~1.4×, down from 2.28×); `range(of:locale:)` is at ASCII/Latin
parity, other corpora ~1.2–1.4× behind.

7. **Capped buffer reserve for the range paths** (2026-07-06): the
   `AnnotatedCE` buffer (and `iter.ces`) were only pre-reserved for texts
   ≤32 UTF-8 bytes; long lines (paths corpus) paid growth reallocs of
   24-byte elements — worst in the backward path, which pre-produces the
   whole text's CEs. Now both forward and backward reserve
   `min(utf8Count, 1024)` (capped so huge inputs don't over-allocate).
   Interleaved A/B on Intel: paths backwards **−17%**, paths forward −5%,
   ascii/latin neutral. (Docs/25's 07-06 baselines predate this by hours —
   the paths range cells are ~5–17% better than recorded there.)

   **Tried and reverted in the same round — parallel arrays:** splitting
   `[AnnotatedCE]` into a dense `[Int64]` CE buffer + packed `[Int64]`
   position windows (8-byte match-loop stride, contains-style). It helped
   long lines (paths backwards −12%) but **regressed short-line corpora**
   (ascii +5%, latin +8%): the second array is a second per-call malloc,
   and short strings are allocation-dominated. One array of structs, one
   malloc. Don't re-split without moving the buffers into the thread-local
   scratch (zero-alloc steady state), which sidesteps the trade entirely.

8. **Backward byte-scan + byte-scan soundness rules** (2026-07-06,
   `16d0322`): backward search had no fast path at all — always full CE
   pre-production. It now gets a byte scan from the end of the text, built
   on an explicit soundness rule that also fixed three holes in the forward
   scan (each had a failing test first): byte-level conclusions are only
   valid over "clean" bytes (printable ASCII + TAB..CR — the other C0
   controls and DEL are completely ignorable in root and produce no CE);
   alternate must be nonIgnorable (shifted makes spaces/punct ignorable);
   and a byte match is only provably FIRST/LAST if it lies entirely in the
   clean prefix (forward) / suffix (backward) — beyond a dirty byte, an
   earlier/later match can hide in a different normalization form.
   Cleanliness is checked inline during the scan (a byte equal to a clean
   pattern byte needs no check), keeping it single-pass. Same commit:
   search's CE path now honors alternate=shifted (`maskedCE()` mirrors
   compare's S3.4 variable handling; variable CEs and their trailing
   primary-ignorables drop below the search mask). Intel interleaved A/B:
   `range(of:.backwards)` ascii −51% (1480→723), paths −65% (2593→918) —
   was the worst API in the matrix at 2.6×/3.45× behind system ICU, now
   near parity; forward `range(of:locale:)` pays +2–5% for the soundness
   fixes; latin/cjk backwards neutral (they fall to the CE path).

**Remaining levers (range):** the non-ASCII CE path (forward ~1.0–1.4×,
backward latin/cjk/thai similar) — a byte-scan extension there must respect
normalization, so it is not a straight port. Scratch-owned search buffers
(see step 7) would remove the remaining per-call allocations. The numeric
digit path costs ~35% on digit-heavy contains (Docs/25 finding #5).

---

## From Foundation/stdlib team meeting (2026-06-24)

Tips from the "Swift String Best Practices" meeting (T Liu, Alejandro
Alonso, Michael Ilseman, Jeremy Schonfeld). Full notes in #swift-perf.

### 21. Reserved TLS key from CoreOS

**Status:** untried — highest-priority item

Our `ScratchBuffers.swift` uses `pthread_key_create` for thread-local
scratch buffers. The meeting notes say: "For thread-local storage, obtain
a reserved TLS key from CoreOS to avoid an extra level of indirection."

A reserved key eliminates one pointer dereference on every `takeScratch()`
/ `giveScratch()` call — our hottest path (every compare, search, sortKey).

**Action:** ask CoreOS contact for a reserved key allocation.

---

### 22. UTF8Span / non-escapable Ref type for string access

**Status:** future (macOS 26+ gating)

Meeting notes: "Use UTF8Span for writing parsers and non-mutating string
algorithms" and "Employ the Ref type (a non-escapable wrapper) to avoid
reference counting for strings."

We already explored Span in round 14 (Doc 16 §9): `String.utf8Span.span`
gives closure-free byte access identical to `withContiguousStorageIfAvailable`
but `~Escapable` prevents storing in struct fields. The "Ref type" pattern
could solve this: wrap the buffer in a non-escapable Ref that we pass down
the call chain with `@inline(__always)`.

Potential: −30–40% on CJK/Thai compare (eliminates the
`withContiguousStorageIfAvailable` closure + `makeIterator` ARC). Requires
the entire 5-call-deep CE chain to use `@inline(__always)` (already done)
and accept `~Escapable` propagation.

**Action:** revisit when macOS 26+ gating is acceptable for the hot path.

---

### 23. `withTemporaryAllocation` (OutputSpan) for scratch buffers

**Status:** untried

Meeting notes: "Prefer withTemporaryAllocation over
withUnsafeTemporaryAllocation to get an OutputSpan with compile-time
lifetime guarantees."

Could replace our sort key level buffers (`SortKeyLevel`) and temporary
CE arrays with OutputSpan-backed temporary allocations — guaranteed
stack-allocated for small sizes, no ARC.

**Action:** investigate once API is stable in the toolchain.

---

### 24. `static var` (computed) over `static let` for constants

**Status:** untried — low priority

Meeting notes: "prefer static var (computed properties) over static let
to avoid lazy initialization and storage on the meta-type, allowing for
direct inlining."

We have ~100 `static let` integer constants across CollationConstants,
CollationFastLatin, SortKey, UTrie2, UCharsTrie. Converting to `static var`
is a mechanical change. Marginal gain expected (compiler likely already
inlines integer literals with WMO), but aligns with stdlib team's
recommendation.

**Action:** batch-convert in a cleanup pass. Benchmark before/after.

---

### 25. Inline array for constant data (avoid C files)

**Status:** investigate

Meeting notes: "Investigate using Swift's inline array feature to define
C constant data directly in Swift, potentially avoiding the need for
separate C files."

Our collation data is bundled as binary resources read at init. The ASCII
CE table (128 entries) and fast-Latin setup data could potentially be
defined as inline arrays — compile-time constant, zero init cost.

**Action:** evaluate whether Swift inline arrays can encode the 128×8-byte
ASCII CE table and whether it eliminates the `DataStorage` allocation.

---

### 26. Avoid intermediate string allocations in Foundation wiring

**Status:** partially addressed

Meeting notes: "Minimize the creation of temporary Swift String objects.
Use mutating methods/in-out parameters."

Our `sortKey(for:into:)` already does this. In `StringProtocol+Locale.swift`,
`range(of:locale:)` creates `String(self)` and `String(aString)` copies —
these are intermediate allocations the meeting specifically warns about.
For `localizedStandardRange`, `CollatorCache` returns a shared collator
avoiding per-call setup.

The remaining allocations: `String(self)` in the search entry points when
`Self` is a Substring. Could be eliminated by accepting `some StringProtocol`
and passing the UTF-8 view directly — but requires API changes in
CollationSearch to accept generic scalars views.

**Action:** profile whether `String(substring)` copies dominate in real
usage (unlikely for short strings, possibly significant for long text).

---

### 27. Numeric digit runs: dense value fast path (no per-run arrays)

**Status:** shipped (2026-07-06). Paths `localizedStandardContains` −22%
(1597→1238 ns, 1.14× behind system ICU → ~0.89×, now ahead);
`localizedStandardRange` paths −16% (1965→1644); `localizedStandardCompare`
paths −5%. Digit-free corpora untouched.

Finding #5 in Docs/25 measured numeric mode (which every `localizedStandard*`
API turns on) costing ~33% on the digit-heavy paths corpus. The cost was in
`appendNumericCEs`: every digit run allocated a fresh `[Int32]` digits array,
and `appendNumericSegmentCEs` copied its `ArraySlice` into a second fresh
Array — two mallocs per digit run, per call (a path like
`IMG_20240115_123456.jpg` has three runs). Digits can't use the pre-computed
ASCII CE table because the table is shared across option sets (numeric
on/off), so every digit goes through the full pipeline.

The fix: a first pass over the run (through the lookahead buffer, consuming
nothing) accumulates the numeric value while counting significant digits.
Runs of ≤ 7 significant digits whose value fits the dense encoding
(< 1_042_490 = 74 + 40·254 + 16·254·254) — practically every run in real
text — emit their single dense CE straight from the value: no arrays at all.
Longer runs (or 7-digit values past the dense capacity, which ICU sends to
the pair encoding — mind that boundary, it is easy to get wrong) fall back
to a **reusable** iterator-owned `numericDigits` scratch and the segmented
pair encoding, which now indexes the scratch directly instead of copying a
slice. Byte-identical sort keys verified by the golden/differential/fuzz
suites; `NumericTests.swift` pins the dense/pair boundary (1042489/1042490),
the 7→8 digit transition, leading-zero equality, and long-run ordering.

---

### 28. Byte-scan eligibility beyond ASCII (CJK) — investigated, parked

**Status:** investigated 2026-07-06, parked; the end-boundary soundness fix
it surfaced is shipped.

The idea: generalize the byte-scan's clean-ASCII rule to per-scalar
eligibility — a scalar where byte identity ⇔ collation identity (NFD-inert,
context-free, single provably-unique CE) — so CJK text gets the definitive
scan and the ~1.3× cjk range cells close. Scoped eligibility to OFFSET /
IMPLICIT CE32 tags (single CE computed injectively from the code point, no
uniqueness audit needed).

**Why it's parked:** probing the root data showed common Han ideographs
carry **longPrimary** tags — explicit data-assigned primaries (CLDR's
curated Han order), not code-point-derived ones. Only rare characters
(e.g. U+4EDD) get OFFSET. So the injective-by-construction eligibility
never fires on real CJK text, and the scalar-wise scan restructuring cost
3–11% on the ascii/paths fast paths while buying nothing (reverted; the
tight byte-wise loops are back).

**What a sound extension needs (recorded design, not built):**
1. longPrimary scalars are only eligible if **no other scalar shares their
   full CE** — requires an init-time uniqueness audit over the trie
   (enumerate scalars, hash CE → collision set; collators are cached, so a
   few ms once is acceptable), materialized as an eligibility bitmap that
   would also replace the per-scalar trie+inert probes.
2. Eligible scalars must not occur as **contraction suffixes** (a
   contraction starting before a backward match window could consume into
   it — the byte scan never visits that side). ICU's unsafe-backward set is
   the right exclusion source.
3. The forward **end-boundary rule** (shipped): a match's following scalar
   must be clean/eligible — a combining mark there belongs to the match's
   last character, and the CE path rejects the split. The ASCII byte scan
   had accepted such matches since it shipped ("ab" matched in
   "ab\u{0301}"); fixed with one following-byte check on match, regression
   tests added. Backwards has no hole (its clean-suffix invariant already
   covers everything after the match).

---

### 29. Engine-gap decomposition: the core is at ICU parity; the gap was the entry

**Status:** measured 2026-07-12 (Intel, standalone WMO harness); stage 1
shipped, stage 2 prototyped pending an API decision.

A probe giving our engine ICU's exact calling contract (pre-pinned UTF-8
buffers, no String) measures **15–16 ns on ascii compare — identical to
ICU** in the same session. The entire "3×" was entry cost, decomposed by
adding one feature per probe (all numbers stable ±1 ns):

| layer | ns |
|---|---|
| engine core (bytes in) | 15 |
| + String→bytes unwrapping ×2 (small-string stack spill + closures) | 25 |
| + `throws` on the entry (the error ABI alone — **10 ns**) | 34 |
| + options parameter & word check | 42 |
| + cold-fallthrough frame | 44 |
| + remaining old-entry structure | 52 (= old Table 1) |

Also measured: the `-no-WMO` build workaround on machine 1 inflates Table 1
(cjk compare −16%, thai −20%, sortKeys −16..−26% under WMO — the shipping
config); the bench shell is 8 ns (ascii) to 14 ns (cjk, ARC on >15-byte
strings); and bench_matrix hands ICU a "th" collator on the thai row while
ours is root — root/root ICU is ~261 ns, so every thai ratio was slightly
flattering. Field-wise options comparison measures the same as the
`icuOptions` word rebuild — the cost is the parameter+branch, not the bit
packing.

**Shipped (stage 1, no API change):** hot/cold split of `compare` — the
default-options fast-Latin byte path in a non-throwing `compareFastPath`
returning `Order?`, thin throwing wrapper, slow path unchanged. Ascii/latin
52→45, paths −9%, cjk/thai neutral. Same commit: removed a duplicated dead
`unsafeStart` block in compareBody (double binary searches on every
shared-prefix compare); reordered `fastLatinUTF8` so lead-byte-ineligible
mismatches (all-Thai/CJK) bail before the isUnsafe binary searches (thai
−4-5%); word-wise UInt64 identical-prefix scan (paths −11-15%).

**Stage 2 (prototyped in the standalone, NOT shipped):** `@inlinable` on the
wrapper + fast path (+`@usableFromInline` on ~7 members): ascii/latin
45→31 ns for out-of-module callers — 1.9× vs ICU, ~10 ns of which is the
String-unwrapping floor. Needs a decision: ABI/API surface commitment vs a
win that only external-module callers see (same-module Foundation callers
already get stage-1 speed).

**Tried and reverted in the same round:** quick-primary CJK dispatch inside
the pinned-buffer closures (regressed cjk +9-40 ns under WMO — the
WMO-optimized compareBody path was already cheaper than the closure-context
dispatch).
