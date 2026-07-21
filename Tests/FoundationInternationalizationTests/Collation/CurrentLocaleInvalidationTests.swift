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

/// The current-locale collator cache revalidates against Foundation's locale generation count (LocaleNotifications), so a mid-process system locale change is picked up by the next localized call — matching the Darwin contract (design record: Collation/Docs/29).
@Suite("Current-locale collator invalidation")
private struct CurrentLocaleInvalidationTests {
    /// Swedish sorts "ä" as a separate letter after "z" while root groups it with "a" — the canonical sv-vs-root discriminator, exercised by the sv locale suite. The locale flips are driven through the same internal hooks the platform notification paths use — LocaleNotifications.cache.reset() bumps the generation, resetCurrent(to:) installs the new current locale.
    @Test func currentLocaleChangeIsPickedUp() async {
        await usingCurrentInternationalizationPreferences {
            var en = LocalePreferences()
            en.languages = ["en-US"]
            en.locale = "en_US"
            var sv = LocalePreferences()
            sv.languages = ["sv-SE"]
            sv.locale = "sv_SE"

            LocaleNotifications.cache.reset()
            LocaleCache.cache.resetCurrent(to: en)
            #expect("ä".localizedCompare("z") == .orderedAscending)

            // Mid-process language change: the very next call must resolve the sv tailoring.
            LocaleNotifications.cache.reset()
            LocaleCache.cache.resetCurrent(to: sv)
            #expect("ä".localizedCompare("z") == .orderedDescending)

            // And back.
            LocaleNotifications.cache.reset()
            LocaleCache.cache.resetCurrent(to: en)
            #expect("ä".localizedCompare("z") == .orderedAscending)

            // Leave no generation binding behind for later tests: the helper's cache reset does not bump the generation.
            LocaleNotifications.cache.reset()
        }
    }
}
