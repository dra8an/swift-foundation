// Fast Latin comparison: a faithful port of CollationFastLatin
// (i18n/collationfastlatin.{h,cpp}, format version 2).
//
// The data files carry a precompiled table of 16-bit "mini CEs" for
// U+0000..U+017F plus general punctuation U+2000..U+203F, built by ICU's
// CollationFastLatinBuilder from the same collation data we read. compare()
// runs the full multi-level comparison directly on those packed words — no
// NFD front end, no CE expansion — and returns bailOutResult for anything it
// cannot prove correct (unsupported characters or mappings, digits under
// numeric collation, secondary differences under backwards-secondary), in
// which case the caller falls through to the regular pipeline.
//
// Like ICU, the scalar streams are walked once per level; the strings are
// known to be well-formed and fully supported after the primary level, which
// vets every character first.

enum CollationFastLatin {
    /// Fast Latin format version; data with any other version is ignored.
    static let version: UInt16 = 2

    static let latinMax: UInt32 = 0x17f
    static let latinLimit = Int(latinMax) + 1
    /// UTF-8 lead byte of LATIN_MAX: 0x00..0xc5 leads are fast-path eligible.
    static let latinMaxUTF8Lead: UInt8 = 0xc5
    static let punctStart: UInt32 = 0x2000
    static let punctLimit: UInt32 = 0x2040
    static let numFastChars = latinLimit + Int(punctLimit - punctStart)

    static let shortPrimaryMask: UInt32 = 0xfc00      // bits 15..10
    static let indexMask: UInt32 = 0x3ff              // bits 9..0 for expansions & contractions
    static let secondaryMask: UInt32 = 0x3e0          // bits 9..5
    static let caseMask: UInt32 = 0x18                // bits 4..3
    static let longPrimaryMask: UInt32 = 0xfff8       // bits 15..3
    static let tertiaryMask: UInt32 = 7               // bits 2..0
    static let caseAndTertiaryMask = caseMask | tertiaryMask

    static let twoShortPrimariesMask = (shortPrimaryMask << 16) | shortPrimaryMask
    static let twoLongPrimariesMask = (longPrimaryMask << 16) | longPrimaryMask
    static let twoSecondariesMask = (secondaryMask << 16) | secondaryMask
    static let twoCasesMask = (caseMask << 16) | caseMask
    static let twoTertiariesMask = (tertiaryMask << 16) | tertiaryMask

    static let contraction: UInt32 = 0x400
    static let expansion: UInt32 = 0x800
    static let minLong: UInt32 = 0xc00
    static let minShort: UInt32 = 0x1000

    // Secondary weight ladder: 5 before-common (00..80), common (A0),
    // 6 after-common (C0..160), 20 high (180..3E0), all in steps of 0x20.
    static let commonSec: UInt32 = 0xa0
    static let minSecHigh: UInt32 = 0x180  // MAX_SEC_AFTER + SEC_INC
    static let secOffset: UInt32 = 0x20
    static let commonSecPlusOffset = commonSec + secOffset
    static let twoSecOffsets = (secOffset << 16) | secOffset
    static let twoCommonSecPlusOffset = (commonSecPlusOffset << 16) | commonSecPlusOffset

    static let lowerCase: UInt32 = 8
    static let twoLowerCases = (lowerCase << 16) | lowerCase

    static let terOffset = secOffset
    static let commonTerPlusOffset = terOffset  // COMMON_TER (0) + TER_OFFSET
    static let twoTerOffsets = (terOffset << 16) | terOffset
    static let twoCommonTerPlusOffset = (commonTerPlusOffset << 16) | commonTerPlusOffset

    static let mergeWeight: UInt32 = 3
    static let eos: UInt32 = 2
    static let bailOut: UInt32 = 1

    static let contrCharMask: UInt32 = 0x1ff
    static let contrLengthShift: UInt32 = 9

    /// Comparison result meaning "use the regular comparison".
    static let bailOutResult: Int32 = -2
    /// Result meaning "eligible, but the per-options setup is not cached
    /// yet": the caller computes it and retries (once per options change).
    static let needsSetupResult: Int32 = -3

    /// One side of the comparison: a scalar stream with one scalar of
    /// lookahead (always primed; nil = end of string). Levels restart by
    /// copying the original side, which is a trivial struct copy.
    struct Side {
        var next: UInt32?
        var rest: String.UnicodeScalarView.Iterator

        /// The current scalar, priming the next one; nil at the end.
        @inline(__always)
        mutating func pop() -> UInt32? {
            guard let c = next else { return nil }
            next = rest.next()?.value
            return c
        }
    }

    /// Computes the options value for compare() and fills the precomputed
    /// primary weights (LATIN_LIMIT entries). Returns -1 if the fast path is
    /// not supported for this data and these options.
    /// (CollationFastLatin::getOptions.)
    static func getOptions(
        table: UnsafeBufferPointer<UInt16>, scriptsData: CollationData,
        reordering: Reordering?, options: Int32, primaries: inout [UInt16]
    ) -> Int32 {
        if table.isEmpty { return -1 }
        if primaries.count != latinLimit {
            primaries = [UInt16](repeating: 0, count: latinLimit)
        }

        let miniVarTop: UInt32
        if (options & CollationOptions.Bits.alternateMask) == 0 {
            // No mini primaries are variable, set a variableTop just below
            // the lowest long mini primary.
            miniVarTop = minLong - 1
        } else {
            let headerLength = Int(table[0] & 0xff)
            let i = 1 + Int((options >> CollationOptions.Bits.maxVariableShift) & 7)
            if i >= headerLength {
                return -1  // variableTop >= digits, should not occur
            }
            miniVarTop = UInt32(table[i])
        }

        var digitsAreReordered = false
        if let reordering {
            var prevStart: UInt32 = 0
            var beforeDigitStart: UInt32 = 0
            var digitStart: UInt32 = 0
            var afterDigitStart: UInt32 = 0
            let reorderCodeDigit = CollationData.reorderCodeFirst + 4  // UCOL_REORDER_CODE_DIGIT
            for group in CollationData.reorderCodeFirst..<(CollationData.reorderCodeFirst + 8) {
                var start = scriptsData.firstPrimaryForGroup(group)
                start = reordering.reorder(start)
                if group == reorderCodeDigit {
                    beforeDigitStart = prevStart
                    digitStart = start
                } else if start != 0 {
                    if start < prevStart {
                        // The permutation affects the groups up to Latin.
                        return -1
                    }
                    // In the future, there might be a special group between
                    // digits & Latin.
                    if digitStart != 0 && afterDigitStart == 0 && prevStart == beforeDigitStart {
                        afterDigitStart = start
                    }
                    prevStart = start
                }
            }
            var latinStart = scriptsData.firstPrimaryForGroup(25)  // USCRIPT_LATIN
            latinStart = reordering.reorder(latinStart)
            if latinStart < prevStart {
                return -1
            }
            if afterDigitStart == 0 {
                afterDigitStart = latinStart
            }
            if !(beforeDigitStart < digitStart && digitStart < afterDigitStart) {
                digitsAreReordered = true
            }
        }

        let base = Int(table[0] & 0xff)  // skip the header
        for c in 0..<latinLimit {
            var p = UInt32(table[base + c])
            if p >= minShort {
                p &= shortPrimaryMask
            } else if p > miniVarTop {
                p &= longPrimaryMask
            } else {
                p = 0
            }
            primaries[c] = UInt16(truncatingIfNeeded: p)
        }
        if digitsAreReordered || (options & CollationOptions.Bits.numeric) != 0 {
            // Bail out for digits.
            for c in 0x30...0x39 { primaries[c] = 0 }
        }

        // Shift the miniVarTop above other options.
        return (Int32(bitPattern: miniVarTop << 16)) | options
    }

    /// Compares the two scalar streams on the mini-CE table. Returns -1/0/1,
    /// or bailOutResult if the regular comparison must be used.
    /// (CollationFastLatin::compareUTF16, over scalars: every supported
    /// character is a single BMP code unit, and everything else bails out,
    /// so scalar order equals code unit order here.)
    static func compare(
        table fullTable: UnsafeBufferPointer<UInt16>, primaries: [UInt16], options optionsIn: Int32,
        left: Side, right: Side
    ) -> Int32 {
        assert((fullTable[0] >> 8) == version)
        let table = UnsafeBufferPointer(rebasing: fullTable[Int(fullTable[0] & 0xff)...])
        let variableTop = UInt32(bitPattern: optionsIn) >> 16  // see getOptions()
        let options = optionsIn & 0xffff  // needed for strength(of:) to work

        // Check for supported characters, fetch mini CEs, and compare
        // primaries. A pair holds the current mini CE in the lower 16 bits
        // and the next one (if any) in the upper 16 bits.
        var l = left
        var r = right
        var leftPair: UInt32 = 0
        var rightPair: UInt32 = 0
        while true {
            // We fetch CEs until we get a non-ignorable primary or reach the end.
            while leftPair == 0 {
                guard let c = l.pop() else {
                    leftPair = eos
                    break
                }
                if c <= latinMax {
                    leftPair = UInt32(primaries[Int(c)])
                    if leftPair != 0 { break }
                    if c <= 0x39 && c >= 0x30 && (options & CollationOptions.Bits.numeric) != 0 {
                        return bailOutResult
                    }
                    leftPair = UInt32(table[Int(c)])
                } else if punctStart <= c && c < punctLimit {
                    leftPair = UInt32(table[Int(c - punctStart) + latinLimit])
                } else {
                    leftPair = lookup(table, c)
                }
                if leftPair >= minShort {
                    leftPair &= shortPrimaryMask
                    break
                } else if leftPair > variableTop {
                    leftPair &= longPrimaryMask
                    break
                } else {
                    leftPair = nextPair(table, c, leftPair, &l)
                    if leftPair == bailOut { return bailOutResult }
                    leftPair = getPrimaries(variableTop, leftPair)
                }
            }

            while rightPair == 0 {
                guard let c = r.pop() else {
                    rightPair = eos
                    break
                }
                if c <= latinMax {
                    rightPair = UInt32(primaries[Int(c)])
                    if rightPair != 0 { break }
                    if c <= 0x39 && c >= 0x30 && (options & CollationOptions.Bits.numeric) != 0 {
                        return bailOutResult
                    }
                    rightPair = UInt32(table[Int(c)])
                } else if punctStart <= c && c < punctLimit {
                    rightPair = UInt32(table[Int(c - punctStart) + latinLimit])
                } else {
                    rightPair = lookup(table, c)
                }
                if rightPair >= minShort {
                    rightPair &= shortPrimaryMask
                    break
                } else if rightPair > variableTop {
                    rightPair &= longPrimaryMask
                    break
                } else {
                    rightPair = nextPair(table, c, rightPair, &r)
                    if rightPair == bailOut { return bailOutResult }
                    rightPair = getPrimaries(variableTop, rightPair)
                }
            }

            if leftPair == rightPair {
                if leftPair == eos { break }
                leftPair = 0
                rightPair = 0
                continue
            }
            let leftPrimary = leftPair & 0xffff
            let rightPrimary = rightPair & 0xffff
            if leftPrimary != rightPrimary {
                return leftPrimary < rightPrimary ? -1 : 1
            }
            if leftPair == eos { break }
            leftPair >>= 16
            rightPair >>= 16
        }

        // In the following, we need to re-fetch each character because we
        // did not buffer the CEs, but we know that the string is well-formed
        // and only contains supported characters and mappings.

        // We might skip the secondary level but continue with the case level
        // which is turned on separately.
        if CollationOptions.strength(of: options) >= CollationOptions.Strength.secondary.rawValue {
            l = left
            r = right
            leftPair = 0
            rightPair = 0
            while true {
                while leftPair == 0 {
                    guard let c = l.pop() else {
                        leftPair = eos
                        break
                    }
                    if c <= latinMax {
                        leftPair = UInt32(table[Int(c)])
                    } else if punctStart <= c && c < punctLimit {
                        leftPair = UInt32(table[Int(c - punctStart) + latinLimit])
                    } else {
                        leftPair = lookup(table, c)
                    }
                    if leftPair >= minShort {
                        leftPair = getSecondariesFromOneShortCE(leftPair)
                        break
                    } else if leftPair > variableTop {
                        leftPair = commonSecPlusOffset
                        break
                    } else {
                        leftPair = nextPair(table, c, leftPair, &l)
                        leftPair = getSecondaries(variableTop, leftPair)
                    }
                }

                while rightPair == 0 {
                    guard let c = r.pop() else {
                        rightPair = eos
                        break
                    }
                    if c <= latinMax {
                        rightPair = UInt32(table[Int(c)])
                    } else if punctStart <= c && c < punctLimit {
                        rightPair = UInt32(table[Int(c - punctStart) + latinLimit])
                    } else {
                        rightPair = lookup(table, c)
                    }
                    if rightPair >= minShort {
                        rightPair = getSecondariesFromOneShortCE(rightPair)
                        break
                    } else if rightPair > variableTop {
                        rightPair = commonSecPlusOffset
                        break
                    } else {
                        rightPair = nextPair(table, c, rightPair, &r)
                        rightPair = getSecondaries(variableTop, rightPair)
                    }
                }

                if leftPair == rightPair {
                    if leftPair == eos { break }
                    leftPair = 0
                    rightPair = 0
                    continue
                }
                let leftSecondary = leftPair & 0xffff
                let rightSecondary = rightPair & 0xffff
                if leftSecondary != rightSecondary {
                    if (options & CollationOptions.Bits.backwardSecondary) != 0 {
                        // Full support for backwards secondary requires
                        // backwards contraction matching and moving
                        // backwards between merge separators.
                        return bailOutResult
                    }
                    return leftSecondary < rightSecondary ? -1 : 1
                }
                if leftPair == eos { break }
                leftPair >>= 16
                rightPair >>= 16
            }
        }

        if (options & CollationOptions.Bits.caseLevel) != 0 {
            let strengthIsPrimary =
                CollationOptions.strength(of: options) == CollationOptions.Strength.primary.rawValue
            l = left
            r = right
            leftPair = 0
            rightPair = 0
            while true {
                while leftPair == 0 {
                    guard let c = l.pop() else {
                        leftPair = eos
                        break
                    }
                    leftPair = c <= latinMax ? UInt32(table[Int(c)]) : lookup(table, c)
                    if leftPair < minLong {
                        leftPair = nextPair(table, c, leftPair, &l)
                    }
                    leftPair = getCases(variableTop, strengthIsPrimary, leftPair)
                }

                while rightPair == 0 {
                    guard let c = r.pop() else {
                        rightPair = eos
                        break
                    }
                    rightPair = c <= latinMax ? UInt32(table[Int(c)]) : lookup(table, c)
                    if rightPair < minLong {
                        rightPair = nextPair(table, c, rightPair, &r)
                    }
                    rightPair = getCases(variableTop, strengthIsPrimary, rightPair)
                }

                if leftPair == rightPair {
                    if leftPair == eos { break }
                    leftPair = 0
                    rightPair = 0
                    continue
                }
                let leftCase = leftPair & 0xffff
                let rightCase = rightPair & 0xffff
                if leftCase != rightCase {
                    if (options & CollationOptions.Bits.upperFirst) == 0 {
                        return leftCase < rightCase ? -1 : 1
                    } else {
                        return leftCase < rightCase ? 1 : -1
                    }
                }
                if leftPair == eos { break }
                leftPair >>= 16
                rightPair >>= 16
            }
        }
        if CollationOptions.strength(of: options) <= CollationOptions.Strength.secondary.rawValue {
            return 0
        }

        // Remove the case bits from the tertiary weight when caseLevel is on
        // or caseFirst is off.
        let withCaseBits = CollationOptions.isTertiaryWithCaseBits(options)

        l = left
        r = right
        leftPair = 0
        rightPair = 0
        while true {
            while leftPair == 0 {
                guard let c = l.pop() else {
                    leftPair = eos
                    break
                }
                leftPair = c <= latinMax ? UInt32(table[Int(c)]) : lookup(table, c)
                if leftPair < minLong {
                    leftPair = nextPair(table, c, leftPair, &l)
                }
                leftPair = getTertiaries(variableTop, withCaseBits, leftPair)
            }

            while rightPair == 0 {
                guard let c = r.pop() else {
                    rightPair = eos
                    break
                }
                rightPair = c <= latinMax ? UInt32(table[Int(c)]) : lookup(table, c)
                if rightPair < minLong {
                    rightPair = nextPair(table, c, rightPair, &r)
                }
                rightPair = getTertiaries(variableTop, withCaseBits, rightPair)
            }

            if leftPair == rightPair {
                if leftPair == eos { break }
                leftPair = 0
                rightPair = 0
                continue
            }
            var leftTertiary = leftPair & 0xffff
            var rightTertiary = rightPair & 0xffff
            if leftTertiary != rightTertiary {
                if CollationOptions.sortsTertiaryUpperCaseFirst(options) {
                    // Pass through EOS and MERGE_WEIGHT and keep real
                    // tertiary weights larger than the MERGE_WEIGHT.
                    // Tertiary CEs (secondary ignorables) are not supported
                    // in fast Latin.
                    if leftTertiary > mergeWeight {
                        leftTertiary ^= caseMask
                    }
                    if rightTertiary > mergeWeight {
                        rightTertiary ^= caseMask
                    }
                }
                return leftTertiary < rightTertiary ? -1 : 1
            }
            if leftPair == eos { break }
            leftPair >>= 16
            rightPair >>= 16
        }
        if CollationOptions.strength(of: options) <= CollationOptions.Strength.tertiary.rawValue {
            return 0
        }

        l = left
        r = right
        leftPair = 0
        rightPair = 0
        while true {
            while leftPair == 0 {
                guard let c = l.pop() else {
                    leftPair = eos
                    break
                }
                leftPair = c <= latinMax ? UInt32(table[Int(c)]) : lookup(table, c)
                if leftPair < minLong {
                    leftPair = nextPair(table, c, leftPair, &l)
                }
                leftPair = getQuaternaries(variableTop, leftPair)
            }

            while rightPair == 0 {
                guard let c = r.pop() else {
                    rightPair = eos
                    break
                }
                rightPair = c <= latinMax ? UInt32(table[Int(c)]) : lookup(table, c)
                if rightPair < minLong {
                    rightPair = nextPair(table, c, rightPair, &r)
                }
                rightPair = getQuaternaries(variableTop, rightPair)
            }

            if leftPair == rightPair {
                if leftPair == eos { break }
                leftPair = 0
                rightPair = 0
                continue
            }
            let leftQuaternary = leftPair & 0xffff
            let rightQuaternary = rightPair & 0xffff
            if leftQuaternary != rightQuaternary {
                return leftQuaternary < rightQuaternary ? -1 : 1
            }
            if leftPair == eos { break }
            leftPair >>= 16
            rightPair >>= 16
        }
        return 0
    }

    /// Compares two well-formed UTF-8 byte streams on the mini-CE table.
    /// Returns -1/0/1, or bailOutResult if the regular comparison must be
    /// used. The byte variant reads characters as raw bytes — ASCII is one
    /// load, U+0080..U+017F assemble from a 0xC2..0xC5 lead + trail — which
    /// is what makes this the fastest path.
    /// (CollationFastLatin::compareUTF8; kept in sync with compare() above,
    /// like ICU keeps compareUTF16 and compareUTF8 in sync.)
    static func compareUTF8(
        table fullTable: UnsafeBufferPointer<UInt16>, primaries: UnsafeBufferPointer<UInt16>, options optionsIn: Int32,
        left: UnsafeBufferPointer<UInt8>, leftStart: Int,
        right: UnsafeBufferPointer<UInt8>, rightStart: Int
    ) -> Int32 {
        assert((fullTable[0] >> 8) == version)
        let table = UnsafeBufferPointer(rebasing: fullTable[Int(fullTable[0] & 0xff)...])
        let variableTop = UInt32(bitPattern: optionsIn) >> 16  // see getOptions()
        let options = optionsIn & 0xffff  // needed for strength(of:) to work

        let leftLength = left.count
        let rightLength = right.count

        // Check for supported characters, fetch mini CEs, and compare
        // primaries. There is no need to assemble code points beyond the
        // two-byte Latin range; nextPairUTF8 reads the bytes it needs.
        var leftIndex = leftStart
        var rightIndex = rightStart
        var leftPair: UInt32 = 0
        var rightPair: UInt32 = 0
        while true {
            while leftPair == 0 {
                if leftIndex == leftLength {
                    leftPair = eos
                    break
                }
                var c = UInt32(left[leftIndex])
                leftIndex += 1
                if c <= 0x7f {
                    leftPair = UInt32(primaries[Int(c)])
                    if leftPair != 0 { break }
                    if c <= 0x39 && c >= 0x30 && (options & CollationOptions.Bits.numeric) != 0 {
                        return bailOutResult
                    }
                    leftPair = UInt32(table[Int(c)])
                } else if c <= UInt32(latinMaxUTF8Lead) && 0xc2 <= c && leftIndex != leftLength,
                          case let t = left[leftIndex], 0x80 <= t && t <= 0xbf {
                    leftIndex += 1
                    c = ((c - 0xc2) << 6) + UInt32(t)
                    leftPair = UInt32(primaries[Int(c)])
                    if leftPair != 0 { break }
                    leftPair = UInt32(table[Int(c)])
                } else {
                    leftPair = lookupUTF8(table, c, left, &leftIndex, leftLength)
                }
                if leftPair >= minShort {
                    leftPair &= shortPrimaryMask
                    break
                } else if leftPair > variableTop {
                    leftPair &= longPrimaryMask
                    break
                } else {
                    leftPair = nextPairUTF8(table, leftPair, left, &leftIndex, leftLength)
                    if leftPair == bailOut { return bailOutResult }
                    leftPair = getPrimaries(variableTop, leftPair)
                }
            }

            while rightPair == 0 {
                if rightIndex == rightLength {
                    rightPair = eos
                    break
                }
                var c = UInt32(right[rightIndex])
                rightIndex += 1
                if c <= 0x7f {
                    rightPair = UInt32(primaries[Int(c)])
                    if rightPair != 0 { break }
                    if c <= 0x39 && c >= 0x30 && (options & CollationOptions.Bits.numeric) != 0 {
                        return bailOutResult
                    }
                    rightPair = UInt32(table[Int(c)])
                } else if c <= UInt32(latinMaxUTF8Lead) && 0xc2 <= c && rightIndex != rightLength,
                          case let t = right[rightIndex], 0x80 <= t && t <= 0xbf {
                    rightIndex += 1
                    c = ((c - 0xc2) << 6) + UInt32(t)
                    rightPair = UInt32(primaries[Int(c)])
                    if rightPair != 0 { break }
                    rightPair = UInt32(table[Int(c)])
                } else {
                    rightPair = lookupUTF8(table, c, right, &rightIndex, rightLength)
                }
                if rightPair >= minShort {
                    rightPair &= shortPrimaryMask
                    break
                } else if rightPair > variableTop {
                    rightPair &= longPrimaryMask
                    break
                } else {
                    rightPair = nextPairUTF8(table, rightPair, right, &rightIndex, rightLength)
                    if rightPair == bailOut { return bailOutResult }
                    rightPair = getPrimaries(variableTop, rightPair)
                }
            }

            if leftPair == rightPair {
                if leftPair == eos { break }
                leftPair = 0
                rightPair = 0
                continue
            }
            let leftPrimary = leftPair & 0xffff
            let rightPrimary = rightPair & 0xffff
            if leftPrimary != rightPrimary {
                return leftPrimary < rightPrimary ? -1 : 1
            }
            if leftPair == eos { break }
            leftPair >>= 16
            rightPair >>= 16
        }

        // The string is now known to be well-formed and fully supported, so
        // the later levels use the unchecked lookups.

        if CollationOptions.strength(of: options) >= CollationOptions.Strength.secondary.rawValue {
            leftIndex = leftStart
            rightIndex = rightStart
            leftPair = 0
            rightPair = 0
            while true {
                while leftPair == 0 {
                    if leftIndex == leftLength {
                        leftPair = eos
                        break
                    }
                    let c = UInt32(left[leftIndex])
                    leftIndex += 1
                    if c <= 0x7f {
                        leftPair = UInt32(table[Int(c)])
                    } else {
                        leftPair = lookupUTF8Unsafe(table, c, left, &leftIndex)
                    }
                    if leftPair >= minShort {
                        leftPair = getSecondariesFromOneShortCE(leftPair)
                        break
                    } else if leftPair > variableTop {
                        leftPair = commonSecPlusOffset
                        break
                    } else {
                        leftPair = nextPairUTF8(table, leftPair, left, &leftIndex, leftLength)
                        leftPair = getSecondaries(variableTop, leftPair)
                    }
                }

                while rightPair == 0 {
                    if rightIndex == rightLength {
                        rightPair = eos
                        break
                    }
                    let c = UInt32(right[rightIndex])
                    rightIndex += 1
                    if c <= 0x7f {
                        rightPair = UInt32(table[Int(c)])
                    } else {
                        rightPair = lookupUTF8Unsafe(table, c, right, &rightIndex)
                    }
                    if rightPair >= minShort {
                        rightPair = getSecondariesFromOneShortCE(rightPair)
                        break
                    } else if rightPair > variableTop {
                        rightPair = commonSecPlusOffset
                        break
                    } else {
                        rightPair = nextPairUTF8(table, rightPair, right, &rightIndex, rightLength)
                        rightPair = getSecondaries(variableTop, rightPair)
                    }
                }

                if leftPair == rightPair {
                    if leftPair == eos { break }
                    leftPair = 0
                    rightPair = 0
                    continue
                }
                let leftSecondary = leftPair & 0xffff
                let rightSecondary = rightPair & 0xffff
                if leftSecondary != rightSecondary {
                    if (options & CollationOptions.Bits.backwardSecondary) != 0 {
                        return bailOutResult
                    }
                    return leftSecondary < rightSecondary ? -1 : 1
                }
                if leftPair == eos { break }
                leftPair >>= 16
                rightPair >>= 16
            }
        }

        if (options & CollationOptions.Bits.caseLevel) != 0 {
            let strengthIsPrimary =
                CollationOptions.strength(of: options) == CollationOptions.Strength.primary.rawValue
            leftIndex = leftStart
            rightIndex = rightStart
            leftPair = 0
            rightPair = 0
            while true {
                while leftPair == 0 {
                    if leftIndex == leftLength {
                        leftPair = eos
                        break
                    }
                    let c = UInt32(left[leftIndex])
                    leftIndex += 1
                    leftPair = c <= 0x7f
                        ? UInt32(table[Int(c)]) : lookupUTF8Unsafe(table, c, left, &leftIndex)
                    if leftPair < minLong {
                        leftPair = nextPairUTF8(table, leftPair, left, &leftIndex, leftLength)
                    }
                    leftPair = getCases(variableTop, strengthIsPrimary, leftPair)
                }

                while rightPair == 0 {
                    if rightIndex == rightLength {
                        rightPair = eos
                        break
                    }
                    let c = UInt32(right[rightIndex])
                    rightIndex += 1
                    rightPair = c <= 0x7f
                        ? UInt32(table[Int(c)]) : lookupUTF8Unsafe(table, c, right, &rightIndex)
                    if rightPair < minLong {
                        rightPair = nextPairUTF8(table, rightPair, right, &rightIndex, rightLength)
                    }
                    rightPair = getCases(variableTop, strengthIsPrimary, rightPair)
                }

                if leftPair == rightPair {
                    if leftPair == eos { break }
                    leftPair = 0
                    rightPair = 0
                    continue
                }
                let leftCase = leftPair & 0xffff
                let rightCase = rightPair & 0xffff
                if leftCase != rightCase {
                    if (options & CollationOptions.Bits.upperFirst) == 0 {
                        return leftCase < rightCase ? -1 : 1
                    } else {
                        return leftCase < rightCase ? 1 : -1
                    }
                }
                if leftPair == eos { break }
                leftPair >>= 16
                rightPair >>= 16
            }
        }
        if CollationOptions.strength(of: options) <= CollationOptions.Strength.secondary.rawValue {
            return 0
        }

        let withCaseBits = CollationOptions.isTertiaryWithCaseBits(options)

        leftIndex = leftStart
        rightIndex = rightStart
        leftPair = 0
        rightPair = 0
        while true {
            while leftPair == 0 {
                if leftIndex == leftLength {
                    leftPair = eos
                    break
                }
                let c = UInt32(left[leftIndex])
                leftIndex += 1
                leftPair = c <= 0x7f
                    ? UInt32(table[Int(c)]) : lookupUTF8Unsafe(table, c, left, &leftIndex)
                if leftPair < minLong {
                    leftPair = nextPairUTF8(table, leftPair, left, &leftIndex, leftLength)
                }
                leftPair = getTertiaries(variableTop, withCaseBits, leftPair)
            }

            while rightPair == 0 {
                if rightIndex == rightLength {
                    rightPair = eos
                    break
                }
                let c = UInt32(right[rightIndex])
                rightIndex += 1
                rightPair = c <= 0x7f
                    ? UInt32(table[Int(c)]) : lookupUTF8Unsafe(table, c, right, &rightIndex)
                if rightPair < minLong {
                    rightPair = nextPairUTF8(table, rightPair, right, &rightIndex, rightLength)
                }
                rightPair = getTertiaries(variableTop, withCaseBits, rightPair)
            }

            if leftPair == rightPair {
                if leftPair == eos { break }
                leftPair = 0
                rightPair = 0
                continue
            }
            var leftTertiary = leftPair & 0xffff
            var rightTertiary = rightPair & 0xffff
            if leftTertiary != rightTertiary {
                if CollationOptions.sortsTertiaryUpperCaseFirst(options) {
                    if leftTertiary > mergeWeight {
                        leftTertiary ^= caseMask
                    }
                    if rightTertiary > mergeWeight {
                        rightTertiary ^= caseMask
                    }
                }
                return leftTertiary < rightTertiary ? -1 : 1
            }
            if leftPair == eos { break }
            leftPair >>= 16
            rightPair >>= 16
        }
        if CollationOptions.strength(of: options) <= CollationOptions.Strength.tertiary.rawValue {
            return 0
        }

        leftIndex = leftStart
        rightIndex = rightStart
        leftPair = 0
        rightPair = 0
        while true {
            while leftPair == 0 {
                if leftIndex == leftLength {
                    leftPair = eos
                    break
                }
                let c = UInt32(left[leftIndex])
                leftIndex += 1
                leftPair = c <= 0x7f
                    ? UInt32(table[Int(c)]) : lookupUTF8Unsafe(table, c, left, &leftIndex)
                if leftPair < minLong {
                    leftPair = nextPairUTF8(table, leftPair, left, &leftIndex, leftLength)
                }
                leftPair = getQuaternaries(variableTop, leftPair)
            }

            while rightPair == 0 {
                if rightIndex == rightLength {
                    rightPair = eos
                    break
                }
                let c = UInt32(right[rightIndex])
                rightIndex += 1
                rightPair = c <= 0x7f
                    ? UInt32(table[Int(c)]) : lookupUTF8Unsafe(table, c, right, &rightIndex)
                if rightPair < minLong {
                    rightPair = nextPairUTF8(table, rightPair, right, &rightIndex, rightLength)
                }
                rightPair = getQuaternaries(variableTop, rightPair)
            }

            if leftPair == rightPair {
                if leftPair == eos { break }
                leftPair = 0
                rightPair = 0
                continue
            }
            let leftQuaternary = leftPair & 0xffff
            let rightQuaternary = rightPair & 0xffff
            if leftQuaternary != rightQuaternary {
                return leftQuaternary < rightQuaternary ? -1 : 1
            }
            if leftPair == eos { break }
            leftPair >>= 16
            rightPair >>= 16
        }
        return 0
    }

    // MARK: Lookups (table already has the header skipped)

    /// (CollationFastLatin::lookup.)
    @inline(__always)
    private static func lookup(_ table: UnsafeBufferPointer<UInt16>, _ c: UInt32) -> UInt32 {
        assert(c > latinMax)
        if punctStart <= c && c < punctLimit {
            return UInt32(table[Int(c - punctStart) + latinLimit])
        } else if c == 0xfffe {
            return mergeWeight
        } else if c == 0xffff {
            return shortPrimaryMask | commonSec | lowerCase  // MAX_SHORT | COMMON_SEC | LOWER_CASE | COMMON_TER(0)
        } else {
            return bailOut
        }
    }

    /// Looks up a lead byte > 0x7f that the two-byte Latin fast path did not
    /// handle: the punctuation block (E2 80 xx), U+FFFE/U+FFFF (EF BF BE/BF),
    /// anything else bails. (CollationFastLatin::lookupUTF8.)
    @inline(__always)
    private static func lookupUTF8(
        _ table: UnsafeBufferPointer<UInt16>, _ c: UInt32,
        _ s8: UnsafeBufferPointer<UInt8>, _ sIndex: inout Int, _ sLength: Int
    ) -> UInt32 {
        let i2 = sIndex + 1
        if i2 < sLength {
            let t1 = s8[sIndex]
            let t2 = s8[i2]
            sIndex += 2
            if c == 0xe2 && t1 == 0x80 && 0x80 <= t2 && t2 <= 0xbf {
                return UInt32(table[(latinLimit - 0x80) + Int(t2)])  // 2000..203F
            } else if c == 0xef && t1 == 0xbf {
                if t2 == 0xbe {
                    return mergeWeight  // U+FFFE
                } else if t2 == 0xbf {
                    return shortPrimaryMask | commonSec | lowerCase  // U+FFFF
                }
            }
        }
        return bailOut
    }

    /// Unchecked lead-byte lookup for the levels after primary, which has
    /// already vetted the whole string as well-formed and fully supported.
    /// (CollationFastLatin::lookupUTF8Unsafe.)
    @inline(__always)
    private static func lookupUTF8Unsafe(
        _ table: UnsafeBufferPointer<UInt16>, _ c: UInt32,
        _ s8: UnsafeBufferPointer<UInt8>, _ sIndex: inout Int
    ) -> UInt32 {
        // The caller handled ASCII.
        if c <= UInt32(latinMaxUTF8Lead) {
            let t = s8[sIndex]
            sIndex += 1
            return UInt32(table[Int((c - 0xc2) << 6) + Int(t)])  // 0080..017F
        }
        let t2 = s8[sIndex + 1]
        sIndex += 2
        if c == 0xe2 {
            return UInt32(table[(latinLimit - 0x80) + Int(t2)])  // 2000..203F
        } else if t2 == 0xbe {
            return mergeWeight  // U+FFFE
        } else {
            return shortPrimaryMask | commonSec | lowerCase  // U+FFFF
        }
    }

    /// Byte-stream variant of nextPair (the s8 branch of
    /// CollationFastLatin::nextPair): the contraction lookahead reads the
    /// next character's bytes and consumes them only on a match.
    private static func nextPairUTF8(
        _ table: UnsafeBufferPointer<UInt16>, _ ceIn: UInt32,
        _ s8: UnsafeBufferPointer<UInt8>, _ sIndex: inout Int, _ sLength: Int
    ) -> UInt32 {
        var ce = ceIn
        if ce >= minLong || ce < contraction {
            return ce  // simple or special mini CE
        } else if ce >= expansion {
            let index = numFastChars + Int(ce & indexMask)
            return (UInt32(table[index + 1]) << 16) | UInt32(table[index])
        } else /* ce >= contraction */ {
            var index = numFastChars + Int(ce & indexMask)
            if sIndex != sLength {
                // Read the next character.
                var c2 = Int32(s8[sIndex])
                var nextIndex = sIndex + 1
                if c2 > 0x7f {
                    if c2 <= Int32(latinMaxUTF8Lead) && 0xc2 <= c2 && nextIndex != sLength,
                       case let t = s8[nextIndex], 0x80 <= t && t <= 0xbf {
                        c2 = ((c2 - 0xc2) << 6) + Int32(t)
                        nextIndex += 1
                    } else {
                        let i2 = nextIndex + 1
                        if i2 < sLength {
                            let t1 = s8[nextIndex]
                            let t2 = s8[i2]
                            if c2 == 0xe2 && t1 == 0x80 && 0x80 <= t2 && t2 <= 0xbf {
                                c2 = Int32(latinLimit - 0x80) + Int32(t2)  // 2000..203F
                            } else if c2 == 0xef && t1 == 0xbf && (t2 == 0xbe || t2 == 0xbf) {
                                c2 = -1  // U+FFFE & U+FFFF cannot occur in contractions.
                            } else {
                                return bailOut
                            }
                        } else {
                            return bailOut
                        }
                        nextIndex += 2
                    }
                }
                // Look for the next character in the contraction suffix
                // list, which is in ascending order of single suffix
                // characters.
                var i = index
                var head = Int32(table[i])  // first skip the default mapping
                var x: Int32
                repeat {
                    i += Int(head >> contrLengthShift)
                    head = Int32(table[i])
                    x = head & Int32(contrCharMask)
                } while x < c2
                if x == c2 {
                    index = i
                    sIndex = nextIndex
                }
            }
            // Return the CE or CEs for the default or contraction mapping.
            let length = Int(table[index]) >> contrLengthShift
            if length == 1 {
                return bailOut
            }
            ce = UInt32(table[index + 1])
            if length == 2 {
                return ce
            }
            return (UInt32(table[index + 2]) << 16) | ce
        }
    }

    /// Resolves a special mini CE: expansions yield their pair; contractions
    /// match at most one following character against the contraction list
    /// (longer contractions bail out via length-1 entries).
    /// (CollationFastLatin::nextPair, UTF-16 variant without NUL handling.)
    private static func nextPair(
        _ table: UnsafeBufferPointer<UInt16>, _ c: UInt32, _ ceIn: UInt32, _ side: inout Side
    ) -> UInt32 {
        var ce = ceIn
        if ce >= minLong || ce < contraction {
            return ce  // simple or special mini CE
        } else if ce >= expansion {
            let index = numFastChars + Int(ce & indexMask)
            return (UInt32(table[index + 1]) << 16) | UInt32(table[index])
        } else /* ce >= contraction */ {
            // Contraction list: Default mapping followed by 0 or more
            // single-character contraction suffix mappings.
            var index = numFastChars + Int(ce & indexMask)
            if let next = side.next {
                // Map the lookahead character to a contraction character
                // index, or -1 if it cannot occur in a contraction.
                var c2: Int32
                if next <= latinMax {
                    c2 = Int32(next)
                } else if punctStart <= next && next < punctLimit {
                    c2 = Int32(next - punctStart) + Int32(latinLimit)
                } else if next == 0xfffe || next == 0xffff {
                    c2 = -1  // U+FFFE & U+FFFF cannot occur in contractions.
                } else {
                    return bailOut
                }
                // Look for the next character in the contraction suffix
                // list, which is in ascending order of single suffix
                // characters.
                var i = index
                var head = Int32(table[i])  // first skip the default mapping
                var x: Int32
                repeat {
                    i += Int(head >> contrLengthShift)
                    head = Int32(table[i])
                    x = head & Int32(contrCharMask)
                } while x < c2
                if x == c2 {
                    index = i
                    _ = side.pop()  // consume the matched character
                }
            }
            // Return the CE or CEs for the default or contraction mapping.
            let length = Int(table[index]) >> contrLengthShift
            if length == 1 {
                return bailOut
            }
            ce = UInt32(table[index + 1])
            if length == 2 {
                return ce
            }
            return (UInt32(table[index + 2]) << 16) | ce
        }
    }

    // MARK: Level transforms (CollationFastLatin::get*)

    @inline(__always)
    private static func getPrimaries(_ variableTop: UInt32, _ pair: UInt32) -> UInt32 {
        let ce = pair & 0xffff
        if ce >= minShort { return pair & twoShortPrimariesMask }
        if ce > variableTop { return pair & twoLongPrimariesMask }
        if ce >= minLong { return 0 }  // variable
        return pair  // special mini CE
    }

    @inline(__always)
    private static func getSecondariesFromOneShortCE(_ ceIn: UInt32) -> UInt32 {
        let ce = ceIn & secondaryMask
        if ce < minSecHigh {
            return ce + secOffset
        } else {
            return ((ce + secOffset) << 16) | commonSecPlusOffset
        }
    }

    private static func getSecondaries(_ variableTop: UInt32, _ pairIn: UInt32) -> UInt32 {
        var pair = pairIn
        if pair <= 0xffff {
            // one mini CE
            if pair >= minShort {
                pair = getSecondariesFromOneShortCE(pair)
            } else if pair > variableTop {
                pair = commonSecPlusOffset
            } else if pair >= minLong {
                pair = 0  // variable
            }
            // else special mini CE
        } else {
            let ce = pair & 0xffff
            if ce >= minShort {
                pair = (pair & twoSecondariesMask) &+ twoSecOffsets
            } else if ce > variableTop {
                pair = twoCommonSecPlusOffset
            } else {
                assert(ce >= minLong)
                pair = 0  // variable
            }
        }
        return pair
    }

    private static func getCases(_ variableTop: UInt32, _ strengthIsPrimary: Bool, _ pairIn: UInt32) -> UInt32 {
        // Primary+caseLevel: Ignore case level weights of primary ignorables.
        // Otherwise: Ignore case level weights of secondary ignorables.
        // For details see the comments in the CollationCompare class.
        // Tertiary CEs (secondary ignorables) are not supported in fast Latin.
        var pair = pairIn
        if pair <= 0xffff {
            // one mini CE
            if pair >= minShort {
                // A high secondary weight means we really have two CEs,
                // a primary CE and a secondary CE.
                let ce = pair
                pair &= caseMask  // explicit weight of primary CE
                if !strengthIsPrimary && (ce & secondaryMask) >= minSecHigh {
                    pair |= lowerCase << 16  // implied weight of secondary CE
                }
            } else if pair > variableTop {
                pair = lowerCase
            } else if pair >= minLong {
                pair = 0  // variable
            }
            // else special mini CE
        } else {
            // two mini CEs, same primary groups, neither expands like above
            let ce = pair & 0xffff
            if ce >= minShort {
                if strengthIsPrimary && (pair & (shortPrimaryMask << 16)) == 0 {
                    pair &= caseMask
                } else {
                    pair &= twoCasesMask
                }
            } else if ce > variableTop {
                pair = twoLowerCases
            } else {
                assert(ce >= minLong)
                pair = 0  // variable
            }
        }
        return pair
    }

    private static func getTertiaries(_ variableTop: UInt32, _ withCaseBits: Bool, _ pairIn: UInt32) -> UInt32 {
        var pair = pairIn
        if pair <= 0xffff {
            // one mini CE
            if pair >= minShort {
                // A high secondary weight means we really have two CEs,
                // a primary CE and a secondary CE.
                let ce = pair
                if withCaseBits {
                    pair = (pair & caseAndTertiaryMask) &+ terOffset
                    if (ce & secondaryMask) >= minSecHigh {
                        pair |= (lowerCase | commonTerPlusOffset) << 16
                    }
                } else {
                    pair = (pair & tertiaryMask) &+ terOffset
                    if (ce & secondaryMask) >= minSecHigh {
                        pair |= commonTerPlusOffset << 16
                    }
                }
            } else if pair > variableTop {
                pair = (pair & tertiaryMask) &+ terOffset
                if withCaseBits {
                    pair |= lowerCase
                }
            } else if pair >= minLong {
                pair = 0  // variable
            }
            // else special mini CE
        } else {
            // two mini CEs, same primary groups, neither expands like above
            let ce = pair & 0xffff
            if ce >= minShort {
                if withCaseBits {
                    pair &= twoCasesMask | twoTertiariesMask
                } else {
                    pair &= twoTertiariesMask
                }
                pair &+= twoTerOffsets
            } else if ce > variableTop {
                pair = (pair & twoTertiariesMask) &+ twoTerOffsets
                if withCaseBits {
                    pair |= twoLowerCases
                }
            } else {
                assert(ce >= minLong)
                pair = 0  // variable
            }
        }
        return pair
    }

    private static func getQuaternaries(_ variableTop: UInt32, _ pairIn: UInt32) -> UInt32 {
        // Return the primary weight of a variable CE, or the maximum primary
        // weight for a non-variable, not-completely-ignorable CE.
        var pair = pairIn
        if pair <= 0xffff {
            // one mini CE
            if pair >= minShort {
                // A high secondary weight means we really have two CEs,
                // a primary CE and a secondary CE.
                if (pair & secondaryMask) >= minSecHigh {
                    pair = twoShortPrimariesMask
                } else {
                    pair = shortPrimaryMask
                }
            } else if pair > variableTop {
                pair = shortPrimaryMask
            } else if pair >= minLong {
                pair &= longPrimaryMask  // variable
            }
            // else special mini CE
        } else {
            // two mini CEs, same primary groups, neither expands like above
            let ce = pair & 0xffff
            if ce > variableTop {
                pair = twoShortPrimariesMask
            } else {
                assert(ce >= minLong)
                pair &= twoLongPrimariesMask  // variable
            }
        }
        return pair
    }
}
