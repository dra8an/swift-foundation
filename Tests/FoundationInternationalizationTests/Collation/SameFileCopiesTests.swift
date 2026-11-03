import Testing
@testable import FoundationInternationalization

/// RootCollator.swift keeps same-file copies of values from other files, so that the `-no-WMO` build reads them as immediates (technique log §51 (as)). Each copy must equal its original.
@Suite struct SameFileCopiesTests {
    @Test func constantsEqualTheirOriginals() {
        #expect(RootCollator.fastLatinBailOut == CollationFastLatin.bailOutResult)
        #expect(RootCollator.latinMaxLead == CollationFastLatin.latinMaxUTF8Lead)
        #expect(RootCollator.prefixDependentResult == CollationCompare.prefixDependent)
    }

    /// Every options word that differs in the bits that primariesKey reads (and in some it ignores).
    @Test func primariesKeyEqualsTheOriginal() {
        for word in Int32(0)..<0x400 {
            #expect(RootCollator.fastLatinPrimariesKey(word) == CollationFastLatin.primariesKey(word), "word \(word)")
        }
        for options in [CollationOptions(), CollationOptions(icuOptionsWord: 0x2), CollationOptions(icuOptionsWord: 0x3c)] {
            #expect(RootCollator.fastLatinPrimariesKey(options.icuOptions) == CollationFastLatin.primariesKey(options.icuOptions))
        }
    }
}
