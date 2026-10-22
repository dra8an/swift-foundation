import Foundation
import Testing
@testable import FoundationInternationalization

/// The CJK fast path of CE production (technique log §51 (v)) against the full path: an iterator with the fast tables takes the fast path, one without them takes `lookup` + `appendCEs`. For every code point of the CJK unified ranges — alone, and followed by its two successors — both must give the same CEs, on root and on the CJK tailorings (where some ideographs are tailored and must leave the fast path).
@Suite struct CJKFastPathTests {
    static let ranges: [ClosedRange<UInt32>] = [0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2A6DF]

    static func mismatches(_ collator: RootCollator) throws -> [String] {
        var fast = CEIterator(
            data: collator.data, base: collator.base, norm: collator.norm, numeric: false, scalars: "".unicodeScalars,
            simpleCEs: collator.simpleCEs, thaiCEs: collator.thaiCEs,
            simpleCEsWithDigits: collator.simpleCEsWithDigits, thaiCEsWithDigits: collator.thaiCEsWithDigits)
        var full = CEIterator(
            data: collator.data, base: collator.base, norm: collator.norm, numeric: false, scalars: "".unicodeScalars)
        try #require(!collator.simpleCEs.isEmpty, "the fast path needs the tables")
        var found: [String] = []
        for range in ranges {
            for c in range {
                for length: UInt32 in [1, 3] {
                    var s = String.UnicodeScalarView()
                    for k in 0..<length {
                        if let u = Unicode.Scalar(c + k) { s.append(u) }
                    }
                    fast.reset(numeric: false, scalars: s)
                    full.reset(numeric: false, scalars: s)
                    try fast.collectAll()
                    try full.collectAll()
                    if fast.ces.toArray() != full.ces.toArray() || fast.scalarsConsumed != full.scalarsConsumed {
                        found.append(String(c, radix: 16) + (length > 1 ? "+2" : ""))
                    }
                }
            }
        }
        return found
    }

    @Test(arguments: ["root", "zh", "zh-stroke", "ja", "ko"])
    func fastPathAgreesWithTheFullPath(name: String) throws {
        let collator = name == "root" ? try RootCollator() : try RootCollator(tailoringNamed: name)
        let found = try Self.mismatches(collator)
        #expect(found.isEmpty, "\(name): \(found.count) mismatches, first: \(found.prefix(8))")
    }
}
