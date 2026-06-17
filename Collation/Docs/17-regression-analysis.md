# Regression Analysis: Commits 6443a35 → 631b343

> Written 2026-06-17. A per-commit bisection of the performance regression
> introduced between the pre-Span baseline (6443a35) and the current HEAD.

## 1. The Commits

```
6443a35  Span benchmarks doc (last pre-Span code state — BASELINE)
50d562e  Span prefix skip (experimental) + integration results
18c286b  Span fast-Latin bail path
49ca4ad  HANDOFF update (doc only)
3500ab3  Thread-local scratch lifetime fix (ScratchBuffers.swift only)
631b343  Split compare into separate functions (attempted fix)
```

## 2. Per-Commit Benchmark (Apple Silicon, quiet machine, 10000 reps)

Each binary built from the exact state of that commit's RootCollator.swift
(+ ScratchBuffers.swift for 3500ab3). Run interleaved, 3 passes.

### ASCII compare (ns/op)

| commit | run 1 | run 2 | run 3 | vs 6443a35 |
|--------|-------|-------|-------|------------|
| **6443a35** (baseline) | 33 | 31 | 31 | — |
| 50d562e (Span prefix skip) | 32 | 32 | 32 | **neutral** |
| 3500ab3 (TLS fix) | 46 | 47 | 47 | **+48%** |
| 18c286b (Span fast-Latin bail) | 46 | 46 | 46 | +48% |
| 631b343 (split functions) | 46 | 46 | 46 | +48% |

### CJK compare (ns/op)

| commit | run 1 | run 2 | run 3 | vs 6443a35 |
|--------|-------|-------|-------|------------|
| **6443a35** (baseline) | 145 | 148 | 143 | — |
| 50d562e | 161 | 161 | 160 | **+11%** |
| 3500ab3 | 171 | 172 | 172 | **+19%** |
| 18c286b | 171 | 173 | 171 | +19% |
| 631b343 | 171 | 170 | 172 | +19% |

### Thai compare (ns/op)

| commit | run 1 | run 2 | run 3 | vs 6443a35 |
|--------|-------|-------|-------|------------|
| **6443a35** | 401 | 403 | — | — |
| 50d562e | 410 | 408 | — | **+2%** |
| 3500ab3 | 426 | 431 | — | **+7%** |
| 18c286b | 423 | 456 | — | +7% |
| 631b343 | 426 | 422 | — | +7% |

### paths compare (ns/op)

| commit | run 1 | run 2 | run 3 | vs 6443a35 |
|--------|-------|-------|-------|------------|
| **6443a35** | 70 | 70 | — | — |
| 50d562e | 69 | 71 | — | **neutral** |
| 3500ab3 | 80 | 81 | — | **+14%** |
| 18c286b | 81 | 81 | — | +14% |
| 631b343 | 80 | 82 | — | +14% |

### CJK sortKey (ns/op)

| commit | run 1 | run 2 | run 3 | vs 6443a35 |
|--------|-------|-------|-------|------------|
| **6443a35** | 254 | 254 | — | — |
| 50d562e | 249 | 251 | — | **neutral** |
| 3500ab3 | 249 | 253 | — | **neutral** |
| 18c286b | 248 | 252 | — | neutral |
| 631b343 | 267 | 253 | — | neutral |

## 3. Where Each Regression Comes From

### The big regression: RootCollator.swift Span changes (50d562e + 18c286b)

The previous bisection was WRONG — it attributed the regression to `3500ab3`
(the TLS fix), but `3500ab3`'s binary included the Span RootCollator changes
too (they're earlier in history). When isolated properly:

**TLS fix alone (6443a35 RootCollator + 3500ab3 ScratchBuffers):**
- ASCII: 32 → 31 ns (neutral)
- CJK: 142 → 143 ns (neutral)
- paths: 70 → 70 ns (neutral)

**The TLS lifetime fix is completely innocent.** The entire regression comes
from the Span changes to RootCollator.swift — the inline `#available` blocks
in `compare()` that bloated the function and changed the compiler's code
layout and inlining decisions.

### 50d562e: Span prefix skip (experimental)

Added inline `#available` for the prefix skip. CJK: +11%. The `#available`
block in the middle of `compare()` disrupts the function's codegen even
though only one branch ever runs.

### 18c286b: Span fast-Latin bail

Added a second inline `#available` for the fast-Latin path. This stacked
with 50d562e to bring ASCII from 32 → 46 (+44%) because the fast-Latin byte
path — the ASCII hot path — is now inside a function whose codegen is bloated
by two `#available` blocks.

### 631b343: split functions

Attempted to fix the regression by splitting `compare()` into separate
functions. This prevented the `#available` branches from sharing codegen,
but the extra function-call indirection (`compare` → `compareWithSpan` →
`compareBody`) added its own overhead. Net: no improvement over 18c286b.

## 4. The Wins That Are Real

1. **Thread-local scratch (concept + lifetime fix)** — eliminating the lock +
   exclusivity checks is a real win. The −19% CJK from the original phase 1
   is confirmed. The lifetime fix (3500ab3) was verified as zero-regression
   when isolated (6443a35 RootCollator + 3500ab3 ScratchBuffers = neutral).

2. **Span fast-Latin bail (concept)** — non-Latin text skipping closures is
   a real win when delivered without codegen bloat. The −10% CJK measured
   against the already-regressed 3500ab3 was real *relative to that baseline*.

3. **sortKey(for:into:) inout API** — unaffected by any of this. The −27%
   sortKey win is clean and confirmed across all commits.

## 5. Recovery Plan

### Step 1: Revert RootCollator.swift to 6443a35

The TLS fix (ScratchBuffers.swift) is clean — keep it. The entire regression
is from the Span changes in RootCollator.swift. Revert RootCollator.swift to
its exact 6443a35 state. This recovers the baseline: ASCII ~31 ns, CJK ~143 ns.

### Step 2: Re-apply the Span fast-Latin bail correctly

The concept (non-Latin text skipping closures) is sound. The delivery was
wrong (inline `#available` bloats the function). The correct approach must
not modify `compare()` at all on pre-macOS-26 codegen. Options:

**(a) Compile-time guard (`#if compiler`):** If the Span API is only available
in certain toolchains, use `#if` instead of `#available`. This means the
Span code doesn't exist in the binary at all on older toolchains — zero
codegen impact. But it doesn't help on new toolchains targeting old macOS.

**(b) Separate source file:** Put the Span compare path in its own file with
`@available` on the entire extension. The original `compare()` in
RootCollator.swift stays untouched. The public API dispatches via a protocol
or a stored function pointer resolved at init. This completely isolates the
two codegen paths.

**(c) Accept the regression on macOS 26 for now:** If the Span bail's −10%
CJK doesn't survive proper A/B against 6443a35 (our earlier tests showed
`50d562e` at +11% CJK, not −10%), then there may be no win to deliver. Park
the Span work until the full pipeline refactor makes it worthwhile.

### Step 3: Verify against 6443a35

Every change must be A/B'd against the `6443a35` binary (bench-6443), not
against any intermediate commit.

## 6. What NOT to Re-Apply

- The Span prefix skip (`spanPrefixSkip`, `PrefixSkipResult`,
  `decodeScalarFromSpan`) — had a correctness bug (53 test failures) and
  showed +11% CJK even without the bug. Remove permanently.
- Inline `#available` in `compare()` — bloats codegen. Use the split-function
  structure instead.
