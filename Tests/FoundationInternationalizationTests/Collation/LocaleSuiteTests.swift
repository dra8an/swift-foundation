import Foundation
import Testing
@testable import FoundationInternationalization

/// Ports of ICU4C's classic per-locale collation suites (cintltst/encoll.c,
/// cdetst.c, cestst.c, cfrtst.c, cjaptst.c, cturtst.c; intltest/ficoll.cpp,
/// lcukocol.cpp, currcoll.cpp). The test-case arrays are extracted
/// mechanically by Tools/extract_locale_suites.py into locale-suites.json;
/// the per-suite loop logic (which cases at which strength/options) is
/// reimplemented here from the C sources.
///
/// Each case checks both comparison directions and sort-key order, like
/// ICU's doTest.
@Suite struct LocaleSuiteTests {
    struct SuiteData: Decodable {
        let source: String
        let arrays: [String: [String]]
        let results: [String: Results]
    }

    enum Results: Decodable {
        case single([Int])
        case pairs([[Int]])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let pairs = try? c.decode([[Int]].self) {
                self = .pairs(pairs)
            } else {
                self = .single(try c.decode([Int].self))
            }
        }

        var single: [Int] {
            if case .single(let v) = self { return v }
            fatalError("expected single-column results")
        }

        var pairs: [[Int]] {
            if case .pairs(let v) = self { return v }
            fatalError("expected two-column results")
        }
    }

    static let suites: [String: SuiteData] = {
        let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)!
            .appendingPathComponent("locale-suites.json")
        return try! JSONDecoder().decode([String: SuiteData].self, from: Data(contentsOf: url))
    }()

    static let root = try! RootCollator()

    private func order(_ i: Int) -> RootCollator.Order {
        i < 0 ? .ascending : i == 0 ? .same : .descending
    }

    /// ICU's doTest: both directions plus sort-key consistency.
    private func doTest(
        _ coll: RootCollator, _ options: CollationOptions,
        _ source: String, _ target: String, _ expected: RootCollator.Order,
        _ label: String, _ failures: inout Int
    ) throws {
        let got = try coll.compare(source, target, options: options)
        let gotReverse = try coll.compare(target, source, options: options)
        let k1 = try coll.sortKey(for: source, options: options)
        let k2 = try coll.sortKey(for: target, options: options)
        let keyOrder: RootCollator.Order =
            k1 == k2 ? .same : (k1.lexicographicallyPrecedes(k2) ? .ascending : .descending)
        let reversed: RootCollator.Order = expected == .same
            ? .same : (expected == .ascending ? .descending : .ascending)
        if got != expected || gotReverse != reversed || keyOrder != expected {
            failures += 1
            if failures <= 5 {
                Issue.record(
                    "[\(label)] \(source.debugDescription) vs \(target.debugDescription): got \(got)/\(gotReverse)/keys \(keyOrder), expected \(expected)"
                )
            }
        }
    }

    private func options(_ strength: CollationOptions.Strength, of base: CollationOptions = CollationOptions(),
                         caseLevel: Bool = false, shifted: Bool = false) -> CollationOptions {
        var o = base
        o.strength = strength
        if caseLevel { o.caseLevel = true }
        if shifted { o.alternate = .shifted }
        return o
    }

    /// encoll.c: English (root). 38 tertiary + 5 primary + 6 secondary cases,
    /// pairwise bug list, and two full expected-order matrices.
    @Test func english() throws {
        let s = Self.suites["en"]!
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.single
        var failures = 0

        let tertiary = options(.tertiary)
        for i in 0..<38 {
            try doTest(Self.root, tertiary, src[i], tgt[i], order(results[i]), "en/ter", &failures)
        }
        let bugs = s.arrays["testBugs"]!
        for i in 0..<bugs.count {
            for j in (i + 1)..<bugs.count {
                try doTest(Self.root, tertiary, bugs[i], bugs[j], .ascending, "en/bugs", &failures)
            }
        }
        let more = s.arrays["testMore"]!
        for i in 0..<more.count {
            for j in 0..<more.count {
                try doTest(Self.root, tertiary, more[i], more[j],
                           order(i == j ? 0 : (i < j ? -1 : 1)), "en/more", &failures)
            }
        }
        let primary = options(.primary)
        for i in 38..<43 {
            try doTest(Self.root, primary, src[i], tgt[i], order(results[i]), "en/pri", &failures)
        }
        let secondary = options(.secondary)
        for i in 43..<49 {
            try doTest(Self.root, secondary, src[i], tgt[i], order(results[i]), "en/sec", &failures)
        }
        let acute = s.arrays["testAcute"]!
        for i in 0..<acute.count {
            for j in 0..<acute.count {
                try doTest(Self.root, secondary, acute[i], acute[j],
                           order(i == j ? 0 : (i < j ? -1 : 1)), "en/acute", &failures)
            }
        }
        #expect(failures == 0)
    }

    /// cdetst.c: German standard (== root data). Two result columns:
    /// [0] primary, [1] tertiary.
    @Test func german() throws {
        let s = Self.suites["de"]!
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.pairs
        var failures = 0
        for i in 0..<src.count {
            try doTest(Self.root, options(.tertiary), src[i], tgt[i], order(results[i][1]), "de/ter", &failures)
            try doTest(Self.root, options(.primary), src[i], tgt[i], order(results[i][0]), "de/pri", &failures)
        }
        #expect(failures == 0)
    }

    /// cestst.c: Spanish. Cases 0..<5 tertiary, 5..<9 primary.
    @Test func spanish() throws {
        let s = Self.suites["es"]!
        let coll = try RootCollator(tailoringNamed: "es")
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.single
        var failures = 0
        for i in 0..<5 {
            try doTest(coll, options(.tertiary, of: coll.defaultOptions), src[i], tgt[i],
                       order(results[i]), "es/ter", &failures)
        }
        for i in 5..<9 {
            try doTest(coll, options(.primary, of: coll.defaultOptions), src[i], tgt[i],
                       order(results[i]), "es/pri", &failures)
        }
        #expect(failures == 0)
    }

    /// cfrtst.c: Canadian French (backwards secondary). Tertiary cases run at
    /// shifted+quaternary; acute matrix at secondary; bug list at tertiary.
    @Test func canadianFrench() throws {
        let s = Self.suites["fr"]!
        let coll = try RootCollator(tailoringNamed: "fr_CA")
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.single
        var failures = 0
        let shifted4 = options(.quaternary, of: coll.defaultOptions, shifted: true)
        for i in 0..<src.count {
            try doTest(coll, shifted4, src[i], tgt[i], order(results[i]), "fr/ter", &failures)
        }
        let secondary = options(.secondary, of: coll.defaultOptions)
        let acute = s.arrays["testAcute"]!
        for i in 0..<acute.count {
            for j in 0..<acute.count {
                try doTest(coll, secondary, acute[i], acute[j],
                           order(i == j ? 0 : (i < j ? -1 : 1)), "fr/acute", &failures)
            }
        }
        let tertiary = options(.tertiary, of: coll.defaultOptions)
        let bugs = s.arrays["testBugs"]!
        for i in 0..<bugs.count {
            for j in (i + 1)..<bugs.count {
                try doTest(coll, tertiary, bugs[i], bugs[j], .ascending, "fr/bugs", &failures)
            }
        }
        #expect(failures == 0)
    }

    /// cjaptst.c: Japanese. Source/target cases at tertiary+caseLevel, then
    /// four ascending sequences at various strengths.
    @Test func japanese() throws {
        let s = Self.suites["ja"]!
        let coll = try RootCollator(tailoringNamed: "ja")
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.single
        var failures = 0
        let ter = options(.tertiary, of: coll.defaultOptions, caseLevel: true)
        for i in 0..<src.count {
            try doTest(coll, ter, src[i], tgt[i], order(results[i]), "ja/ter", &failures)
        }
        let sequences: [(String, CollationOptions)] = [
            ("testBaseCases", options(.primary, of: coll.defaultOptions)),
            ("testPlainDakutenHandakutenCases", options(.secondary, of: coll.defaultOptions)),
            ("testSmallLargeCases", options(.tertiary, of: coll.defaultOptions, caseLevel: true)),
            ("testKatakanaHiraganaCases", options(.quaternary, of: coll.defaultOptions, caseLevel: true)),
            ("testChooonKigooCases", options(.quaternary, of: coll.defaultOptions, caseLevel: true)),
        ]
        for (name, opts) in sequences {
            let cases = s.arrays[name]!
            for i in 0..<(cases.count - 1) {
                try doTest(coll, opts, cases[i], cases[i + 1], .ascending, "ja/\(name)", &failures)
            }
        }
        #expect(failures == 0)
    }

    /// cturtst.c: Turkish. Cases 0..<8 tertiary, 8..<11 primary.
    @Test func turkish() throws {
        let s = Self.suites["tr"]!
        let coll = try RootCollator(tailoringNamed: "tr")
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.single
        var failures = 0
        for i in 0..<8 {
            try doTest(coll, options(.tertiary, of: coll.defaultOptions), src[i], tgt[i],
                       order(results[i]), "tr/ter", &failures)
        }
        for i in 8..<11 {
            try doTest(coll, options(.primary, of: coll.defaultOptions), src[i], tgt[i],
                       order(results[i]), "tr/pri", &failures)
        }
        #expect(failures == 0)
    }

    /// ficoll.cpp: Finnish. Cases 0..<4 tertiary, 4..<5 primary.
    @Test func finnish() throws {
        let s = Self.suites["fi"]!
        let coll = try RootCollator(tailoringNamed: "fi")
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.single
        var failures = 0
        for i in 0..<4 {
            try doTest(coll, options(.tertiary, of: coll.defaultOptions), src[i], tgt[i],
                       order(results[i]), "fi/ter", &failures)
        }
        for i in 4..<5 {
            try doTest(coll, options(.primary, of: coll.defaultOptions), src[i], tgt[i],
                       order(results[i]), "fi/pri", &failures)
        }
        #expect(failures == 0)
    }

    /// lcukocol.cpp: Korean, tertiary.
    @Test func korean() throws {
        let s = Self.suites["ko"]!
        let coll = try RootCollator(tailoringNamed: "ko")
        let src = s.arrays["testSourceCases"]!
        let tgt = s.arrays["testTargetCases"]!
        let results = s.results["results"]!.single
        var failures = 0
        for i in 0..<src.count {
            try doTest(coll, options(.tertiary, of: coll.defaultOptions), src[i], tgt[i],
                       order(results[i]), "ko/ter", &failures)
        }
        #expect(failures == 0)
    }

    /// currcoll.cpp: all currency symbols in collation order (root), full
    /// expected-order matrix.
    @Test func currency() throws {
        let s = Self.suites["currency"]!
        let symbols = s.arrays["currency"]!
        var failures = 0
        let tertiary = options(.tertiary)
        for i in 0..<symbols.count {
            for j in 0..<symbols.count {
                try doTest(Self.root, tertiary, symbols[i], symbols[j],
                           order(i == j ? 0 : (i < j ? -1 : 1)), "currency", &failures)
            }
        }
        #expect(failures == 0)
    }
}
