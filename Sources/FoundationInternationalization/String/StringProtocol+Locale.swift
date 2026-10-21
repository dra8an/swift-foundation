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

// The collation wrappers below are generic and not `@inlinable`, so a caller in another module runs their unspecialized code. Each one converts its arguments with `_collationString` and calls a non-generic `String` method, so the collator work runs as specialized code.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension StringProtocol {
    /// `String(self)` without the generic `String.init` in unspecialized code: a metatype compare finds a `String` (no copy) or a `Substring` first.
    @inline(__always)
    fileprivate var _collationString: String {
        if let string = _specialize(self, for: String.self) { return string }
        if let substring = _specialize(self, for: Substring.self) { return String(substring) }
        return String(self)
    }

    /// Compares the string with another using a localized comparison in the current locale.
    public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _collationString._localizedCompare(aString._collationString)
    }

    public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _collationString._localizedCaseInsensitiveCompare(aString._collationString)
    }

    public func localizedStandardCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _collationString._localizedStandardCompare(aString._collationString)
    }

    /// Compares the string using the specified options and locale.
    public func compare<T: StringProtocol>(_ aString: T, options mask: String.CompareOptions = [], range: Range<Index>? = nil, locale: Locale?) -> ComparisonResult {
        if let locale, !mask.contains(.literal) {
            let lhs: String
            if let range {
                lhs = self[range]._collationString
            } else {
                lhs = _collationString
            }
            if let result = lhs._compare(aString._collationString, options: mask, locale: locale) {
                return result
            }
        }
        var substr = Substring(self)
        if let range { substr = substr[range] }
        return String(substr).compare(Substring(aString), options: mask)
    }

    /// Returns true if the string contains the given string using a case-insensitive, diacritic-insensitive, locale-aware search (Finder-style matching).
    public func localizedStandardContains<T: StringProtocol>(_ string: T) -> Bool {
        _collationString._localizedStandardContains(string._collationString)
    }

    public func localizedCaseInsensitiveContains<T: StringProtocol>(_ string: T) -> Bool {
        _collationString._localizedCaseInsensitiveContains(string._collationString)
    }

    /// Returns the range of the first occurrence of the given string using a case-insensitive, diacritic-insensitive, locale-aware search (Finder-style matching).
    public func localizedStandardRange<T: StringProtocol>(of string: T) -> Range<Index>? {
        let text = _collationString  // once: search input AND rebase source
        guard let range = text._localizedStandardSearch(for: string._collationString) else { return nil }
        return rebaseRange(range, from: text)
    }

    /// Returns the range of the first occurrence of the given string, searching with the specified options and locale.
    public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = [], range searchRange: Range<Index>? = nil, locale: Locale?) -> Range<Index>? {
        guard let locale else { return nil }
        if mask.contains(.literal) { return nil }
        let text: String
        if let searchRange {
            text = self[searchRange]._collationString
        } else {
            text = _collationString
        }
        guard let range = text._search(for: aString._collationString, options: mask, locale: locale) else { return nil }
        if let searchRange {
            return rebaseRange(range, from: text, offsetBy: searchRange.lowerBound)
        }
        return rebaseRange(range, from: text)
    }

    /// Maps a range the search produced (indices into the materialized `source` String) back into SELF's index space. A Substring's indices stay base-string-relative — mapping through a fresh `String(self)` returned copy-space indices, misaligned for every Substring receiver (caught by SubstringReceiverTests).
    private func rebaseRange(_ range: Range<String.Index>, from source: String) -> Range<Index>? {
        // A String receiver gave `_collationString` itself, not a copy, and the search builds its indices on `source`: the range is already in self's index space.
        if Self.self == String.self { return range }
        return rebaseRange(range, from: source, offsetBy: startIndex)
    }

    /// As above, with the search having run on the slice starting at `base` in self (the `range(of:range:)` case). `source` is a copy of self from `base` on, so it holds the same UTF-8 code units: UTF-8 offsets carry over, and both index steps are O(1) on native strings (scalar offsets walked both strings).
    private func rebaseRange(_ range: Range<String.Index>, from source: String, offsetBy base: Index) -> Range<Index>? {
        // The two common receivers step through their concrete UTF-8 views, not through the generic witnesses.
        if let substring = _specialize(self, for: Substring.self) {
            return _rebase(range, from: source, into: substring.utf8, offsetBy: base, limit: endIndex)
        }
        if let string = _specialize(self, for: String.self) {
            return _rebase(range, from: source, into: string.utf8, offsetBy: base, limit: endIndex)
        }
        return _rebase(range, from: source, into: utf8, offsetBy: base, limit: endIndex)
    }
}

@inline(__always)
private func _rebase<UTF8: Collection>(_ range: Range<String.Index>, from source: String, into target: UTF8, offsetBy base: String.Index, limit: String.Index) -> Range<String.Index>? where UTF8.Index == String.Index {
    let sourceUTF8 = source.utf8
    let startOffset = sourceUTF8.distance(from: sourceUTF8.startIndex, to: range.lowerBound)
    let endOffset = sourceUTF8.distance(from: sourceUTF8.startIndex, to: range.upperBound)
    guard let start = target.index(base, offsetBy: startOffset, limitedBy: limit),
          let end = target.index(start, offsetBy: endOffset - startOffset, limitedBy: limit) else {
        return nil
    }
    return start..<end
}

/// The collator work of the wrappers above, on concrete strings.
extension String {
    fileprivate func _localizedCompare(_ other: String) -> ComparisonResult {
        if let collator = CollatorCache.shared.collatorForCurrentLocale(),
           let result = try? collator.compare(self, other) {
            return result.comparisonResult
        }
        return compare(other)
    }

    fileprivate func _localizedCaseInsensitiveCompare(_ other: String) -> ComparisonResult {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
            var opts = collator.defaultOptions
            opts.strength = .secondary
            if let result = try? collator.compare(self, other, options: opts) {
                return result.comparisonResult
            }
        }
        return compare(other, options: .caseInsensitive)
    }

    fileprivate func _localizedStandardCompare(_ other: String) -> ComparisonResult {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
            var opts = collator.defaultOptions
            opts.strength = .secondary
            opts.numeric = true
            if let result = try? collator.compare(self, other, options: opts) {
                return result.comparisonResult
            }
        }
        return compare(other, options: [.caseInsensitive, .numeric])
    }

    /// nil if the locale has no collator or the compare throws; the caller then uses the literal comparison.
    fileprivate func _compare(_ other: String, options mask: String.CompareOptions, locale: Locale) -> ComparisonResult? {
        guard let collator = CollatorCache.shared.collator(for: locale) else { return nil }
        let opts = CollationOptions.from(foundationOptions: mask, base: collator.defaultOptions)
        guard let result = try? collator.compare(self, other, options: opts) else { return nil }
        return result.comparisonResult
    }

    fileprivate func _localizedStandardContains(_ pattern: String) -> Bool {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
            var opts = collator.defaultOptions
            opts.strength = .primary
            opts.numeric = true
            return collator.contains(pattern: pattern, in: self, options: opts)
        }
        return _localizedCaseInsensitiveContains(pattern)
    }

    fileprivate func _localizedCaseInsensitiveContains(_ pattern: String) -> Bool {
        if let collator = CollatorCache.shared.collatorForCurrentLocale() {
            var opts = collator.defaultOptions
            opts.strength = .secondary
            return collator.contains(pattern: pattern, in: self, options: opts)
        }
        return contains(pattern)
    }

    fileprivate func _localizedStandardSearch(for pattern: String) -> Range<String.Index>? {
        guard let collator = CollatorCache.shared.collatorForCurrentLocale() else { return nil }
        var opts = collator.defaultOptions
        opts.strength = .primary
        opts.numeric = true
        return collator.search(for: pattern, in: self, options: opts)
    }

    fileprivate func _search(for pattern: String, options mask: String.CompareOptions, locale: Locale) -> Range<String.Index>? {
        guard let collator = CollatorCache.shared.collator(for: locale) else { return nil }
        let opts = CollationOptions.from(foundationOptions: mask, base: collator.defaultOptions)
        return mask.contains(.backwards)
            ? collator.searchBackwards(for: pattern, in: self, options: opts)
            : collator.search(for: pattern, in: self, options: opts)
    }
}
