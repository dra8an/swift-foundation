import Foundation
import Testing
@testable import Collation

/// Ports of the non-rule test cases from ICU4C's cintltst/cmsccoll.c
/// (miscellaneous collation regressions), extracted by
/// Tools/extract_cmsccoll.py into cmsccoll.json. Each case is a locale +
/// options + a string list where every pair i<j must compare ascending
/// (genericLocaleStarter), or equal for the one UCOL_EQUAL case — checked in
/// both directions plus sort-key order, like ICU's doTest.
///
/// The other ~88 call sites in cmsccoll.c build collators from rule strings
/// (see Docs/12-rule-builder-decision.md); TestExtremeCompression is
/// programmatic and reimplemented below.
@Suite struct CmsccollTests {
    struct File: Decodable {
        let cases: [Case]
    }

    struct Case: Decodable {
        let name: String
        let locale: String
        let attrs: [[String]]
        let expected: String
        let strings: [String]
    }

    static let cases: [Case] = {
        let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)!
            .appendingPathComponent("cmsccoll.json")
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }()

    static let root = try! RootCollator()
    static let collators: [String: RootCollator] = Dictionary(
        uniqueKeysWithValues: ["zh", "da", "fr", "ko", "ja", "th"].map {
            ($0, try! RootCollator(tailoringNamed: $0))
        })

    static func collator(_ locale: String) -> RootCollator {
        locale == "root" ? root : collators[locale]!
    }

    private func apply(_ attrs: [[String]], to options: inout CollationOptions) {
        for attr in attrs {
            switch (attr[0], attr[1]) {
            case ("strength", "primary"): options.strength = .primary
            case ("strength", "secondary"): options.strength = .secondary
            case ("strength", "tertiary"): options.strength = .tertiary
            case ("strength", "quaternary"): options.strength = .quaternary
            case ("alternate", "shifted"): options.alternate = .shifted
            case ("caseFirst", "upper"): options.caseFirst = .upperFirst
            case ("caseLevel", "on"): options.caseLevel = true
            case ("numeric", "on"): options.numeric = true
            default: fatalError("unhandled attribute \(attr)")
            }
        }
    }

    @Test(arguments: 0..<20) func cmsccoll(caseIndex: Int) throws {
        let c = Self.cases[caseIndex]
        let collator = Self.collator(c.locale)
        var options = collator.defaultOptions
        apply(c.attrs, to: &options)
        let expected: RootCollator.Order = c.expected == "equal" ? .same : .ascending
        let reversed: RootCollator.Order = expected == .same ? .same : .descending

        var failures = 0
        let keys = try c.strings.map { try collator.sortKey(for: $0, options: options) }
        for i in 0..<c.strings.count {
            for j in (i + 1)..<c.strings.count {
                let got = try collator.compare(c.strings[i], c.strings[j], options: options)
                let gotReverse = try collator.compare(c.strings[j], c.strings[i], options: options)
                let keyOrder: RootCollator.Order =
                    keys[i] == keys[j] ? .same
                    : (keys[i].lexicographicallyPrecedes(keys[j]) ? .ascending : .descending)
                if got != expected || gotReverse != reversed || keyOrder != expected {
                    failures += 1
                    if failures <= 5 {
                        Issue.record(
                            "[\(c.name)] \(c.strings[i].debugDescription) vs \(c.strings[j].debugDescription): got \(got)/\(gotReverse)/keys \(keyOrder), expected \(expected)"
                        )
                    }
                }
            }
        }
        #expect(failures == 0, "[\(c.name)] \(failures) pair failures")
    }

    /// TestExtremeCompression (reimplemented; it generates its data):
    /// for each length 20..<500, the four strings "aa…a" + {a,b,c,d} must
    /// sort ascending — stressing primary lead-byte compression runs.
    @Test func extremeCompression() throws {
        var options = CollationOptions()
        options.strength = .tertiary
        var failures = 0
        for length in 20..<500 {
            let prefix = String(repeating: "a", count: length - 1)
            let strings = ["a", "b", "c", "d"].map { prefix + $0 }
            let keys = try strings.map { try Self.root.sortKey(for: $0, options: options) }
            for i in 0..<4 {
                for j in (i + 1)..<4 {
                    if try Self.root.compare(strings[i], strings[j], options: options) != .ascending
                        || !keys[i].lexicographicallyPrecedes(keys[j]) {
                        failures += 1
                        if failures <= 3 {
                            Issue.record("length \(length): [\(i)] !< [\(j)]")
                        }
                    }
                }
            }
        }
        #expect(failures == 0, "\(failures) failures across compression lengths")
    }
}
