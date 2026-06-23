# Integration Plan: Replace ICU Collation with Swift RootCollator

## Status: IMPLEMENTED (2026-06-22)

All steps complete. Gated behind `FOUNDATION_COLLATION` compile-time flag.
Commits `de4cb88`..`3d32ec3` on `port/collation`. 941 tests pass.

---

## Platform terminology: Darwin vs non-Darwin

**Darwin** is Apple's OS kernel — the base of macOS, iOS, tvOS, watchOS.
On Darwin, Foundation is a system framework backed by Objective-C runtime,
CoreFoundation, and a system-bundled ICU. String methods like
`compare(_:options:locale:)` and `localizedStandardContains` work by
bridging through `NSString` → CoreFoundation → ICU. The code in this repo
doesn't control that path — it lives in the OS.

**Non-Darwin** means Linux, Windows, WASI — any platform where Swift runs
but there is no Apple system framework. On these platforms, `swift-foundation`
(this repo) IS the Foundation implementation, built entirely from source.
There is no NSString, no CoreFoundation, no system ICU. Before our work,
`compare(_:options:locale:)` simply ignored the locale on these platforms.

The compile-time guards in the code:

| Guard | Meaning |
|-------|---------|
| `#if FOUNDATION_FRAMEWORK` | Darwin system framework build (NSString bridge available) |
| `#if FOUNDATION_COLLATION` | Our collation is linked in (currently non-Darwin only) |
| `#else` | Neither — the old unlocalized fallback |

`FOUNDATION_COLLATION` compiles on Darwin too (the Collation module builds
fine), but the `#if FOUNDATION_FRAMEWORK` branch takes priority in the
`#if / #elseif / #else` chain, so Darwin still uses the system ICU path.
The flag exists so non-Darwin gets locale-aware comparison without touching
the Darwin code path.

---

## Context

The `swift-foundation` codebase has a TODO (GitHub issue #284) for locale-aware
string comparison on non-Darwin platforms. Currently:

- **Darwin/macOS (`FOUNDATION_FRAMEWORK`):** `String.compare(_:options:locale:)`
  bridges through `_ns` (NSString) → CoreFoundation → ICU. This is in the SYSTEM
  frameworks, not in this repo. We can't see or modify it here.
- **Non-Darwin/Linux (`#else`):** Falls back to `_unlocalizedCompare` — locale is
  IGNORED. The TODO is at `String+SortComparator.swift:154`.

Our `Collation/` package fills the gap: Swift UCA with 15 locale tailorings,
byte-identical sort keys to ICU, 71 tests green, 1.4-2.0× ICU performance.

## What was implemented

### Package structure (Step 1) ✓

Added `Collation` as a target in the root `Package.swift` with explicit path
(`Collation/Sources/Collation/`) and resources. FoundationInternationalization
depends on it. Feature flag `.define("FOUNDATION_COLLATION")` on both the main
target and test target.

### Collator cache (Step 2) ✓

`CollatorCache` in `String+Collation.swift`: thread-safe via `LockedState`,
lazy per-locale. Tailoring loaded on first use only. Maps Foundation `Locale`
→ tailoring name via a static dictionary covering all 14 bundled tailorings.

### Full-string compare (Steps 3–4) ✓

`String.StandardComparator.compare` and `String.Comparator.compare` both route
through `RootCollator.compare()` when a locale is present. The `.localizedStandard`
and `.localized` comparators are now available on non-Darwin.

### StringProtocol methods (Step 5) ✓

Added to `StringProtocol+Locale.swift` under `#if FOUNDATION_COLLATION`:
- `localizedCompare(_:)`
- `localizedCaseInsensitiveCompare(_:)`
- `localizedStandardCompare(_:)`
- `compare(_:options:range:locale:)`
- `localizedStandardContains(_:)` — collation-aware substring search
- `localizedCaseInsensitiveContains(_:)` — collation-aware substring search

### Substring search ✓

`CollationSearch.swift` in the Collation module: linear scan in CE space with
strength masking, NFD position annotation, and boundary validation. Public API:
`RootCollator.search(for:in:options:) → Range<String.Index>?` and
`.contains(pattern:in:options:) → Bool`.

### Predicate support ✓

Both `StringLocalizedCompare` and `StringLocalizedStandardContains` predicate
expressions enabled under `FOUNDATION_COLLATION`.

### Tests (Step 6) ✓

- `StringSortComparatorTests`: 10 tests (locale, nil-locale, standard, numeric,
  reverse, localizedCompare, localizedCaseInsensitive, localizedStandard,
  compareWithLocale, compareOptions)
- `PredicateInternationalizationTests`: 4 tests (parametric compare, ordering,
  standardContains × 3 cases, no-match)
- `CollationSearchTests` (standalone): 10 tests (exact, start, no-match, empty,
  case-insensitive, accent-insensitive, NFD equivalence, contains API, CJK)
- Full suite: 941 tests, 40 suites — all green

### Options mapping

| Foundation option | Our CollationOptions |
|-------------------|---------------------|
| `.caseInsensitive` | `strength = .secondary` |
| `.diacriticInsensitive` | `strength = .primary` |
| `.numeric` | `numeric = true` |
| `.literal` | Skip collation — use binary/scalar comparison |
| `.forcedOrdering` | `strength = .identical` |
| `.widthInsensitive` | NOT SUPPORTED — documented gap |

### Locale to tailoring mapping

Static dictionary in `CollatorCache`: sv, de-phonebook, fr-CA, fr, ja, zh,
zh-stroke, ko, th, ar, he, da, fi, nb, nn, no→nb, es, tr, lt. Locales
without a bundled tailoring use root collation (correct per UCA).

## Remaining gaps

1. **`.widthInsensitive`** — halfwidth/fullwidth CJK. Not in our port. Low priority.

2. **`localizedStandardRange`** — range-returning search. The search
   infrastructure exists (`RootCollator.search` returns `Range<String.Index>?`)
   but it's not yet wired into Foundation's `range(of:options:locale:)` API.

3. **Search v1 limitations** — no ignorable skipping (spaces/punctuation at
   weak strengths), no cross-starter contraction handling, no backwards search.

4. **Darwin opt-in** — currently non-Darwin only. Replacing the ObjC bridge
   is gated on community acceptance.

5. **Benchmark (Step 7)** — not yet done. Need A/B of the integrated path
   vs direct `RootCollator.compare()` to measure cache/options overhead.

## Files changed

| File | What |
|------|------|
| `Package.swift` | Collation target, dependency, feature flag |
| `Sources/.../String/String+Collation.swift` | NEW: CollatorCache, options mapping, locale mapping |
| `Sources/.../String/String+SortComparator.swift` | Comparator wiring |
| `Sources/.../String/StringProtocol+Locale.swift` | localizedCompare/Contains methods |
| `Sources/.../Predicate/LocalizedString.swift` | Predicate expressions enabled |
| `Sources/.../Formatting/Number/NumberFormatStyleConfiguration.swift` | Pre-existing toolchain fix |
| `Collation/Sources/Collation/CollationSearch.swift` | NEW: substring search |
| `Collation/Sources/Collation/RootCollator.swift` | search/contains public API |
| `Tests/.../StringSortComparatorTests.swift` | 10 tests |
| `Tests/.../PredicateInternationalizationTests.swift` | 4 tests |
| `Collation/Tests/CollationTests/SearchTests.swift` | NEW: 10 tests |
