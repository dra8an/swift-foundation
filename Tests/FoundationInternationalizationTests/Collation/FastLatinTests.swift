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

    /// The order of two sort keys, as -1 / 0 / 1.
    static func keyOrder(_ collator: RootCollator, _ a: String, _ b: String, _ options: CollationOptions) throws -> Int {
        let ka = try collator.sortKey(for: a, options: options)
        let kb = try collator.sortKey(for: b, options: options)
        return ka.lexicographicallyPrecedes(kb) ? -1 : (kb.lexicographicallyPrecedes(ka) ? 1 : 0)
    }

    /// With alternate = shifted, the fast path must treat the same characters as variable as the full path does, for each "max variable" group. The case is ICU's regression test for ICU-21992 (Bengali, max variable = space): the top of the group's mini primaries must include the tertiary bits, or the last characters of the group count as not variable.
    @Test func shiftedCompareAgreesWithSortKeysICU21992() throws {
        let bengali = try RootCollator(tailoringNamed: "bn")
        var options = bengali.defaultOptions
        options.strength = .tertiary
        options.alternate = .shifted
        options.maxVariable = .space
        let s1 = "\u{0002}\u{2000}湢", s2 = "ô\u{0B00}\u{0B03}"
        #expect(try bengali.compare(s1, s2, options: options).rawValue == Self.keyOrder(bengali, s1, s2, options))
    }

    /// The same agreement for every character of the fast Latin table (U+0001...U+017F, U+2000...U+203F) against 16 characters from the groups that "max variable" selects (controls, spaces, punctuation, symbols, currency signs, a digit, a letter), alone and after a letter, for each "max variable" group. U+00A0 is the last space of the table: before the fix of ICU-21992 it disagreed with 66 other characters.
    @Test(arguments: [CollationOptions.MaxVariable.space, .punctuation, .symbol, .currency])
    func shiftedCompareAgreesWithSortKeysForEachGroup(maxVariable: CollationOptions.MaxVariable) throws {
        let root = try Self.root
        var options = root.defaultOptions
        options.strength = .tertiary
        options.alternate = .shifted
        options.maxVariable = maxVariable
        let partners: [UInt32] = [0x01, 0x09, 0x20, 0x21, 0x24, 0x2B, 0x30, 0x61, 0xA0, 0xA2, 0xA7, 0xBF, 0x2000, 0x2010, 0x2020, 0x203F]
        var disagreements = 0
        var first = ""
        for prefix in ["", "a"] {
            // One sort key per string; a pair then costs one compare.
            var strings: [(String, [UInt8])] = []
            for value in Array(UInt32(0x01)...0x17F) + Array(UInt32(0x2000)...0x203F) {
                let string = prefix + String(try #require(Unicode.Scalar(value)))
                strings.append((string, try root.sortKey(for: string, options: options)))
            }
            for value in partners {
                let partner = prefix + String(try #require(Unicode.Scalar(value)))
                let partnerKey = try root.sortKey(for: partner, options: options)
                for (string, key) in strings {
                    let compared = try root.compare(string, partner, options: options).rawValue
                    let byKeys = key.lexicographicallyPrecedes(partnerKey) ? -1 : (partnerKey.lexicographicallyPrecedes(key) ? 1 : 0)
                    if compared != byKeys {
                        disagreements += 1
                        if first.isEmpty { first = "\(string.unicodeScalars.map { String($0.value, radix: 16) }) / \(partner.unicodeScalars.map { String($0.value, radix: 16) }): compare \(compared), sort keys \(byKeys)" }
                    }
                }
            }
        }
        #expect(disagreements == 0, "first: \(first)")
    }

    /// A reordering that puts Latin before the digits (ICU's `colReorder=latn-digit`), made from the script starts of the root data: the lead bytes from the end of the digits to the end of Latin (the reserved bytes before Latin, then Latin) move down to the first lead byte of the digits, and the lead bytes of the digits move up behind them. The engine reads a reordering only from tailoring data, and no bundled tailoring moves the digits, so the test makes this one.
    static func latinBeforeDigits() throws -> Reordering {
        let data = try Self.root.data
        let digitGroup = CollationData.reorderCodeFirst + 4  // UCOL_REORDER_CODE_DIGIT
        let latinGroup: Int32 = 25  // USCRIPT_LATIN
        let digitStart = data.firstPrimaryForGroup(digitGroup)
        let digitLimit = data.lastPrimaryForGroup(digitGroup) &+ 1
        let latinStart = data.firstPrimaryForGroup(latinGroup)
        let latinLimit = data.lastPrimaryForGroup(latinGroup) &+ 1
        // Each group is a run of whole lead bytes, and Latin comes after the digits: the permutation needs no ranges for split lead bytes.
        let bounds = [digitStart, digitLimit, latinStart, latinLimit]
        try #require(bounds.allSatisfy { $0 & 0xff_ffff == 0 }, "\(bounds.map { String($0, radix: 16) })")
        try #require(0 < digitStart && digitStart < digitLimit && digitLimit <= latinStart && latinStart < latinLimit, "\(bounds.map { String($0, radix: 16) })")
        let firstDigit = Int(digitStart >> 24), afterDigits = Int(digitLimit >> 24), afterLatin = Int(latinLimit >> 24)
        var table = (0...255).map { UInt8($0) }
        for lead in firstDigit..<afterDigits { table[lead] = UInt8(lead + (afterLatin - afterDigits)) }
        for lead in afterDigits..<afterLatin { table[lead] = UInt8(lead - (afterDigits - firstDigit)) }
        return Reordering(table: table, rawRanges: [])
    }

    /// The sort key of the root data under a reordering, with the default options: the full path (CE production and the key writer), which never uses fast Latin.
    static func sortKey(_ s: String, reordering: Reordering) throws -> [UInt8] {
        let root = try Self.root
        let scratch = ScratchBuffers(data: root.data, base: nil, norm: root.norm)
        var key: [UInt8] = []
        try scratch.resetCollectAndWriteKey(
            numeric: false, scalars: s.unicodeScalars, compressibleBytes: root.data.compressibleBytes,
            options: CollationOptions().icuOptions, variableTopValue: 0,
            reordering: reordering, terminate: true, into: &key)
        return key
    }

    /// When a reordering moves the digits, the mini CEs of the digits in the fast Latin table are in the wrong place: the fast path must leave at a digit. `getOptions` clears the primaries of the digits and sets the numeric flag, which tells the compare to leave there (ICU-23016). The three pairs and their orders are those of ICU's test (cmsccoll.c, TestDigitReordering, `colReorder=latn-digit`): the sort keys give ICU's order, the fast path leaves for the two pairs with digits, and it still decides the pair of letters.
    @Test func digitsMovedByReorderingLeaveTheFastPathICU23016() throws {
        let root = try Self.root
        let reordering = try Self.latinBeforeDigits()
        let table = root.data.fastLatinTable
        var primaries: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: table, scriptsData: root.data, reordering: reordering,
            options: CollationOptions().icuOptions, primaries: &primaries)
        #expect(packed >= 0)
        #expect(packed & CollationOptions.Bits.numeric != 0)
        #expect(primaries[0x30...0x39].allSatisfy { $0 == 0 })
        #expect(primaries[Int(UnicodeScalar("A").value)] != 0)

        let leaves = CollationFastLatin.bailOutResult
        let cases: [(String, String, byKeys: Int, fast: Int32)] = [
            ("123", "ABC", 1, leaves), ("ABC", "123", -1, leaves), ("123", "124", -1, leaves), ("ABC", "ABD", -1, -1),
        ]
        for (a, b, byKeys, fast) in cases {
            let ka = try Self.sortKey(a, reordering: reordering), kb = try Self.sortKey(b, reordering: reordering)
            #expect((ka.lexicographicallyPrecedes(kb) ? -1 : (kb.lexicographicallyPrecedes(ka) ? 1 : 0)) == byKeys, "\(a) vs \(b), sort keys")
            let viaScalars = CollationFastLatin.compare(
                table: table, primaries: primaries, options: packed, left: Self.side(a), right: Self.side(b))
            #expect(viaScalars == fast, "\(a) vs \(b), scalars")
            #expect(try Self.utf8Compare(a, b, table: table, primaries: primaries, packed: packed) == fast, "\(a) vs \(b), UTF-8")
        }
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
