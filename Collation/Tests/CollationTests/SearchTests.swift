import Testing
@testable import Collation

@Suite("Collation Search")
struct CollationSearchTests {
    let collator = try! RootCollator()

    @Test func exactMatch() {
        let result = collator.search(for: "world", in: "hello world")
        #expect(result != nil)
        #expect("hello world"[result!] == "world")
    }

    @Test func noMatch() {
        let result = collator.search(for: "xyz", in: "hello world")
        #expect(result == nil)
    }

    @Test func matchAtStart() {
        let result = collator.search(for: "hello", in: "hello world")
        #expect(result != nil)
        #expect("hello world"[result!] == "hello")
    }

    @Test func emptyPattern() {
        let result = collator.search(for: "", in: "hello")
        #expect(result != nil)
        #expect(result! == "hello".startIndex..<"hello".startIndex)
    }

    @Test func emptyText() {
        let result = collator.search(for: "x", in: "")
        #expect(result == nil)
    }

    @Test func caseInsensitiveSearch() {
        var opts = CollationOptions()
        opts.strength = .secondary
        let result = collator.search(for: "HELLO", in: "say hello world", options: opts)
        #expect(result != nil)
        #expect("say hello world"[result!] == "hello")
    }

    @Test func accentInsensitiveSearch() {
        var opts = CollationOptions()
        opts.strength = .primary
        let result = collator.search(for: "cafe", in: "the café is open", options: opts)
        #expect(result != nil)
        #expect("the café is open"[result!] == "café")
    }

    @Test func nfdEquivalence() {
        let eAcute = "caf\u{00E9}"
        let ePlusCombining = "caf\u{0065}\u{0301}"
        let result = collator.search(for: eAcute, in: "at the \(ePlusCombining) today")
        #expect(result != nil)
    }

    @Test func containsAPI() {
        #expect(collator.contains(pattern: "world", in: "hello world"))
        #expect(!collator.contains(pattern: "xyz", in: "hello world"))
    }

    @Test func unicodeText() {
        let result = collator.search(for: "日本", in: "東京は日本の首都")
        #expect(result != nil)
        #expect("東京は日本の首都"[result!] == "日本")
    }

    // MARK: - Ignorable skipping

    @Test func zeroWidthSpaceBetween() {
        let text = "a\u{200B}b"
        let result = collator.search(for: "ab", in: text)
        #expect(result != nil, "ZWSP should be ignorable at default strength")
    }

    @Test func softHyphenBetween() {
        let text = "a\u{00AD}b"
        let result = collator.search(for: "ab", in: text)
        #expect(result != nil, "Soft hyphen should be ignorable at default strength")
    }

    @Test func multipleIgnorablesBetween() {
        let text = "a\u{200B}\u{200B}\u{200B}b"
        let result = collator.search(for: "ab", in: text)
        #expect(result != nil, "Multiple ZWSP should be ignorable")
    }

    @Test func accentInTargetAtPrimaryStrength() {
        var opts = CollationOptions()
        opts.strength = .primary
        let result = collator.search(for: "ab", in: "a\u{0301}b", options: opts)
        #expect(result != nil, "Combining accent should be ignorable at primary strength")
    }

    @Test func accentInTargetAtTertiaryStrength() {
        let result = collator.search(for: "ab", in: "a\u{0301}b")
        #expect(result == nil, "Combining accent should NOT be ignorable at tertiary strength")
    }

    @Test func searchAccentedInPlainAtPrimary() {
        var opts = CollationOptions()
        opts.strength = .primary
        let result = collator.search(for: "á", in: "abc", options: opts)
        #expect(result != nil, "á should match a at primary strength")
    }

    @Test func extraAccentInTargetAtSecondary() {
        var opts = CollationOptions()
        opts.strength = .secondary
        let result = collator.search(for: "cafe", in: "the café is here", options: opts)
        #expect(result != nil, "cafe should match café at secondary strength")
    }

    @Test func ignorableInPattern() {
        let result = collator.search(for: "a\u{200B}b", in: "ab")
        #expect(result != nil, "ZWSP in pattern should be ignorable")
    }

    @Test func ignorableInBoth() {
        let result = collator.search(for: "a\u{200B}b", in: "xa\u{00AD}by")
        #expect(result != nil, "Different ignorables in pattern and text should both be skipped")
    }

    @Test func accentInPatternAtPrimary() {
        var opts = CollationOptions()
        opts.strength = .primary
        let result = collator.search(for: "café", in: "at the cafe now", options: opts)
        #expect(result != nil, "Accented pattern should match plain text at primary")
    }

    @Test func matchRangeWithIgnorables() {
        let text = "xa\u{200B}by"
        let result = collator.search(for: "ab", in: text)
        #expect(result != nil)
        if let r = result {
            #expect(text[r] == "a\u{200B}b", "Range should include the ignorable character")
        }
    }

    @Test func punctuationNotIgnoredAtDefault() {
        let result = collator.search(for: "ab", in: "a.b")
        #expect(result == nil, "Punctuation is not ignorable at default (non-shifted) strength")
    }
}
