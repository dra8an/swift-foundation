import Testing
@testable import FoundationInternationalization

/// Ports of the behavioral parts of ICU4C's CollationAPITest
/// (intltest/apicoll.cpp). Most of that suite exercises the C++ API surface
/// — constructors, clone/operators, registry and display names, rule-string
/// access, collation element iterators, subclassing — which has no
/// counterpart here. What carries over is comparison and sort-key behavior:
/// TestProperty's comparisons, TestCompare's strength behavior,
/// TestCollationKey/TestSortKey's key properties, and TestMaxVariable.
@Suite struct ApicollTests {
    private static let _root = Result { try RootCollator() }
    static var root: RootCollator { get throws { try _root.get() } }

    /// TestProperty: basic comparisons at default (tertiary) strength under
    /// the en collator (root-equivalent for these strings).
    @Test func propertyComparisons() throws {
        let c = try Self.root
        #expect(try c.compare("ab", "abc") == .ascending)
        #expect(try c.compare("ab", "AB") == .ascending)
        #expect(try c.compare("blackbird", "black-bird") == .descending)
        #expect(try c.compare("black bird", "black-bird") == .ascending)
        #expect(try c.compare("Hello", "hello") == .descending)
        #expect(try c.compare("", "") == .same)
        #expect(try c.compare("ab\u{E4}", "ab\u{DF}") == .ascending)  // ab-ä < ab-ß
    }

    /// TestCompare: "Abcda" vs "abcda" is a tertiary (case) difference only.
    @Test func compareStrengths() throws {
        var options = CollationOptions()
        #expect(options.strength == .tertiary)  // ICU's default strength
        #expect(try Self.root.compare("Abcda", "abcda", options: options) == .descending)
        options.strength = .secondary
        #expect(try Self.root.compare("Abcda", "abcda", options: options) == .same)
        options.strength = .primary
        #expect(try Self.root.compare("Abcda", "abcda", options: options) == .same)
    }

    /// TestCollationKey: the empty string's key has empty levels (exactly
    /// 01 01 00 at tertiary strength), and a string of completely ignorable
    /// characters (U+0001, U+034F CGJ) produces the same key.
    @Test func emptyAndIgnorableKeys() throws {
        let empty = try Self.root.sortKey(for: "")
        #expect(empty == [1, 1, 0])
        let ignorable = try Self.root.sortKey(for: "\u{01}\u{34F}")
        #expect(ignorable == empty)
        #expect(try Self.root.compare("\u{01}\u{34F}", "") == .same)
    }

    /// TestCollationKey/TestSortKey: keys order like compare() at each
    /// strength, and a lower-strength key is a prefix of the higher-strength
    /// key (minus the terminator) for strings without higher-level data.
    @Test func sortKeyStrengths() throws {
        var identical = CollationOptions()
        identical.strength = .identical
        let keyUpperI = try Self.root.sortKey(for: "Abcda", options: identical)
        let keyLowerI = try Self.root.sortKey(for: "abcda", options: identical)
        #expect(keyLowerI.lexicographicallyPrecedes(keyUpperI))

        var secondary = CollationOptions()
        secondary.strength = .secondary
        let keyUpperS = try Self.root.sortKey(for: "Abcda", options: secondary)
        let keyLowerS = try Self.root.sortKey(for: "abcda", options: secondary)
        #expect(keyUpperS == keyLowerS)

        // The secondary key without its 00 terminator prefixes the
        // identical-strength key of the same string.
        #expect(Array(keyLowerI.prefix(keyLowerS.count - 1)) == keyLowerS.dropLast())
    }

    /// TestMaxVariable: with maxVariable=currency and alternate=shifted,
    /// currency symbols become variable (ignorable below quaternary) while
    /// digits stay regular.
    @Test func maxVariableCurrency() throws {
        var options = CollationOptions()
        options.alternate = .shifted
        options.maxVariable = .currency
        #expect(try Self.root.compare("", "$", options: options) == .same)
        #expect(try Self.root.compare("", "\u{20AC}", options: options) == .same)
        #expect(try Self.root.compare("$", "0", options: options) == .ascending)
        // The default maxVariable (punctuation) leaves currency regular.
        options.maxVariable = .punctuation
        #expect(try Self.root.compare("", "$", options: options) == .ascending)
    }
}
