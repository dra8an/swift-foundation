import Foundation
import Testing
@testable import UCACollation

/// Differential tests against ICU4C: Tools/gen_golden.c produced
/// Golden/matrix-<option-set>.txt by running ucol_strcollUTF8 over every ordered
/// pair of Golden/corpus.txt strings, for each option set (a named combination of collator settings). Our
/// compare() must agree on all pairs, for every option set — against both
/// the regular data and the NFD-only ICU4X variant (ICU's verdict does not
/// depend on which data *we* read; correct results must be identical).
@Suite struct DifferentialTests {
    static let collators: [(String, RootCollator)] = [
        ("regular", try! RootCollator()),
        ("icu4x", RootCollator(data: try! .rootICU4X(), norm: try! .standard())),
    ]

    /// Must match the optionSets table in Tools/gen_golden.c.
    static let optionSets: [(String, CollationOptions)] = {
        func options(_ strength: CollationOptions.Strength, _ tweak: (inout CollationOptions) -> Void = { _ in }) -> CollationOptions {
            var o = CollationOptions()
            o.strength = strength
            tweak(&o)
            return o
        }
        return [
            ("primary", options(.primary)),
            ("secondary", options(.secondary)),
            ("tertiary", options(.tertiary)),
            ("quaternary", options(.quaternary)),
            ("identical", options(.identical)),
            ("shifted", options(.quaternary) { $0.alternate = .shifted }),
            ("shifted3", options(.tertiary) { $0.alternate = .shifted }),
            ("case1", options(.primary) { $0.caseLevel = true }),
            ("caselevel", options(.tertiary) { $0.caseLevel = true }),
            ("upperfirst", options(.tertiary) { $0.caseFirst = .upperFirst }),
            ("lowerfirst", options(.tertiary) { $0.caseFirst = .lowerFirst }),
            ("french", options(.tertiary) { $0.backwardSecondary = true }),
            ("numeric", options(.tertiary) { $0.numeric = true }),
        ]
    }()

    static let corpus: [String] = {
        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        return try! String(contentsOf: golden.appendingPathComponent("corpus.txt"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }()

    @Test(arguments: 0..<13, [0, 1])
    func matchesICU(optionSetIndex: Int, collatorIndex: Int) throws {
        let (optionSetName, options) = Self.optionSets[optionSetIndex]
        let (variant, collator) = Self.collators[collatorIndex]
        let corpus = Self.corpus

        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        let matrix = try String(
            contentsOf: golden.appendingPathComponent("matrix-\(optionSetName).txt"), encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: true)
        try #require(corpus.count == matrix.count, "corpus/matrix size mismatch — regenerate goldens")

        var failures = 0
        for (i, row) in matrix.enumerated() {
            try #require(row.count == corpus.count)
            for (j, expected) in row.enumerated() {
                let got: Character
                switch try collator.compare(corpus[i], corpus[j], options: options) {
                case .ascending: got = "<"
                case .same: got = "="
                case .descending: got = ">"
                }
                if got != expected {
                    failures += 1
                    if failures <= 10 {
                        Issue.record(
                            "[\(optionSetName)/\(variant)] compare(\(corpus[i].debugDescription), \(corpus[j].debugDescription)): got \(got), ICU says \(expected)"
                        )
                    }
                }
            }
        }
        #expect(failures == 0, "[\(optionSetName)/\(variant)] \(failures) of \(corpus.count * corpus.count) pairs disagree with ICU")
    }
}
