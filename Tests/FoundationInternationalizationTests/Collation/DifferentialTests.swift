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
#if canImport(FoundationEssentials)
@testable import FoundationEssentials
@testable import FoundationInternationalization
#elseif FOUNDATION_FRAMEWORK
@testable import Foundation
#endif

/// Differential tests against ICU4C: utils/collation/gen_golden.c produced
/// Golden/matrix-<option-set>.txt by running ucol_strcollUTF8 over every ordered
/// pair of Golden/corpus.txt strings, for each option set (a named combination of collator settings). Our
/// compare() must agree on all pairs, for every option set — against both
/// the regular data and the NFD-only root data (ICU's verdict does not
/// depend on which data *we* read; correct results must be identical).
@Suite struct DifferentialTests {
    private static let _collators = Result {
        [("regular", try RootCollator()),
         ("nfd-only", RootCollator(data: try CollationTestData.rootNFDOnly(), norm: try .standard()))]
    }
    static var collators: [(String, RootCollator)] { get throws { try _collators.get() } }

    /// Must match the optionSets table in utils/collation/gen_golden.c.
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

    private static let _corpus = Result {
        guard let golden = collationTestFolder("Golden") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try String(contentsOf: golden.appendingPathComponent("corpus.txt"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
    static var corpus: [String] { get throws { try _corpus.get() } }

    @Test(arguments: 0..<13, [0, 1])
    func matchesICU(optionSetIndex: Int, collatorIndex: Int) throws {
        let (optionSetName, options) = Self.optionSets[optionSetIndex]
        let (variant, collator) = try Self.collators[collatorIndex]
        let corpus = try Self.corpus

        let golden = try #require(collationTestFolder("Golden"))
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
