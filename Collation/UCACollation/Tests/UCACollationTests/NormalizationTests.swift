import Foundation
import Testing
@testable import UCACollation

@Suite struct NormalizationTests {
    static let collator = try! RootCollator()
    var collator: RootCollator { Self.collator }

    /// Differential test of the fused NFD front end against Foundation's
    /// decomposedStringWithCanonicalMapping (NFD), single scalars.
    ///
    /// Ranges are limited to Unicode blocks whose normalization is stable, so
    /// the system's (possibly older) Unicode version agrees with our
    /// Unicode 17 tables.
    @Test func singleScalarsMatchFoundationNFD() throws {
        let ranges: [ClosedRange<UInt32>] = [
            0x20...0x33ff,        // Latin..CJK symbols, incl. Greek, Cyrillic,
                                  // Indic, Tibetan, Jamo, kana
            0xac00...0xacff,      // Hangul syllables (sample)
            0xd770...0xd7a3,      // Hangul syllables (end of block)
            0xf900...0xfaff,      // CJK compatibility ideographs
            0xfb00...0xfb4f,      // ligatures, Hebrew presentation forms
            0x1d100...0x1d1ff,    // musical symbols (supplementary)
            0x2f800...0x2f87f,    // CJK compat supplement (sample)
        ]
        var mismatches = 0
        for range in ranges {
            for v in range {
                guard let scalar = Unicode.Scalar(v) else { continue }
                let s = String(scalar)
                let ours = collator.nfd(s)
                let foundations = s.decomposedStringWithCanonicalMapping
                if ours != foundations {
                    mismatches += 1
                    if mismatches <= 10 {
                        Issue.record("U+\(String(v, radix: 16, uppercase: true)): ours \(Array(ours.unicodeScalars)), Foundation \(Array(foundations.unicodeScalars))")
                    }
                }
            }
        }
        #expect(mismatches == 0)
    }

    /// Same differential over base+marks combinations, exercising canonical
    /// reordering of combining marks (including non-canonical input order).
    @Test func combiningSequencesMatchFoundationNFD() throws {
        let bases = ["a", "e", "o", "s", "d", "q", "α", "ι", "я", "ậ", "ơ", "ự"]
        let marks: [UInt32] = [0x0301, 0x0323, 0x0302, 0x0308, 0x031b, 0x030a]
        var mismatches = 0
        for base in bases {
            for m1 in marks {
                for m2 in marks {
                    var s = base
                    s.unicodeScalars.append(Unicode.Scalar(m1)!)
                    s.unicodeScalars.append(Unicode.Scalar(m2)!)
                    let ours = collator.nfd(s)
                    let foundations = s.decomposedStringWithCanonicalMapping
                    if ours != foundations {
                        mismatches += 1
                        if mismatches <= 10 {
                            Issue.record("\(s.debugDescription): ours \(Array(ours.unicodeScalars)), Foundation \(Array(foundations.unicodeScalars))")
                        }
                    }
                }
            }
        }
        #expect(mismatches == 0)
    }

    @Test func knownDecompositions() throws {
        // Recursive expansion: ạ + circumflex, precomposed, all orders.
        let nfd = collator.nfd("ậ").unicodeScalars.map(\.value)
        #expect(nfd == [0x61, 0x323, 0x302])
        // Hangul arithmetic.
        #expect(collator.nfd("각").unicodeScalars.map(\.value) == [0x1100, 0x1161, 0x11a8])
        // One-way (Å angstrom sign).
        #expect(collator.nfd("\u{212B}").unicodeScalars.map(\.value) == [0x41, 0x30a])
        // Compatibility-only ligature does NOT decompose canonically.
        #expect(collator.nfd("ﬁ").unicodeScalars.map(\.value) == [0xfb01])
        // Tibetan composite vowel: starter-less decomposition to two non-starters.
        #expect(collator.nfd("\u{0F73}").unicodeScalars.map(\.value) == [0x0f71, 0x0f72])
        // Canonical reordering of out-of-order marks (ccc 230 before ccc 220).
        #expect(collator.nfd("a\u{0302}\u{0323}").unicodeScalars.map(\.value) == [0x61, 0x323, 0x302])
    }
}

/// Canonical equivalence at the collator level: all forms of the same text
/// must compare equal, against both the regular (closure) data and the
/// NFD-only ICU4X-variant data.
@Suite struct CanonicalEquivalenceTests {
    static let collators: [(String, RootCollator)] = [
        ("regular", try! RootCollator()),
        ("icu4x", RootCollator(data: try! .rootICU4X(), norm: try! .standard())),
    ]

    static let equivalenceClasses: [[String]] = [
        ["é", "e\u{301}"],
        ["ậ", "a\u{323}\u{302}", "a\u{302}\u{323}", "ạ\u{302}", "â\u{323}"],
        ["가", "\u{1100}\u{1161}"],
        ["각", "\u{1100}\u{1161}\u{11A8}"],
        ["Å", "A\u{30A}", "\u{212B}"],
        ["ΐ", "\u{3B9}\u{308}\u{301}"],
        ["\u{1E0C}\u{307}", "\u{1E0A}\u{323}", "D\u{323}\u{307}", "D\u{307}\u{323}"],
        ["Ṩ", "s\u{323}\u{307}".uppercased(), "S\u{307}\u{323}"],
        ["\u{0F73}", "\u{0F71}\u{0F72}"],
        ["豈", "\u{8C48}"],
        ["\u{1D15E}", "\u{1D157}\u{1D165}"],
        ["ợ", "o\u{31B}\u{323}", "ơ\u{323}", "ọ\u{31B}"],
    ]

    @Test(arguments: [0, 1]) func equivalentFormsCompareEqual(collatorIndex: Int) throws {
        let (name, collator) = Self.collators[collatorIndex]
        // Canonical equivalents are equal at every strength — including
        // identical, whose tiebreaker compares NFD forms.
        for strength in [CollationOptions.Strength.tertiary, .identical] {
            var options = CollationOptions()
            options.strength = strength
            for cls in Self.equivalenceClasses {
                for a in cls {
                    for b in cls {
                        let order = try collator.compare(a, b, options: options)
                        #expect(order == .same, "[\(name)/\(strength)] \(a.debugDescription) vs \(b.debugDescription)")
                    }
                }
            }
        }
    }
}
