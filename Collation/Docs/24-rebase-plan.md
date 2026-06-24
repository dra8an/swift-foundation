# Rebase Plan: port/collation onto upstream/main

## Current state

Our branch `port/collation` is based on `upstream/release/6.3` (fork point
`dbacc67`). Upstream `main` has advanced significantly since then, including
PR #1683 which implements the same API we implement (String.compare with
locale) using a different approach.

## PR #1683 (already merged to upstream/main)

**Author:** Ivan Bliznyuk (@IvanBl)
**Merged:** February 2026
**Approach:** ICU-based locale comparison via `ucol_open` + `ucol_strcollUTF8`
**Flag:** `FOUNDATION_ICU_STRING_COMPARE` (defaults off)
**Scope:** `compare(_:options:range:locale:)` only

**Files added/modified:**
- `Sources/FoundationEssentials/String/StringProtocol+Stub.swift` — added
  `compare(_:locale:)` overload behind `FOUNDATION_ICU_STRING_COMPARE`
- `Sources/FoundationInternationalization/String/String+Comparison_ICU.swift`
  — new file: `compareStringsWithLocale` using `ucol_open`/`ucol_strcollUTF8`
- `Tests/.../StringComparisonLocaleTests.swift` — new test file

**Options supported:** `.caseInsensitive`, `.diacriticInsensitive`, `.numeric`

**Key characteristics:**
- Creates and destroys ICU collator (`ucol_open`/`ucol_close`) per call
- No caching
- Depends on `_FoundationICU` (system ICU)
- Feature flag defaults to off

## Our approach (port/collation)

**Approach:** Self-contained Swift UCA implementation (no ICU dependency)
**Scope:** Full: compare, search, predicates, all localized* methods
**Performance:** 1.5–2.8× faster than system ICU on Foundation APIs

**Files we modify/add in the same areas:**
- `Sources/FoundationInternationalization/String/StringProtocol+Locale.swift`
  — adds `localizedCompare`, `compare(_:locale:)`, search methods
- `Sources/FoundationInternationalization/String/String+SortComparator.swift`
  — wires comparators through our collator
- `Sources/FoundationInternationalization/String/String+Collation.swift`
  — CollatorCache, options mapping
- `Sources/FoundationInternationalization/Collation/` — 15 source files
- `Sources/FoundationInternationalization/Predicate/LocalizedString.swift`
  — predicates enabled

## Conflicts on rebase

### 1. CRITICAL: Duplicate `compare(_:options:range:locale:)` definition

**PR #1683** adds this method in `StringProtocol+Stub.swift` (FoundationEssentials)
behind `#if FOUNDATION_ICU_STRING_COMPARE`.

**We** add this method in `StringProtocol+Locale.swift` (FoundationInternationalization)
unconditionally.

**If both exist:** Compile error (duplicate method) when `FOUNDATION_ICU_STRING_COMPARE`
is enabled. If the flag is off, ours is the only one — no conflict.

**Resolution:** Remove PR #1683's version. Ours is unconditional, more complete
(supports `.backwards`, `.forcedOrdering`, `.literal` bypass), and doesn't
need ICU.

### 2. `String+Comparison_ICU.swift` — dead file

PR #1683's ICU comparison implementation becomes dead code. It calls
`ucol_open`/`ucol_strcollUTF8` — functionality our collator replaces entirely.

**Resolution:** Delete this file. Our collator handles everything it does, faster.

### 3. `StringProtocol+Stub.swift` — diff conflict

PR #1683 modified this file to add the locale overload and a `dynamic package func
_localizedCompare_platform`. These additions would conflict with our approach
since we don't use the dynamic-replacement mechanism.

**Resolution:** Revert PR #1683's additions to this file. Our implementation
lives in FoundationInternationalization, not FoundationEssentials.

### 4. Test files

PR #1683 added `StringComparisonLocaleTests.swift`. Our tests are in
`StringSortComparatorTests.swift` and the `Collation/` test directory.

**Resolution:** Keep their tests — they test the same behavior we support.
If any tests reference `FOUNDATION_ICU_STRING_COMPARE`, change to unconditional.

### 5. Package.swift

PR #1683 may have added `FOUNDATION_ICU_STRING_COMPARE` as a `.define()`.
We removed all such flags.

**Resolution:** Remove the `FOUNDATION_ICU_STRING_COMPARE` define if present.

## Other upstream changes since 6.3

Beyond PR #1683, upstream `main` has ~180 commits ahead of our fork point.
These include:
- Hebrew calendar feature (PR #2017) — no conflict with us
- `_FoundationDarwinExtras` import changes — may touch files we modified
- Various formatting/calendar/URL fixes — unlikely to conflict

A full rebase will require resolving merge conflicts in files that both
upstream and we modified. The most likely conflicts:
- `Package.swift` — restructured by multiple PRs
- `Sources/FoundationInternationalization/Predicate/LocalizedString.swift`
  — we removed the `#if FOUNDATION_FRAMEWORK` guard
- `Sources/FoundationInternationalization/String/String+SortComparator.swift`
  — heavily modified by us

## Strategy options

### Option A: Rebase onto main, replace PR #1683

1. `git rebase upstream/main`
2. Resolve conflicts (mostly Package.swift and String files)
3. Delete PR #1683's files (`String+Comparison_ICU.swift`)
4. Remove `FOUNDATION_ICU_STRING_COMPARE` flag
5. Keep their tests, remove the flag guard

**Pros:** Clean tree, one implementation, no dead code
**Cons:** Reviewers may push back on replacing a recently-merged PR

### Option B: Coexist with PR #1683

1. Keep PR #1683's code behind its flag (defaults off)
2. Our code is unconditional
3. The flag becomes a fallback path (if someone wants ICU, they can enable it)

**Pros:** Non-confrontational, no need to delete someone else's work
**Cons:** Dead code, two implementations of the same API, confusing

### Option C: New PR branch from main

1. Create a fresh branch from current `upstream/main`
2. Apply our changes as new commits (not rebasing the old history)
3. This avoids merge conflicts entirely — just add our files

**Pros:** Cleanest diff for PR review, no merge noise
**Cons:** Loses git history of development, more manual work

## Recommendation

**Option C** is the best for PR submission. The reviewers care about the
final diff, not our development history. We:
1. Branch from `upstream/main`
2. Add `Sources/FoundationInternationalization/Collation/` (15 files + resources)
3. Add `Sources/FoundationInternationalization/String/String+Collation.swift`
4. Modify `String+SortComparator.swift`, `StringProtocol+Locale.swift`,
   `LocalizedString.swift`
5. Remove `String+Comparison_ICU.swift` and `FOUNDATION_ICU_STRING_COMPARE`
6. Add tests
7. Modify `Package.swift` (resources)

The PR description would explain: "This replaces the ICU-based implementation
from #1683 with a self-contained Swift collation engine that is 1.5–2.8×
faster and supports the full API surface (search, predicates, all options)."

## Tina's concerns revisited

| Concern | PR #1683's answer | Our answer |
|---------|-------------------|-----------|
| Platform parity | Uses ICU everywhere (same engine as Darwin under the hood) | Same Swift collator everywhere, Darwin feature flag for opt-in |
| Performance | Creates/destroys collator per call (slow) | Cached, 1.5–2.8× faster than system ICU |
| Options coverage | 3 options | 5 options + search + predicates |
| ICU dependency | Requires `_FoundationICU` | Self-contained, no ICU needed |
| Behavioral consistency | Matches ICU behavior (same bugs as system) | Byte-identical sort keys to ICU (verified by 123 conformance tests) |
| Feature flag | `FOUNDATION_ICU_STRING_COMPARE` (off by default) | Darwin runtime flag (same pattern as Hebrew calendar) |
| Path to Darwin | Could enable flag on Darwin eventually | Darwin feature flag already wired, ready to flip |

## Open questions for Foundation team

1. Is replacing PR #1683 acceptable? Or should both coexist?
2. Is the resource size (2.8 MB for collation data + tailorings) acceptable
   for FoundationInternationalization?
3. Is the Darwin feature flag pattern (like Hebrew calendar) the right
   approach for eventual Darwin opt-in?
4. Should we use package traits (as Tina suggested) once swift-tools-version
   is bumped?
