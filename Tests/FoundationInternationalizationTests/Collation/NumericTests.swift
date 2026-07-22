import Testing
@testable import FoundationInternationalization

/// Numeric collation (CODAN) edge cases around the digit-run encodings:
/// the dense single-CE encoding covers values up to 1_042_489 (74 + 40*254
/// + 16*254*254); larger values — including 7-digit values past that
/// capacity — use the digit-pair encoding. These pin the boundary and the
/// invariants the encodings must preserve (added with the digit-run fast
/// path that accumulates small runs into a value without a digits array).
@Suite("Numeric collation")
struct NumericTests {
    let collator = try! RootCollator()
    var numericOpts: CollationOptions {
        var opts = CollationOptions()
        opts.numeric = true
        return opts
    }

    private func cmp(_ a: String, _ b: String) throws -> Int {
        try collator.compare(a, b, options: numericOpts).rawValue
    }

    private func keysOrderedSame(_ strings: [String]) throws {
        var keys: [[UInt8]] = []
        for s in strings {
            keys.append(try collator.sortKey(for: s, options: numericOpts))
        }
        for i in 1..<keys.count {
            #expect(keys[i - 1].lexicographicallyPrecedes(keys[i]),
                    "sort keys must order \(strings[i-1]) < \(strings[i])")
        }
    }

    @Test func denseEncodingBoundary() throws {
        // 1_042_489 is the last value in the dense encoding; 1_042_490 is the
        // first in the pair encoding. Ordering must be seamless across it.
        let ordered = ["1042488", "1042489", "1042490", "1042491"]
        for i in 1..<ordered.count {
            #expect(try cmp(ordered[i - 1], ordered[i]) < 0, "\(ordered[i-1]) < \(ordered[i])")
            #expect(try cmp(ordered[i], ordered[i - 1]) > 0)
        }
        try keysOrderedSame(ordered)
    }

    @Test func sevenToEightDigitBoundary() throws {
        // Max 7-digit (pair-encoded, past dense capacity) vs min 8-digit.
        #expect(try cmp("9999999", "10000000") < 0)
        #expect(try cmp("10000000", "9999999") > 0)
        try keysOrderedSame(["9999998", "9999999", "10000000", "10000001"])
    }

    @Test func leadingZerosAreEqual() throws {
        #expect(try cmp("00012", "12") == 0)
        #expect(try cmp("0", "000") == 0)
        #expect(try cmp("a001042490z", "a1042490z") == 0)
    }

    @Test func longDigitRuns() throws {
        // Well past 7 significant digits: pair encoding with multiple CEs.
        #expect(try cmp("12345678901234567890", "12345678901234567891") < 0)
        #expect(try cmp("099999999999999999999", "100000000000000000000") < 0)
        try keysOrderedSame(["99999999999999999999", "100000000000000000000"])
    }

    @Test func trailingZeroPairs() throws {
        // The pair encoding trims trailing 00 pairs; equal numbers with
        // different textual lengths via leading zeros must stay equal.
        #expect(try cmp("1200000000", "01200000000") == 0)
        #expect(try cmp("1200000000", "1200000001") < 0)
    }

    @Test func digitRunsInContext() throws {
        // Runs embedded in text (the Finder file-name case).
        #expect(try cmp("file9.txt", "file10.txt") < 0)
        #expect(try cmp("IMG_20240115.jpg", "IMG_20240116.jpg") < 0)
        #expect(try cmp("v1.9.9", "v1.10.0") < 0)
    }

    @Test func numericSearchStillMatches() throws {
        // Digit runs produce one CE per run: the pattern's run must match
        // the text's run as a unit.
        var opts = numericOpts
        opts.strength = .primary
        #expect(collator.contains(pattern: "42", in: "answer 42 found", options: opts))
        #expect(!collator.contains(pattern: "4", in: "answer 42 found", options: opts),
                "a digit run is one unit — '4' must not match inside '42'")
    }
}
