import Testing
@testable import FoundationInternationalization

/// The restart-safety tables (the latin table below U+0300 and the two-level BMP table above it) against the full check they replace. The latin table is filled by calling that check, but the BMP table is built from the data structures directly, so it is equal only if the build is right: this compares every BMP code point in both numeric modes, for root and for every bundled tailoring (technique log §51).
@Suite struct RestartSafetyTests {
    static let tailorings = [
        "af", "am", "ar", "as", "az", "be", "bg", "bn", "bo", "bs", "cs", "cy", "da", "de-phonebook",
        "el", "en-emoji", "es", "et", "fa", "fi", "fil", "fo", "fr_CA", "fr", "ga", "gl", "gu", "ha",
        "haw", "he", "hi", "hr", "hu", "hy", "id", "ig", "is", "it", "ja", "ka", "kk", "kl", "km", "kn",
        "ko", "kok", "ku", "ky", "lb", "lo", "lt", "lv", "mk", "ml", "mn", "mr", "ms", "mt", "my", "nb",
        "ne", "nl", "nn", "or", "pa", "pl", "ps", "pt", "ro", "ru", "se", "si", "sk", "sl", "sq", "sr",
        "sv", "sw", "ta", "te", "th", "ti", "tk", "to", "tr", "tt", "ug", "uk", "ur", "uz", "vi", "wae",
        "wo", "xh", "yo", "zh-stroke", "zh", "zu",
    ]

    /// The code points where the table disagrees with the full check (empty when they agree).
    private static func mismatches(_ collator: RootCollator) -> [String] {
        let s = collator.restartSafety
        var found: [String] = []
        for c: UInt32 in 0...0xFFFF {
            for numeric in [false, true] {
                let expected = RestartSafety.slowIsUnsafe(
                    c, numeric: numeric, dataUnsafe: s.dataUnsafe, baseUnsafe: s.baseUnsafe,
                    dataTrie: s.dataTrie, baseTrie: s.baseTrie, norm: s.norm)
                if s.isUnsafe(c, numeric: numeric) != expected, found.count < 10 {
                    found.append("U+\(String(c, radix: 16, uppercase: true)) numeric \(numeric): expected \(expected)")
                }
            }
        }
        return found
    }

    @Test func rootTablesMatchTheFullCheck() throws {
        #expect(Self.mismatches(try RootCollator()) == [])
        #expect(Self.mismatches(RootCollator(data: try .rootICU4X(), norm: try .standard())) == [])
    }

    @Test(arguments: tailorings) func tailoringTablesMatchTheFullCheck(name: String) throws {
        #expect(Self.mismatches(try RootCollator(tailoringNamed: name)) == [], "[\(name)]")
    }

    /// The tables must not be trivially all-safe: root has unsafe code points above U+0300 in both modes (combining marks; the Thai consonants that end prefix-vowel contractions; digits with numeric on).
    @Test func rootTableIsNotEmpty() throws {
        let s = try RootCollator().restartSafety
        #expect(s.isUnsafe(0x0301, numeric: false))   // combining acute: lead ccc 230
        #expect(s.isUnsafe(0x0E01, numeric: false))   // Thai ko kai
        #expect(!s.isUnsafe(0x0E50, numeric: false))  // Thai digit zero, numeric off
        #expect(s.isUnsafe(0x0E50, numeric: true))    // ... numeric on
        #expect(!s.isUnsafe(0x4E00, numeric: true))   // CJK ideograph
    }
}
