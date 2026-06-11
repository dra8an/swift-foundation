import Foundation
import Testing
@testable import UCACollation

/// Differential test against ICU4C: Tools/gen_golden.c produced
/// Golden/matrix.txt by running ucol_strcollUTF8 (root collator, UCOL_PRIMARY)
/// over every ordered pair of Golden/corpus.txt strings, using the same
/// ucadata.icu that this package bundles. Our compare() must agree on all pairs.
@Suite struct DifferentialTests {
    @Test func matchesICUOnFullPairwiseMatrix() throws {
        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        let corpus = try String(contentsOf: golden.appendingPathComponent("corpus.txt"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        let matrix = try String(contentsOf: golden.appendingPathComponent("matrix.txt"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)

        try #require(corpus.count == matrix.count, "corpus/matrix size mismatch — regenerate matrix.txt")

        let collator = try RootCollator()
        var failures = 0
        for (i, row) in matrix.enumerated() {
            try #require(row.count == corpus.count)
            for (j, expected) in row.enumerated() {
                let got: Character
                switch try collator.compare(corpus[i], corpus[j]) {
                case .ascending: got = "<"
                case .same: got = "="
                case .descending: got = ">"
                }
                if got != expected {
                    failures += 1
                    if failures <= 10 {
                        Issue.record(
                            "compare(\(corpus[i].debugDescription), \(corpus[j].debugDescription)): got \(got), ICU says \(expected)"
                        )
                    }
                }
            }
        }
        #expect(failures == 0, "\(failures) of \(corpus.count * corpus.count) pairs disagree with ICU")
    }
}
