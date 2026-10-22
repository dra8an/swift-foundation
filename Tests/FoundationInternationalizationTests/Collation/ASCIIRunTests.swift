import Foundation
import Testing
@testable import FoundationInternationalization

/// The bulk ASCII run of `CEIterator.collectAll` (technique log §51 (t); the Thai strings also cover the rejected Thai run of §51 (u)) against the one-character-per-call path it shortcuts: for every input, collator and numeric mode, both must produce the same CEs and leave the same scalar count and decomposition flag. The run reads the source directly and hands the first scalar it cannot use back to the NFD front end, so the risky inputs are the boundaries: an ASCII run followed by combining marks, contraction starters, digits, prefix contexts, other scripts, and the end of the string.
@Suite struct ASCIIRunTests {
    static let built: [String] = [
        "", "a", "abc", "hello world", "a\u{0301}", "abc\u{0301}def", "e\u{0301}\u{0300}x",
        "cafe\u{0301}", "café latte", "Ålesund", "straße", "chata", "chleba", "llama", "calle", "dzwon",
        "dž", "lj", "nj", "ch", "cH", "CH", "abc123", "x9y", "12345", "0042a", "a1b2c3",
        "aー", "カー", "ab\u{30FC}", "abc\u{0E40}\u{0E01}", "\u{0E40}\u{0E01}abc", "abc中文def",
        "a\u{00B7}l", "l\u{00B7}l", "o\u{0308}", "abc\u{0308}", "aa", "aaa", "AaAa", "/usr/lib/libc.dylib",
        "x\u{1F600}y", "tab\there", "line\nbreak", "end ", " lead", "a\u{200B}b", "a\u{00AD}b",
        // Thai: inert consonants and vowels go through the run; tone marks, sara u/uu and phinthu have a
        // non-zero ccc and go back (NFD may reorder them); prefix vowels and digits are 0 in the table.
        "กรมวัง", "กรมศักดิ์", "ก่า", "กุ", "กู", "กฺ", "เก", "แกะ", "ไก่", "โก๋", "๑๒๓", "ก๑", "กั้น", "นํ้า",
        "น้ำ", "ฤๅ", "ๆ", "ก\u{0E48}\u{0E38}", "ก\u{0E38}\u{0E48}", "abcก่", "ก่abc", "กabcข", "ab\u{0E48}",
        "\u{0E48}ก", "กข\u{0301}", "ภาษาไทย", "ข้าวผัด", "สวัสดี",
    ]

    static func strings() throws -> [String] {
        let golden = Bundle.module.url(forResource: "Golden", withExtension: nil)!
        var all = built
        for file in ["corpus.txt", "fuzz-corpus.txt"] {
            all += try String(contentsOf: golden.appendingPathComponent(file), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        return all
    }

    private static func iterator(_ c: RootCollator, _ s: String, numeric: Bool) -> CEIterator {
        CEIterator(
            data: c.data, base: c.base, norm: c.norm, numeric: numeric, scalars: s.unicodeScalars,
            simpleCEs: c.simpleCEs, thaiCEs: c.thaiCEs,
            simpleCEsWithDigits: c.simpleCEsWithDigits, thaiCEsWithDigits: c.thaiCEsWithDigits)
    }

    /// The mismatching inputs (empty when the two paths agree).
    static func mismatches(_ collator: RootCollator, _ strings: [String]) throws -> [String] {
        var found: [String] = []
        for s in strings {
            for numeric in [false, true] {
                var bulk = iterator(collator, s, numeric: numeric)
                try bulk.collectAll()
                var single = iterator(collator, s, numeric: numeric)
                while try single.appendMore() {}
                if bulk.ces.toArray() != single.ces.toArray()
                    || bulk.scalarsConsumed != single.scalarsConsumed
                    || bulk.sawDecomposition != single.sawDecomposition {
                    found.append("numeric=\(numeric) [\(s.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))]")
                }
            }
        }
        return found
    }

    @Test func rootAgreesWithTheSingleCharacterPath() throws {
        let found = try Self.mismatches(try RootCollator(), try Self.strings())
        #expect(found.isEmpty, "\(found.count) mismatches, first: \(found.prefix(5))")
    }

    @Test(arguments: RestartSafetyTests.tailorings)
    func tailoringAgreesWithTheSingleCharacterPath(name: String) throws {
        let found = try Self.mismatches(try RootCollator(tailoringNamed: name), Self.built)
        #expect(found.isEmpty, "\(name): \(found.count) mismatches, first: \(found.prefix(5))")
    }
}
