import Foundation
import Testing
@testable import Collation

/// Port of ICU4C's G7CollationTest::TestG7Locales (intltest/g7coll.cpp): a
/// fixed set of 15 strings with their expected order for each of the eight
/// G7 locales, checked pairwise. The demo tests and the remaining result
/// rows build collators from rule strings — out of scope until a rule
/// builder exists (Docs/12-rule-builder-decision.md). Data extracted
/// mechanically by Tools/extract_g7coll.py into g7coll.json (which is
/// faithful to the C values, including the spots where ICU's own character
/// comments disagree with the code units, e.g. "blabkbirds").
///
/// Options: ICU's test sets quaternary+shifted but then *replaces* the
/// collator with one rebuilt from its rule string, which resets the
/// attributes — the known issue ICU-10671 ("TestG7Locales does not test
/// ignore-punctuation"). The expected orders therefore encode each locale's
/// default options (e.g. "blabk-birds" < "blabkbird" needs a primary-visible
/// hyphen), and that is what we run with.
@Suite struct G7CollationTests {
    struct Fixture: Decodable {
        let strings: [String]
        let locales: [String]
        let orders: [[Int]]
    }

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)!
            .appendingPathComponent("g7coll.json")
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    /// en/fr-FR/de/it have no tailoring relevant to these strings (ICU's
    /// createInstance falls back to root); fr_CA and ja are bundled.
    static func collator(for locale: String) throws -> RootCollator {
        switch locale {
        case "fr_CA": return try RootCollator(tailoringNamed: "fr_CA")
        case "ja_JP": return try RootCollator(tailoringNamed: "ja")
        default: return try RootCollator()
        }
    }

    @Test(arguments: 0..<8)
    func g7Locale(index: Int) throws {
        let fixture = Self.fixture
        let locale = fixture.locales[index]
        let collator = try Self.collator(for: locale)
        let options = collator.defaultOptions
        let order = fixture.orders[index]
        var failures = 0
        for j in 0..<order.count {
            for n in (j + 1)..<order.count {
                let a = fixture.strings[order[j]]
                let b = fixture.strings[order[n]]
                // ICU's doTest: both directions plus sort-key order.
                let got = try collator.compare(a, b, options: options)
                let gotReverse = try collator.compare(b, a, options: options)
                let ka = try collator.sortKey(for: a, options: options)
                let kb = try collator.sortKey(for: b, options: options)
                if got != .ascending || gotReverse != .descending
                    || !ka.lexicographicallyPrecedes(kb) {
                    failures += 1
                    if failures <= 5 {
                        Issue.record(
                            "[\(locale)] \(a.debugDescription) vs \(b.debugDescription): got \(got)/\(gotReverse)"
                        )
                    }
                }
            }
        }
        #expect(failures == 0, "\(locale): \(failures) failing pairs")
    }
}
