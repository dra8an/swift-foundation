import Testing
@testable import UCACollation

@Suite struct PrimaryCompareTests {
    static let collator = try! RootCollator()
    var collator: RootCollator { Self.collator }

    @Test func dataLoads() throws {
        let data = try CollationData.root()
        #expect(data.ce32s.count > 0)
        #expect(data.ces.count > 0)
        #expect(data.jamoCE32sStart >= 0)
        // Single-byte primary lead for numeric collation (0x10 in ICU 79 root data).
        #expect(data.numericPrimary == 0x1000_0000)
    }

    @Test func basicLetterOrder() throws {
        #expect(try collator.compare("a", "b") == .ascending)
        #expect(try collator.compare("b", "a") == .descending)
        #expect(try collator.compare("a", "a") == .same)
        #expect(try collator.compare("abc", "abd") == .ascending)
        #expect(try collator.compare("ab", "b") == .ascending)
    }

    @Test func caseIsPrimaryEqual() throws {
        // Case is a tertiary difference; equal at primary strength.
        #expect(try collator.compare("a", "A") == .same)
        #expect(try collator.compare("HELLO", "hello") == .same)
        // 'Z' shares its primary with 'z', which sorts after 'a'.
        #expect(try collator.compare("Z", "a") == .descending)
    }

    @Test func groupOrder() throws {
        // Root order of major groups: space < punctuation < digits < letters.
        #expect(try collator.compare(" ", "!") == .ascending)
        #expect(try collator.compare("!", "1") == .ascending)
        #expect(try collator.compare("9", "a") == .ascending)
        // No numeric mode: plain digit-by-digit weights.
        #expect(try collator.compare("12", "2") == .ascending)
    }

    @Test func prefixesAndEmpty() throws {
        #expect(try collator.compare("", "") == .same)
        #expect(try collator.compare("", "a") == .ascending)
        #expect(try collator.compare("a", "a ") == .ascending)
    }

    @Test func scriptsAndImplicits() throws {
        // Latin < Greek < Han (OFFSET/implicit primaries) < unassigned (lead byte 0xFE).
        #expect(try collator.compare("z", "α") == .ascending)
        #expect(try collator.compare("α", "一") == .ascending)
        #expect(try collator.compare("一", "\u{0378}") == .ascending)
        // Han characters are ordered among themselves.
        #expect(try collator.compare("一", "丁") != .same)
    }

    @Test func hangul() throws {
        // Hangul syllables decompose to Jamo; syllable order follows code point order
        // in the root for these.
        #expect(try collator.compare("가", "나") == .ascending)
        #expect(try collator.compare("가", "가") == .same)
        #expect(try collator.compare("a", "가") == .ascending)
        // 각 = 가 + trailing consonant: longer Jamo sequence sorts after.
        #expect(try collator.compare("가", "각") == .ascending)
    }

    @Test func controlCharactersArePrimaryIgnorable() throws {
        // U+0001 etc. are primary ignorable; U+0000 maps through the U0000 tag.
        #expect(try collator.compare("a\u{1}b", "ab") == .same)
        #expect(try collator.compare("a\u{0}b", "ab") == .same)
    }

    @Test func expansionsWork() throws {
        // U+00E6 LATIN SMALL LETTER AE expands to two primaries (a, e) in root.
        let primaries = try collator.primaries(of: "æ")
        #expect(primaries.filter { $0 != 0 }.count == 2)
        #expect(try collator.compare("æ", "ae") == .same)
    }
}
