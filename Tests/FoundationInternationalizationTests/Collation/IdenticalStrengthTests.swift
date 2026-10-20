import Testing
import FoundationEssentials
@testable import FoundationInternationalization

/// Identical-strength compares (`.forcedOrdering`, and so `String.StandardComparator.localizedStandard`) first take a byte fast-Latin pass at tertiary strength: the levels are compared in order, so a non-zero tertiary result is the identical-strength result, and only ties go on to the quaternary and identical levels (technique log §51). The referee is byte-wise sort-key order at identical strength: the sort key always carries every level.
@Suite struct IdenticalStrengthTests {
    static func identical(_ base: CollationOptions) -> CollationOptions {
        var o = base
        o.strength = .identical
        return o
    }

    static func check(_ c: RootCollator, _ options: CollationOptions, _ pairs: [(String, String)]) throws -> Int {
        var failures = 0
        for (a, b) in pairs {
            let expected = try RestartBackupTests.keyOrder(c, a, b, options)
            let got = try c.compare(a, b, options: options)
            if got != expected {
                failures += 1
                if failures <= 5 {
                    Issue.record("\(a.debugDescription) vs \(b.debugDescription): compare \(got), keys \(expected)")
                }
            }
        }
        return failures
    }

    /// Pairs that tie at tertiary strength and differ only at the identical level, or not at all.
    static let ties: [(String, String)] = [
        ("ab", "a\u{200B}b"), ("a\u{200B}b", "ab"),  // a completely ignorable zero-width space
        ("ab", "a\u{00AD}b"),  // soft hyphen
        ("\u{00E1}", "a\u{0301}"),  // canonically equivalent: equal even at identical
        ("item1", "item1\u{200B}"), ("Item", "Item"),
        ("abc", "abd"), ("ABC", "abc"), ("abc", "ABC"),  // decided at primary / tertiary
    ]

    @Test(arguments: [0, 1])
    func identicalStrengthMatchesKeyOrder(numericFlag: Int) throws {
        let c = try RootCollator()
        var base = c.defaultOptions
        base.numeric = numericFlag == 1
        let options = Self.identical(base)
        let fuzz = RestartBackupTests.fuzz
        let ri = RestartBackupTests.riwords
        try #require(fuzz.count > 1000 && ri.count > 30000)
        var pairs = (1..<fuzz.count).map { (fuzz[$0 - 1], fuzz[$0]) }
        pairs += stride(from: 1, to: ri.count, by: 7).map { (ri[$0 - 1], ri[$0]) }
        pairs += Self.ties
        pairs += pairs.map { ($0.1, $0.0) }
        #expect(try Self.check(c, options, pairs) == 0)
    }

    /// `.localizedStandard` (numeric, case-insensitive, forced ordering) orders like the engine at identical strength with numeric on, ties included.
    ///
    /// Runs on the preferences actor: it reads the current-locale collator many times, and a test that switches the current locale with the test-only `LocaleCache.resetCurrent(to:)` (not concurrency-safe by its own documentation) must not run at the same time — a read between that test's `reset()` and its `resetCurrent` stores the old locale's collator under the new generation, and the other test then sees it (seen as a 1-in-8 failure of `wrapperAppliesTailoringDefaults`).
    @Test func localizedStandardComparatorMatchesEngine() async throws {
        try await usingCurrentInternationalizationPreferences {
        let c = try #require(CollatorCache.shared.collatorForCurrentLocale())
        var options = Self.identical(c.defaultOptions)
        options.numeric = true
        let words = Array(RestartBackupTests.fuzz.prefix(400)) + Self.ties.flatMap { [$0.0, $0.1] } + ["file2", "file10", "File10", "file010"]
        let comparator = String.StandardComparator.localizedStandard
        var failures = 0
        for a in words.prefix(120) {
            for b in words where a != b || a.isEmpty {
                let expected: ComparisonResult = switch try c.compare(a, b, options: options) {
                case .ascending: .orderedAscending
                case .same: .orderedSame
                case .descending: .orderedDescending
                }
                if comparator.compare(a, b) != expected {
                    failures += 1
                    if failures <= 5 { Issue.record("\(a.debugDescription) vs \(b.debugDescription)") }
                }
            }
        }
        #expect(failures == 0)
        }
    }
}
