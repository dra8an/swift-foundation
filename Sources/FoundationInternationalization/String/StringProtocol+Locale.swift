//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif

#if FOUNDATION_FRAMEWORK
internal import _ForSwiftFoundation
#endif

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension StringProtocol {
    /// A capitalized representation of the string that is produced
    /// using the current locale.
    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public var localizedCapitalized: String {
#if FOUNDATION_FRAMEWORK && !canImport(_FoundationICU)
        _ns.localizedCapitalized
#else
        String(self)._capitalized(with: .current)
#endif
    }

    /// Returns a capitalized representation of the string
    /// using the specified locale.
    @available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
    public func capitalized(with locale: Locale?) -> String {
#if FOUNDATION_FRAMEWORK && !canImport(_FoundationICU)
        _ns.capitalized(with: locale)
#else
        String(self)._capitalized(with: locale)
#endif
    }

    /// A lowercase version of the string that is produced using the current
    /// locale.
    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public var localizedLowercase: String {
#if FOUNDATION_FRAMEWORK && !canImport(_FoundationICU)
        _ns.localizedLowercase
#else
        String(self)._lowercased(with: .current)
#endif
    }


    /// Returns a version of the string with all letters
    /// converted to lowercase, taking into account the specified
    /// locale.
    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public func lowercased(with locale: Locale?) -> String {
#if FOUNDATION_FRAMEWORK && !canImport(_FoundationICU)
        _ns.lowercased(with: locale)
#else
        String(self)._lowercased(with: locale)
#endif
    }

    /// An uppercase version of the string that is produced using the current
    /// locale.
    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public var localizedUppercase: String {
#if FOUNDATION_FRAMEWORK && !canImport(_FoundationICU)
        _ns.localizedUppercase
#else
        String(self)._uppercased(with: .current)
#endif
    }

    /// Returns a version of the string with all letters
    /// converted to uppercase, taking into account the specified
    /// locale.
    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public func uppercased(with locale: Locale?) -> String {
#if FOUNDATION_FRAMEWORK && !canImport(_FoundationICU)
        _ns.uppercased(with: locale)
#else
        String(self)._uppercased(with: locale)
#endif
    }
}

#if FOUNDATION_COLLATION
import Collation

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension StringProtocol {
    /// Compares the string with another using a localized comparison
    /// in the current locale.
    public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        let collator = CollatorCache.shared.collator(for: .current)
        if let collator, let result = try? collator.compare(String(self), String(aString)) {
            return result.comparisonResult
        }
        return String(self).compare(aString)
    }

    /// Compares the string with another using a case-insensitive, localized
    /// comparison in the current locale.
    public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        let collator = CollatorCache.shared.collator(for: .current)
        if let collator {
            var opts = CollationOptions()
            opts.strength = .secondary
            if let result = try? collator.compare(String(self), String(aString), options: opts) {
                return result.comparisonResult
            }
        }
        return String(self).compare(aString, options: .caseInsensitive)
    }

    /// Compares the string with another using a localized, numeric comparison
    /// in the current locale (Finder-style ordering).
    public func localizedStandardCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        let collator = CollatorCache.shared.collator(for: .current)
        if let collator {
            var opts = CollationOptions()
            opts.strength = .secondary
            opts.numeric = true
            if let result = try? collator.compare(String(self), String(aString), options: opts) {
                return result.comparisonResult
            }
        }
        return String(self).compare(aString, options: [.caseInsensitive, .numeric])
    }

    /// Compares the string using the specified options and locale.
    public func compare<T: StringProtocol>(_ aString: T, options mask: String.CompareOptions = [], range: Range<Index>? = nil, locale: Locale?) -> ComparisonResult {
        if let locale {
            if mask.contains(.literal) {
                var substr = Substring(self)
                if let range { substr = substr[range] }
                return String(substr).compare(Substring(aString), options: mask)
            }
            let collator = CollatorCache.shared.collator(for: locale)
            let opts = CollationOptions.from(foundationOptions: mask)
            let lhs: String
            if let range {
                lhs = String(self[range])
            } else {
                lhs = String(self)
            }
            if let collator, let result = try? collator.compare(lhs, String(aString), options: opts) {
                return result.comparisonResult
            }
        }
        var substr = Substring(self)
        if let range { substr = substr[range] }
        return String(substr).compare(Substring(aString), options: mask)
    }
}
#endif
