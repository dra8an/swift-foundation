import Foundation
import Testing
@testable import FoundationInternationalization

/// Randomized differential testing: Golden/fuzz-corpus.txt holds 2000 seeded
/// random strings weighted toward collation trouble spots (see
/// Tools/gen_fuzz_corpus.py); Golden/fuzz-keys-<option-set>.txt holds ICU's
/// sort keys for them. Byte-identical keys imply identical ordering for all
/// pairs, so this is a complete order check without a pairwise matrix.
@Suite struct FuzzTests {
    @Test(arguments: 0..<13, [0, 1])
    func fuzzKeysMatchICU(optionSetIndex: Int, collatorIndex: Int) throws {
        let (optionSetName, options) = DifferentialTests.optionSets[optionSetIndex]
        let (variant, collator) = try DifferentialTests.collators[collatorIndex]

        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        let corpus = try String(
            contentsOf: golden.appendingPathComponent("fuzz-corpus.txt"), encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let expected = try String(
            contentsOf: golden.appendingPathComponent("fuzz-keys-\(optionSetName).txt"),
            encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: true)
        try #require(corpus.count == expected.count, "fuzz corpus/keys mismatch — regenerate")

        var failures = 0
        for (i, expectedHex) in expected.enumerated() {
            let key = try collator.sortKey(for: corpus[i], options: options)
            let hex = key.map { String(format: "%02x", $0) }.joined()
            if hex != expectedHex {
                failures += 1
                if failures <= 5 {
                    Issue.record(
                        "[\(optionSetName)/\(variant)] fuzz \(i) \(corpus[i].unicodeScalars.map { String($0.value, radix: 16) }):\n  ours \(hex)\n  ICU  \(expectedHex)"
                    )
                }
            }
        }
        #expect(failures == 0, "[\(optionSetName)/\(variant)] \(failures) of \(corpus.count) fuzz keys differ")
    }
}
