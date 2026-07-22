import Foundation
import Testing
@testable import FoundationInternationalization

/// The official UCA/CLDR conformance suite (UTS #10 / TR35 Root Data Files):
/// CollationTest_CLDR_*_SHORT.txt list strings in root-collation order; for
/// every pair of consecutive lines, compare(prev, cur) must not be
/// "descending", and sort keys must order the same way.
///
/// Mirrors ICU's UCAConformanceTest: strength=identical, normalization on,
/// caseFirst/caseLevel off; alternate per file (non-ignorable vs shifted).
///
/// Lines containing unpaired surrogates are skipped: Swift Strings cannot
/// represent them (the scalar-based design shares this property with ICU4X).
/// Skipping a line compares its neighbors directly, which the files' total
/// order permits.
@Suite struct ConformanceTests {
    private static let _collators = Result {
        [("regular", try RootCollator()),
         ("icu4x", RootCollator(data: try .rootICU4X(), norm: try .standard()))]
    }
    static var collators: [(String, RootCollator)] { get throws { try _collators.get() } }

    static func parse(file: String) throws -> [String] {
        let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)!
            .appendingPathComponent(file)
        let content = try String(contentsOf: url, encoding: .utf8)
        var strings: [String] = []
        var skipped = 0
        for line in content.split(separator: "\n") {
            if line.isEmpty || line.hasPrefix("#") { continue }
            var s = ""
            var representable = true
            for hex in line.split(separator: " ") {
                guard let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) else {
                    representable = false  // unpaired surrogate or invalid
                    break
                }
                s.unicodeScalars.append(scalar)
            }
            if representable {
                strings.append(s)
            } else {
                skipped += 1
            }
        }
        // The files contain a small number of unpaired-surrogate lines.
        try #require(skipped < 200, "unexpectedly many skipped lines: \(skipped)")
        return strings
    }

    private func run(file: String, alternate: CollationOptions.Alternate, collatorIndex: Int) throws {
        let (variant, collator) = try Self.collators[collatorIndex]
        var options = CollationOptions()
        options.strength = .identical
        options.alternate = alternate

        let strings = try Self.parse(file: file)
        try #require(strings.count > 100_000, "conformance file too short: \(strings.count)")

        var failures = 0
        var prev = strings[0]
        var prevKey = try collator.sortKey(for: prev, options: options)
        for i in 1..<strings.count {
            let cur = strings[i]
            let curKey = try collator.sortKey(for: cur, options: options)
            let order = try collator.compare(prev, cur, options: options)
            let keyOrder: RootCollator.Order =
                prevKey == curKey ? .same
                : prevKey.lexicographicallyPrecedes(curKey) ? .ascending : .descending
            if order == .descending || keyOrder == .descending || order != keyOrder {
                failures += 1
                if failures <= 5 {
                    Issue.record(
                        "[\(variant)] line \(i): \(prev.unicodeScalars.map { String($0.value, radix: 16) }) vs \(cur.unicodeScalars.map { String($0.value, radix: 16) }): compare=\(order), keys=\(keyOrder)"
                    )
                }
            }
            prev = cur
            prevKey = curKey
        }
        #expect(failures == 0, "[\(variant)/\(file)] \(failures) of \(strings.count - 1) adjacent pairs out of order")
    }

    @Test(arguments: [0, 1]) func nonIgnorable(collatorIndex: Int) throws {
        try run(file: "CollationTest_NON_IGNORABLE_SHORT.txt",
                alternate: .nonIgnorable, collatorIndex: collatorIndex)
    }

    @Test(arguments: [0, 1]) func shifted(collatorIndex: Int) throws {
        try run(file: "CollationTest_SHIFTED_SHORT.txt",
                alternate: .shifted, collatorIndex: collatorIndex)
    }
}
