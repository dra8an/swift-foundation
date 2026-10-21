//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import Testing

#if canImport(FoundationEssentials)
@testable import FoundationEssentials
@testable import FoundationInternationalization
#elseif FOUNDATION_FRAMEWORK
@testable import Foundation
#endif

/// Substring receivers must get ranges back in THEIR OWN index space —
/// a Substring's indices are base-string-relative, so mapping offsets into
/// a fresh String copy (0-based) misaligns every result by the substring's
/// start offset (§26/§39 wrapper audit).
@Suite("Substring receiver index spaces")
private struct SubstringReceiverTests {
    @Test func localizedStandardRangeOnSubstring() {
        let base = "xxcafe latte"
        let sub = base.dropFirst(2)   // "cafe latte", indices offset by 2
        guard let r = sub.localizedStandardRange(of: "latte") else {
            Issue.record("no match found")
            return
        }
        #expect(String(sub[r]) == "latte")
    }

    @Test func rangeOfLocaleOnSubstring() {
        let base = "zzbeta gamma"
        let sub = base.dropFirst(2)   // "beta gamma"
        guard let r = sub.range(of: "gamma", options: [], locale: Locale(identifier: "en")) else {
            Issue.record("no match found")
            return
        }
        #expect(String(sub[r]) == "gamma")
    }

    @Test func rangeOfWithSearchRangeOnString() {
        let s = "alpha beta alpha"
        let second = s.index(s.startIndex, offsetBy: 6)..<s.endIndex
        guard let r = s.range(of: "alpha", options: [], range: second, locale: Locale(identifier: "en")) else {
            Issue.record("no match found")
            return
        }
        #expect(String(s[r]) == "alpha")
        #expect(r.lowerBound >= second.lowerBound)
    }

    /// A String receiver returns the search's range without a rebase (the search ran on the receiver itself). It must equal the rebased range of the same text as a whole-string Substring.
    @Test func stringReceiverRangeEqualsRebasedRange() {
        let en = Locale(identifier: "en")
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let cases: [(text: String, pattern: String)] = [
            ("cafe latte", "latte"),
            ("Café LATTE café", "cafe"),
            ("e\u{301}cole, école", "ecole"),
            ("x\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467} family \u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}", "family"),
            ("Straße strasse", "STRASSE"),
            ("file10 file2", "file2"),
            ("한국어 텍스트", "텍스트"),
            ("ภาษาไทย ภาษา", "ภาษา"),
            ("no match here", "xyz"),
        ]
        var matches = 0
        for (text, pattern) in cases {
            let whole = text[...]
            let standard = text.localizedStandardRange(of: pattern)
            #expect(standard == whole.localizedStandardRange(of: pattern), "localizedStandardRange: \(text) / \(pattern)")
            let forward = text.range(of: pattern, options: options, locale: en)
            #expect(forward == whole.range(of: pattern, options: options, locale: en), "range(of:): \(text) / \(pattern)")
            let backward = text.range(of: pattern, options: options.union(.backwards), locale: en)
            #expect(backward == whole.range(of: pattern, options: options.union(.backwards), locale: en), "backwards: \(text) / \(pattern)")
            if standard != nil { matches += 1 }
        }
        #expect(matches >= 7)
    }

    /// Multibyte text before and inside the match: UTF-8 offsets, scalar offsets and Character offsets all differ here, so a rebase that mixes them up returns the wrong text.
    @Test func rebaseWithMultibyteText() {
        let en = Locale(identifier: "en")
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let base = "ÄÖ\u{1F600}e\u{301} – café LÄTTE, e\u{301}cole 한국어 end"
        let sub = base.dropFirst(4)   // " – café …": starts after 2 two-byte letters, an emoji and a decomposed é
        let searchRange = base.index(base.startIndex, offsetBy: 5)..<base.endIndex
        for (pattern, expected) in [("latte", "LÄTTE"), ("ecole", "e\u{301}cole"), ("한국어", "한국어"), ("cafe", "café"), ("end", "end")] {
            #expect(sub.localizedStandardRange(of: pattern).map { String(sub[$0]) } == expected, "localizedStandardRange: \(pattern)")
            #expect(sub.range(of: pattern, options: options, locale: en).map { String(sub[$0]) } == expected, "range(of:): \(pattern)")
            #expect(sub.range(of: pattern, options: options.union(.backwards), locale: en).map { String(sub[$0]) } == expected, "backwards: \(pattern)")
            #expect(base.range(of: pattern, options: options, range: searchRange, locale: en).map { String(base[$0]) } == expected, "search range: \(pattern)")
            #expect(sub.range(of: pattern, options: options, range: searchRange, locale: en).map { String(sub[$0]) } == expected, "Substring search range: \(pattern)")
        }
    }
}
