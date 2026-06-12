import Testing
@testable import Collation

/// Unit tests for the fast Latin path (CollationFastLatin). The end-to-end
/// correctness evidence is the existing suites — the differential matrices
/// and the key-agreement tests run every compare() through the integrated
/// fast path — so what is pinned here is the machinery itself: that the fast
/// path actually engages (returns real results, not bail-outs) where it
/// should, and bails out where it must.
@Suite struct FastLatinTests {
    static let root = try! RootCollator()

    static func side(_ s: String) -> CollationFastLatin.Side {
        var iterator = s.unicodeScalars.makeIterator()
        return CollationFastLatin.Side(next: iterator.next()?.value, rest: iterator)
    }

    /// Computes (table, primaries, packed options) for an option set, like
    /// RootCollator's per-scratch cache does.
    static func setup(_ options: CollationOptions) -> (UnsafeBufferPointer<UInt16>, [UInt16], Int32) {
        let table = Self.root.data.fastLatinTable
        var primaries: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: table, scriptsData: Self.root.data, reordering: nil,
            options: options.icuOptions, primaries: &primaries)
        return (table, primaries, packed)
    }

    @Test func rootTableLoadsAndOptionsAreSupported() throws {
        let table = Self.root.data.fastLatinTable
        #expect(!table.isEmpty)
        #expect(table[0] >> 8 == CollationFastLatin.version)
        let (_, primaries, packed) = Self.setup(CollationOptions())
        #expect(packed >= 0)
        #expect(primaries.count == CollationFastLatin.latinLimit)
        // Letters have short primaries; with alternate=non-ignorable nothing
        // is variable, so space and punctuation keep nonzero primaries too.
        #expect(primaries[Int(UnicodeScalar("a").value)] != 0)
        #expect(primaries[0x20] != 0)
    }

    @Test func engagesForPlainText() throws {
        let (table, primaries, packed) = Self.setup(CollationOptions())
        // Real results, not bail-outs, for plain ASCII and Latin-1 text.
        for (a, b, expected) in [
            ("ab", "ac", Int32(-1)),
            ("ab", "ab", 0),
            ("b", "a", 1),
            ("côte", "côte", 0),       // U+00F4 is in the table
            ("ab", "abc", -1),
            ("Hello", "hello", 1),
        ] {
            let got = CollationFastLatin.compare(
                table: table, primaries: primaries, options: packed,
                left: Self.side(a), right: Self.side(b))
            #expect(got == expected, "\(a) vs \(b)")
        }
    }

    @Test func bailsOutWhereItMust() throws {
        let (table, primaries, packed) = Self.setup(CollationOptions())
        // Out-of-range characters bail (the integration layer normally
        // pre-checks the first scalars; mid-string ones bail here).
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
        let (_, numPrimaries, numPacked) = Self.setup(numeric)
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
        let (_, frPrimaries, frPacked) = Self.setup(french)
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
        let (table, primaries, packed) = Self.setup(shifted)
        #expect(packed >= 0)
        // Punctuation is variable under shifted: primary zeroed in the
        // precomputed table, and "black-bird" == "blackbird" up to tertiary.
        #expect(primaries[Int(UnicodeScalar("-").value)] == 0)
        #expect(CollationFastLatin.compare(
            table: table, primaries: primaries, options: packed,
            left: Self.side("black-bird"), right: Self.side("blackbird")) == 0)
        // At quaternary strength the variable difference resurfaces.
        var shiftedQ = shifted
        shiftedQ.strength = .quaternary
        let (_, qPrimaries, qPacked) = Self.setup(shiftedQ)
        #expect(CollationFastLatin.compare(
            table: table, primaries: qPrimaries, options: qPacked,
            left: Self.side("black-bird"), right: Self.side("blackbird")) == -1)
    }

    /// The integrated path agrees with sort keys (which never use fast
    /// Latin) for pairs chosen to traverse every level loop and the
    /// punctuation/contraction handling, across option sets.
    @Test func integrationAgreesWithSortKeys() throws {
        let pairs = [
            ("ab", "ac"), ("ab", "Ab"), ("ab", "ab"), ("p\u{E9}ch\u{E9}", "p\u{EA}che"),
            ("black-bird", "blackbird"), ("black bird", "black-bird"),
            ("a\u{2014}b", "a-b"),  // em dash: punctuation block lookup
            ("Tt", "tT"), ("a", "a\u{1}"), ("ab", "abc"), ("", "a"),
        ]
        for (name, options) in [
            ("default", CollationOptions()),
            ("shifted", { var o = CollationOptions(); o.alternate = .shifted; return o }()),
            ("quaternary-shifted", { var o = CollationOptions(); o.strength = .quaternary; o.alternate = .shifted; return o }()),
            ("upperFirst", { var o = CollationOptions(); o.caseFirst = .upperFirst; return o }()),
            ("caseLevel", { var o = CollationOptions(); o.caseLevel = true; return o }()),
            ("primary", { var o = CollationOptions(); o.strength = .primary; return o }()),
            ("identical", { var o = CollationOptions(); o.strength = .identical; return o }()),
        ] {
            for (a, b) in pairs {
                let got = try Self.root.compare(a, b, options: options)
                let ka = try Self.root.sortKey(for: a, options: options)
                let kb = try Self.root.sortKey(for: b, options: options)
                let keyOrder: RootCollator.Order =
                    ka == kb ? .same : (ka.lexicographicallyPrecedes(kb) ? .ascending : .descending)
                #expect(got == keyOrder, "[\(name)] \(a.debugDescription) vs \(b.debugDescription)")
            }
        }
    }
}
