import Foundation
import Testing
@testable import FoundationInternationalization

/// The two inputs of the NFD front end (technique log §51 (y)): a contiguous native string is read through its pinned UTF-8 bytes (`ScalarSource`), a non-contiguous one — here a lazily bridged `NSString` — through a String iterator. Both must give the same compare results, sort keys and search results, also where the compare restarts after a shared prefix (where the bytes source skips by lead bytes).
@Suite struct ScalarSourceTests {
    static let words = [
        "", "a", "abc", "abd", "café", "cafe", "Straße", "strasse", "e\u{301}cole", "école",
        "กรรเกด", "กรรไกร", "กรมธรรม์", "กรมธรรม์ประกันภัย", "ก่า", "เก", "中文", "中国", "日本語", "カー",
        "/usr/lib/libc.dylib", "/usr/lib/libcrypto.dylib", "x\u{1F600}y", "x\u{1F601}y", "file10", "file2",
        "ภาษาไทย", "ภาษาไทยดี", "ὀδυσσεύς", "ὈΔΥΣΣΕΎΣ", "한국어", "한국인",
    ]

    /// A bridged copy of `s`: an NSString-backed String whose UTF-8 is not contiguous.
    static func bridged(_ s: String) -> String { NSString(string: s) as String }

    @Test func bridgedInputIsNotContiguous() {
        let b = Self.bridged("กรรเกด")
        #expect(b.utf8.withContiguousStorageIfAvailable { _ in true } == nil, "the test needs a non-contiguous string")
    }

    @Test(arguments: ["root", "th", "ja", "sv", "fr_CA"])
    func bothInputsAgree(name: String) throws {
        let collator = name == "root" ? try RootCollator() : try RootCollator(tailoringNamed: name)
        var options = collator.defaultOptions
        for numeric in [false, true] {
            options.numeric = numeric
            for a in Self.words {
                let ba = Self.bridged(a)
                #expect(try collator.sortKey(for: a, options: options) == collator.sortKey(for: ba, options: options), "\(name) sortKey \(a)")
                for b in Self.words {
                    let bb = Self.bridged(b)
                    let native = try collator.compare(a, b, options: options)
                    #expect(try collator.compare(ba, bb, options: options) == native, "\(name) \(a) / \(b)")
                    #expect(try collator.compare(a, bb, options: options) == native, "\(name) \(a) / bridged \(b)")
                }
            }
        }
    }

    /// The scalar offsets of a range, so that ranges into a native and a bridged copy of the same text compare.
    static func offsets(_ r: Range<String.Index>?, in s: String) -> [Int]? {
        r.map { [s.unicodeScalars.distance(from: s.startIndex, to: $0.lowerBound),
                 s.unicodeScalars.distance(from: s.startIndex, to: $0.upperBound)] }
    }

    @Test(arguments: ["root", "th", "ja"])
    func searchAgreesOnBothInputs(name: String) throws {
        let collator = name == "root" ? try RootCollator() : try RootCollator(tailoringNamed: name)
        let texts = Self.words.map { $0 + " " + $0 } + ["the café and the cafe", "กรรเกด กรรไกร", "x/usr/lib/y"]
        let patterns = ["", "a", "cafe", "café", "กรร", "ไก", "lib", "中", "e\u{301}", "ประกัน"]
        var options = collator.defaultOptions
        for strength in [CollationOptions.Strength.primary, .tertiary] {
            options.strength = strength
            for t in texts {
                let bt = Self.bridged(t)
                for p in patterns {
                    let bp = Self.bridged(p)
                    #expect(collator.contains(pattern: bp, in: bt, options: options) == collator.contains(pattern: p, in: t, options: options), "\(name) contains \(p) in \(t)")
                    #expect(Self.offsets(collator.search(for: bp, in: bt, options: options), in: bt) == Self.offsets(collator.search(for: p, in: t, options: options), in: t), "\(name) search \(p) in \(t)")
                    #expect(Self.offsets(collator.searchBackwards(for: bp, in: bt, options: options), in: bt) == Self.offsets(collator.searchBackwards(for: p, in: t, options: options), in: t), "\(name) backwards \(p) in \(t)")
                }
            }
        }
    }
}
