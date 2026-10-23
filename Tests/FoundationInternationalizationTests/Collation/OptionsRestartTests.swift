import Foundation
import Testing
@testable import FoundationInternationalization

/// The identical-prefix restart under NON-default options (technique log §51 (z)). Two option settings carry state from the skipped prefix into the rest of the string: alternate=shifted (primary-ignorable CEs after a variable CE are ignored) and a backward secondary level (the secondary weights are compared from the end). The CE compare detects the cases where the prefix can change the result, and the caller compares again from the start (`CollationCompare.prefixDependent`). ICU 79.1's doCompare has no such check: its compare disagrees with its own sort keys on these pairs.
///
/// The referee is byte-wise sort-key order (sortKey() never skips a prefix), as in RestartBackupTests, but for many option sets: the Foundation ones (secondary; secondary + numeric; primary), case first, case level, backward secondary and shifted. Inputs: native strings (the byte scan's restart and compareFromRestart) and bridged strings (compareBody's skip walk).
@Suite struct OptionsRestartTests {
    static let collatorNames = ["", "th", "ja", "sv", "fr_CA"]

    /// The option sets, each built on the collator's own defaults.
    static func optionSets(_ c: RootCollator) -> [(String, CollationOptions)] {
        let d = c.defaultOptions
        var sets: [(String, CollationOptions)] = [("defaults", d)]
        var o = d; o.strength = .secondary; sets.append(("secondary", o))
        o.numeric = true; sets.append(("secondary numeric", o))
        o = d; o.strength = .primary; sets.append(("primary", o))
        o = d; o.caseFirst = .upperFirst; sets.append(("upper first", o))
        o = d; o.strength = .primary; o.caseLevel = true; sets.append(("primary case level", o))
        o = d; o.backwardSecondary = !d.backwardSecondary; sets.append(("backward secondary toggled", o))
        o = d; o.alternate = .shifted; o.strength = .quaternary; sets.append(("shifted quaternary", o))
        o = d; o.alternate = .shifted; o.maxVariable = .symbol; o.strength = .secondary; sets.append(("shifted symbol secondary", o))
        o = d; o.alternate = .shifted; o.backwardSecondary = true; o.strength = .quaternary; sets.append(("shifted backward", o))
        return sets
    }

    /// Continuations around the restart point: the RestartBackupTests ones, plus variable scalars, primary-ignorable starters (safe to restart at) and the two together.
    static let continuations = RestartBackupTests.continuations + [
        " ", "-", "\u{0E4C}", "\u{0B55}", "\u{00AD}\u{0301}", " \u{0900}", "-\u{0E47}",
    ]

    static func builtPairs(_ words: [String], every k: Int) -> [(String, String)] {
        var pairs: [(String, String)] = []
        for w in stride(from: 0, to: words.count, by: k).map({ words[$0] }) {
            for x in continuations {
                pairs.append((w, w + x))
                for y in continuations where y != x { pairs.append((w + x, w + y)) }
            }
        }
        return pairs
    }

    /// Checks compare() against the key order for each pair and option set, both ways round; answers the number of disagreements and records the first few.
    static func check(_ c: RootCollator, _ name: String, _ pairs: [(String, String)], bridge: Bool = false) throws -> Int {
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

    @Test(arguments: ["", "th"])
    func riwordsAdjacentPairs(name: String) throws {
        let words = RestartBackupTests.riwords
        try #require(words.count > 30000)
        let c = try RestartBackupTests.collator(name)
        let pairs = stride(from: 1, to: words.count, by: 4).map { (words[$0 - 1], words[$0]) }
        #expect(try Self.check(c, name, pairs) == 0)
    }

    @Test(arguments: collatorNames)
    func fuzzAdjacentPairs(name: String) throws {
        let fuzz = RestartBackupTests.fuzz
        try #require(fuzz.count > 1000)
        let c = try RestartBackupTests.collator(name)
        let pairs = (1..<fuzz.count).map { (fuzz[$0 - 1], fuzz[$0]) }
        #expect(try Self.check(c, name, pairs) == 0)
    }

    @Test(arguments: collatorNames)
    func builtPairsAroundTheRestart(name: String) throws {
        try #require(RestartBackupTests.riwords.count > 30000 && RestartBackupTests.fuzz.count > 1000)
        let c = try RestartBackupTests.collator(name)
        let pairs = Self.builtPairs(RestartBackupTests.riwords, every: 701) + Self.builtPairs(RestartBackupTests.fuzz, every: 97)
        #expect(try Self.check(c, name, pairs) == 0)
    }

    /// The skip walk (bridged, non-contiguous strings) on the same built pairs, fewer words.
    @Test(arguments: collatorNames)
    func bridgedBuiltPairs(name: String) throws {
        try #require(RestartBackupTests.riwords.count > 30000 && RestartBackupTests.fuzz.count > 1000)
        let c = try RestartBackupTests.collator(name)
        let pairs = Self.builtPairs(RestartBackupTests.riwords, every: 3001) + Self.builtPairs(RestartBackupTests.fuzz, every: 401)
        #expect(try Self.check(c, name, pairs, bridge: true) == 0)
    }

    /// Every safe BMP starter whose CEs start with primary 0 (U+0900, U+0E4C, U+00AD, ...), right after the restart: after a variable scalar (shifted), and at the end of a prefix pair whose prefix ends in a combining mark (backward secondary).
    @Test func primaryIgnorableStartersAfterTheRestart() throws {
        let root = try RootCollator()
        let safety = root.restartSafety
        var primary = CollationOptions()
        primary.strength = .primary
        var starters: [String] = []
        for v in UInt32(0x20)..<0x10000 {
            guard let u = Unicode.Scalar(v), !safety.isUnsafe(v, numeric: false) else { continue }
            let s = String(Character(u))
            guard s.unicodeScalars.count == 1 else { continue }
            if try root.compare("b", "b" + s, options: primary) == .same { starters.append(s) }
        }
        try #require(starters.count > 100, "the data has more than 100 such starters")
        var shiftedPairs: [(String, String)] = []
        var backwardPairs: [(String, String)] = []
        for m in starters {
            shiftedPairs += [("a b", "a " + m + "b"), ("a-b", "a-" + m + "b"), ("a ", "a " + m)]
            for k in stride(from: UInt32(0x300), through: 0x36F, by: 5) {
                let mark = String(Character(Unicode.Scalar(k)!))
                backwardPairs += [("e" + mark, "e" + mark + m), ("e" + mark + "b", "e" + mark + "b" + m)]
            }
        }
        var shifted = CollationOptions()
        shifted.alternate = .shifted
        var backward = CollationOptions()
        backward.backwardSecondary = true
        let fr = try RootCollator(tailoringNamed: "fr_CA")
        let th = try RootCollator(tailoringNamed: "th")
        var failures = 0
        for (c, options, pairs, label) in [
            (root, shifted, shiftedPairs, "root shifted"), (th, th.defaultOptions, shiftedPairs, "th defaults"),
            (root, backward, backwardPairs, "root backward"), (fr, fr.defaultOptions, backwardPairs, "fr_CA defaults"),
        ] {
            for strength in [CollationOptions.Strength.secondary, .tertiary, .quaternary] {
                var o = options
                o.strength = strength
                for (a, b) in pairs {
                    let expected = try RestartBackupTests.keyOrder(c, a, b, o)
                    if try c.compare(a, b, options: o) != expected {
                        failures += 1
                        if failures <= 5 {
                            Issue.record("[\(label), strength \(strength)] \(a.unicodeScalars.map { String($0.value, radix: 16) }) vs \(b.unicodeScalars.map { String($0.value, radix: 16) }): keys \(expected)")
                        }
                    }
                }
            }
        }
        #expect(failures == 0)
    }
}
