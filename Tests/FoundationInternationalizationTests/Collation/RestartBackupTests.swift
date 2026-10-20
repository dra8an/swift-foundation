import Foundation
import Testing
@testable import FoundationInternationalization

/// The compare entry restarts CE iteration after a shared prefix at the point the byte scan chooses — ICU's backup rule: when either first-differing scalar is unsafe to restart at, step back while the scalar at the new position is unsafe (RootCollator.restartScalarCount, technique log §51). These pairs put the difference right after scalars that are safe or unsafe in every way the data has — Thai consonants (contraction suffixes), prefix vowels, tone marks, combining marks, the middle-dot prefix context, kana voicing marks, digits — and one word a prefix of the next.
///
/// The referee is byte-wise sort-key order: sortKey() never skips a prefix, and its order equals compare() at the same options. Only each collator's own default options reach the byte-scan restart, so each collator runs with those.
@Suite struct RestartBackupTests {
    static let collatorNames = ["", "th", "ja", "sv", "fr_CA"]

    static func collator(_ name: String) throws -> RootCollator {
        name.isEmpty ? try RootCollator() : try RootCollator(tailoringNamed: name)
    }

    static let riwords: [String] = {
        guard let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)?
            .appendingPathComponent("riwords.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map { line -> Substring in
                if let hash = line.firstIndex(of: "#") { return line[..<hash] }
                return line
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }()

    static let fuzz: [String] = {
        guard let url = Bundle.module.url(forResource: "Golden", withExtension: nil)?
            .appendingPathComponent("fuzz-corpus.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }()

    /// Continuations around the restart point: unsafe and safe scalars of each kind.
    static let continuations = [
        "ก", "เ", "\u{0E48}", "า", "ะ",  // Thai consonant, prefix vowel, tone mark, sara aa, sara a
        "a", "\u{0301}", "1", "\u{00B7}",  // Latin letter, combining acute, digit, middle dot (prefix context after l)
        "か", "\u{3099}",  // kana, voicing mark (prefix context in ja)
    ]

    /// The order of the two sort keys.
    static func keyOrder(_ c: RootCollator, _ a: String, _ b: String, _ options: CollationOptions) throws -> RootCollator.Order {
        let ka = try c.sortKey(for: a, options: options)
        let kb = try c.sortKey(for: b, options: options)
        if ka == kb { return .same }
        return ka.lexicographicallyPrecedes(kb) ? .ascending : .descending
    }

    /// Checks compare() against the key order for each pair, both ways round; answers the number of disagreements and records the first few.
    static func check(_ c: RootCollator, _ name: String, _ pairs: [(String, String)]) throws -> Int {
        let options = c.defaultOptions
        var failures = 0
        for (a, b) in pairs {
            let expected = try keyOrder(c, a, b, options)
            let forward = try c.compare(a, b, options: options)
            let reversed = try c.compare(b, a, options: options)
            let expectedReversed: RootCollator.Order = expected == .same ? .same : (expected == .ascending ? .descending : .ascending)
            if forward != expected || reversed != expectedReversed {
                failures += 1
                if failures <= 5 {
                    let hex = { (s: String) in s.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ") }
                    Issue.record("[\(name.isEmpty ? "root" : name)] \(hex(a)) vs \(hex(b)): compare \(forward)/\(reversed), keys \(expected)")
                }
            }
        }
        return failures
    }

    /// Prefix pairs and pairs that differ right after a shared prefix, for every k-th word.
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

    @Test(arguments: ["", "th"])
    func riwordsAdjacentPairs(name: String) throws {
        try #require(Self.riwords.count > 30000)
        let c = try Self.collator(name)
        let pairs = (1..<Self.riwords.count).map { (Self.riwords[$0 - 1], Self.riwords[$0]) }
        #expect(try Self.check(c, name, pairs) == 0)
    }

    @Test(arguments: collatorNames)
    func builtPairsAroundTheRestart(name: String) throws {
        try #require(Self.riwords.count > 30000 && Self.fuzz.count > 1000)
        let c = try Self.collator(name)
        let pairs = Self.builtPairs(Self.riwords, every: 211) + Self.builtPairs(Self.fuzz, every: 23)
        #expect(try Self.check(c, name, pairs) == 0)
    }

    @Test(arguments: collatorNames)
    func fuzzAdjacentPairs(name: String) throws {
        try #require(Self.fuzz.count > 1000)
        let c = try Self.collator(name)
        let pairs = (1..<Self.fuzz.count).map { (Self.fuzz[$0 - 1], Self.fuzz[$0]) }
        #expect(try Self.check(c, name, pairs) == 0)
    }
}
