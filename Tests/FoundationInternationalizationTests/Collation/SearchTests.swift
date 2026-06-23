import Testing
@testable import FoundationInternationalization

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

    // MARK: - Backwards search

    @Test func backwardsFindsLast() {
        let text = "abc abc abc"
        let first = collator.search(for: "abc", in: text)
        let last = collator.searchBackwards(for: "abc", in: text)
        #expect(first != nil)
        #expect(last != nil)
        #expect(first!.lowerBound < last!.lowerBound, "Backwards should find last occurrence")
        #expect(text[last!] == "abc")
    }

    @Test func backwardsSingleOccurrence() {
        let text = "hello world"
        let forward = collator.search(for: "world", in: text)
        let backward = collator.searchBackwards(for: "world", in: text)
        #expect(forward == backward, "Single occurrence: forward and backward should match")
    }

    @Test func backwardsNoMatch() {
        let result = collator.searchBackwards(for: "xyz", in: "hello world")
        #expect(result == nil)
    }

    @Test func backwardsCaseInsensitive() {
        var opts = CollationOptions()
        opts.strength = .secondary
        let text = "Hello hello HELLO"
        let last = collator.searchBackwards(for: "hello", in: text, options: opts)
        #expect(last != nil)
        #expect(text[last!] == "HELLO")
    }

    @Test func backwardsAccentInsensitive() {
        var opts = CollationOptions()
        opts.strength = .primary
        let text = "cafe café CAFÉ"
        let last = collator.searchBackwards(for: "cafe", in: text, options: opts)
        #expect(last != nil)
        #expect(text[last!] == "CAFÉ")
    }

    @Test func backwardsEmpty() {
        let result = collator.searchBackwards(for: "", in: "hello")
        #expect(result != nil)
    }

    // MARK: - Cross-starter contractions

    @Test func koreanSyllableSearch() {
        // 가 (U+AC00) = Jamo L ㄱ (U+1100) + V ㅏ (U+1161), composed Hangul
        // Search for the syllable in text containing the composed form
        let result = collator.search(for: "가", in: "나는 가수입니다")
        #expect(result != nil, "Should find composed Hangul syllable")
    }

    @Test func koreanJamoSequenceSearch() {
        // Search for decomposed Jamo sequence
        let decomposed = "\u{1100}\u{1161}"  // ㄱ + ㅏ = 가
        let result = collator.search(for: decomposed, in: "나는 가수입니다")
        #expect(result != nil, "Should find decomposed Jamo matching composed Hangul")
    }

    @Test func koreanSearchInDecomposed() {
        // Search for composed syllable in decomposed text
        let decomposedText = "\u{1102}\u{1161}\u{1102}\u{1173}\u{11AB} \u{1100}\u{1161}\u{1109}\u{116E}"
        let result = collator.search(for: "가", in: decomposedText)
        #expect(result != nil, "Should find composed syllable in decomposed Jamo text")
    }

    @Test func lithuanianChContraction() throws {
        // Lithuanian has ch contraction — test with lt tailoring
        let lt = try RootCollator(tailoringNamed: "lt")
        let result = lt.search(for: "ch", in: "archery")
        #expect(result != nil, "Should find 'ch' in text with lt tailoring")
    }

    // MARK: - Czech locale (cs) — ch is a single letter after h

    @Test func czechChSearch() throws {
        let cs = try RootCollator(tailoringNamed: "cs")
        let text = "pochod"
        let result = cs.search(for: "ch", in: text)
        #expect(result != nil, "Should find 'ch' in Czech text")
        if let r = result {
            let matched = String(text[r])
            let startOff = text.distance(from: text.startIndex, to: r.lowerBound)
            let endOff = text.distance(from: text.startIndex, to: r.upperBound)
            #expect(matched == "ch", "Expected 'ch' but got '\(matched)' at [\(startOff)..\(endOff)]")
        }
    }

    @Test func czechChCaseInsensitive() throws {
        let cs = try RootCollator(tailoringNamed: "cs")
        var opts = CollationOptions()
        opts.strength = .secondary
        let result = cs.search(for: "CH", in: "pochod", options: opts)
        #expect(result != nil, "Case-insensitive 'CH' should match 'ch' in Czech")
    }

    @Test func czechChMultipleOccurrences() throws {
        let cs = try RootCollator(tailoringNamed: "cs")
        let text = "chlapec v chrámu"
        let result = cs.search(for: "chrám", in: text)
        #expect(result != nil, "Should find 'chrám' after first 'ch'")
    }

    @Test func czechRWithCaron() throws {
        let cs = try RootCollator(tailoringNamed: "cs")
        let result = cs.search(for: "ř", in: "Dvořák")
        #expect(result != nil, "Should find ř in Czech text")
    }

    @Test func czechSWithCaron() throws {
        let cs = try RootCollator(tailoringNamed: "cs")
        let result = cs.search(for: "š", in: "šest škol")
        #expect(result != nil, "Should find š in Czech text")
        if let r = result {
            #expect("šest škol"[r] == "š")
        }
    }

    @Test func czechCaronVsPlainNotEqualAtTertiary() throws {
        let cs = try RootCollator(tailoringNamed: "cs")
        // š and s are different letters in Czech — search in a word without plain s
        let result = cs.search(for: "s", in: "šílenství")
        // "šílenství" has 's' at position 5 (š-í-l-e-n-s-t-v-í), so this WILL match
        // Instead test that š itself doesn't match s
        let result2 = cs.search(for: "s", in: "ší")
        #expect(result2 == nil, "š and s are different letters in Czech — 's' should NOT match 'š'")
    }

    // MARK: - Spanish locale (es) — ñ and digraphs

    @Test func spanishSearchForCh() throws {
        let es = try RootCollator(tailoringNamed: "es")
        let text = "muchacho"
        let result = es.search(for: "ch", in: text)
        #expect(result != nil, "Should find 'ch' in Spanish text")
        if let r = result {
            #expect(text[r] == "ch")
        }
    }

    @Test func spanishSearchForLl() throws {
        let es = try RootCollator(tailoringNamed: "es")
        let text = "calle llena"
        let result = es.search(for: "ll", in: text)
        #expect(result != nil, "Should find 'll' in Spanish text")
    }

    @Test func spanishSearchForEne() throws {
        let es = try RootCollator(tailoringNamed: "es")
        let text = "el niño juega mañana"
        let result = es.search(for: "niño", in: text)
        #expect(result != nil, "Should find 'niño' in Spanish text")
        if let r = result {
            let matched = String(text[r])
            let startOff = text.distance(from: text.startIndex, to: r.lowerBound)
            let endOff = text.distance(from: text.startIndex, to: r.upperBound)
            #expect(matched == "niño", "Expected 'niño' but got '\(matched)' at [\(startOff)..\(endOff)]")
        }
    }

    @Test func spanishEneVsN() throws {
        let es = try RootCollator(tailoringNamed: "es")
        // ñ and n are different letters in Spanish
        let result = es.search(for: "ano", in: "el año nuevo")
        #expect(result == nil, "ñ and n are different letters — 'ano' should NOT match 'año'")
    }

    @Test func spanishEneCaseInsensitive() throws {
        let es = try RootCollator(tailoringNamed: "es")
        var opts = CollationOptions()
        opts.strength = .secondary
        let result = es.search(for: "NIÑO", in: "el niño", options: opts)
        #expect(result != nil, "Case-insensitive search for NIÑO should match niño")
    }

    @Test func spanishChInMiddleOfWord() throws {
        let es = try RootCollator(tailoringNamed: "es")
        let text = "derecho"
        let result = es.search(for: "echo", in: text)
        #expect(result != nil, "Should find 'echo' spanning the 'ch' in 'derecho'")
        if let r = result {
            #expect(text[r] == "echo")
        }
    }

    @Test func spanishMultipleChOccurrences() throws {
        let es = try RootCollator(tailoringNamed: "es")
        let text = "chocolate y churros con leche"
        let result = es.search(for: "leche", in: text)
        #expect(result != nil, "Should find 'leche' after multiple 'ch' occurrences")
        if let r = result {
            #expect(text[r] == "leche")
        }
    }
}
