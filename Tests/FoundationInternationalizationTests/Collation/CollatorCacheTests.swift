import Testing
import FoundationEssentials
@testable import FoundationInternationalization

/// The entries that the Foundation wrappers use (technique log §51 (ak)): the collators of CollatorCache in place in their slots, through a pointer, and the default-options compare. Each must give the same answers as the plain instance methods.
@Suite struct CollatorCacheTests {
    static let strings: [String] = CollationConcurrencyTests.strings

    static func collators() throws -> [RootCollator] {
        try [RootCollator()] + ["th", "sv", "ja", "fr_CA", "da"].map { try RootCollator(tailoringNamed: $0) }
    }

    /// `compareWithDefaultOptions` skips the options compare of the entry guard; the results must not change.
    @Test func defaultOptionsCompareMatchesCompare() throws {
        let s = Self.strings
        for collator in try Self.collators() {
            for i in s.indices {
                for j in [(i + 1) % s.count, (i * 7 + 3) % s.count, i] {
                    #expect(try collator.compareWithDefaultOptions(s[i], s[j]) == collator.compare(s[i], s[j]),
                            "\(s[i].debugDescription) vs \(s[j].debugDescription)")
                }
            }
        }
    }

    /// The pointer entries against the instance methods, on the explicit-locale slots.
    @Test func pointerEntriesMatchInstanceMethods() throws {
        let s = Self.strings
        var secondary = CollationOptions(); secondary.strength = .secondary
        var primaryNumeric = CollationOptions(); primaryNumeric.strength = .primary; primaryNumeric.numeric = true
        for id in ["en_US", "sv_SE", "fr_CA", "th_TH", "ja_JP"] {
            let p = try #require(CollatorCache.shared.collator(in: Locale(identifier: id)))
            let c = p.pointee
            #expect(RootCollator.defaultOptions(at: p) == c.defaultOptions)
            for i in s.indices {
                let a = s[i], b = s[(i + 1) % s.count]
                #expect(try RootCollator.compareWithDefaultOptions(at: p, a, b) == c.compare(a, b))
                for o in [secondary, primaryNumeric] {
                    #expect(try RootCollator.compare(at: p, a, b, options: o) == c.compare(a, b, options: o))
                }
                let text = a + " " + b
                #expect(RootCollator.contains(at: p, pattern: b, in: text, options: secondary) == c.contains(pattern: b, in: text, options: secondary))
                #expect(RootCollator.search(at: p, for: b, in: text, options: secondary, backwards: false) == c.search(for: b, in: text, options: secondary))
                #expect(RootCollator.search(at: p, for: b, in: text, options: secondary, backwards: true) == c.searchBackwards(for: b, in: text, options: secondary))
            }
        }
    }

    /// Each identifier keeps ONE slot: switching between locales publishes the same slots again, it does not allocate new ones.
    @Test func explicitLocaleSlotsAreInterned() throws {
        let en = try #require(CollatorCache.shared.collator(in: Locale(identifier: "en_US")))
        let sv = try #require(CollatorCache.shared.collator(in: Locale(identifier: "sv_SE")))
        #expect(en != sv)
        for _ in 0..<3 {
            #expect(CollatorCache.shared.collator(in: Locale(identifier: "en_US")) == en)
            #expect(CollatorCache.shared.collator(in: Locale(identifier: "sv_SE")) == sv)
        }
    }

    /// The current-locale slot gives the same pointer while the locale generation does not change.
    @Test func currentLocaleSlotIsStable() throws {
        let generation = LocaleNotifications.cache.count()
        let first = try #require(CollatorCache.shared.currentLocaleCollator())
        let second = try #require(CollatorCache.shared.currentLocaleCollator())
        // Another test may change the locale in between; then a new slot is right.
        if LocaleNotifications.cache.count() == generation {
            #expect(first == second)
        }
    }
}
