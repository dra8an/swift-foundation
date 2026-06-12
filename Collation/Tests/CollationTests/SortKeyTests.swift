import Foundation
import Testing
@testable import Collation

/// Sort key tests: byte-for-byte identity with ICU's ucol_getSortKey
/// (Golden/keys-<option-set>.txt), and the defining invariant that byte-wise
/// key comparison equals compare() for every corpus pair.
@Suite struct SortKeyTests {
    @Test(arguments: 0..<13, [0, 1])
    func keysMatchICUByteForByte(optionSetIndex: Int, collatorIndex: Int) throws {
        let (optionSetName, options) = DifferentialTests.optionSets[optionSetIndex]
        let (variant, collator) = DifferentialTests.collators[collatorIndex]
        let corpus = DifferentialTests.corpus

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
        let (_, collator) = DifferentialTests.collators[0]
        let corpus = DifferentialTests.corpus

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
}
