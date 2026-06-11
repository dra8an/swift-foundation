import Testing
@testable import UCACollation

/// Targeted tests that the context-dependent paths (prefix and contraction
/// matching) actually fire — the reference matrices prove agreement with ICU,
/// these prove the mappings are context-sensitive at all.
@Suite struct ContextTests {
    static let collators: [(String, RootCollator)] = [
        ("regular", try! RootCollator()),
        ("icu4x", RootCollator(data: try! .rootICU4X(), norm: try! .standard())),
    ]

    /// Root data has exactly four prefix entries: U+00B7 (and U+0387) after
    /// l/L gets a secondary-only CE (Catalan l·l support). After any other
    /// character, U+00B7 keeps its default punctuation CE.
    /// (The vowel-dependent kana prolonged sound mark is a Japanese tailoring,
    /// not root data — milestone 7.)
    @Test(arguments: [0, 1]) func middleDotDependsOnPrefix(collatorIndex: Int) throws {
        let (name, collator) = Self.collators[collatorIndex]
        let afterL = try collator.collationElements(of: "l·")[1]
        let afterX = try collator.collationElements(of: "x·")[1]
        #expect(afterL != afterX, "[\(name)] prefix condition after l did not fire")
        // The prefixed CE is secondary-only: primary weight 0.
        #expect(Collation.primaryFromCE(afterL) == 0, "[\(name)] l·'s dot must be primary-ignorable")
        #expect(Collation.primaryFromCE(afterX) != 0, "[\(name)] x·'s dot keeps its punctuation primary")
        // Uppercase L and the Greek ano teleia variant behave the same way.
        #expect(try collator.collationElements(of: "L·")[1] == afterL)
        #expect(try collator.collationElements(of: "l\u{0387}")[1] == afterL)
    }

    /// Tibetan U+0F71+U+0F72 is a contraction in root data equal to the
    /// composite vowel U+0F73 (which decomposes to that very sequence).
    /// The contraction must consume the second mark: one CE pair, not two
    /// independent mark CEs.
    @Test(arguments: [0, 1]) func tibetanVowelContraction(collatorIndex: Int) throws {
        let (name, collator) = Self.collators[collatorIndex]
        let composite = try collator.collationElements(of: "\u{0F73}")
        let sequence = try collator.collationElements(of: "\u{0F71}\u{0F72}")
        #expect(composite == sequence, "[\(name)] 0F71+0F72 must yield identical CEs to 0F73")
    }

    /// Blocking (UTS #10 S2.1.2): U+0F80 (ccc 130) between U+0F71 and U+0F72
    /// (also ccc 130) blocks the discontiguous match; 0F71+0F80 matches as a
    /// contraction instead, and the result differs from the unblocked order.
    @Test(arguments: [0, 1]) func equalCCCBlocksDiscontiguousMatch(collatorIndex: Int) throws {
        let (name, collator) = Self.collators[collatorIndex]
        let blocked = try collator.collationElements(of: "\u{0F71}\u{0F80}\u{0F72}")
        let unblocked = try collator.collationElements(of: "\u{0F71}\u{0F72}\u{0F80}")
        #expect(blocked != unblocked, "[\(name)] equal-ccc mark order must be significant (blocking)")
    }
}

/// Kana/Tibetan canonical equivalents through the contraction machinery.
@Suite struct ContextEquivalenceTests {
    @Test(arguments: [0, 1]) func equivalentsThroughContexts(collatorIndex: Int) throws {
        let (name, collator) = ContextTests.collators[collatorIndex]
        var options = CollationOptions()
        options.strength = .identical
        let classes: [[String]] = [
            ["ば", "は\u{3099}"],
            ["ぱ", "は\u{309A}"],
            ["ヴ", "ウ\u{3099}"],
            ["\u{0F75}", "\u{0F71}\u{0F74}"],
            ["\u{0F81}", "\u{0F71}\u{0F80}"],
            ["ཀ\u{0F73}", "ཀ\u{0F71}\u{0F72}"],
        ]
        for cls in classes {
            for a in cls {
                for b in cls {
                    #expect(try collator.compare(a, b, options: options) == .same,
                            "[\(name)] \(a.debugDescription) vs \(b.debugDescription)")
                }
            }
        }
    }
}
