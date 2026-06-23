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
}
