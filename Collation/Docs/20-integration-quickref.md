# Collation Integration: Quick Reference

## What this solves

GitHub issue #284: `String.compare(_:options:locale:)` and all locale-aware
string APIs (`localizedCompare`, `localizedStandardContains`,
`localizedStandardRange`, `String.Comparator` with locale) do not work on
non-Darwin platforms. They silently fall back to unlocalized comparison.

## What we built

A Swift implementation of the Unicode Collation Algorithm (UTS #10 / CLDR
root + tailorings), ported from ICU4C's "collation v2" design. Full-string
comparison produces sort keys byte-identical to ICU. Substring search uses
collation-aware CE matching with strength masking. 15 locale tailorings
bundled (sv, da, fi, nb, nn, de-phonebook, fr, fr-CA, es, tr, lt, cs, ja,
zh, ko, th, ar, he), loaded on demand.

## How the integration works

```
#if FOUNDATION_FRAMEWORK
    // Darwin: NSString → CoreFoundation → system ICU
    // Unchanged. We don't touch this path.

#elseif FOUNDATION_COLLATION
    // Non-Darwin: our collator handles locale-aware comparison and search.
    // CollatorCache resolves Locale → RootCollator (lazy, thread-safe).
    // CompareOptions map to CollationOptions (strength, numeric, etc.).
    // RootCollator.compare() or .search() does the work.

#else
    // No collator linked: old unlocalized fallback. Unchanged.
#endif
```

The `FOUNDATION_COLLATION` compile flag is set on the
`FoundationInternationalization` target in Package.swift. On Darwin,
`FOUNDATION_FRAMEWORK` is checked first in the `#if` chain, so the
collation path is never reached — Darwin continues using the system ICU.

## What's enabled

| API | Before | After (non-Darwin) |
|-----|--------|-------------------|
| `String.Comparator(options:locale:)` | Locale ignored | Locale-aware via collation |
| `.localizedStandard` / `.localized` | Not available | Available |
| `localizedCompare(_:)` | Not available | Locale-aware |
| `localizedCaseInsensitiveCompare(_:)` | Not available | Locale-aware |
| `localizedStandardCompare(_:)` | Not available | Locale-aware, numeric |
| `compare(_:options:range:locale:)` | Locale ignored | Locale-aware |
| `localizedStandardContains(_:)` | Not available | Collation-aware search |
| `localizedCaseInsensitiveContains(_:)` | Not available | Collation-aware search |
| `localizedStandardRange(of:)` | Not available | Collation-aware search |
| `range(of:options:range:locale:)` | Locale ignored | Collation-aware search |
| `#Predicate { $0.localizedCompare($1) }` | Not available | Works |
| `#Predicate { $0.localizedStandardContains(...) }` | Not available | Works |

## Module structure

```
Package.swift
├── FoundationEssentials          (no changes)
├── FoundationInternationalization
│   ├── depends on: Collation     (new dependency)
│   ├── flag: FOUNDATION_COLLATION
│   ├── String+Collation.swift    (new: cache, options mapping, locale mapping)
│   ├── String+SortComparator.swift  (modified: #elseif wiring)
│   ├── StringProtocol+Locale.swift  (modified: localized methods + search)
│   └── Predicate/LocalizedString.swift  (modified: predicates enabled)
└── Collation/                    (standalone SwiftPM package)
    ├── Sources/Collation/
    │   ├── RootCollator.swift    (public API: compare, sortKey, search)
    │   ├── CollationSearch.swift (substring search)
    │   ├── CollationElements.swift, NFDIterator.swift, ...
    │   └── Resources/           (ucadata.icu, nfd.bin, tailorings/*.bin)
    └── Tests/CollationTests/    (123 tests, standalone)
```

The Collation module builds and tests independently (`swift test` in
`Collation/`). When FoundationInternationalization links it, the glue code
in `String+Collation.swift` bridges between Foundation types and the
collator.

## Key design decisions

- **Compile-time flag, not runtime** — `FOUNDATION_COLLATION` is a
  `.define()` in Package.swift, not a runtime feature check. Appropriate
  because it gates non-Darwin only; there is no system service to query.

- **Lazy collator cache** — `CollatorCache` uses `LockedState` (from
  FoundationEssentials), one `RootCollator` per locale, loaded on first use.
  A Swedish comparison on a server that never sees Swedish text pays nothing.

- **Graceful fallback** — if the collator fails to init (corrupted data,
  missing resource), every call site falls back to unlocalized comparison
  rather than crashing.

- **No Darwin behavior change** — the `#if FOUNDATION_FRAMEWORK` path is
  always checked first. Darwin builds are unaffected even though
  `FOUNDATION_COLLATION` is technically defined.

## Performance

Tested 2026-07-06 on Apple Silicon (macOS 26) against system ICU (via NSString bridge).

**Foundation API integration (what users actually call):**

| API | ASCII | Latin | CJK | Paths |
|-----|-------|-------|-----|-------|
| `localizedCompare` | **1.5× faster** | **2.8× faster** | **1.6× faster** | **1.8× faster** |
| `localizedStandardCompare` | **1.4× faster** | **2.5× faster** | **1.5× faster** | **1.7× faster** |
| `localizedCaseInsensitiveCompare` | **1.4× faster** | **2.5× faster** | **1.5× faster** | **1.8× faster** |
| `compare(_:locale:)` | **1.0×** | **1.6× faster** | **1.1× faster** | **1.2× faster** |
| `localizedStdContains` | **2.3× faster** | **3.2× faster** | **2.7× faster** | **2.0× faster** |
| `localizedCaseIContains` | **2.3× faster** | **3.3× faster** | **2.7× faster** | **2.1× faster** |
| `localizedStdRange` | **2.2× faster** | **3.1× faster** | **2.5× faster** | **1.4× faster** |
| `range(of:locale:)` | **0.9×** | **1.2× faster** | 0.9× | 0.7× |
| `range(backwards)` | **0.9×** | **1.3× faster** | 0.9× | **1.1× faster** |

**Direct collation (RootCollator.compare, no Foundation overhead):**

| Operation | Ratio vs ICU |
|-----------|-------------|
| Sort keys (ASCII/Latin/CJK) | 1.8–2.1× slower |
| Compare (ASCII/Latin) | 2.4–2.8× slower |
| Compare (CJK/Thai) | 1.9–3.0× slower |

Direct collation arithmetic is slower than ICU (C vs Swift overhead), but
the Foundation API layer is faster because system ICU pays the ObjC bridge
cost (NSString → CoreFoundation → ICU) that we avoid entirely.

## Remaining gaps

- `.widthInsensitive` — not a collation feature. It's a scalar-level
  fullwidth→halfwidth transformation handled by FoundationEssentials before
  comparison. On non-Darwin it's unimplemented (`_toHalfWidth()` is a
  `fatalError` TODO). The fix belongs in FoundationEssentials, not our module.
- Darwin opt-in — feature flag added, defaults off. Ready for Apple to flip.
