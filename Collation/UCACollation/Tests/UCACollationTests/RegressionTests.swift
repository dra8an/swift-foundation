import Foundation
import Testing
@testable import UCACollation

/// Ports of ICU4C's CollationRegressionTest (intltest/regcoll.cpp): the 13
/// cases that exercise the root (en_US) collator with strength settings over
/// compareArray triplet tables, extracted mechanically by
/// Tools/extract_regcoll.py into regcoll.json. The skipped cases (rule-string
/// collators, CollationElementIterator API, object identity) are counted in
/// the extractor's output.
///
/// Each triplet is (source, relation, target) with relation "<", "=", ">",
/// checked in both directions plus sort-key order.
@Suite struct RegressionTests {
    struct File: Decodable {
        let cases: [Case]
    }

    struct Case: Decodable {
        let name: String
        let locale: String
        let strength: String
        let attrs: [[String]]
        let triplets: [[String]]
    }

    static let cases: [Case] = {
        let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)!
            .appendingPathComponent("regcoll.json")
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }()

    static let root = try! RootCollator()

    @Test(arguments: 0..<13) func regression(caseIndex: Int) throws {
        let c = Self.cases[caseIndex]
        let collator = c.locale == "root" ? Self.root : try RootCollator(tailoringNamed: c.locale)
        var options = collator.defaultOptions
        switch c.strength {
        case "primary": options.strength = .primary
        case "secondary": options.strength = .secondary
        case "tertiary": options.strength = .tertiary
        case "quaternary": options.strength = .quaternary
        case "identical": options.strength = .identical
        default: Issue.record("\(c.name): unknown strength \(c.strength)"); return
        }
        for attr in c.attrs {
            switch (attr[0], attr[1]) {
            case ("UCOL_NORMALIZATION_MODE", "UCOL_ON"):
                break  // always on in this implementation
            case ("UCOL_NORMALIZATION_MODE", "UCOL_OFF"):
                // Test4114077: the extractor selected the normalization-ON
                // array; the OFF phase's array is excluded.
                break
            case ("UCOL_STRENGTH", "UCOL_SECONDARY"):
                options.strength = .secondary
            case ("UCOL_STRENGTH", "UCOL_TERTIARY"):
                options.strength = .tertiary
            default:
                Issue.record("\(c.name): unhandled attribute \(attr)")
                return
            }
        }

        var failures = 0
        for triplet in c.triplets {
            let (source, relation, target) = (triplet[0], triplet[1], triplet[2])
            let expected: RootCollator.Order =
                relation == "<" ? .ascending : relation == "=" ? .same : .descending
            let reversed: RootCollator.Order =
                expected == .same ? .same : (expected == .ascending ? .descending : .ascending)
            let got = try collator.compare(source, target, options: options)
            let gotReverse = try collator.compare(target, source, options: options)
            let k1 = try collator.sortKey(for: source, options: options)
            let k2 = try collator.sortKey(for: target, options: options)
            let keyOrder: RootCollator.Order =
                k1 == k2 ? .same : (k1.lexicographicallyPrecedes(k2) ? .ascending : .descending)
            if got != expected || gotReverse != reversed || keyOrder != expected {
                failures += 1
                Issue.record(
                    "[\(c.name)] \(source.debugDescription) \(relation) \(target.debugDescription): got \(got)/\(gotReverse)/keys \(keyOrder)"
                )
            }
        }
        #expect(failures == 0, "[\(Self.cases[caseIndex].name)] \(failures) triplet failures")
    }
}
