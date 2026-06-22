# Integration Plan: Replace ICU Collation with Pure-Swift RootCollator

## Context

The `swift-foundation` codebase has a TODO (GitHub issue #284) for locale-aware
string comparison on non-Darwin platforms. Currently:

- **Darwin/macOS (`FOUNDATION_FRAMEWORK`):** `String.compare(_:options:locale:)`
  bridges through `_ns` (NSString) → CoreFoundation → ICU. This is in the SYSTEM
  frameworks, not in this repo. We can't see or modify it here.
- **Non-Darwin/Linux (`#else`):** Falls back to `_unlocalizedCompare` — locale is
  IGNORED. The TODO is at `String+SortComparator.swift:154`.

Our `Collation/` package fills the gap: Swift UCA with 15 locale tailorings,
byte-identical sort keys to ICU, 61 tests green, 1.4-2.0× ICU performance.

## The integration point

```swift
// String+SortComparator.swift:144-156
public func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
#if FOUNDATION_FRAMEWORK
    if isLocalized {
        return lhs.compare(rhs, options: options, locale: Locale.current).withOrder(order)
    } else {
        return lhs.compare(rhs, options: options).withOrder(order)
    }
#else
    // TODO: Until compare(_:options:locale:) is ported — THIS IS US
    return lhs.compare(rhs, options: options).withOrder(order)
#endif
}
```

Also need to handle `String.Comparator` (lines 241-249) which has a specific
locale and options.

## Architecture

### What we replace

The `#else` path. Our collator provides `compare(_:_:options:) -> Order` which
maps directly to `ComparisonResult`.

### What stays unchanged

- The `#if FOUNDATION_FRAMEWORK` path (Darwin system bridge)
- All locale/collation IDENTIFIER handling (`Locale.Collation`, `ucol_getKeywordValues`)
- The unlocalized `_unlocalizedCompare` path (used when no locale specified)

### Options mapping

| Foundation option | Our CollationOptions |
|-------------------|---------------------|
| `.caseInsensitive` | `strength = .secondary` |
| `.diacriticInsensitive` | `strength = .primary` |
| `.numeric` | `numeric = true` |
| `.literal` | Skip collation — use binary/scalar comparison |
| `.forcedOrdering` | Use `.identical` strength as tiebreaker |
| `.widthInsensitive` | NOT SUPPORTED yet — document gap |
| locale ("sv", "de@collation=phonebook", etc.) | `RootCollator(tailoringNamed:)` |

### Locale to tailoring name mapping

Our 15 bundled tailorings: sv, de-phonebook, fr-CA, ja, zh, ko, th, ar, he,
da, fi, nb, nn, es, tr. Map from Foundation's `Locale.identifier` or
`Locale.collation.identifier` to our tailoring name. Locales without a
tailoring use the root collator.

## Implementation steps

### Step 1: Package structure

Move or reference Collation sources so FoundationInternationalization can
import them. Options:
- **(a)** Add as a local package dependency in Package.swift
- **(b)** Copy sources into `Sources/FoundationInternationalization/Collation/`
- **(c)** Keep separate module, import with `@_exported`

Decision needed from the user.

### Step 2: Collator cache

Create a thread-safe singleton cache (per locale identifier → RootCollator).
RootCollator is `Sendable` and immutable after init, so it can be shared.

```swift
// StringCollator.swift (new file)
final class CollatorCache: @unchecked Sendable {
    static let shared = CollatorCache()
    func collator(for locale: Locale) -> RootCollator { ... }
}
```

### Step 3: Wire into compare

Replace the `#else` TODO:

```swift
#else
if isLocalized {
    let collator = CollatorCache.shared.collator(for: .current)
    let opts = CollationOptions.from(foundationOptions: options)
    let result = try? collator.compare(lhs, rhs, options: opts)
    return (result ?? .same).withOrder(order)
} else {
    return lhs.compare(rhs, options: options).withOrder(order)
}
#endif
```

### Step 4: Handle `String.Comparator` (specific locale)

Same pattern but uses the comparator's stored locale instead of `.current`.

### Step 5: Handle the `localizedCompare`, `localizedStandardCompare` methods

These are in `StringProtocol+Locale.swift` and currently gate on
`FOUNDATION_FRAMEWORK`. Add `#else` implementations using our collator.

### Step 6: Run tests

Target tests:
- `StringSortComparatorTests` (locale, standardLocalized)
- `StringTests` (localizedCompare, localizedStandardCompare, localizedCaseInsensitiveCompare)
- `PredicateInternationalizationTests` (testLocalizedCompare)
- `SortDescriptorConversionTests` (selector conversions)

### Step 7: Benchmark

- Compare our `String.compare(_:_:locale:)` vs the Darwin NSString path
- Profile with the same bench corpora (ASCII, Latin, CJK, paths, Thai)

## Gaps to address

1. **`.widthInsensitive`** — halfwidth/fullwidth CJK. Not in our port. Low priority
   (rare option in practice).

2. **`localizedStandardContains` / `localizedStandardRange`** — substring search
   with collation. Our port only does full-string compare, not substring search.
   This is a significant gap — may need a separate search implementation or
   fallback to the existing diacritics-stripping approach.

3. **Dutch locale (nl)** — tested in `capitalize_localized` but that's case mapping,
   not collation. Root collation should work for Dutch comparison.

4. **Greek locale (el)** — same as Dutch, tested for case mapping only.

5. **Darwin path replacement** — longer-term goal. Would eliminate the ObjC bridge
   overhead on macOS/iOS. Gated on community acceptance.

## Verification

1. Build: `swift build` with FoundationInternationalization importing Collation
2. Tests: `swift test --filter FoundationInternationalizationTests` — all green
3. Benchmark: A/B against existing `_unlocalizedCompare` and against Darwin path
4. Conformance: our 61-test Collation suite still passes
5. Cross-validate: sort 10k strings with our path vs ICU, compare output

