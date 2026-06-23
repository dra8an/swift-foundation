//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing

#if canImport(FoundationEssentials)
@testable import FoundationEssentials
@testable import FoundationInternationalization
#else
@testable import Foundation
#endif

@Suite("String SortComparator")
private struct StringSortComparatorTests {
    @Test func compareOptionsDescriptor() {
        let compareOptions = String.Comparator(options: [.numeric])
        #expect(
            compareOptions.compare("ttestest005", "test2") ==
            "test005".compare("test2", options: [.numeric]))
        #expect(
            compareOptions.compare("test2", "test005") ==
            "test2".compare("test005", options: [.numeric]))
    }

#if FOUNDATION_FRAMEWORK
    // TODO: Until we support String.compare(_:options:locale:) in FoundationInternationalization, only support unlocalized comparisons
    // https://github.com/apple/swift-foundation/issues/284
    @Test func locale() {
        let swedishComparator = String.Comparator(options: [], locale: Locale(identifier: "sv"))
        #expect(swedishComparator.compare("ă", "ã") == .orderedAscending)
        #expect(swedishComparator.locale == Locale(identifier: "sv"))
    }

    @Test func nilLocale() {
        let swedishComparator = String.Comparator(options: [], locale: nil)
        #expect(swedishComparator.compare("ă", "ã") == .orderedDescending)
    }

    @Test func standardLocalized() async {
        await usingCurrentInternationalizationPreferences {
            var prefs = LocalePreferences()
            prefs.languages = ["en-US"]
            prefs.locale = "en_US"
            LocaleCache.cache.resetCurrent(to: prefs)
            let localizedStandard = String.StandardComparator.localizedStandard
            #expect(localizedStandard.compare("ă", "ã") == .orderedAscending)
        }

        let unlocalizedStandard = String.StandardComparator.lexical
        #expect(unlocalizedStandard.compare("ă", "ã") == .orderedDescending)
    }
#elseif FOUNDATION_COLLATION
    @Test func locale() {
        let swedishComparator = String.Comparator(options: [], locale: Locale(identifier: "sv"))
        #expect(swedishComparator.compare("ă", "ã") == .orderedAscending)
        #expect(swedishComparator.locale == Locale(identifier: "sv"))
    }

    @Test func nilLocale() {
        let swedishComparator = String.Comparator(options: [], locale: nil)
        #expect(swedishComparator.compare("ă", "ã") == .orderedDescending)
    }

    @Test func standardLocalized() {
        let localizedStandard = String.StandardComparator.localizedStandard
        #expect(localizedStandard.compare("test2", "test10") == .orderedAscending)

        let unlocalizedStandard = String.StandardComparator.lexical
        #expect(unlocalizedStandard.compare("ă", "ã") == .orderedDescending)
    }

    @Test func localizedCompare() {
        #expect("a".localizedCompare("b") == .orderedAscending)
        #expect("b".localizedCompare("a") == .orderedDescending)
        #expect("a".localizedCompare("a") == .orderedSame)
        #expect("a".localizedCompare("A") == .orderedAscending)
    }

    @Test func localizedCaseInsensitiveCompare() {
        #expect("a".localizedCaseInsensitiveCompare("A") == .orderedSame)
        #expect("café".localizedCaseInsensitiveCompare("CAFÉ") == .orderedSame)
        #expect("a".localizedCaseInsensitiveCompare("b") == .orderedAscending)
    }

    @Test func localizedStandardCompare() {
        #expect("file2".localizedStandardCompare("file10") == .orderedAscending)
        #expect("file10".localizedStandardCompare("file2") == .orderedDescending)
        #expect("File2".localizedStandardCompare("file2") == .orderedSame)
    }

    @Test func compareWithLocale() {
        let sv = Locale(identifier: "sv")
        #expect("ă".compare("ã", locale: sv) == .orderedAscending)
        #expect("a".compare("b", locale: sv) == .orderedAscending)
    }

    @Test func numericComparison() {
        let numComparator = String.Comparator(options: [.numeric], locale: Locale(identifier: "en"))
        #expect(numComparator.compare("test2", "test10") == .orderedAscending)
        #expect(numComparator.compare("test10", "test2") == .orderedDescending)
        #expect(numComparator.compare("test10", "test10") == .orderedSame)
    }

    @Test func reverseOrder() {
        let reversed = String.StandardComparator(.localized, order: .reverse)
        #expect(reversed.compare("a", "b") == .orderedDescending)
        #expect(reversed.compare("b", "a") == .orderedAscending)
    }

    @Test func localizedStandardRange() {
        let text = "the café is open"
        let range = text.localizedStandardRange(of: "cafe")
        #expect(range != nil, "Should find 'cafe' in 'café' at primary strength")
        if let r = range {
            #expect(text[r] == "café")
        }
    }

    @Test func localizedStandardRangeNoMatch() {
        let range = "hello world".localizedStandardRange(of: "xyz")
        #expect(range == nil)
    }

    @Test func rangeWithLocale() {
        let sv = Locale(identifier: "sv")
        let text = "hello world"
        let range = text.range(of: "world", locale: sv)
        #expect(range != nil)
        if let r = range {
            #expect(text[r] == "world")
        }
    }

    @Test func rangeWithLocaleCaseInsensitive() {
        let en = Locale(identifier: "en")
        var opts = String.CompareOptions()
        opts.insert(.caseInsensitive)
        let text = "Hello World"
        let range = text.range(of: "hello", options: opts, locale: en)
        #expect(range != nil)
        if let r = range {
            #expect(text[r] == "Hello")
        }
    }
#endif
}
