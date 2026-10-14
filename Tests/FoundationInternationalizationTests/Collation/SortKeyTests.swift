import Foundation
import Testing
@testable import FoundationInternationalization

/// Sort key tests: byte-for-byte identity with ICU's ucol_getSortKey
/// (Golden/keys-<option-set>.txt), and the defining invariant that byte-wise
/// key comparison equals compare() for every corpus pair.
@Suite struct SortKeyTests {
    @Test(arguments: 0..<13, [0, 1])
    func keysMatchICUByteForByte(optionSetIndex: Int, collatorIndex: Int) throws {
        let (optionSetName, options) = DifferentialTests.optionSets[optionSetIndex]
        let (variant, collator) = try DifferentialTests.collators[collatorIndex]
        let corpus = try DifferentialTests.corpus

        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        let expected = try String(
            contentsOf: golden.appendingPathComponent("keys-\(optionSetName).txt"), encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: true)
        try #require(expected.count == corpus.count, "corpus/keys size mismatch — regenerate goldens")

        var failures = 0
        for (i, expectedHex) in expected.enumerated() {
            let key = try collator.sortKey(for: corpus[i], options: options)
            let hex = key.map { String(format: "%02x", $0) }.joined()
            if hex != expectedHex {
                failures += 1
                if failures <= 5 {
                    Issue.record(
                        "[\(optionSetName)/\(variant)] sortKey(\(corpus[i].debugDescription)):\n  ours \(hex)\n  ICU  \(expectedHex)"
                    )
                }
            }
        }
        #expect(failures == 0, "[\(optionSetName)/\(variant)] \(failures) of \(corpus.count) keys differ from ICU")
    }

    /// The defining invariant: byte-comparing sort keys must order exactly
    /// like compare() with the same options.
    @Test(arguments: 0..<13)
    func keyComparisonEqualsCompare(optionSetIndex: Int) throws {
        let (optionSetName, options) = DifferentialTests.optionSets[optionSetIndex]
        let (_, collator) = try DifferentialTests.collators[0]
        let corpus = try DifferentialTests.corpus

        let keys = try corpus.map { try collator.sortKey(for: $0, options: options) }
        var failures = 0
        for i in corpus.indices {
            for j in corpus.indices {
                let byOrder = try collator.compare(corpus[i], corpus[j], options: options)
                let byKey: RootCollator.Order
                if keys[i] == keys[j] {
                    byKey = .same
                } else if keys[i].lexicographicallyPrecedes(keys[j]) {
                    byKey = .ascending
                } else {
                    byKey = .descending
                }
                if byOrder != byKey {
                    failures += 1
                    if failures <= 5 {
                        Issue.record(
                            "[\(optionSetName)] \(corpus[i].debugDescription) vs \(corpus[j].debugDescription): compare=\(byOrder), keys=\(byKey)"
                        )
                    }
                }
            }
        }
        #expect(failures == 0, "[\(optionSetName)] \(failures) invariant violations")
    }

    // MARK: Single-pass writer stress

    /// Run lengths at and around each compression maxCount: case 7 and 13, secondary 33, tertiary 97, quaternary 113, plus two long runs.
    static let writerStressLengths = [1, 2, 7, 8, 13, 14, 33, 34, 97, 98, 113, 114, 200, 400]

    /// String families that drive each level of the single-pass writer through long common-weight runs: variable CEs, secondary and case weights, implicit primaries, merge separators, Hangul, digits, Thai, expansions, and ignorables. The writer sizes its region from a per-CE byte bound and compacts the levels in place; its debug asserts stop the test if either is wrong.
    static let writerStressFamilies: [(Int) -> String] = [
        { String(repeating: "a", count: $0) },
        { String(repeating: "a", count: $0) + "b" },
        { String(repeating: "A", count: $0) + "a" },
        { String(repeating: "aA", count: $0) },
        { String(repeating: " ", count: $0) },
        { String(repeating: " ", count: $0) + "a" },
        { String(repeating: "a ", count: $0) },
        { String(repeating: ",", count: $0) },
        { String(repeating: "\u{0301}", count: $0) },
        { "a" + String(repeating: "\u{0301}", count: $0) },
        { String(repeating: "a\u{0301}", count: $0) },
        { String(repeating: "\u{4E00}", count: $0) },
        { String(repeating: "\u{4E00}\u{20000}", count: $0) },
        { String(repeating: "\u{1F600}", count: $0) },
        { String(repeating: "\u{FFFE}", count: $0) },
        { String(repeating: "a\u{FFFE}b", count: $0) },
        { String(repeating: "\u{AC00}", count: $0) },
        { String(repeating: "9", count: $0) },
        { String(repeating: "0", count: $0) + "1" },
        { String(repeating: "\u{0E01}\u{0E33}", count: $0) },
        { String(repeating: "\u{00DF}", count: $0) },
        { String(repeating: "\u{FB01}", count: $0) },
        { String(repeating: "\u{3000}", count: $0) },
        { String(repeating: "\u{0000}", count: $0) },
        { String(repeating: "\u{00AD}", count: $0) },
    ]

    /// Every combination of the settings that change the writer's output, at one strength: alternate, case level, case-first, backwards secondary, numeric.
    static func writerStressOptions(strength: CollationOptions.Strength) -> [CollationOptions] {
        var out: [CollationOptions] = []
        for alternate in [CollationOptions.Alternate.nonIgnorable, .shifted] {
            for caseLevel in [false, true] {
                for caseFirst in [CollationOptions.CaseFirst.off, .lowerFirst, .upperFirst] {
                    for backward in [false, true] {
                        for numeric in [false, true] {
                            var o = CollationOptions()
                            o.strength = strength
                            o.alternate = alternate
                            o.caseLevel = caseLevel
                            o.caseFirst = caseFirst
                            o.backwardSecondary = backward
                            o.numeric = numeric
                            out.append(o)
                        }
                    }
                }
            }
        }
        return out
    }

    /// The defining invariant again, on strings built to stress the single-pass writer, over all 240 option combinations (5 strengths × 48). The pairs sit on the compression boundaries: each family at consecutive run lengths (33 against 34, 97 against 98, ...), each family against its neighbour at the same length, and the empty string against every family. `compare()` is an independent implementation of the same order, so the check needs no second writer and no reference data.
    @Test(arguments: [CollationOptions.Strength.primary, .secondary, .tertiary, .quaternary, .identical])
    func singlePassWriterOrdersLikeCompare(strength: CollationOptions.Strength) throws {
        let (_, collator) = try DifferentialTests.collators[0]
        let families = Self.writerStressFamilies
        let lengths = Self.writerStressLengths

        var strings: [String] = []
        for family in families {
            for n in lengths { strings.append(family(n)) }
        }
        let empty = strings.count
        strings.append("")
        func index(_ family: Int, _ k: Int) -> Int { family * lengths.count + k }

        var pairs: [(Int, Int)] = []
        for f in families.indices {
            pairs.append((empty, index(f, 0)))
            for k in lengths.indices {
                if k + 1 < lengths.count { pairs.append((index(f, k), index(f, k + 1))) }
                if f + 1 < families.count { pairs.append((index(f, k), index(f + 1, k))) }
            }
        }
        try #require(pairs.count > 600, "the pair derivation broke — the test would cover almost nothing")

        func order(_ a: [UInt8], _ b: [UInt8]) -> RootCollator.Order {
            if a == b { return .same }
            return a.lexicographicallyPrecedes(b) ? .ascending : .descending
        }

        var failures = 0
        for options in Self.writerStressOptions(strength: strength) {
            let keys = try strings.map { try collator.sortKey(for: $0, options: options) }
            for (i, j) in pairs {
                for (a, b) in [(i, j), (j, i)] {
                    let byOrder = try collator.compare(strings[a], strings[b], options: options)
                    let byKey = order(keys[a], keys[b])
                    if byOrder != byKey {
                        failures += 1
                        if failures <= 5 {
                            Issue.record("""
                                [\(options)] \(strings[a].debugDescription) vs \(strings[b].debugDescription): compare=\(byOrder), keys=\(byKey)
                                """)
                        }
                    }
                }
            }
        }
        #expect(failures == 0, "[\(strength)] \(failures) invariant violations")
    }
}
