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

/// A tailoring's default SETTINGS (fr_CA backwards secondary) must apply when no options are passed — engine entries resolve nil options to the collator's defaultOptions, and the CompareOptions translation merges onto that base (the bug §44's test found; fix decision in optimization-targets.md §45).
@Suite("Tailoring default options")
private struct TailoringDefaultOptionsTests {
    /// French backwards secondary: "côte" sorts before "coté" (the last accent difference decides). A collator opened for fr_CA must apply it with NO options argument, like ucol_open + ucol_strcoll.
    @Test func engineAppliesTailoringDefaults() throws {
        let fr = try RootCollator(tailoringNamed: "fr_CA")
        #expect(try fr.compare("coté", "côte") == .descending)
        // Explicit options still win: forward secondary restores the root order.
        var forward = fr.defaultOptions
        forward.backwardSecondary = false
        #expect(try fr.compare("coté", "côte", options: forward) == .ascending)
        // Root behavior unchanged: its defaultOptions are the plain defaults.
        let root = try RootCollator()
        #expect(try root.compare("coté", "côte") == .ascending)
    }

    /// The same pair through the Foundation wrapper with fr_CA as the current locale — the exact scenario the bug hid: character-data tailorings applied, settings tailorings silently did not.
    @Test func wrapperAppliesTailoringDefaults() async {
        await usingCurrentInternationalizationPreferences {
            var en = LocalePreferences()
            en.languages = ["en-US"]
            en.locale = "en_US"
            var fr = LocalePreferences()
            fr.languages = ["fr-CA"]
            fr.locale = "fr_CA"

            LocaleNotifications.cache.reset()
            LocaleCache.cache.resetCurrent(to: en)
            #expect("coté".localizedCompare("côte") == .orderedAscending)

            LocaleNotifications.cache.reset()
            LocaleCache.cache.resetCurrent(to: fr)
            #expect("coté".localizedCompare("côte") == .orderedDescending)

            // Leave no generation binding behind for later tests.
            LocaleNotifications.cache.reset()
        }
    }
}
