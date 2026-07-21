# Optimization Targets

> Living document. Ideas for further performance wins, tracked with status.

## Guiding principle

The pre-baked fast-Latin setup (−22% ASCII) showed the pattern: if something
is checked per-call but the answer is fixed at init, store the answer once and
skip the check. Look for more instances of this.

## THE ALLOCATION/RESOLUTION HUNT (the pattern that keeps paying — check
## every per-call path for it)

Three of the project's largest single wins came from the same shape of
defect and the same 30-minute method. **Any per-call path that has not
been through this audit is a suspect.**

**The defect shape:** work whose RESULT is identical (or near-identical)
across calls, redone per call — allocating a buffer, resolving a
locale/options/setup, hashing a string key, copying a fat struct. It
hides because each instance looks cheap and idiomatic in source.

**The three case studies:**
- **§30 storage boxes:** the 768-byte collator struct copied at every
  call boundary → one class reference. `localizedCompare` HALVED.
- **§37 search buffers:** three arrays malloc'd/freed per search() call
  (~40% of cjk search) → reused ScratchBuffers slots. Engine search
  −50%; the last sub-parity matrix cells flipped.
- **§38 locale resolution:** identifier scans + 2–3 string-keyed
  dictionary probes per compare(_:locale:) call → one-slot cache. Every
  explicit-locale row −190..250 ns; the last at-parity cell → 1.50×.

**The method (proven, ~30 min):**
1. Hold-loop the ONE operation (temporary bench hook or probe package;
   never committed) and `sample PID 10`.
2. Read "Sort by top of stack". The convicting symbols:
   `nanov2_malloc*/nanov2_free/tiny_malloc*` (malloc traffic),
   `swift_allocObject`, `Hasher.combine/_finalize` +
   `__RawDictionaryStorage.find` (string-keyed lookups),
   `swift_retain/release` in large blocks, `String.init`/
   `_uncheckedFromUTF8`/`hasPrefix` (string materialization),
   `swift_beginAccess`/`AccessSet` (exclusivity),
   `LockedState`/`os_unfair_lock` (per-call locking).
3. When possible, profile the CHEAP SIBLING of the expensive API
   (localizedCompare next to compare(locale:)) — the diff of the two
   profiles is a shopping list.
4. Fix by reuse: scratch-owned buffers (removeAll(keepingCapacity:)),
   one-slot caches keyed for a pointer-equality hit, init-resolved
   setups behind ONE reference (§31/§37 rule: hand state to hot entries
   as one class ref, never as multiple inouts — inout scopes are paid
   before any fast path runs).
5. Gate as always; certify unrelated rows per §34 before believing them.

**Calibration — when profiler samples are REAL vs phantom:** samples in
malloc/hash/lock/refcount chains convert to wall-clock nearly 1:1 (they
are serial dependencies — §37/§38 delivered what the profile promised).
Samples spread over independent cheap loads and branches DO NOT (the
out-of-order core runs them for free: the §35 unsafe-mask and §36
hasBuffered nulls both "showed" ~265 samples and delivered nothing).
Allocation/resolution samples are the trustworthy kind.

**Standing audit list (paths not yet through the hunt):**
- [x] §26 wrapper string conversions — AUDITED (§39): found and fixed a
      Substring index-space BUG in rebaseRange; duplicate conversions
      deduped. The one remaining Substring materialization is the
      engine's String input contract — accepted.
- [x] `confirmMatch`/`buildNFDSourceMap` — AUDITED (§41): the match
      tax on decomposing text was 7× a no-match scan, ~all allocator
      traffic (2 temporaries PER DECOMPOSING SCALAR + per-call map).
      Fixed: trie count twin + scratch-owned map; match tax −86%.
- [x] `isValidEndBoundary`/`isValidStartBoundary` walks — AUDITED
      (§42): whole-string count walk + up to three separate offset
      walks per confirmed match, fused into confirmMatch's index
      construction (one bounded walk). Match confirmations −17..19%;
      paths stdRange (frequent hits, long lines) −12% in the shipping
      build. The WMO inlining trap it exposed is §42's lesson.
- [x] String.Comparator / SortDescriptor / Predicate paths — AUDITED
      (§40): StandardComparator resolved Locale.current per comparison
      (~90 ns × n·log n in sorts) — fixed via collatorForCurrentLocale
      (287→229). String.Comparator clean; the others delegate.
- [x] CollationOptions.from + CompareOptions.init per call — AUDITED
      (2026-07-16): built the module WMO (build-only; the machine-1
      SIGILL is runtime-only) and swept every object file — the symbol
      does not exist and no call sites reference it. Fully inlined/
      constant-folded under WMO; the 85 §38-profile samples were a
      -no-WMO bench-build artifact (Docs/25 already documents that
      handicap). No code change. Verdict cost ~2–3 ns/call in the
      bench build only — not worth an API-side workaround.
- [x] sortKey entry ladder — AUDITED (§43, 2026-07-16): the entry is
      EXONERATED (TLS ~20 ns, throws ~0 — the §30 box already collected
      it, the standing "sortKey still pays throws" note was stale). The
      gap was the WRITER: 56–60% of sortKey on every corpus. SHIPPED
      2026-07-20: direct multi-pass writer — sortKey −11..16% on
      ascii/latin/cjk/thai (1.44–1.53× vs ICU, was 1.67–1.81×); paths
      +5% accepted residual (§43's paths saga). Ladder committed:
      `build_sk_ladder.sh`.
- [ ] UPSTREAM-PREP conformance pass (CONTRIBUTION_GUIDELINE.md, read
      2026-07-20; comment unwrap DONE at `05677e6`): remaining items —
      force unwraps (`base!` in the engine paths; the guideline wants
      guard/precondition shapes), §-reference comments (the guideline
      bans PR/bug-reference comments; ours point at the technique log —
      decide translate-or-strip before proposing), unsafe-API isolation
      review, and swift-benchmark entries under Benchmarks/. Not a
      bench item; schedule before the upstream proposal.
- [ ] The skRet variant allocates BY API CONTRACT (returns fresh
      [UInt8]) — documented, inout twin exists; not a defect.
- Machine 2: run the same audit over any AS-only wiring.
- [x] Locale-change invalidation — DECIDED + SHIPPED (§44, Docs/29):
      generation-count revalidation via LocaleNotifications (the
      documented Calendar/TimeZone mechanism; FE's counter made
      package-visible). Bench-build cost +15..18 ns on the localized
      compare rows (LockedState read; framework build = relaxed atomic
      ≈ free) — accepted, correctness contract. Regression test flips
      the current locale mid-process (suite now 1515/122).
- [ ] **BUG (found by §44's test, filed):** `compare`/`sortKey`/search
      entries default to `CollationOptions()`, NOT the collator's
      `defaultOptions` — so tailoring default SETTINGS (fr_CA
      backwardSecondary) never apply through the no-options Foundation
      wrappers; character-data tailorings apply fine. Diverges from
      Darwin for fr-CA current locale. Fix needs a decision: wrappers
      pass `collator.defaultOptions`, and the CompareOptions
      translation should MERGE onto that base rather than start fresh.
      Audit the fast-Latin defaultFLWord interaction (it is already
      baked from defaultOptions — the entries just never ask for it).
- UPSTREAM note (outside collation scope): the localized case-mapping
      entries at the top of StringProtocol+Locale.swift (capitalized/
      lowercased/uppercased with .current) evaluate Locale.current per
      call — the §40 shape exactly. Heavyweight operations, so
      proportionally smaller — flag in the upstream conversation, do not
      patch from here.

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

---

### 30. The 768-byte collator: receiver copies at every call boundary

**Status:** shipped 2026-07-13 (storage-box refactor + bench-harness fix).

Disassembly of the §29 probes answered "why does `throws` cost 10 ns": it
doesn't. RootCollator was a ~768-byte struct, and a method call materializes
`self` as a stack copy. Around a NON-throwing call in a loop the optimizer
hoists that copy out; around a THROWING call it cannot (the error edge
breaks the access-scope reasoning), so the bench loops re-copied 768 bytes
per iteration (`memcpy(stack, &collatorGlobal, 0x300)` visible per
iteration in the disassembly). A loop-local receiver restores the hoist:
the throwing probe drops 34→24 ns, within 1 ns of the non-throwing one —
`throws` itself costs ~1 ns, as the ABI predicts. Every previously recorded
Table-1 row (compare AND sortKey) carried ~10-12 ns of this artifact.

**Fixes shipped:**
1. BenchFoundation holds the collator in a loop-local `let` for the engine
   rows (the honest shape — real callers hold locals).
2. RootCollator's stored state moved into one `final class Storage`
   (immutable after init, @unchecked Sendable like the struct); the struct
   holds a single reference and forwards via computed properties. A
   RootCollator value is now one pointer: no more 768-byte traffic at ANY
   call boundary, including the CollatorCache fetch inside every Foundation
   String API call.

**Measured (Intel):** engine compare ascii 46→38-40, paths 109→98-99 (repo
harness); standalone WMO: global-receiver == local-receiver (36 vs 34), sk
ascii 395→348 (−12%), cjk cmp −3%, thai −2%, no regressions.
**`localizedCompare` HALVED: ascii 255-264→117-118 ns, paths 331-338→
183-186** — the cache fetch copied the collator per call.

**Upstream note:** the missed hoist (loop-invariant indirect-self copy
across a throwing call) is a reportable Swift optimizer limitation; reduced
test case = §29 probeA/probeA2 pair.

Remaining ascii-compare ladder after this: ~15 loop + ~10 String unwrap +
~8 residual ≈ 34-38 vs ICU 16.

---

### 31. Quick-primary CJK dispatch at the byte-scan mismatch (third attempt — shipped)

**Status:** shipped 2026-07-13. **cjk compare 232 → 82 ns (−65%): 3.2× behind
ICU → 1.13×.** Ascii/latin/paths +1–2 ns, thai neutral (lead-byte gate).

The §29-style probe ladder on the cjk corpus showed the minimal deciding
work — decode two scalars, compare their single-CE primaries — costs 21 ns
on pinned buffers (FASTER than ICU's whole 72 ns compare), while the
shipping path spent 232 ns rebuilding scalar iterators in compareBody to
re-derive what the byte scan already knew. The dispatch now runs inside the
pinned-buffer closures at fastLatinUTF8's mismatch offset.

Three lessons paid for twice (07-06 and twice today), now structural rules:
1. **The pinned-buffer closures may only call STATIC functions with trivial
   parameters.** An instance-method call there degrades codegen +17-22% on
   every corpus, even ones that never execute the new code.
2. **Fat by-value parameters on the shared hot call tax everyone.** The
   dispatch takes its init-resolved trie views (QuickCJKSetup) as ONE
   heap-boxed pointer, and lives in a SECOND static call that Latin-resolved
   compares never reach.
3. **Cold-path work must be gated before any decode:** a one-byte lead gate
   (CJK blocks start at 0xE3; Thai is 0xE0) keeps the thai bail-out free.

Also shipped: `quickPrimary` (instance and static twins) now handles the
**longPrimary** tag — the tag most real-world Han actually carries (the
bench corpus's rare ideographs are offset/implicit; common 日本中 are
longPrimary and previously always fell through to the full pipeline, both
here and in compareBody). Comparing actual primaries needs no §28
injectivity: equal primaries simply fall through. Eligibility is resolved
at init (no script reordering, non-shifted default); zh and shifted
collators skip the dispatch entirely.

---

### 32. Thai round plan (the last compare row above 2.5×) — untried

**Status:** planned 2026-07-13, not started. Thai compare 637 ns vs ICU 258
(2.47×, WMO EngineBench) — the one workload that runs the full CE pipeline
per call (marks, contractions, real normalization). Method: §29-style probe
ladder FIRST (pinned-buffer pipeline entry, then stage by stage) to
attribute the 379 ns before changing anything; EngineBench WMO A/B per
experiment.

Levers, in order:

1. **NFD mark pass-through for already-ordered marks** (est −60 ns/compare;
   also helps sortKey). In `NFDIterator.next()`, a non-decomposing scalar
   with ccc>0 currently routes through the full `refill()` buffering (unit +
   marks arrays, flushMarks sort) even when NO reordering can occur. When
   the current scalar has no decomposition, ccc(c)>0, and the PEEKED next
   scalar is a starter (leadCCC==0) or end-of-input, emit `c` directly and
   stash the peeked scalar in `pendingFirst` (mechanism already exists for
   quickDecomp). Fall back to refill() when two non-starters are adjacent
   or the mark decomposes. This mirrors ICU's FCD pass-through, which never
   buffers Thai marks. Correctness gate: full ICU-reference conformance run
   (433k lines) + fuzz keys — canonical ordering is where subtle bugs live.

2. **Thread-local scratch cost, quantify then maybe fix**: every pipeline
   entry pays takeScratch/giveScratch; estimates range 2–22 ns and it has
   never been pinned. Step 1: stub to a preallocated global (single-threaded
   bench only) and A/B the thai row. Step 2 (only if >8 ns): store the TLS
   value as an Unmanaged raw pointer so take/give become plain loads around
   pthread_getspecific, removing retain/release atomics.

3. **CE-buffer machinery** — `ces` array append + appendMore dispatch per
   scalar; attack informed by whatever the ladder attributes.

After thai, the standing queue: sortKey entry ladder (§29 never ran for
sortKey; it still pays throws + the ~22 ns reset), the five sub-parity
range-search cells (§28 audit or reuse QuickCJKSetup/longPrimary for search
CE production), stage-2 @inlinable (§29, awaiting the user's API decision),
and the Swift optimizer report (§30; reduced test case reproducible from
§29's probeA/probeA2 description).

---

### 33. Cross-machine divergence: CE-array parameter shape in the sort-key writer

**Status:** RESOLVED 2026-07-15. `borrowing [Int64]` shipped (`44c9497`).

Machine 2's `3aaa1d5` changed `writeSortKeyUpToQuaternary`'s `ces`
parameter `[Int64]` → `UnsafeBufferPointer<Int64>`, wrapping the (only)
call site in `withUnsafeBufferPointer`, to remove a per-call retain/release
pair on the Array storage. Their measurement (Apple Silicon, 6.4, WMO
EngineBench): sortKey −2..−4% (ascii 202→194, latin 218→213, cjk 213→207,
paths 453→441), 1511 tests pass.

On Intel/6.3.1 the same commit is a consistent sortKey REGRESSION.
Interleaved A/B (pre-fix `f3acf29` binary vs `3aaa1d5` binary, six
alternating rounds across two sessions, min per binary, WMO EngineBench):

| corpus | sk pre-fix | sk 3aaa1d5 | Δ | skRet pre | skRet 3aaa1d5 |
|--------|-----------:|-----------:|---|----------:|--------------:|
| paths  | 796 | 879 | **+10%** | 1023 | 1091 |
| thai   | 508 | 532 | +4.7%    | 676  | 696  |
| ascii  | 337 | 348 | +3.3%    | ~505 | ~502 |

compare identical (86–87 paths) on all binaries — clean control. Cause
hypothesis: the call-site closure blocks WMO from inlining the writer into
`sortKey`, so the entire key-writing loop runs de-optimized — cost scales
with key length, which is why paths (longest keys) hurts most. This
generalizes §31 lesson 1 beyond the pinned-buffer closures: **on
6.3.1/Intel, a closure wrapping a hot call site is a codegen hazard even
outside compare.**

**Resolution: `ces: borrowing [Int64]`** — direct call, no closures.
`borrowing` is an explicit +0 pass. Intel: regression fully erased (paths
798 vs 796 pre-fix). **Machine 2 verification (Apple Silicon 6.4):**
`borrowing` is a no-op — optimizer already eliminates the retain/release
for the direct `[Int64]` parameter under WMO (ascii 200 vs 198, paths
454 vs 453 — identical within noise). The ARC pair that `3aaa1d5`
measured was an artifact of the earlier session's thermal state, not a
real per-call retain. `borrowing` is the correct neutral choice: it
prevents Intel's closure regression while being a no-op on Apple Silicon.

Same-day re-baseline at `3aaa1d5` (K=3, run_benchmarks.sh, this machine):
compare rows match Docs/25 within noise (ascii 36, latin 35, cjk 83,
paths 86, thai 636); the sortKey rows carry the regression above (ascii
347, latin 376, cjk 366, paths 883, thai 516). Docs/25's Table 1 is
deliberately NOT updated until the parameter-shape decision lands.

---

### 34. §32 thai round, part 1: probe ladder, NFD mark pass-through, and the alignment trap

**Status:** shipped 2026-07-14. Gates: 1511 tests / 120 suites green (incl. 433k-line conformance + 52k fuzz keys).

**Ladder (thai corpus, WMO, ns/compare-pair; probes in a scratch package,
repo untouched):** P0 full compare 639 (EngineBench same session 631 ✓);
P1 compareBody direct 597 → entry+byte-scan ≈ 42; P2 scalar skip-walk alone
126; P3 scratch take/give 5 (settles §32 lever 2: below the 8 ns action
threshold, estimate range was 2–22 — NO Unmanaged-TLS work needed);
P4 pipeline core (skip+reset+compareUpToQuaternary, scratch hoisted) 570;
P5 NFD drain both strings 345; P6 P5+collectAll 549 (CE production ≈ +200).

**Skip-walk statistics (P7):** 99% of adjacent pairs share a prefix (avg 3.3
of 6.8 scalars), but 88% hit the unsafe-start fallback and re-iterate from
zero — Thai consonants and า are contraction continuations (unsafe), so a
safe restart deeper than 0 exists in only 45% of prefix pairs at avg depth
1.9. ICU-style partial backup is NOT the gap (ICU has the same fallback and
still runs 258); the 126 ns walk being duplicated byte-scan work remains a
follow-up lever (byte-mismatch handoff).

**Lever 1 shipped shape:** lone-mark pass-through at refill()'s head — a
non-decomposing ccc>0 scalar whose peeked follower starts with ccc 0 (or
EOI) becomes the unit directly (no absorb/flushMarks, no carried round
trip), follower stashed in pendingFirst. All guards from one norm.value()
lookup. next() stays byte-identical so no other corpus can be affected by
construction. sawDecomposition stays false (output 1:1 — also helps
search's lazy position path on Thai).

**Shapes tried and rejected (all measured, quiet machine, interleaved):**
inline branch in next() (+58 paths sk), @inline(never) mutating helper
called from next() (+50 paths sk), refill-head + @inline(never) refill
(identical to refill-head alone — the attribute did nothing measurable).

**THE ALIGNMENT TRAP (bench-truth finding, applies to all Intel WMO paths
sortKey verdicts):** every variant showed paths sk +50..65, yet paths never
executes any new code. sample-profiler diff put the entire delta inside
writeSortKeyUpToQuaternary; otool disassembly showed its 2585 instructions
BYTE-IDENTICAL between PRE and variant binaries — only the function's start
address shifted (NFDIterator.swift precedes SortKey.swift in the WMO
emission order, so any size change upstream moves the writer's loop
alignment). A null-change probe (same-size dead function) landed clean,
which first looked like semantic causation — alignment is chaotic like
that. ALSO: WMO builds of identical sources are NOT bit-identical
(__TEXT differs, behavior equal), so whole-binary hashes prove nothing.

**RULES going forward:**
1. An Intel WMO paths-sortKey delta within ±7% is UNTRUSTWORTHY until the
   hot function's instruction stream is diffed (otool -tv, addresses
   stripped). Identical instructions = alignment luck, not a regression.
2. This puts an uncertainty band on §33's Intel magnitude (+10% paths for
   the UnsafeBufferPointer shape) — §33's writer instructions genuinely
   differed (parameter + closure), so the mechanism stands, but part of the
   magnitude may be alignment.
3. Machine 2 (Apple Silicon) should sanity-check paths sk for this commit;
   AS is far less alignment-sensitive.

**Final numbers (WMO EngineBench, quiet machine, min of 3 interleaved
rounds vs unchanged tip; writer instruction-certified before measuring):**

| corpus | cmp pre | cmp new | sk pre | sk new | skRet pre | skRet new |
|--------|--------:|--------:|-------:|-------:|----------:|----------:|
| thai   | 643 | **615** | 510 | **486** | 684 | **664** |
| ascii  | 36  | 36  | 339 | 339 | 491 | 498 |
| latin  | 36  | 36  | 370 | 370 | 511 | 513 |
| cjk    | 81  | 81  | 368 | 363 | 578 | 574 |
| paths  | 86  | 87  | 804 | 851* | 1012 | 1057* |

\* alignment shift, certified: writeSortKeyUpToQuaternary's 2585
instructions byte-identical, start address moved (rule 1 above).

Thai engine compare 643→615 (2.45×→~2.37× vs ICU 260), sortKey −5%.
Modest vs the §32 −60 estimate: marks are only ~2/word; the remaining gap
is CE production (~200 ns, §32 lever 3 — Thai-block simple-CE table and a
buffer-free single-step contraction match are the designed next attacks)
and the duplicated skip-walk (~126 ns, byte-mismatch handoff).

---

### 35. §32 thai round, part 2: Thai simple-CE table and the walk-skip

**Status:** shipped 2026-07-15 (`4a73ada` lever 3a, `26e340f` lever 3b).
Gates: 1511 tests / 120 suites green after each (incl. 433k conformance +
fuzz keys). All numbers WMO EngineBench, min of 3 interleaved rounds,
writer instruction-certified per §34 before every paths verdict.

**Re-attribution after §34** (committed ladder, `build_thai_ladder.sh`):
P0 579 / P1 522 / P2 skip-walk 123 / P3 scratch 6 / P4 core 495 /
P5 NFD 306 / P6 +CE 426 — CE production down to ~120 (was ~204), NFD
front end the largest remaining item.

**Lever 3a — Thai-block simple-CE table (`4a73ada`):** second 128-entry
init-built table (U+0E00–0E7F) beside the ASCII one (`buildSimpleCEs`
generalized with a range offset). Consonants and tone/vowel marks are
single simple CEs → skip trie walk + appendCEs dispatch. Specials
(prefix-vowel contractions, digits) stay 0 sentinels → full path, so the
contraction/numeric machinery is untouched. appendMore's new branch sits
after the ASCII fast path; ASCII returns before it, other scripts pay one
wrapped-subtract compare. **thai compare 608→557 (−8%), sortKey 482→451
(−6%); ascii/latin/cjk neutral; paths inside the certified band.**

**Lever 3b — walk-skip (`26e340f`):** §34's P7 showed 88% of thai pairs
end the identical-prefix walk in the shared=0 unsafe fallback. The byte
scan already delivers the mismatch offset (it feeds quickCJKDispatch,
incl. on the all-Thai bail at the lead-byte gate); a static
`mismatchRestartIsUnsafe` helper (§31 shape) backs up to the scalar start — one
backup serves both sides, prefix bytes being equal — decodes the two
first-differing scalars, and checks restart safety. Unsafe → compareBody
takes the fallback exit directly (identical behavior, no walk). Hint
threads compare → slowPath → body; non-default options and bridged
strings never compute it. `NFDIterator.reset` needed `@inline(__always)`
back (fell out of line after the restructure — profile-confirmed).
**thai compare 563→546; everything else neutral.**

**Probe-ceiling lesson (bench truth):** ladder P8 (pipeline with no walk)
promised ~−110; the shipped lever delivers −17. In context the walk is
far cheaper than standalone — it pre-warms the exact bytes the pipeline
re-reads, and the restart-safety searches move into mismatchRestartIsUnsafe rather
than disappear (sample profile: compareBody 1078→463, mismatchRestartIsUnsafe +265,
fastPath +75). Standalone probe deltas are CEILINGS, not estimates, when
the deleted work shares memory traffic with what remains.

**Round state:** thai compare 637 → ~546 (−14%, 2.47×→~2.10× vs ICU
258–260), sortKey 513 → ~452 (−12%). Cross-day absolutes drift a few ns
with machine load; per-day interleaved pairs are the record.

**Tried and reverted — Thai unsafe-mask (2026-07-15, same day):** a
128-bit init-built restart-safety mask for U+0E00–0E7F, fed to
mismatchRestartIsUnsafe as two UInt64 parameters, to replace its isUnsafe
binary searches (~265 profile samples). Measured: thai compare −4
(noise level — the out-of-order core hides those searches behind the
surrounding work; leaf-profile samples overstate their wall-clock cost)
while **every other corpus's compare paid +5..+9 ns** (ascii/latin 35→42,
cjk 81→90, paths 86→91 — consistent across rounds). §31's rule,
sharpened: **the pinned-buffer closure context is codegen-fragile; even
two extra property reads captured into it tax all corpora.** New data may
enter the fast path only through the existing boxed setup pointer — and a
−4 ns lever justifies nothing. (Also renamed: walkIsUseless →
mismatchRestartIsUnsafe.)

**Next, in order:**
1. **NFD per-scalar floor (306 ns both strings):** the String scalar
   iterator itself — the parked Span-based pipeline refactor (HANDOFF
   backlog; high risk, blocked on toolchain ergonomics). This is the
   remaining thai gap; the cheap levers are exhausted.
2. Buffer-free single-step contraction match for the prefix vowels —
   demoted: the remaining CE share (~120) caps it well under the earlier
   estimate, against the S2.1 machinery's correctness risk.

---

### 36. The NFD per-scalar floor: decomposed — Span refactor RETIRED

**Status:** investigated 2026-07-15 (ladder probes P5a–P5d, two null
experiments). No code shipped; the ladder probes are committed. The
"Span-based CE pipeline refactor" (HANDOFF backlog, Docs/16 §9.6/§10,
"potential −30–40% CJK/Thai") is RETIRED on the evidence below.

**Floor decomposition (thai corpus, both strings, WMO ladder):**

| probe | ns/pair | meaning |
|---|---:|---|
| P5a raw String scalar iteration | 58–60 | 4.4 ns/scalar — the iterator is cheap |
| P5b + isInert per scalar | 67–72 | the trie hit adds ~0.9 ns/scalar |
| P5c hand-decoded UTF-8 bytes | 124–126 | the "byte floor" is SLOWER than the String iterator |
| P5d full NFD drain, local iterator | 195 | machinery = ~128/pair ≈ 9.5 ns/scalar |
| P5 same drain via class-stored scratch | 298–306 | probe-shape exclusivity tax ~103 (real pipeline pays ~3% — it passes the iterators inout) |

Docs/16's premise — that `String.UnicodeScalarView.Iterator` ARC/overhead
is the hidden cost a Span/byte front end would eliminate — is a phantom on
this toolchain: the iterator runs at 4.4 ns/scalar and beats a hand-rolled
byte decoder. There is nothing for Span to win back; the refactor's
estimate inherited a 2026-06 profile misread.

**Null experiment 1 (unsafe-mask, §35):** already recorded — leaf-profile
samples of independent loads overstate wall-clock.

**Null experiment 2 (hasBuffered dispatch flag, same day):** collapsing
next()'s three buffer checks (pendingMark / unit / carried) into one
maintained flag measured ±5 ns on every corpus (writer-certified). The
three checks are independent L1-hot loads the out-of-order core already
runs in parallel; the dispatch head costs nothing.

**Conclusion:** the remaining thai engine gap (~530 vs ICU ~260) is
per-scalar serial dependency chains (optional unwrap → trie load →
branch → append), not any removable layer. No cheap lever remains; a
batched/fused pipeline redesign is the only shape that could attack it,
and with thai `localizedCompare` already 1.53× FASTER than system ICU the
engine row is bragging rights, not user-visible cost. Next frontiers per
the standing queue: the two cjk range cells (0.84×) and the sortKey entry
ladder (§29 never ran for sortKey).

---

### 37. Allocation-free search: the cjk range cells flipped

**Status:** shipped 2026-07-16. Gates: 1511 tests / 120 suites green.

**Attribution (engine-level cjk search probe, `build_cjk_probe.sh`, WMO;
sample profile):** searchForward 1264 + pattern produceMaskedCEs 903
samples — and ~2400 samples of allocator traffic (nano malloc/free,
swift_allocObject, refcount, malloc-type cache). Every search() call
allocated the pattern CE array, the annotated text-CE window (with a
~1 KB reserve), and contains' text buffer, then freed them. The CE
arithmetic itself (appendCEs + offset math) was ~430 samples. The
standing-queue guess (quickPrimary prefilter for search CE production)
was aimed at the wrong block.

**Shipped shape:** three reusable buffers on ScratchBuffers (patternCEs,
annotatedCEs, maskedTextCEs); the search/searchBackwards/contains entries
take the scratch as ONE class reference; producers fill caller-owned
arrays (removeAll(keepingCapacity:) + reserve, §14 discipline). First
attempt passed the buffers as three inout parameters — that opened
exclusivity scopes at the call boundary and cost the BYTE-SCAN corpora
(ascii/paths range) +30..40 ns despite never touching the buffers;
the class-reference shape opens scopes only after the byte scan bails.
Rule: **hand thread-local state to search entries as one reference, not
as per-buffer inouts — inout scopes are paid before the fast path runs.**

**Measured (BF -no-WMO, min of 3 interleaved rounds; engine probe WMO):**

engine cjk search/line: 863 → 410–440 (−50%).

| corpus | contains | stdRange | range fwd | range back |
|--------|---------:|---------:|----------:|-----------:|
| cjk    | 1042→679 | 1150→744 | **1526→1073** | **1520→1065..1235** |
| ascii  | 895→546  | 993→617  | 466→456 | 472→466 |
| latin  | 957→570  | 1066→661 | 1394→988 | 1339→931 |
| paths  | 999→574  | 1362→929 | 589→582 | 647→640 |
| thai   | 846→558  | 1366→989 | 1472→1148 | 1370→1046 |

Against system ICU (cjk range 1312/1331): the LAST two sub-parity cells
in the matrix flipped to ~1.2× faster. Every search-family row improved
30–45% except the byte-scan range rows, which are neutral by design.

**Closed 2026-07-16:** Docs/25 re-baselined (coherent K=3 at `1b43bbc`) —
zero cells behind system ICU on either machine. Table 1 certified
unchanged post-§37 (compare ±2 mixed-sign = noise; paths sortKey inside
the §34 band with the writer's instruction stream byte-identical).
Machine 2 confirmed §37 on Apple Silicon (−29..35%) and resolved §33
(borrowing neutral on 6.4 — correct cross-platform shape, no fallback).

---

### 38. One-slot locale-resolution cache: the explicit-locale wrapper tax

**Status:** shipped 2026-07-16. Gates: 1511 tests / 120 suites green.

compare(_:locale:) cost 409 ns on ascii while localizedCompare cost 118 —
same 36 ns engine compare underneath. Profile (holdcmp loop, -no-WMO):
the gap was per-call locale resolution — locale.identifier
materialization, resolveLanguage's hasPrefix/contains scans + substring,
2–3 string-keyed dictionary probes under the cache lock, plus
retain/release churn (~400 samples) and Hasher work (~215).

**Shipped:** a one-slot (identifier → collator) cache in CollatorCache,
checked before full resolution. Callers overwhelmingly pass the same
Locale repeatedly; comparing its identifier against the slot hits the
String pointer-equality fast path, so a repeat resolves in lock +
compare + return. range(of:locale:)/range(backwards) share collator(for:)
and inherit the win.

**Measured (BF -no-WMO, min of 3 interleaved rounds; flat ~−200 ns on
every explicit-locale row):**

| corpus | compare(locale:) | range fwd | range back |
|--------|-----------------:|----------:|-----------:|
| ascii  | 409→219 | 454→263 | 459→268 |
| latin  | 416→222 | 1022→787 | 1109→885 |
| cjk    | 478→284 | 1077→854 | 1240→992 |
| paths  | 511→313 | **579→391** | 636→442 |
| thai   | 1064→838 | 1069→850 | 1208→976 |

paths range(of:) — the matrix's last at-parity cell (0.99×) — flips to
**1.50× ahead** (391 vs system 587); ascii range to ~2.2×; cjk range to
~1.53×/1.33×. The residual compare(locale:)-vs-localizedCompare gap
(~100 ns) is the options translation + the heavier generic entry — the
honest remaining wrapper cost. Docs/25 tables not yet re-baselined with
§38; the §37 run (`1b43bbc`) predates it.

---

### 39. Wrapper-string audit: a Substring index-space BUG, not a perf item

**Status:** shipped 2026-07-16. Gates: 1514 tests / 121 suites green
(the original 1511 + three new regression tests).

The first box on the ALLOCATION/RESOLUTION HUNT audit list (§26 wrapper
string conversions) turned up a wrong-answer bug instead of nanoseconds:
`rebaseRange` mapped the search result's offsets into a FRESH
`String(self)` copy and returned that copy's indices as `Self.Index`.
For String receivers the copy shares identity — harmless. For SUBSTRING
receivers, whose indices are base-string-relative, every
`localizedStandardRange`/`range(of:locale:)` result was misaligned by
the substring's start offset. Never caught because tests and benches
always used whole Strings (SubstringReceiverTests now covers it).

**Fix:** rebase in self's OWN index space with scalar-offset math
(matching the scalar-aligned indices the search produces), via
`unicodeScalars.index(_:offsetBy:limitedBy:)` from `startIndex` (or the
searchRange base). This also deletes the `String(self)` inside
rebaseRange and the duplicate conversion in localizedStandardRange — the
dedupe fell out of the correctness fix.

**Perf side (holdsub probe, -no-WMO, Substring receivers):** stdRange
632→620 ascii / 728→714 cjk; ranged range(of:) 285→282 / 887→877. The
remaining Substring cost (~+50 vs String receivers on compare) is the
one required materialization — the engine takes String; removing that
means a generic pipeline (not worth it; see §36's dependency-chain
verdict).

**Audit-list lesson:** the box was filed as a ~50 ns cleanup; the audit
found a correctness bug that no benchmark could ever show. Working the
list pays even when the nanoseconds don't.

---

### 40. Comparator audit: Locale.current per comparison in StandardComparator

**Status:** shipped 2026-07-16. Gates: 1514 tests / 121 suites green.

Second box on the hunt list (Comparator/SortDescriptor/Predicate paths).
Attribution rows (BF -no-WMO, ascii): String.Comparator.compare 197 ns
(stored locale — §38's slot absorbs resolution); StandardComparator
.localizedStandard **287 ns** — it resolved `collator(for: .current)`,
evaluating the Locale.current accessor PER COMPARISON (~90 ns), which
sorts multiply by n·log n. SortDescriptor/KeyPathComparator/Predicate
have no resolution of their own — they delegate to these two.

**Fix (one line × two build branches):** use
`collatorForCurrentLocale()` — the same cached current-locale resolution
the localized* String APIs use. **287→229 (−21%)**, String.Comparator
unchanged (control). The remaining +60 vs the direct
localizedStandardCompare API (~170) is options translation + protocol
dispatch + the cache lock — accepted floor without struct-side caching
on the public Codable comparator types.

**Bench-truth incident worth remembering:** the first two attribution
attempts silently measured a STALE binary — the temp hook had a compile
error swallowed by `>/dev/null`, `set -e` masked by an `&&` list, and a
`strings`-based hook check that can never work (Swift packs ≤15-byte
literals inline, invisible to `strings`). Rules: never bench a probe
binary without seeing its build stderr, and verify hooks by their OUTPUT
ROWS, not by binary inspection. (This also means §38's holdcmp loop
never fired — its attribution stands anyway: the sample window landed on
the compare(locale:) phase of the normal run, and §38's A/B verdict was
measured on the real APIs, not the hook.)

---

### 41. nfdMap: the match-confirmation tax on decomposing text

**Status:** shipped 2026-07-15 (machine 1). Gates: 1514 tests / 121
suites green. Probe committed: `build_accented_probe.sh`
(accented-probe/main.swift — the A/B/C workload below).

Next box on the hunt list: `confirmMatch`/`buildNFDSourceMap`. The path
fires only when a search on DECOMPOSING text reaches a full CE match —
which is why the benchmark matrix never showed it: ascii/paths are
handled by the byte scan, cjk/thai text does not decompose
(`sawDecomposition` stays false, NFD offsets are identity), and the
latin corpus row searches line 1's prefix in all 200 lines, so ~1 line
in 200 pays it. Real-world accented Latin (French, German, Vietnamese
…) with a matching needle — the common `localizedStandardRange` case on
non-English text — pays it on EVERY hit. A user-facing latency defect
sitting in the matrix's blind spot.

**Workload (new probe, engine-level, full WMO, bench-accented-64,
K=9):** per-line search, three variants — A: needle = that line's last
8 chars (full CE scan, then match); B: needle = first 8 chars (instant
match); C: needle absent (full CE scan, no match — the control).
Hook premise verified by output rows: hits A=200/200, B=200/200, C=0.

| variant | ns/op | pays |
|---|---:|---|
| C absent (control) | 3 024 | full-line CE scan, no map |
| B start-match | 16 057 | ~8-char CE scan + map build |
| A end-match | 21 293 | full-line CE scan + map build |

A successful match costs **~18 µs over the no-match scan of the same
line — 7×**. B is the smoking gun: an instant position-0 match still
pays 16 µs, because `buildNFDSourceMap` walks and allocates over the
WHOLE text regardless of where the match sits.

**Profile conviction (hold-loop B, `sample` 10 s, ~10 k busy-thread
samples):** ~4 800 samples in allocator/refcount leaves — nanov2
malloc/free 1 864, allocObject/slowAllocTyped 661, malloc-size/
type-cache 678, retain/release/dealloc ~1 100, array-grow
(`_consumeAndCreateNew`) 203 — the trustworthy serial kind (§ hunt
calibration). Plus 479 in `UnicodeScalarView.distance` (the
`reserveCapacity(text.unicodeScalars.count)` walk is O(n)), ~630 in the
map-build body (enumerated iteration + append), and ~900 in dyld
platform-version checks (`_availability_version_check`,
`os_system_version_get_current_version`, `dyld_get_*_platform`) sitting
under the typed-malloc descriptor path — i.e. MORE allocation traffic
in disguise; verify they vanish with the allocs post-fix. Source: the
`[Int]` map is one alloc per call, but the loop body allocates TWO
fresh `[UInt32]` temporaries (`decomposed`/`fullyDecomposed`) per
decomposing scalar — ~128 malloc/free pairs per 64-char accented line.

**Fix shape (decided from the nfd trie layout):** the temporaries can
be deleted outright, not scratch-pooled — the map only needs the
decomposition COUNT per source scalar, and the trie entry encodes it
directly (`(value >> 16) & 7`; length-7 = Hangul, arithmetic 2/3; else
the pool slice is readable in place for the second level). Plan:
1. count-only twin of `appendDecomposition` on `NormalizationData`
   (mirrors it exactly so the two can never drift);
2. `buildNFDSourceMap` fills a scratch-owned `nfdSourceMap` slot
   (`removeAll(keepingCapacity:)` + reserve, §14/§37 discipline),
   threaded as inout past the byte scan like the window buffer, with a
   local `built` flag replacing the Optional;
3. drop the O(n) `unicodeScalars.count` reserve walk (reserve
   `min(utf8.count, 1024)` like the window; warm after first use).

**Measured (same probe, engine-level full WMO, accented-64, K=9):**

| variant | before | after | Δ |
|---|---:|---:|---|
| A end-match | 21 293 | **5 617** | **−74%** |
| B start-match | 16 057 | **2 551** | **−84%** |
| C absent (control) | 3 024 | 3 029 | neutral ✓ |

The match tax (A−C) fell 18.3 µs → 2.6 µs (**−86%**), and an instant
match (B) is now cheaper than a full no-match scan, as it should be.
Post-fix re-sample of hold-B: ZERO allocator samples — nanov2/
allocObject/malloc-type AND the ~900 dyld platform-version samples all
gone (confirming the latter were typed-malloc descriptor overhead, not
a real availability check in our path). The profile is now real work:
the trie count walk (buildNFDSourceMap 1 418 + fullDecompositionCount
1 328 — note the loop runs ~6× more iterations/sec post-fix, so
same-code sample counts are not comparable across the two profiles),
CE production, and the follow-up below.

**Follow-up surfaced by the post-fix profile:** `isValidEndBoundary`
does `scalarOffset >= scalars.count` — an O(n) UnicodeScalarView walk
per confirmed match, now the top remaining match-tax leaf
(`UnicodeScalarView.distance` 1 349 samples in hold-B; it then walks
AGAIN to the offset). Restructure to a single bounded walk
(`index(_:offsetBy:limitedBy:)` shape). Filed on the audit list; not
folded into this box to keep the attribution clean. The whole-text map
walk for a position-0 match (truncate at the candidate's `nfdEnd`) is
the second-order item behind it — only worth it once the boundary walk
is gone.

**Certification (BF -no-WMO, base `78ccaa8` vs §41 at the same build
recipe, interleaved K=3, cjk + paths):** all 24 rows within ±2.6%
mixed-sign — the added searchForward/searchBackwardMatch inout
parameter and the ScratchBuffers field are free on the standard
corpora (the inout scope opens only after the byte scan, per the §37
rule). The full-matrix drift vs `1b43bbc` on rows no code touched
(contains/localizedCompare +20–50 ns) appears in BOTH A/B sides —
inherited -no-WMO placement/run variance from the §38–§40 span, not
§41; the A/B is the proof. Binaries positively identified by nm symbol
check (fullDecompositionCount: new=1, base=0 — nm, never `strings`,
§40 rule). Table 1 engine rows: compare/sortKey call graphs untouched
by construction; matrix deltas vs `1b43bbc` ±4% mixed-sign, within the
§34 placement band.

---

### 42. Boundary-walk fusion in confirmMatch — and the WMO inlining trap

**Status:** shipped 2026-07-16 (machine 1). Gates: 1514 tests / 121
suites green.

The §41 follow-up box. Attribution came free with §41's post-fix
profile (hold-B): `UnicodeScalarView.distance` 1 349 samples — that is
`isValidEndBoundary`'s `scalarOffset >= scalars.count` check, a
WHOLE-STRING walk per confirmed match — plus the validator bodies and
`index(offsetBy:)`. In total the old tail walked the text up to four
times per match: count walk, start-boundary walk, end-boundary walk,
then index construction again for the returned range.

**Fix, part 1 — fusion:** boundary validation folded into the index
construction confirmMatch already does: ONE bounded walk to the start
offset (`index(_:offsetBy:limitedBy:)`), boundary-check the scalar
there, short hop to the end offset, boundary-check there. A boundary
is valid when its scalar is a starter (ccc 0) or sits at the text's
edge — semantics unchanged, case-by-case equivalent on all reachable
inputs. Both validators deleted.

**The trap this exposed (the reason to always carry a control
variant):** the first build IMPROVED the match variants but regressed
the absent-control +9% — consistently, across interleaved rounds. nm
told the story: in the base binary confirmMatch has NO symbol (WMO
inlined it fully into the scan loops); with the fused tail the
function grew past the inlining threshold, stopped inlining, and the
hot fail-fast CE-equality loop — which runs at EVERY candidate
position — paid an 11-argument function call per candidate.

**Fix, part 2 — the §29 hot/cold split, again:** the equality head
stays in confirmMatch (tiny, inlines away — 0 symbols, verified); the
once-per-match range construction moved behind `@inline(never)
confirmedRange`. The control then came back BETTER than base: the
head-only function is smaller than the original, whose inlined tail
had been bloating the scan loops all along.

**Measured (engine probe, full WMO, accented-64, interleaved K=3
mins; `build_accented_probe.sh`):**

| variant | base (§41) | §42 | Δ |
|---|---:|---:|---|
| A end-match | 5 624 | 4 685 | **−16.7%** |
| B start-match | 2 542 | 2 060 | **−19.0%** |
| C absent (control) | 3 026 | 2 818 | **−6.9%** |

**Shipping build (BF -no-WMO, interleaved K=3, cjk + paths):** all
rows neutral (±2.2% mixed-sign) except **paths localizedStdRange
963→845 (−12.3%)** — a real matrix-visible win: stdRange is never
byte-scan eligible (case/diacritic-insensitive strength), the paths
needle hits many lines (shared path prefixes), and every hit paid the
whole-line count walk on the corpus with the longest lines. Docs/25's
`13337d4` tables predate this row change; fold at the next coherent
re-baseline (expected paths stdRange speedup ≈1.69×, was 1.46×).

**Bench-truth incident (the §40 trap, new variant):** the first §42
A/B base binary was silently PRE-§41 — the §41 certification had built
base sources into `.build` last and never rebuilt. Caught by binary
size, confirmed by nm (no fullDecompositionCount symbol). Rule
addition: **an A/B that builds the base into `.build` leaves `.build`
stale — symbol-verify BOTH sides of every A/B before running, and
rebuild `.build` after certification.**

**Lessons recorded:** (1) growing a hot function's cold tail can
silently un-inline the hot head under WMO — watch symbol
appearance/disappearance with nm, split hot/cold when it happens;
(2) the probe's absent-control variant is what caught it — every
match-path probe needs a no-match control; (3) the remaining
match-confirmation cost is now the map walk itself (§41's noted
second-order item: truncate at the candidate's nfdEnd) plus one
unavoidable bounded walk for index construction.

---

### 43. sortKey decomposition: the entry is exonerated; the writer IS the gap

**Status:** SHIPPED 2026-07-20 (machine 1) — lever (a), the direct
multi-pass writer. Gates: 1514 tests / 121 suites green on the wired
writer (byte-identical key suites: 21 option sets × 2 data variants vs
ICU reference answers + 52k fuzz keys), plus the probe's own
option-matrix identity check (8 sets incl. french/shifted/upperFirst:
0 mismatched lines on every corpus). Ladder committed:
`build_sk_ladder.sh` (sk-ladder/main.swift; stage clones verified
byte-identical to the public entry over each corpus before timing).
Shipped shape and the paths saga below, after the attribution record.

The §29-style entry ladder that never ran for sortKey. Stages: S0
public `sortKey(for:into:)`, S1 caller-held scratch (S0−S1 = TLS),
S2 non-throwing clone (S1−S2 = throws structure), S3 reset+collectAll
only, S4 writer only on pre-collected CEs (verbatim buffer state,
sentinel included), S5 reset only.

**Measured (engine ladder, full WMO, K=9 min, ns/op, 2026-07-16):**

| stage | ascii | latin | cjk | paths | thai |
|---|---:|---:|---:|---:|---:|
| S0 public | 354 | 388 | 381 | 848 | 511 |
| S1 no-TLS | 332 | 369 | 365 | 805 | 493 |
| S2 no-throws | 344 | 378 | 366 | 850 | 499 |
| S3 pipeline only | 112 | 127 | 156 | 367 | 210 |
| S4 writer only | **208** | **220** | **179** | **429** | **292** |
| S5 reset only | 20 | 20 | 24 | 45 | 36 |
| *ICU whole sortKey* | *194* | *208* | *222* | *671* | *270* |

**Findings:**
1. **Entry exonerated:** TLS take/give ≈ 20 ns, throws ≈ 0 (S2 lands
   ABOVE S1 — inside codegen wobble; the §30 storage box already
   collected the "throws tax", which was always the struct copy), glue
   ≈ 10. The §29-for-compare story does not repeat; the standing
   "sortKey still pays throws + reset" queue note was stale.
2. **The writer is the whole gap:** 56–60% of sortKey everywhere; on
   ascii the write phase alone (208) exceeds ICU's entire
   ucol_getSortKey (194) while the CE pipeline (112) fits comfortably
   inside it.
3. **Writer profile (hold-loop S4 ascii, `holdS4` arg, 10 s sample):**
   ZERO allocator traffic (the §14/§37 warm-buffer discipline holds) —
   not an allocation box. Split: ~41% core level-byte logic, **~35%
   Array append machinery** (append(contentsOf:) 252 samples,
   replaceSubrange 142, memmove 150, uniqueness checks 111 +
   capacity/mutation helpers ~90), ~14% ARC + exclusivity on the level
   buffers.

**Levers (round plan, by expected value):**
- **(a) Writer redesign to the ICU shape** — ONE output buffer, one
  pass per level written directly into it; eliminates the intermediate
  level buffers and the final assembly. Attacks the 35% machinery
  share plus part of the core. Gated hard by the byte-identical-key
  suites — safe to experiment with, unsafe to ship without them.
- **(b) ARC/exclusivity shave** on the level-buffer plumbing (~14%,
  §37-style single-reference discipline).
- **(c) TLS ~20 ns** — parked on the §21 CoreOS reserved-key ask.

**Dead ends that bound this round (do not re-attempt):** §15 fusing CE
production into the writer (rejected, +11..44%); §16 raw pointers for
the key byte loop (aliasing reloads beat Array); §33's call-site
closure shape (blocks WMO inlining of the writer on 6.3). §34's
alignment band applies to ANY paths-sortKey delta measured under WMO.

**SHIPPED (lever (a)): `writeSortKeyUpToQuaternaryDirect`** — one pass
per level written straight into the key through the 64-byte stack-batch
idiom (the §31 primary batching generalized): no intermediate level
buffers, no assembly copies, nibble packing inline for the case level,
French backwards-secondary written per byte with in-place segment
reversal in the key. Each pass replicates the variable-CE skip exactly
(the primaries those tests depend on — zero, NO_CE, merge separator —
are reorder-invariant, so per-pass un-reordered p is sound). The
buffered writer STAYS as the reference implementation; the ladder's
identity check compares the two on every run.

**Writer-only (ladder, S4 buffered vs S4b direct, full WMO):** ascii
216→177 (−18%), latin 237→192 (−19%), cjk 197→156 (−21%), thai
245→205 (−16%), paths 438→427 (−2.5%).

**Shipped totals (EngineBench full WMO, coherent K=3 at the §43
commit, vs the `13337d4` baseline):** sortKey ascii 338→295 (1.74×→
**1.51×**), latin 376→321 (**1.53×**), cjk 370→316 (**1.44×**), thai
459→408 (**1.51×**), paths 782→817 (1.17×→1.22× — see below); skRet
−7..12% except paths ~flat.

**The paths saga (three findings, each §-grade):**
1. **The §33 dead end re-confirmed, quantitatively:** the first wiring
   wrapped the passes in `ces.withUnsafeBufferPointer { }` — paths sk
   read +8% (EngineBench A/B vs the buffered base, interleaved;
   consistent). Removing the closure for `borrowing [Int64]` passes
   recovered ~40 ns. Same shape, same row, same magnitude as §33.
2. **Writer deltas must be certified in the SHIPPING binary.** The
   ladder's same-binary S4/S4b said direct is FASTER on paths CEs
   (438→427); the EngineBench entry context said slower. Probe-context
   codegen ≠ shipping codegen — the §34/§35 lesson in a new costume.
   The EngineBench A/B is the writer's bench truth, not the ladder.
3. **A false hypothesis, killed by corpus fact:** a CE-count dispatch
   hybrid (direct <64 CEs, buffered above) was tried and REMOVED —
   every paths line is 23–61 chars (median 30), the same CE counts as
   ascii; the threshold never fired. The paths cost is the CE MIX plus
   entry-context codegen, not length.

**Accepted residual:** paths sk +35 ns (+5% same-session interleaved,
inside the row's historical ±7% placement band but consistently
reproduced). Rationale: four corpora win −11..16%, paths remains the
BEST sk row vs ICU (1.22×), and machine 2's independent layout will
arbitrate whether the residual is Intel-placement or structural. If it
reproduces on AS and paths sortKey ever matters more, the recorded
next idea is a mix-aware dispatch — NOT the length threshold.

---

### 44. Locale-change invalidation shipped — and the tailoring-defaults bug it found

**Status:** shipped 2026-07-20. Gates: 1515 tests / 122 suites green
(the invalidation regression test adds one of each — NEW GATE COUNT).
Full decision record: **Docs/29**.

The last design box on the audit list. `collatorForCurrentLocale`'s
cache now stores (collator, generation) and revalidates against
`LocaleNotifications.cache.count()` — the documented mechanism
Calendar/TimeZone use process-wide; FE's counter made
package-visible (three `package` keywords, the established
`_LocaleProtocol`/`LockedState` pattern). Generation is read BEFORE
resolution so a racing reset can only cause one extra re-resolve,
never staleness. The regression test flips the current locale
mid-process via the internal hooks (en ↔ sv, "ä" vs "z" — the
canonical sv discriminator) and verifies the very next call follows.

**Measured cost (BF -no-WMO, interleaved K=3, ascii, min):**
localizedCompare 135→151, stdCmp 167→185, caseICmp 169→184 — the
package build's LockedState round-trip; contains/range +2..7
(amortized); engine and explicit-locale rows neutral. The FRAMEWORK
build pays a relaxed atomic load (~1–2 ns) instead. Accepted:
correctness contract, and the rows stay 2.8–6× ahead of system ICU.
Docs/25's `e232237` tables predate this (+16 on three Table-2 cells);
fold at the next re-baseline.

**The bug the test found (filed on the audit list):** the first test
draft used the French pair ("coté"/"côte") and failed — because
`compare()` defaults to `CollationOptions()`, NOT the collator's
`defaultOptions`, so a tailoring's default SETTINGS (fr_CA backwards
secondary) never apply through the no-options Foundation wrappers.
Character-data tailorings (sv) work; settings tailorings don't.
Divergence from Darwin for fr-CA current locale. §39's lesson repeats
for the second time: the audit list's design items keep finding
correctness bugs no benchmark can see.
