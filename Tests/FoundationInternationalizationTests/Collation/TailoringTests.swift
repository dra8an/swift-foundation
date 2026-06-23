import Foundation
import Testing
@testable import FoundationInternationalization

/// Locale tailoring tests: each locale collator is built from the bundled
/// %%CollationBin extracted from ICU's compiled resources, runs with the
/// locale's default options (decoded from the binary), and must reproduce
/// ICU's comparison matrix and sort keys for that locale.
@Suite struct TailoringTests {
    /// (option-set name in golden files, bundled tailoring resource name)
    static let locales: [(String, String)] = [
        ("de-phonebook", "de-phonebook"),
        ("sv", "sv"),
        ("da", "da"),
        ("fr-CA", "fr_CA"),
        ("tr", "tr"),
        ("lt", "lt"),
        ("ja", "ja"),
        ("zh", "zh"),
    ]

    static let collators: [String: RootCollator] = Dictionary(
        uniqueKeysWithValues: locales.map { ($0.0, try! RootCollator(tailoringNamed: $0.1)) })

    @Test(arguments: 0..<8)
    func matchesICUMatrix(localeIndex: Int) throws {
        let (name, _) = Self.locales[localeIndex]
        let collator = Self.collators[name]!
        let options = collator.defaultOptions
        let corpus = DifferentialTests.corpus

        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        let matrix = try String(
            contentsOf: golden.appendingPathComponent("matrix-\(name).txt"), encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: true)
        try #require(matrix.count == corpus.count)

        var failures = 0
        for (i, row) in matrix.enumerated() {
            for (j, expected) in row.enumerated() {
                let got: Character
                switch try collator.compare(corpus[i], corpus[j], options: options) {
                case .ascending: got = "<"
                case .same: got = "="
                case .descending: got = ">"
                }
                if got != expected {
                    failures += 1
                    if failures <= 5 {
                        Issue.record(
                            "[\(name)] compare(\(corpus[i].debugDescription), \(corpus[j].debugDescription)): got \(got), ICU says \(expected)"
                        )
                    }
                }
            }
        }
        #expect(failures == 0, "[\(name)] \(failures) of \(corpus.count * corpus.count) pairs disagree with ICU")
    }

    @Test(arguments: 0..<8)
    func keysMatchICU(localeIndex: Int) throws {
        let (name, _) = Self.locales[localeIndex]
        let collator = Self.collators[name]!
        let options = collator.defaultOptions
        let corpus = DifferentialTests.corpus

        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        let expected = try String(
            contentsOf: golden.appendingPathComponent("keys-\(name).txt"), encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: true)
        try #require(expected.count == corpus.count)

        var failures = 0
        for (i, expectedHex) in expected.enumerated() {
            let key = try collator.sortKey(for: corpus[i], options: options)
            let hex = key.map { String(format: "%02x", $0) }.joined()
            if hex != expectedHex {
                failures += 1
                if failures <= 5 {
                    Issue.record("[\(name)] sortKey(\(corpus[i].debugDescription)):\n  ours \(hex)\n  ICU  \(expectedHex)")
                }
            }
        }
        #expect(failures == 0, "[\(name)] \(failures) of \(corpus.count) keys differ from ICU")
    }

    /// Sanity checks that the locale defaults decoded from the binaries are
    /// what CLDR specifies.
    @Test func localeDefaultsDecoded() throws {
        #expect(Self.collators["fr-CA"]!.defaultOptions.backwardSecondary)
        #expect(Self.collators["da"]!.defaultOptions.caseFirst == .upperFirst)
        #expect(!Self.collators["sv"]!.defaultOptions.backwardSecondary)
    }

    /// Classic per-locale orderings, as a readable smoke test.
    @Test func classicOrderings() throws {
        var primary = CollationOptions()
        primary.strength = .primary
        // Swedish: ö sorts after z.
        #expect(try Self.collators["sv"]!.compare("z", "ö") == .ascending)
        // Danish: aa is primary-equal to å (tertiary differences remain),
        // so Aaron sorts after Zebra.
        #expect(try Self.collators["da"]!.compare("aa", "å", options: primary) == .same)
        #expect(try Self.collators["da"]!.compare("Aaron", "Zebra") == .descending)
        // German phonebook: ü is primary-equal to ue.
        #expect(try Self.collators["de-phonebook"]!.compare("Müller", "Mueller", options: primary) == .same)
        // Turkish: ı sorts before i.
        #expect(try Self.collators["tr"]!.compare("ıb", "ib") == .ascending)
        // fr-CA defaults compare accents from the end.
        #expect(try Self.collators["fr-CA"]!.compare("cote", "côte") == .ascending)
    }
}
