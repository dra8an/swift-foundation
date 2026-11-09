import Foundation
import Testing
@testable import FoundationInternationalization

/// The quick CJK compare (compareFastPath, compareAfterOptionsPass: two different CJK ideographs at the first difference are decided by their primaries) for every collator: with script reordering (ja, zh, zh-stroke, ko, th), the tailored ideographs' normal CE32 (ja, zh), and alternate=shifted (th's default; explicit shifted options) — technique log §51 (ap). Before, it was off for collators with reordering or a shifted default. The referee is byte-wise sort-key order, which never takes the quick path; bridged strings take compareBody's walk and its instance twin `quickPrimaryCompare`.
@Suite struct QuickCJKTests {
    static let collatorNames = ["", "ja", "zh", "zh-stroke", "th", "ko"]

    /// Ideographs from the three CJK unified ranges, by stride: tailored ones (ja 6355, zh 21005, zh-stroke 23826) and untailored ones.
    static let ideographs: [String] = {
        var out: [String] = []
        for (range, stride) in [(UInt32(0x4E00)...0x9FFF, UInt32(29)), (0x3400...0x4DBF, 97), (0x20000...0x2A6DF, 389)] {
            var c = range.lowerBound
            while c <= range.upperBound {
                if let u = Unicode.Scalar(c) { out.append(String(Character(u))) }
                c += stride
            }
        }
        return out
    }()

    static func pairs(every k: Int) -> [(String, String)] {
        let ids = ideographs
        var out: [(String, String)] = []
        for i in Swift.stride(from: 1, to: ids.count, by: k) {
            let a = ids[i - 1], b = ids[i]
            for p in ["", "\u{6771}", "\u{30AB}", "a", " ", "1"] {
                out.append((p + a, p + b))
            }
            out.append((a, a + b))  // a prefix pair: decided after the end of one string
            out.append((a + "x", b + "y"))
        }
        return out
    }

    static func optionSets(_ c: RootCollator) -> [(String, CollationOptions)] {
        let d = c.defaultOptions
        var sets: [(String, CollationOptions)] = [("defaults", d)]
        var o = d; o.strength = .secondary; sets.append(("secondary", o))
        o = d; o.alternate = .shifted; o.strength = .quaternary; sets.append(("shifted quaternary", o))
        o = d; o.strength = .identical; sets.append(("identical", o))
        o = d; o.caseFirst = .upperFirst; sets.append(("upper first", o))
        return sets
    }

    static func check(_ name: String, _ pairs: [(String, String)], bridge: Bool) throws -> Int {
        let c = try RestartBackupTests.collator(name)
        var failures = 0
        for (setName, options) in optionSets(c) {
            for (a, b) in pairs {
                let expected = try RestartBackupTests.keyOrder(c, a, b, options)
                let (ca, cb) = bridge ? (ScalarSourceTests.bridged(a), ScalarSourceTests.bridged(b)) : (a, b)
                let forward = try c.compare(ca, cb, options: options)
                let reversed = try c.compare(cb, ca, options: options)
                let expectedReversed: RootCollator.Order = expected == .same ? .same : (expected == .ascending ? .descending : .ascending)
                if forward != expected || reversed != expectedReversed {
                    failures += 1
                    if failures <= 5 {
                        let hex = { (s: String) in s.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ") }
                        Issue.record("[\(name.isEmpty ? "root" : name), \(setName)\(bridge ? ", bridged" : "")] \(hex(a)) vs \(hex(b)): compare \(forward)/\(reversed), keys \(expected)")
                    }
                }
            }
        }
        return failures
    }

    @Test(arguments: collatorNames)
    func ideographPairsMatchKeyOrder(name: String) throws {
        #expect(try Self.check(name, Self.pairs(every: 1), bridge: false) == 0)
    }

    @Test(arguments: collatorNames)
    func bridgedIdeographPairsMatchKeyOrder(name: String) throws {
        #expect(try Self.check(name, Self.pairs(every: 5), bridge: true) == 0)
    }

    /// The tailored ideographs (normal CE32 in the tailoring's own data: ja 6355, zh 21005, zh-stroke 23826), sorted by their sort keys and paired with their neighbours: their primaries are consecutive, so a primary computed wrongly from the normal CE32 changes some results. The code-point pairs above rarely put two tailored neighbours together.
    @Test(arguments: ["ja", "zh", "zh-stroke"])
    func tailoredNeighboursMatchKeyOrder(name: String) throws {
        let c = try RestartBackupTests.collator(name)
        var tailored: [String] = []
        for range in [UInt32(0x4E00)...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF] {
            for cp in range {
                let ce32 = c.data.trie.get(cp)
                if ce32 != CollationConstants.fallbackCE32, !CollationConstants.isSpecialCE32(ce32), let u = Unicode.Scalar(cp) {
                    tailored.append(String(Character(u)))
                }
            }
        }
        try #require(tailored.count > 5000, "\(name) tailors thousands of ideographs")
        let sample = Swift.stride(from: 0, to: tailored.count, by: 3).map { tailored[$0] }
        let sorted = try sample.map { ($0, try c.sortKey(for: $0)) }.sorted { $0.1.lexicographicallyPrecedes($1.1) }.map { $0.0 }
        var pairs: [(String, String)] = []
        for i in 1..<sorted.count {
            pairs.append((sorted[i - 1], sorted[i]))
            pairs.append(("\u{6771}" + sorted[i - 1], "\u{6771}" + sorted[i]))
        }
        #expect(try Self.check(name, pairs, bridge: false) == 0)
        #expect(try Self.check(name, Array(pairs.prefix(400)), bridge: true) == 0)
    }

    /// The release quick path does not test the variable top: every primary that quickCJKPrimary returns for a CJK unified ideograph must be above the highest variable top (maxVariable = currency), so that a primary difference decides under alternate=shifted too. Checked here for every ideograph of root and of all bundled tailorings.
    @Test func quickPrimariesAreNeverVariable() throws {
        let names = RestartSafetyTests.tailorings.sorted()
        try #require(names.count > 90, "the bundled tailorings")
        var failures = 0
        for name in [""] + names {
            let c = try RestartBackupTests.collator(name)
            let maxVariableTop = c.quickCJKMaxVariableTopForTesting
            for range in [UInt32(0x4E00)...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2EBEF, 0x30000...0x323AF] {
                for cp in range {  // every code point of these ranges, stricter than the CJK-unified test of the hot path
                    let p = c.quickCJKPrimaryForTesting(cp)
                    if p != 0 && p <= maxVariableTop {
                        failures += 1
                        if failures <= 5 { Issue.record("[\(name.isEmpty ? "root" : name)] U+\(String(cp, radix: 16)): quick primary \(String(p, radix: 16)) <= variable top \(String(maxVariableTop, radix: 16))") }
                    }
                }
            }
        }
        #expect(failures == 0)
    }
}
