import Foundation
import Testing
@testable import FoundationInternationalization

/// Position-reporting gate.
///
/// Every other collation suite compares CE bytes or sort-key bytes: the
/// conformance files assert an ordering, the differential and fuzz suites
/// assert key bytes against ICU reference answers. None of them looks at the
/// OFFSETS the search APIs report, and four separate bugs have now been found
/// in that channel by hand (a Substring index-space error in `rebaseRange`,
/// tailoring default settings, and the discontiguous-contraction scalar count
/// below). Each was invisible to every gate, and each was found by a
/// throwaway probe that should have been a test.
///
/// The core invariant here needs no reference implementation: the CE iterator
/// must consume exactly as many scalars as the NFD front end produces for the
/// same input. `scalarsConsumed` is what annotates every `AnnotatedCE` with
/// `nfdStart`/`nfdEnd`, which `confirmMatch` converts into the returned
/// `String.Index` range — so any drift in that counter silently corrupts every
/// position the search APIs report, while leaving CEs and sort keys perfect.
/// Running it over the conformance corpora turns "positions are reported by
/// hand-checked example" into "positions are checked on every input we have".
@Suite struct PositionInvariantTests {
    private static let _collator = Result { try RootCollator() }
    static var collator: RootCollator { get throws { try _collator.get() } }

    /// Scalars the NFD front end yields for `s` — the number the CE iterator
    /// must account for.
    private static func nfdScalarCount(_ s: String, norm: NormalizationData) -> Int {
        var nfd = NFDIterator(norm: norm, scalars: s.unicodeScalars)
        var n = 0
        while nfd.next() != nil { n += 1 }
        return n
    }

    /// Drives a CE iterator to the NO_CE terminator and reports its scalar count.
    private static func consumedScalars(
        _ s: String, collator: RootCollator, numeric: Bool, withTables: Bool
    ) throws -> Int {
        var iter: CEIterator
        if withTables {
            iter = CEIterator(
                data: collator.data, base: collator.base, norm: collator.norm,
                numeric: numeric, scalars: s.unicodeScalars,
                simpleCEs: collator.simpleCEs, thaiCEs: collator.thaiCEs,
                simpleCEsWithDigits: collator.simpleCEsWithDigits,
                thaiCEsWithDigits: collator.thaiCEsWithDigits)
        } else {
            iter = CEIterator(
                data: collator.data, base: collator.base, norm: collator.norm,
                numeric: numeric, scalars: s.unicodeScalars)
        }
        _ = try iter.collectAll()
        return iter.scalarsConsumed
    }

    /// THE gate for the whole bug class: over both official conformance
    /// corpora, the CE iterator's scalar count must equal the NFD scalar
    /// count — for the plain pipeline, for the simple-CE table fast paths,
    /// and for numeric mode (which consumes digit runs through a separate
    /// path). A discontiguous contraction that forgets to count the scalar it
    /// removes fails here on the first line that reaches the branch.
    @Test(arguments: ["CollationTest_NON_IGNORABLE_SHORT.txt", "CollationTest_SHIFTED_SHORT.txt"])
    func ceIteratorAccountsForEveryNFDScalar(file: String) throws {
        let collator = try Self.collator
        let strings = try ConformanceTests.parse(file: file)
        try #require(strings.count > 100_000, "conformance file too short: \(strings.count)")

        var failures = 0
        for s in strings {
            let expected = Self.nfdScalarCount(s, norm: collator.norm)
            for (numeric, withTables) in [(false, false), (false, true), (true, true)] {
                let consumed = try Self.consumedScalars(
                    s, collator: collator, numeric: numeric, withTables: withTables)
                if consumed != expected {
                    failures += 1
                    if failures <= 5 {
                        let hex = s.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
                        Issue.record(
                            "[\(file)] numeric=\(numeric) tables=\(withTables): consumed \(consumed), NFD has \(expected) — [\(hex)]"
                        )
                    }
                }
            }
        }
        #expect(failures == 0, "[\(file)] \(failures) scalar-count mismatches")
    }

    /// Same invariant over the seeded fuzz corpus and the golden corpus, which
    /// carry option-set and script coverage the conformance files do not.
    @Test(arguments: ["fuzz-corpus.txt", "corpus.txt"])
    func ceIteratorAccountsForEveryNFDScalarInGoldenCorpora(file: String) throws {
        let collator = try Self.collator
        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        let strings = try String(
            contentsOf: golden.appendingPathComponent(file), encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        try #require(!strings.isEmpty, "empty corpus \(file)")

        var failures = 0
        for s in strings {
            let expected = Self.nfdScalarCount(s, norm: collator.norm)
            for (numeric, withTables) in [(false, false), (false, true), (true, true)] {
                let consumed = try Self.consumedScalars(
                    s, collator: collator, numeric: numeric, withTables: withTables)
                if consumed != expected { failures += 1 }
            }
        }
        #expect(failures == 0, "[\(file)] \(failures) scalar-count mismatches")
    }

    // MARK: API-level position invariants

    /// Inputs that reach the UTS #10 S2.1.3 discontiguous branch in ROOT data,
    /// discovered by instrumenting the "remove C" site and sweeping the UCA
    /// corpus. Root contracts Cyrillic и/И + U+0306 (breve, ccc 230) and Arabic
    /// forms with U+0653/U+0654; an intervening mark of LOWER ccc (U+0334, ccc
    /// 1, or U+0591, ccc 220) does not block the match, so S is replaced by S+C
    /// and C is removed from the lookahead out of order.
    static let discontiguousSequences = [
        "\u{0438}\u{0334}\u{0306}",           // и + tilde overlay + breve
        "\u{0438}\u{0306}\u{0334}",           // и + breve + tilde overlay
        "\u{0439}\u{0334}",                   // й (precomposed) + tilde overlay
        "\u{0418}\u{0334}\u{0306}",           // И uppercase
        "\u{0438}\u{0591}\u{0306}",           // и + Hebrew etnahta (ccc 220) + breve
        "\u{0627}\u{0334}\u{0653}",           // Arabic alef + tilde overlay + maddah
        "\u{0622}\u{0334}",                   // Arabic alef with madda + tilde overlay
    ]

    /// A match placed after a discontiguous contraction must be reported at its
    /// true offset. This is the exact failure the bug produced: the range came
    /// back one scalar short, and boundary validation then rejected it, so the
    /// API returned nil — a missed match, not a shifted one.
    @Test func matchAfterDiscontiguousContractionIsReportedCorrectly() throws {
        let collator = try Self.collator
        for prefix in Self.discontiguousSequences {
            let text = prefix + "abc"
            let expected = Self.trailingRange(of: 3, in: text)
            let forward = collator.search(for: "abc", in: text)
            #expect(forward != nil, "forward search missed 'abc' in \(text.debugDescription)")
            #expect(forward == expected, "forward range wrong in \(text.debugDescription)")

            let backward = collator.searchBackwards(for: "abc", in: text)
            #expect(backward != nil, "backward search missed 'abc' in \(text.debugDescription)")
            #expect(backward == expected, "backward range wrong in \(text.debugDescription)")
        }
    }

    /// The same sequences with a decomposing character in front, so the NFD
    /// offset → source offset map is exercised on top of the drifted count
    /// (source scalars and NFD scalars no longer line up).
    @Test func matchAfterDiscontiguousContractionWithDecompositionInFront() throws {
        let collator = try Self.collator
        for core in Self.discontiguousSequences {
            let text = "caf\u{00e9} " + core + "abc"   // é precomposed: NFD expands it
            let expected = Self.trailingRange(of: 3, in: text)
            let result = collator.search(for: "abc", in: text)
            #expect(result != nil, "missed 'abc' in \(text.debugDescription)")
            #expect(result == expected, "wrong range in \(text.debugDescription)")
        }
    }

    /// Content round-trip: whatever range a search reports, the text at that
    /// range must itself compare equal to the pattern. Oracle-free, and it
    /// catches any misalignment regardless of cause — a range off by one
    /// scalar cannot collate equal to the pattern.
    @Test func reportedRangeContentsMatchThePattern() throws {
        let collator = try Self.collator
        var checked = 0
        for core in Self.discontiguousSequences {
            for pattern in ["abc", "XY", core] {
                let text = "pre " + core + "mid" + pattern + " post"
                guard let r = collator.search(for: pattern, in: text) else { continue }
                checked += 1
                let matched = String(text[r])
                #expect(
                    try collator.compare(matched, pattern) == .same,
                    "reported range \(matched.debugDescription) does not collate equal to pattern \(pattern.debugDescription) in \(text.debugDescription)"
                )
            }
        }
        #expect(checked > 0, "no matches exercised the round-trip invariant")
    }

    /// Searching a string for itself must report the whole string, whatever
    /// contractions or discontiguous matches it contains.
    ///
    /// The hard case is a discontiguous match whose skipped mark is COMPLETELY
    /// IGNORABLE: the mark is filtered out of both the pattern CEs and the text
    /// buffer, so the match's last CE is the contraction itself — and that CE
    /// consumed a NON-CONTIGUOUS scalar set (the base plus a scalar on the far
    /// side of the skipped mark). Reporting the last CE's end as the match end
    /// excluded the far-side scalar, landed mid-combining-sequence, and was
    /// rejected by boundary validation, so the API returned nil. Fixed by
    /// tracking per-CE NFD spans and taking the min start / max end over a
    /// match's CEs; see CEIterator.spanStart and confirmedRange.
    @Test func selfSearchCoversTheWholeString() throws {
        let collator = try Self.collator
        for s in Self.discontiguousSequences {
            let r = collator.search(for: s, in: s)
            #expect(r != nil, "self-search missed \(s.debugDescription)")
            #expect(r == s.startIndex..<s.endIndex, "self-search range wrong for \(s.debugDescription)")
        }
    }

    /// The same, with the discontiguous contraction at the END of a longer
    /// text: the match's own end is what the old first/last span arithmetic
    /// got wrong, so exercise it both alone and after leading content.
    @Test func matchEndingAtDiscontiguousContraction() throws {
        let collator = try Self.collator
        for core in Self.discontiguousSequences {
            for lead in ["", "abc ", "caf\u{00e9} "] {
                let text = lead + core
                let expected = Self.trailingRange(of: core.unicodeScalars.count, in: text)
                let r = collator.search(for: core, in: text)
                #expect(r != nil, "missed \(core.debugDescription) in \(text.debugDescription)")
                #expect(r == expected, "wrong range for \(core.debugDescription) in \(text.debugDescription)")
            }
        }
    }

    /// The §39 class: a Substring receiver must produce indices in the
    /// receiver's own index space, not the parent buffer's.
    @Test func substringReceiverReportsSelfRelativeIndices() throws {
        let collator = try Self.collator
        for core in Self.discontiguousSequences {
            let parent = "IGNORE THIS PREFIX " + core + "abc"
            let receiver = parent.dropFirst("IGNORE THIS PREFIX ".count)
            guard let r = collator.search(for: "abc", in: String(receiver)) else {
                Issue.record("missed 'abc' in substring receiver for \(core.debugDescription)")
                continue
            }
            let asString = String(receiver)
            #expect(asString[r] == "abc", "substring receiver range points at \(asString[r].debugDescription)")
        }
    }

    private static func trailingRange(of scalars: Int, in text: String) -> Range<String.Index> {
        let start = text.unicodeScalars.index(
            text.unicodeScalars.startIndex, offsetBy: text.unicodeScalars.count - scalars)
        return start..<text.endIndex
    }
}
