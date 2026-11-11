//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
@testable import FoundationInternationalization

/// Behavioral tests at primary strength.
@Suite struct PrimaryCompareTests {
    private static let _collator = Result { try RootCollator() }
    var collator: PrimaryStrengthCollator {
        get throws { PrimaryStrengthCollator(base: try Self._collator.get()) }
    }

    /// Wrapper fixing options at primary strength, preserving the original shape of these tests (written when compare() was primary-only).
    struct PrimaryStrengthCollator {
        let base: RootCollator
        func compare(_ l: String, _ r: String) throws -> RootCollator.Order {
            var options = CollationOptions()
            options.strength = .primary
            return try base.compare(l, r, options: options)
        }
        func primaries(of s: String) throws -> [UInt32] {
            try base.primaries(of: s)
        }
    }

    @Test func dataLoads() throws {
        let data = try CollationData.root()
        #expect(data.ce32s.count > 0)
        #expect(data.ces.count > 0)
        #expect(data.jamoCE32sStart >= 0)
        // Single-byte primary lead for numeric collation (0x10 in ICU 79 root data).
        #expect(data.numericPrimary == 0x1000_0000)
    }

    @Test(arguments: [
        ("a", "b", RootCollator.Order.ascending), ("b", "a", .descending), ("a", "a", .same), ("abc", "abd", .ascending), ("ab", "b", .ascending),
    ])
    func basicLetterOrder(left: String, right: String, expected: RootCollator.Order) throws {
        #expect(try collator.compare(left, right) == expected)
    }

    /// Case is a tertiary difference, so it is equal at primary strength; "Z" shares its primary with "z", which sorts after "a".
    @Test(arguments: [("a", "A", RootCollator.Order.same), ("HELLO", "hello", .same), ("Z", "a", .descending)])
    func caseIsPrimaryEqual(left: String, right: String, expected: RootCollator.Order) throws {
        #expect(try collator.compare(left, right) == expected)
    }

    /// Root order of the major groups: space < punctuation < digits < letters. Without numeric mode, digits compare digit by digit ("12" < "2").
    @Test(arguments: [(" ", "!"), ("!", "1"), ("9", "a"), ("12", "2")])
    func groupOrder(smaller: String, larger: String) throws {
        #expect(try collator.compare(smaller, larger) == .ascending)
    }

    @Test(arguments: [("", "", RootCollator.Order.same), ("", "a", .ascending), ("a", "a ", .ascending)])
    func prefixesAndEmpty(left: String, right: String, expected: RootCollator.Order) throws {
        #expect(try collator.compare(left, right) == expected)
    }

    /// Latin < Greek < Han (OFFSET and implicit primaries) < unassigned (lead byte 0xFE).
    @Test(arguments: [("z", "α"), ("α", "一"), ("一", "\u{0378}")])
    func scriptsAndImplicits(smaller: String, larger: String) throws {
        #expect(try collator.compare(smaller, larger) == .ascending)
    }

    /// Han characters are ordered among themselves.
    @Test func hanIdeographsAreOrdered() throws {
        #expect(try collator.compare("一", "丁") != .same)
    }

    /// Hangul syllables decompose to Jamo; in the root, syllable order follows code point order for these. 각 = 가 + a trailing consonant: the longer Jamo sequence sorts after.
    @Test(arguments: [("가", "나", RootCollator.Order.ascending), ("가", "가", .same), ("a", "가", .ascending), ("가", "각", .ascending)])
    func hangul(left: String, right: String, expected: RootCollator.Order) throws {
        #expect(try collator.compare(left, right) == expected)
    }

    @Test func controlCharactersArePrimaryIgnorable() throws {
        // U+0001 etc. are primary ignorable; U+0000 maps through the U0000 tag.
        #expect(try collator.compare("a\u{1}b", "ab") == .same)
        #expect(try collator.compare("a\u{0}b", "ab") == .same)
    }

    @Test func expansionsWork() throws {
        // U+00E6 LATIN SMALL LETTER AE expands to two primaries (a, e) in root.
        let primaries = try collator.primaries(of: "æ")
        #expect(primaries.filter { $0 != 0 }.count == 2)
        #expect(try collator.compare("æ", "ae") == .same)
    }
}
