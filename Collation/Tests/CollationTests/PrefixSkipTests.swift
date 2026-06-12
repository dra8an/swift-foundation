import Testing
@testable import Collation

/// Targeted tests for the identical-prefix skip in compare(): pairs whose
/// shared prefix ends right where restarting iteration is dangerous —
/// contraction trailers, combining marks, prefix-context (precontext)
/// characters, digit runs under numeric collation.
///
/// The referee is sortKey(): it never skips (it always processes the whole
/// string), and byte-wise key order is documented to equal compare() at the
/// same options. Any skip bug that changes a result breaks that agreement.
@Suite struct PrefixSkipTests {
    static let root = try! RootCollator()
    static let ja = try! RootCollator(tailoringNamed: "ja")
    static let th = try! RootCollator(tailoringNamed: "th")

    /// compare() agrees with byte-wise sort key order, in both directions.
    func expectKeyAgreement(
        _ collator: RootCollator, _ a: String, _ b: String,
        options: CollationOptions,
        _ comment: Comment? = nil
    ) throws {
        let keyOrder: RootCollator.Order
        let ka = try collator.sortKey(for: a, options: options)
        let kb = try collator.sortKey(for: b, options: options)
        if ka == kb {
            keyOrder = .same
        } else {
            keyOrder = ka.lexicographicallyPrecedes(kb) ? .ascending : .descending
        }
        #expect(try collator.compare(a, b, options: options) == keyOrder, comment)
        let reversed: RootCollator.Order = switch keyOrder {
        case .ascending: .descending
        case .descending: .ascending
        case .same: .same
        }
        #expect(try collator.compare(b, a, options: options) == reversed, comment)
    }

    func expectKeyAgreementAtAllStrengths(
        _ collator: RootCollator, _ a: String, _ b: String,
        numeric: Bool = false, backwardSecondary: Bool = false,
        _ comment: Comment? = nil
    ) throws {
        for strength in [CollationOptions.Strength.primary, .secondary, .tertiary, .quaternary, .identical] {
            var options = collator.defaultOptions
            options.strength = strength
            options.numeric = numeric
            options.backwardSecondary = backwardSecondary
            try expectKeyAgreement(collator, a, b, options: options, comment)
        }
    }

    @Test func numericDigitRunsSpanningTheBoundary() throws {
        var options = CollationOptions()
        options.numeric = true
        // The shared prefix ends inside a digit run; restarting there without
        // backing up would compare "2" against "0" instead of 2 against 10.
        #expect(try Self.root.compare("a12", "a2", options: options) == .descending)
        #expect(try Self.root.compare("x12", "x13", options: options) == .ascending)
        #expect(try Self.root.compare("12", "123", options: options) == .ascending)
        for (a, b) in [("a12", "a2"), ("x12", "x13"), ("12", "123"), ("a02", "a2"), ("b10x", "b10y")] {
            try expectKeyAgreementAtAllStrengths(Self.root, a, b, numeric: true)
        }
    }

    @Test func prolongedSoundMarkNeedsTheSkippedKana() throws {
        // ja: U+30FC's mapping has kana prefix (precontext) conditions; the
        // shared prefix must back up so the mark still sees its base kana.
        for (a, b) in [("カー", "カア"), ("ミー", "ミア"), ("カアー", "カアア"), ("ピーチ", "ピアノ")] {
            try expectKeyAgreementAtAllStrengths(Self.ja, a, b, a == "カー" ? "prolonged sound mark" : nil)
        }
    }

    @Test func combiningMarksAtTheBoundary() throws {
        // First difference lands on a combining mark (lccc != 0): the mark
        // may reorder or contract with what precedes it.
        for (a, b) in [
            ("cote\u{0301}", "cote"),                 // é decomposed vs plain
            ("cot\u{0302}e", "cote\u{0301}"),         // marks on different bases
            ("a\u{0301}\u{0327}", "a\u{0327}\u{0301}"),  // canonically equivalent mark order
            ("\u{0418}\u{0306}x", "\u{0418}y"),       // Cyrillic И + breve (root contraction)
        ] {
            try expectKeyAgreementAtAllStrengths(Self.root, a, b)
            try expectKeyAgreementAtAllStrengths(Self.root, a, b, backwardSecondary: true)
        }
    }

    @Test func thaiPrevowelContractions() throws {
        // th: prevowel + consonant pairs are contractions; consonants are
        // contraction trailers, so a difference right after a shared prevowel
        // must back up over it.
        for (a, b) in [("เก", "เข"), ("เกา", "เขา"), ("แกะ", "แกๆ")] {
            try expectKeyAgreementAtAllStrengths(Self.th, a, b)
        }
    }

    @Test func hangulAndSupplementaryBoundaries() throws {
        for (a, b) in [
            ("가나", "가다"),                          // syllables (arithmetic decomposition)
            ("가\u{1100}", "가\u{1161}"),              // syllable then raw Jamo
            ("\u{1D400}b", "\u{1D400}c"),             // supplementary-plane shared prefix
        ] {
            try expectKeyAgreementAtAllStrengths(Self.root, a, b)
        }
    }

    @Test func prefixOfTheOtherAndIgnorableTails() throws {
        for (a, b) in [
            ("ab", "abc"),
            ("ab", "ab\u{0001}"),    // completely ignorable tail: equal below identical
            ("ab", "ab\u{0301}"),    // secondary-only tail
        ] {
            try expectKeyAgreementAtAllStrengths(Self.root, a, b)
        }
    }

    @Test func unsafeBackwardSetParses() throws {
        let data = try CollationData.root()
        // The root data must carry a non-trivial serialized set (contraction
        // trailers), and membership must see both BMP and supplementary parts.
        #expect(!data.unsafeBackward.isEmpty)
        // U+0306 (combining breve) trails the Cyrillic И contraction.
        #expect(data.unsafeBackwardContains(0x0306))
        // 'b' starts no contraction suffix in root data.
        #expect(!data.unsafeBackwardContains(UInt32(UnicodeScalar("b").value)))
    }
}
