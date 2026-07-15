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
}
