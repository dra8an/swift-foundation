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

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension StringProtocol {
    /// Compares the string with another using a localized comparison
    /// in the current locale.
    public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        if let collator = CollatorCache.shared.collatorForCurrentLocale(),
           let result = try? collator.compare(String(self), String(aString)) {
            return result.comparisonResult
        }
        return String(self).compare(aString)
    }

    public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
            var opts = CollationOptions()
            opts.strength = .secondary
            if let result = try? collator.compare(String(self), String(aString), options: opts) {
                return result.comparisonResult
            }
        }
        return String(self).compare(aString, options: .caseInsensitive)
    }

    public func localizedStandardCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
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

    /// Returns true if the string contains the given string using a
    /// case-insensitive, diacritic-insensitive, locale-aware search
    /// (Finder-style matching).
    public func localizedStandardContains<T: StringProtocol>(_ string: T) -> Bool {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
            var opts = CollationOptions()
            opts.strength = .primary
            opts.numeric = true
            return collator.contains(pattern: String(string), in: String(self), options: opts)
        }
        return String(self).localizedCaseInsensitiveContains(String(string))
    }

    public func localizedCaseInsensitiveContains<T: StringProtocol>(_ string: T) -> Bool {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
            var opts = CollationOptions()
            opts.strength = .secondary
            return collator.contains(pattern: String(string), in: String(self), options: opts)
        }
        return String(self).contains(String(string))
    }

    /// Returns the range of the first occurrence of the given string using a
    /// case-insensitive, diacritic-insensitive, locale-aware search
    /// (Finder-style matching).
    public func localizedStandardRange<T: StringProtocol>(of string: T) -> Range<Index>? {
        let collator = CollatorCache.shared.collatorForCurrentLocale()
        if let collator {
            var opts = CollationOptions()
            opts.strength = .primary
            opts.numeric = true
            let text = String(self)  // once: search input AND rebase source
            if let range = collator.search(for: String(string), in: text, options: opts) {
                return rebaseRange(range, from: text)
            }
        }
        return nil
    }

    /// Returns the range of the first occurrence of the given string,
    /// searching with the specified options and locale.
    public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = [], range searchRange: Range<Index>? = nil, locale: Locale?) -> Range<Index>? {
        guard let locale else { return nil }
        if mask.contains(.literal) { return nil }
        let collator = CollatorCache.shared.collator(for: locale)
        let opts = CollationOptions.from(foundationOptions: mask)
        let backwards = mask.contains(.backwards)
        let text: String
        if let searchRange {
            text = String(self[searchRange])
        } else {
            text = String(self)
        }
        if let collator {
            let range = backwards
                ? collator.searchBackwards(for: String(aString), in: text, options: opts)
                : collator.search(for: String(aString), in: text, options: opts)
            if let range {
                if let searchRange {
                    return rebaseRange(range, from: text, offsetBy: searchRange.lowerBound)
                }
                return rebaseRange(range, from: text)
            }
        }
        return nil
    }

    /// Maps a range the search produced (indices into the materialized
    /// `source` String) back into SELF's index space. Scalar-offset math on
    /// both sides: the search's indices are scalar-aligned, and a
    /// Substring's scalar count matches its materialized copy while its
    /// indices stay base-string-relative — mapping through a fresh
    /// `String(self)` returned copy-space indices, misaligned for every
    /// Substring receiver (§39; caught by SubstringReceiverTests).
    private func rebaseRange(_ range: Range<String.Index>, from source: String) -> Range<Index>? {
        rebaseRange(range, from: source, offsetBy: startIndex)
    }

    /// As above, with the search having run on the slice starting at `base`
    /// in self (the `range(of:range:)` case).
    private func rebaseRange(_ range: Range<String.Index>, from source: String, offsetBy base: Index) -> Range<Index>? {
        let sourceScalars = source.unicodeScalars
        let startOffset = sourceScalars.distance(from: sourceScalars.startIndex, to: range.lowerBound)
        let endOffset = sourceScalars.distance(from: sourceScalars.startIndex, to: range.upperBound)
        let selfScalars = self.unicodeScalars
        guard let start = selfScalars.index(base, offsetBy: startOffset, limitedBy: endIndex),
              let end = selfScalars.index(base, offsetBy: endOffset, limitedBy: endIndex) else {
            return nil
        }
        return start..<end
    }
}
