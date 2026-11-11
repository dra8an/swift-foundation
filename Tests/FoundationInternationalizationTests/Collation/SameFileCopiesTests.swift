//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
@testable import FoundationInternationalization

/// RootCollator.swift, CollationCompare.swift and SortKey.swift keep same-file copies of values from other files, so that the `-no-WMO` build reads them as immediates. Each copy must equal its original.
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

    /// The copies of the CE compare (CollationCompare) and of the sort key writer (CollationKeys).
    @Test func compareAndKeyWriterConstantsEqualTheirOriginals() {
        #expect(CollationCompare.noCEPrimary == CollationConstants.noCEPrimary)
        #expect(CollationCompare.noCEWeight16 == CollationConstants.noCEWeight16)
        #expect(CollationCompare.mergeSeparatorPrimary == CollationConstants.mergeSeparatorPrimary)
        #expect(CollationCompare.onlyTertiaryMask == CollationConstants.onlyTertiaryMask)
        #expect(CollationCompare.caseAndTertiaryMask == CollationConstants.caseAndTertiaryMask)
        #expect(CollationCompare.bitAlternateMask == CollationOptions.Bits.alternateMask)
        #expect(CollationCompare.bitUpperFirst == CollationOptions.Bits.upperFirst)
        #expect(CollationCompare.bitCaseFirst == CollationOptions.Bits.caseFirst)
        #expect(CollationCompare.bitCaseFirstAndUpperMask == CollationOptions.Bits.caseFirstAndUpperMask)
        #expect(CollationCompare.bitCaseLevel == CollationOptions.Bits.caseLevel)
        #expect(CollationCompare.bitBackwardSecondary == CollationOptions.Bits.backwardSecondary)
        #expect(CollationCompare.strengthShift == CollationOptions.Bits.strengthShift)
        #expect(CollationCompare.primaryStrength == CollationOptions.Strength.primary.rawValue)
        #expect(CollationCompare.secondaryStrength == CollationOptions.Strength.secondary.rawValue)
        #expect(CollationCompare.tertiaryStrength == CollationOptions.Strength.tertiary.rawValue)
        #expect(CollationKeys.noCEPrimary == CollationConstants.noCEPrimary)
        #expect(CollationKeys.noCEWeight16 == CollationConstants.noCEWeight16)
        #expect(CollationKeys.mergeSeparatorPrimary == CollationConstants.mergeSeparatorPrimary)
        #expect(CollationKeys.onlyTertiaryMask == CollationConstants.onlyTertiaryMask)
        #expect(CollationKeys.caseAndTertiaryMask == CollationConstants.caseAndTertiaryMask)
        #expect(CollationKeys.bitAlternateMask == CollationOptions.Bits.alternateMask)
        #expect(CollationKeys.bitUpperFirst == CollationOptions.Bits.upperFirst)
        #expect(CollationKeys.bitCaseFirst == CollationOptions.Bits.caseFirst)
        #expect(CollationKeys.bitCaseFirstAndUpperMask == CollationOptions.Bits.caseFirstAndUpperMask)
        #expect(CollationKeys.bitCaseLevel == CollationOptions.Bits.caseLevel)
        #expect(CollationKeys.bitBackwardSecondary == CollationOptions.Bits.backwardSecondary)
        #expect(CollationKeys.strengthShift == CollationOptions.Bits.strengthShift)
        #expect(CollationKeys.primaryStrength == CollationOptions.Strength.primary.rawValue)
        #expect(CollationKeys.secondaryStrength == CollationOptions.Strength.secondary.rawValue)
        #expect(CollationKeys.tertiaryStrength == CollationOptions.Strength.tertiary.rawValue)
    }

    /// The copied option helpers over every options word of 16 bits (strength, case, alternate, maxVariable, numeric bits).
    @Test func compareAndKeyWriterHelpersEqualTheOriginals() {
        var mismatches: [Int32] = []
        for word in Int32(0)..<0x10000 {
            let strength = CollationOptions.strength(of: word)
            let mask = CollationOptions.tertiaryMask(of: word)
            let upper = CollationOptions.sortsTertiaryUpperCaseFirst(word)
            if CollationCompare.strength(of: word) != strength || CollationKeys.strength(of: word) != strength
                || CollationCompare.tertiaryMask(of: word) != mask || CollationKeys.tertiaryMask(of: word) != mask
                || CollationCompare.sortsTertiaryUpperCaseFirst(word) != upper || CollationKeys.sortsTertiaryUpperCaseFirst(word) != upper {
                mismatches.append(word)
            }
        }
        #expect(mismatches.isEmpty, "first mismatching words: \(mismatches.prefix(8))")
    }
}
