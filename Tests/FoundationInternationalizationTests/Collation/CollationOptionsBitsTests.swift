import Testing
@testable import FoundationInternationalization

/// The compare entry's guard tests the caller's options against the collator's default options by bit pattern (`RootCollator.bits(of:)`). That is sound only if equal patterns mean equal options and different options give different patterns — checked here over every option combination (technique log §51).
@Suite struct CollationOptionsBitsTests {
    static func allCombinations() -> [CollationOptions] {
        var all: [CollationOptions] = []
        for strength in [CollationOptions.Strength.primary, .secondary, .tertiary, .quaternary, .identical] {
            for alternate in [CollationOptions.Alternate.nonIgnorable, .shifted] {
                for maxVariable in [CollationOptions.MaxVariable.space, .punctuation, .symbol, .currency] {
                    for caseFirst in [CollationOptions.CaseFirst.off, .lowerFirst, .upperFirst] {
                        for flags in 0..<8 {
                            var o = CollationOptions()
                            o.strength = strength
                            o.alternate = alternate
                            o.maxVariable = maxVariable
                            o.caseFirst = caseFirst
                            o.caseLevel = flags & 1 != 0
                            o.backwardSecondary = flags & 2 != 0
                            o.numeric = flags & 4 != 0
                            all.append(o)
                        }
                    }
                }
            }
        }
        return all
    }

    @Test func layoutIsSevenBytes() {
        #expect(MemoryLayout<CollationOptions>.size == 7)
        #expect(RootCollator.optionBitsAreExact)
    }

    @Test func patternsAreEqualExactlyWhenOptionsAreEqual() {
        let all = Self.allCombinations()
        #expect(all.count == 960)
        let patterns = all.map(RootCollator.bits(of:))
        #expect(Set(patterns).count == all.count, "two different option sets share a bit pattern")
        // Equal options built separately give equal patterns.
        for o in all {
            var copy = CollationOptions()
            copy.strength = o.strength
            copy.alternate = o.alternate
            copy.maxVariable = o.maxVariable
            copy.caseFirst = o.caseFirst
            copy.caseLevel = o.caseLevel
            copy.backwardSecondary = o.backwardSecondary
            copy.numeric = o.numeric
            #expect(RootCollator.bits(of: copy) == RootCollator.bits(of: o))
        }
        // And the guard's test agrees with the options word, which encodes every field.
        #expect(Set(all.map(\.icuOptions)).count == all.count)
    }

    /// The fast-Latin setup cache is keyed by `CollationFastLatin.primariesKey`, not by the whole options word: one getOptions on the key must give the same primaries as on the word, and the same packed options once the word replaces the key in bits 15..0. Checked for every option combination, on root and on tailorings with script reordering.
    @Test(arguments: ["", "zh", "ja", "ru", "el", "de-phonebook"])
    func fastLatinSetupDependsOnlyOnTheKey(tailoring: String) throws {
        let root = try CollationData.root()
        var data = root
        var reordering: Reordering? = nil
        if !tailoring.isEmpty {
            let t = try CollationData.tailoring(bytes: CollationData.tailoring(named: tailoring))
            if let d = t.data { data = d }
            reordering = t.reordering
        }
        let table = data.fastLatinTable.isEmpty ? root.fastLatinTable : data.fastLatinTable
        let scriptsData = data.scriptStarts.isEmpty ? root : data
        for o in Self.allCombinations() {
            let word = o.icuOptions
            var direct: [UInt16] = []
            let packedDirect = CollationFastLatin.getOptions(
                table: table, scriptsData: scriptsData, reordering: reordering, options: word, primaries: &direct)
            let key = CollationFastLatin.primariesKey(word)
            var viaKey: [UInt16] = []
            let packedKey = CollationFastLatin.getOptions(
                table: table, scriptsData: scriptsData, reordering: reordering, options: key, primaries: &viaKey)
            let packed = packedKey < 0 ? packedKey : (packedKey & ~0xffff) | word
            #expect(packed == packedDirect, "[\(tailoring)] word \(String(word, radix: 16))")
            if packedDirect >= 0 { #expect(viaKey == direct, "[\(tailoring)] word \(String(word, radix: 16))") }
        }
    }
}
