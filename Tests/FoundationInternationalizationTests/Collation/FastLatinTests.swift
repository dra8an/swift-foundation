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

/// Unit tests for the fast Latin path (CollationFastLatin). The end-to-end correctness evidence is the existing suites — the differential matrices and the key-agreement tests run every compare() through the integrated fast path — so what is pinned here is the machinery itself: that the fast path actually engages (returns real results, not bail-outs) where it should, and bails out where it must.
@Suite struct FastLatinTests {
    private static let _root = Result { try RootCollator() }
    static var root: RootCollator { get throws { try _root.get() } }

    static func side(_ s: String) -> CollationFastLatin.Side {
        var iterator = s.unicodeScalars.makeIterator()
        return CollationFastLatin.Side(next: iterator.next()?.value, rest: iterator)
    }

    /// Computes (table, primaries, packed options) for an option set, like RootCollator's per-scratch cache does.
    static func setup(_ options: CollationOptions) throws -> (UnsafeBufferPointer<UInt16>, [UInt16], Int32) {
        let table = try Self.root.data.fastLatinTable
        var primaries: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: table, scriptsData: try Self.root.data, reordering: nil,
            options: options.icuOptions, primaries: &primaries)
        return (table, primaries, packed)
    }

    @Test func rootTableLoadsAndOptionsAreSupported() throws {
        let table = try Self.root.data.fastLatinTable
        #expect(!table.isEmpty)
        #expect(table[0] >> 8 == CollationFastLatin.version)
        let (_, primaries, packed) = try Self.setup(CollationOptions())
        #expect(packed >= 0)
        #expect(primaries.count == CollationFastLatin.latinLimit)
        // Letters have short primaries; with alternate=non-ignorable nothing is variable, so space and punctuation keep nonzero primaries too.
        #expect(primaries[Int(UnicodeScalar("a").value)] != 0)
        #expect(primaries[0x20] != 0)
    }

    /// Real results, not bail-outs, for plain ASCII and Latin-1 text.
    @Test(arguments: [
        ("ab", "ac", Int32(-1)),
        ("ab", "ab", 0),
        ("b", "a", 1),
        ("côte", "côte", 0),       // U+00F4 is in the table
        ("ab", "abc", -1),
        ("Hello", "hello", 1),
    ])
    func engagesForPlainText(a: String, b: String, expected: Int32) throws {
        let (table, primaries, packed) = try Self.setup(CollationOptions())
        let got = CollationFastLatin.compare(
            table: table, primaries: primaries, options: packed,
            left: Self.side(a), right: Self.side(b))
        #expect(got == expected, "\(a) vs \(b)")
    }

    @Test func bailsOutWhereItMust() throws {
        let (table, primaries, packed) = try Self.setup(CollationOptions())
        // Out-of-range characters bail (the integration layer normally pre-checks the first scalars; mid-string ones bail here).
        #expect(CollationFastLatin.compare(
            table: table, primaries: primaries, options: packed,
            left: Self.side("a\u{4E00}"), right: Self.side("ab")) == CollationFastLatin.bailOutResult)
        // Combining marks are out of range too.
        #expect(CollationFastLatin.compare(
            table: table, primaries: primaries, options: packed,
            left: Self.side("a\u{300}"), right: Self.side("ab")) == CollationFastLatin.bailOutResult)

        // Digits bail under numeric collation (their primaries are zeroed).
        var numeric = CollationOptions()
        numeric.numeric = true
        let (_, numPrimaries, numPacked) = try Self.setup(numeric)
        #expect((0x30...0x39).allSatisfy { numPrimaries[$0] == 0 })
        #expect(CollationFastLatin.compare(
            table: table, primaries: numPrimaries, options: numPacked,
            left: Self.side("a2"), right: Self.side("a10")) == CollationFastLatin.bailOutResult)
        // ... but compare without digits still works under numeric options.
        #expect(CollationFastLatin.compare(
            table: table, primaries: numPrimaries, options: numPacked,
            left: Self.side("ab"), right: Self.side("ac")) == -1)

        // Backwards secondary bails only when a secondary difference shows.
        var french = CollationOptions()
        french.backwardSecondary = true
        let (_, frPrimaries, frPacked) = try Self.setup(french)
        #expect(frPacked >= 0)
        #expect(CollationFastLatin.compare(
            table: table, primaries: frPrimaries, options: frPacked,
            left: Self.side("cote"), right: Self.side("cot\u{E9}")) == CollationFastLatin.bailOutResult)
        #expect(CollationFastLatin.compare(
            table: table, primaries: frPrimaries, options: frPacked,
            left: Self.side("cote"), right: Self.side("cotf")) == -1)
    }

    @Test func shiftedPunctuationIsVariable() throws {
        var shifted = CollationOptions()
        shifted.alternate = .shifted
        let (table, primaries, packed) = try Self.setup(shifted)
        #expect(packed >= 0)
        // Punctuation is variable under shifted: primary zeroed in the precomputed table, and "black-bird" == "blackbird" up to tertiary.
        #expect(primaries[Int(UnicodeScalar("-").value)] == 0)
        #expect(CollationFastLatin.compare(
            table: table, primaries: primaries, options: packed,
            left: Self.side("black-bird"), right: Self.side("blackbird")) == 0)
        // At quaternary strength the variable difference resurfaces.
        var shiftedQ = shifted
        shiftedQ.strength = .quaternary
        let (_, qPrimaries, qPacked) = try Self.setup(shiftedQ)
        #expect(CollationFastLatin.compare(
            table: table, primaries: qPrimaries, options: qPacked,
            left: Self.side("black-bird"), right: Self.side("blackbird")) == -1)
    }

    static func utf8Compare(
        _ a: String, _ b: String, table: UnsafeBufferPointer<UInt16>,
        primaries: [UInt16], packed: Int32
    ) throws -> Int32 {
        var aa = a
        var bb = b
        return try aa.withUTF8 { lBytes in
            try bb.withUTF8 { rBytes in
                try primaries.withUnsafeBufferPointer { pBuf in
                    CollationFastLatin.compareUTF8(
                        table: table, primaries: try #require(pBuf.baseAddress), options: packed,
                        left: lBytes, right: rBytes)
                }
            }
        }
    }

    /// The UTF-8 variant agrees with the scalar variant and handles the byte-level cases: two-byte Latin assembly, the three-byte punctuation block, and bail-outs for unsupported lead bytes.
    @Test(arguments: [
        ("ab", "ac"), ("ab", "ab"), ("b", "a"), ("Hello", "hello"),
        ("p\u{E9}ch\u{E9}", "p\u{EA}che"),       // 2-byte Latin-1 leads
        ("\u{152}uf", "\u{153}uf"),              // Œ/œ: Latin Extended-A
        ("a\u{2014}b", "a-b"),                   // em dash: E2 80 94
        ("a\u{4E00}", "ab"),                     // CJK lead byte: bail
        ("a\u{300}", "ab"),                      // combining mark: bail
        ("ab", "abc"), ("", "a"),
    ])
    func utf8VariantMatchesScalarVariant(a: String, b: String) throws {
        let (table, primaries, packed) = try Self.setup(CollationOptions())
        let viaScalars = CollationFastLatin.compare(
            table: table, primaries: primaries, options: packed,
            left: Self.side(a), right: Self.side(b))
        let viaBytes = try Self.utf8Compare(a, b, table: table, primaries: primaries, packed: packed)
        #expect(viaBytes == viaScalars, "\(a.debugDescription) vs \(b.debugDescription)")
    }

    private static let _da = Result { try RootCollator(tailoringNamed: "da") }
    static var da: RootCollator { get throws { try _da.get() } }

    /// The contraction lookahead consumes multi-byte characters correctly: da tailors "aa" (a contraction with its own fast Latin table), which sorts as a separate letter after z.
    @Test(arguments: [("aa", "ab", Int32(1)), ("aa", "z", 1), ("ab", "ac", -1)])
    func utf8ContractionLookahead(a: String, b: String, expected: Int32) throws {
        let da = try Self.da
        #expect(!da.data.fastLatinTable.isEmpty)
        var primaries: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: da.data.fastLatinTable, scriptsData: try #require(da.base), reordering: nil,
            options: da.defaultOptions.icuOptions, primaries: &primaries)
        #expect(packed >= 0)
        let got = try Self.utf8Compare(a, b, table: da.data.fastLatinTable, primaries: primaries, packed: packed)
        #expect(got == expected, "\(a) vs \(b)")
    }

    /// The same contraction through the integrated path, against sort keys (which never use fast Latin).
    @Test(arguments: [("aa", "ab"), ("aa", "z"), ("haab", "hzb"), ("a\u{E5}", "aa")])
    func danishContractionAgreesWithSortKeys(a: String, b: String) throws {
        let da = try Self.da
        let got = try da.compare(a, b)
        let ka = try da.sortKey(for: a)
        let kb = try da.sortKey(for: b)
        let keyOrder: RootCollator.Order =
            ka == kb ? .same : (ka.lexicographicallyPrecedes(kb) ? .ascending : .descending)
        #expect(got == keyOrder, "\(a.debugDescription) vs \(b.debugDescription)")
    }

    /// The option sets of `integrationAgreesWithSortKeys`, by name.
    static func integrationOptions(_ name: String) -> CollationOptions {
        var o = CollationOptions()
        switch name {
        case "shifted": o.alternate = .shifted
        case "quaternary-shifted": o.strength = .quaternary; o.alternate = .shifted
        case "upperFirst": o.caseFirst = .upperFirst
        case "caseLevel": o.caseLevel = true
        case "primary": o.strength = .primary
        case "identical": o.strength = .identical
        default: break
        }
        return o
    }

    /// The integrated path agrees with sort keys (which never use fast Latin) for pairs chosen to traverse every level loop and the punctuation/contraction handling, across option sets.
    @Test(arguments: ["default", "shifted", "quaternary-shifted", "upperFirst", "caseLevel", "primary", "identical"], [
        ("ab", "ac"), ("ab", "Ab"), ("ab", "ab"), ("p\u{E9}ch\u{E9}", "p\u{EA}che"),
        ("black-bird", "blackbird"), ("black bird", "black-bird"),
        ("a\u{2014}b", "a-b"),  // em dash: punctuation block lookup
        ("Tt", "tT"), ("a", "a\u{1}"), ("ab", "abc"), ("", "a"),
    ])
    func integrationAgreesWithSortKeys(optionSet: String, pair: (String, String)) throws {
        let options = Self.integrationOptions(optionSet)
        let (a, b) = pair
        let got = try Self.root.compare(a, b, options: options)
        let ka = try Self.root.sortKey(for: a, options: options)
        let kb = try Self.root.sortKey(for: b, options: options)
        let keyOrder: RootCollator.Order =
            ka == kb ? .same : (ka.lexicographicallyPrecedes(kb) ? .ascending : .descending)
        #expect(got == keyOrder, "[\(optionSet)] \(a.debugDescription) vs \(b.debugDescription)")
    }
}
