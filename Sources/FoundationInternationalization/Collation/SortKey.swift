// Sort key generation: faithful port of
// CollationKeys::writeSortKeyUpToQuaternary (i18n/collationkeys.{h,cpp}) and
// the BOCSU identical-level encoder (i18n/bocsu.{h,cpp}).
//
// Operates on a NO_CE-terminated CE array. Script reordering hooks are
// omitted (milestone 7). The invariant: byte-wise comparison of two sort keys
// equals compare() at the same options.

/// Per-level byte buffer. (collationkeys.cpp SortKeyLevel.)
struct SortKeyLevel {
    var bytes: [UInt8] = []

    var isEmpty: Bool { bytes.isEmpty }

    mutating func appendByte(_ b: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: b))
    }

    /// Appends the non-zero bytes of a 16-bit weight.
    mutating func appendWeight16(_ w: UInt32) {
        assert((w & 0xffff) != 0)
        let b0 = UInt8(truncatingIfNeeded: w >> 8)
        let b1 = UInt8(truncatingIfNeeded: w)
        bytes.append(b0)
        if b1 != 0 { bytes.append(b1) }
    }

    /// Appends the non-zero prefix of a 32-bit weight.
    mutating func appendWeight32(_ w: UInt32) {
        assert(w != 0)
        let b = (UInt8(truncatingIfNeeded: w >> 24), UInt8(truncatingIfNeeded: w >> 16),
                 UInt8(truncatingIfNeeded: w >> 8), UInt8(truncatingIfNeeded: w))
        bytes.append(b.0)
        if b.1 != 0 {
            bytes.append(b.1)
            if b.2 != 0 {
                bytes.append(b.2)
                if b.3 != 0 { bytes.append(b.3) }
            }
        }
    }

    /// Appends a 16-bit weight byte-reversed (for the backwards-secondary
    /// level, which is re-reversed segment-wise later).
    mutating func appendReverseWeight16(_ w: UInt32) {
        assert((w & 0xffff) != 0)
        let b0 = UInt8(truncatingIfNeeded: w >> 8)
        let b1 = UInt8(truncatingIfNeeded: w)
        if b1 == 0 {
            bytes.append(b0)
        } else {
            bytes.append(b1)
            bytes.append(b0)
        }
    }

    /// Appends all but the last byte (the trailing 01 from NO_CE) to the key.
    func appendTo(_ key: inout [UInt8]) {
        assert(bytes.last == 1)
        let n = bytes.count - 1
        if n <= 0 { return }  // level compressed to nothing — skip the copy entirely
        // Copy from a contiguous buffer pointer so the append takes Array's
        // memcpy fast path, not the slice/Collection iteration path.
        bytes.withUnsafeBufferPointer { p in
            key.append(contentsOf: UnsafeBufferPointer(start: p.baseAddress, count: n))
        }
    }
}

/// Reusable storage for the four per-level buffers (lives in ScratchBuffers;
/// writeSortKeyUpToQuaternary borrows and returns it).
struct SortKeyLevelBuffers {
    var cases = SortKeyLevel()
    var secondaries = SortKeyLevel()
    var tertiaries = SortKeyLevel()
    var quaternaries = SortKeyLevel()
}

enum CollationKeys {
    // Secondary level: Compress up to 33 common weights as 05..25 or 25..45.
    private static let secCommonLow: UInt32 = 5
    private static let secCommonMiddle: UInt32 = secCommonLow + 0x20
    private static let secCommonHigh: UInt32 = secCommonLow + 0x40
    private static let secCommonMaxCount = 0x21

    // Case level, lowerFirst: Compress common weights as nibbles 1..7..13, mixed=14, upper=15.
    private static let caseLowerFirstCommonLow: UInt32 = 1
    private static let caseLowerFirstCommonMiddle: UInt32 = 7
    private static let caseLowerFirstCommonHigh: UInt32 = 13
    private static let caseLowerFirstCommonMaxCount = 7
    // Case level, upperFirst: Compress common weights as nibbles 3..15, mixed=2, upper=1.
    private static let caseUpperFirstCommonLow: UInt32 = 3
    private static let caseUpperFirstCommonHigh: UInt32 = 15
    private static let caseUpperFirstCommonMaxCount = 13

    // Tertiary level, only tertiary weights: Compress up to 97 common weights as 05..65 or 65..C5.
    private static let terOnlyCommonLow: UInt32 = 5
    private static let terOnlyCommonMiddle: UInt32 = terOnlyCommonLow + 0x60
    private static let terOnlyCommonHigh: UInt32 = terOnlyCommonLow + 0xc0
    private static let terOnlyCommonMaxCount = 0x61
    // Tertiary level, caseFirst=lowerFirst: Compress common weights as 05..25 or 25..45.
    private static let terLowerFirstCommonLow: UInt32 = 5
    private static let terLowerFirstCommonMiddle: UInt32 = terLowerFirstCommonLow + 0x20
    private static let terLowerFirstCommonHigh: UInt32 = terLowerFirstCommonLow + 0x40
    private static let terLowerFirstCommonMaxCount = 0x21
    // Tertiary level, caseFirst=upperFirst: Compress common weights as 85..A5 or A5..C5.
    private static let terUpperFirstCommonLow: UInt32 = 5 + 0x80
    private static let terUpperFirstCommonMiddle: UInt32 = terUpperFirstCommonLow + 0x20
    private static let terUpperFirstCommonHigh: UInt32 = terUpperFirstCommonLow + 0x40
    private static let terUpperFirstCommonMaxCount = 0x21

    // Quaternary level: Compress up to 113 common weights as 1C..8C or 8C..FC.
    private static let quatCommonLow: UInt32 = 0x1c
    private static let quatCommonMiddle: UInt32 = quatCommonLow + 0x70
    private static let quatCommonHigh: UInt32 = quatCommonLow + 0xe0
    private static let quatCommonMaxCount = 0x71
    // Shifted primary lead bytes must not overlap the common compression range.
    private static let quatShiftedLimitByte: UInt32 = quatCommonLow - 1  // 0x1b

    private static let levelSeparator: UInt8 = 1

    /// Map from strength to the level-flag set to write (CASE_LEVEL is
    /// independent; IDENTICAL_LEVEL is written separately).
    private static func levelFlags(strength: Int32) -> UInt32 {
        switch strength {
        case CollationOptions.Strength.primary.rawValue: return 2
        case CollationOptions.Strength.secondary.rawValue: return 6
        case CollationOptions.Strength.tertiary.rawValue: return 0x16
        default: return 0x36  // quaternary and identical
        }
    }

    private static let primaryFlag: UInt32 = 2
    private static let secondaryFlag: UInt32 = 4
    private static let caseFlag: UInt32 = 8
    private static let tertiaryFlag: UInt32 = 0x10
    private static let quaternaryFlag: UInt32 = 0x20

    /// Writes the sort key for levels up to the strength in `options`
    /// (without identical level and without the 00 terminator).
    /// (CollationKeys::writeSortKeyUpToQuaternary.)
    static func writeSortKeyUpToQuaternary(
        ces: borrowing [Int64], compressibleBytes: UnsafeBufferPointer<Bool>,
        options: Int32, variableTopValue: UInt32, reordering: Reordering? = nil,
        into key: inout [UInt8], reusing buffers: inout SortKeyLevelBuffers
    ) {
        var levels = levelFlags(strength: CollationOptions.strength(of: options))
        if (options & CollationOptions.Bits.caseLevel) != 0 {
            levels |= caseFlag
        }

        let variableTop: UInt32
        if (options & CollationOptions.Bits.alternateMask) == 0 {
            variableTop = 0
        } else {
            // +1 so that we can use "<" and primary ignorables test out early.
            variableTop = variableTopValue + 1
        }

        let tertiaryMask = CollationOptions.tertiaryMask(of: options)

        // Borrow the reusable level buffers by swapping (not copying, so the
        // appends below never copy-on-write); swapped back, grown, at the end.
        var cases = SortKeyLevel()
        var secondaries = SortKeyLevel()
        var tertiaries = SortKeyLevel()
        var quaternaries = SortKeyLevel()
        swap(&cases, &buffers.cases)
        swap(&secondaries, &buffers.secondaries)
        swap(&tertiaries, &buffers.tertiaries)
        swap(&quaternaries, &buffers.quaternaries)
        // isEmpty guards: removeAll on a never-used array hits the shared
        // empty-singleton storage and takes the copy-on-write slow path.
        if !cases.bytes.isEmpty { cases.bytes.removeAll(keepingCapacity: true) }
        if !secondaries.bytes.isEmpty { secondaries.bytes.removeAll(keepingCapacity: true) }
        if !tertiaries.bytes.isEmpty { tertiaries.bytes.removeAll(keepingCapacity: true) }
        if !quaternaries.bytes.isEmpty { quaternaries.bytes.removeAll(keepingCapacity: true) }

        var prevReorderedPrimary: UInt32 = 0  // 0==no compression
        var commonCases = 0
        var commonSecondaries = 0
        var commonTertiaries = 0
        var commonQuaternaries = 0

        var prevSecondary: UInt32 = 0
        var secSegmentStart = 0

        // Batch primary bytes: accumulate into a fixed stack buffer and
        // flush to `key` periodically. Converts many individual append()
        // calls (each with an Array growth check) into fewer bulk copies.
        var primBuf = (
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
        )
        var primCount = 0
        let primCapacity = 64

        @inline(__always)
        func flushPrimaries(_ buf: UnsafePointer<UInt8>, _ count: Int, _ key: inout [UInt8]) {
            key.append(contentsOf: UnsafeBufferPointer(start: buf, count: count))
        }

        var cesIndex = 0
        while true {
            var ce = ces[cesIndex]
            cesIndex += 1
            var p = UInt32(truncatingIfNeeded: ce >> 32)
            if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                // Variable CE, shift it to quaternary level.
                // Ignore all following primary ignorables, and shift further variable CEs.
                if commonQuaternaries != 0 {
                    commonQuaternaries -= 1
                    while commonQuaternaries >= quatCommonMaxCount {
                        quaternaries.appendByte(quatCommonMiddle)
                        commonQuaternaries -= quatCommonMaxCount
                    }
                    // Shifted primary weights are lower than the common weight.
                    quaternaries.appendByte(quatCommonLow + UInt32(commonQuaternaries))
                    commonQuaternaries = 0
                }
                repeat {
                    if (levels & quaternaryFlag) != 0 {
                        if let reordering { p = reordering.reorder(p) }
                        if (p >> 24) >= quatShiftedLimitByte {
                            // Prevent shifted primary lead bytes from
                            // overlapping with the common compression range.
                            quaternaries.appendByte(quatShiftedLimitByte)
                        }
                        quaternaries.appendWeight32(p)
                    }
                    repeat {
                        ce = ces[cesIndex]
                        cesIndex += 1
                        p = UInt32(truncatingIfNeeded: ce >> 32)
                    } while p == 0
                } while p < variableTop && p > CollationConstants.mergeSeparatorPrimary
            }
            // ce could be primary ignorable, or NO_CE, or the merge separator,
            // or a regular primary CE, but it is not variable.
            // If ce==NO_CE, then write nothing for the primary level but
            // terminate compression on all levels and then exit the loop.
            if p > CollationConstants.noCEPrimary && (levels & primaryFlag) != 0 {
                // Test the un-reordered primary for compressibility.
                let isCompressible = compressibleBytes[Int(p >> 24)]
                if let reordering { p = reordering.reorder(p) }
                let p1 = p >> 24
                if !isCompressible || p1 != (prevReorderedPrimary >> 24) {
                    if prevReorderedPrimary != 0 {
                        if p < prevReorderedPrimary {
                            if p1 > UInt32(CollationConstants.mergeSeparatorPrimary >> 24) {
                                withUnsafeMutablePointer(to: &primBuf.0) { $0[primCount] = 3 }
                                primCount += 1
                            }
                        } else {
                            withUnsafeMutablePointer(to: &primBuf.0) { $0[primCount] = 0xff }
                            primCount += 1
                        }
                    }
                    withUnsafeMutablePointer(to: &primBuf.0) { $0[primCount] = UInt8(truncatingIfNeeded: p1) }
                    primCount += 1
                    prevReorderedPrimary = isCompressible ? p : 0
                }
                let p2 = UInt8(truncatingIfNeeded: p >> 16)
                if p2 != 0 {
                    withUnsafeMutablePointer(to: &primBuf.0) { $0[primCount] = p2 }
                    primCount += 1
                    let p3 = UInt8(truncatingIfNeeded: p >> 8)
                    if p3 != 0 {
                        withUnsafeMutablePointer(to: &primBuf.0) { $0[primCount] = p3 }
                        primCount += 1
                        let p4 = UInt8(truncatingIfNeeded: p)
                        if p4 != 0 {
                            withUnsafeMutablePointer(to: &primBuf.0) { $0[primCount] = p4 }
                            primCount += 1
                        }
                    }
                }
                if primCount >= primCapacity - 6 {
                    withUnsafePointer(to: &primBuf.0) { flushPrimaries($0, primCount, &key) }
                    primCount = 0
                }
            }

            let lower32 = UInt32(truncatingIfNeeded: ce)
            if lower32 == 0 { continue }  // completely ignorable

            if (levels & secondaryFlag) != 0 {
                let s = lower32 >> 16
                if s == 0 {
                    // secondary ignorable
                } else if s == 0x0500  // COMMON_WEIGHT16
                    && ((options & CollationOptions.Bits.backwardSecondary) == 0
                        || p != CollationConstants.mergeSeparatorPrimary) {
                    commonSecondaries += 1
                } else if (options & CollationOptions.Bits.backwardSecondary) == 0 {
                    if commonSecondaries != 0 {
                        commonSecondaries -= 1
                        while commonSecondaries >= secCommonMaxCount {
                            secondaries.appendByte(secCommonMiddle)
                            commonSecondaries -= secCommonMaxCount
                        }
                        let b: UInt32 = s < 0x0500
                            ? secCommonLow + UInt32(commonSecondaries)
                            : secCommonHigh - UInt32(commonSecondaries)
                        secondaries.appendByte(b)
                        commonSecondaries = 0
                    }
                    secondaries.appendWeight16(s)
                } else {
                    // Backwards secondary: weights are appended byte-reversed;
                    // each merge-separated segment is reversed at its end.
                    if commonSecondaries != 0 {
                        commonSecondaries -= 1
                        // Append reverse weights. The level will be re-reversed later.
                        let remainder = commonSecondaries % secCommonMaxCount
                        let b: UInt32 = prevSecondary < 0x0500
                            ? secCommonLow + UInt32(remainder)
                            : secCommonHigh - UInt32(remainder)
                        secondaries.appendByte(b)
                        commonSecondaries -= remainder
                        while commonSecondaries > 0 {
                            secondaries.appendByte(secCommonMiddle)
                            commonSecondaries -= secCommonMaxCount
                        }
                    }
                    if p > 0 && p <= CollationConstants.mergeSeparatorPrimary {
                        // The merge separator or NO_CE: reverse the segment.
                        if secSegmentStart < secondaries.bytes.count - 1 {
                            secondaries.bytes[secSegmentStart...].reverse()
                        }
                        secondaries.appendByte(
                            p == CollationConstants.noCEPrimary
                                ? UInt32(levelSeparator) : UInt32(CollationConstants.mergeSeparatorPrimary >> 24))
                        prevSecondary = 0
                        secSegmentStart = secondaries.bytes.count
                    } else {
                        secondaries.appendReverseWeight16(s)
                        prevSecondary = s
                    }
                }
            }

            if (levels & caseFlag) != 0 {
                let ignore: Bool =
                    CollationOptions.strength(of: options) == CollationOptions.Strength.primary.rawValue
                    ? p == 0 : lower32 <= 0xffff
                if !ignore {
                    var c = (lower32 >> 8) & 0xff  // case bits & tertiary lead byte
                    assert((c & 0xc0) != 0xc0)
                    if (c & 0xc0) == 0 && c > UInt32(levelSeparator) {
                        commonCases += 1
                    } else {
                        if (options & CollationOptions.Bits.upperFirst) == 0 {
                            // lowerFirst: Compress common weights to nibbles 1..7..13, mixed=14, upper=15.
                            // If there are only common (=lowest) weights in the whole level,
                            // then we need not write anything.
                            if commonCases != 0 && (c > UInt32(levelSeparator) || !cases.isEmpty) {
                                commonCases -= 1
                                while commonCases >= caseLowerFirstCommonMaxCount {
                                    cases.appendByte(caseLowerFirstCommonMiddle << 4)
                                    commonCases -= caseLowerFirstCommonMaxCount
                                }
                                let b: UInt32 = c <= UInt32(levelSeparator)
                                    ? caseLowerFirstCommonLow + UInt32(commonCases)
                                    : caseLowerFirstCommonHigh - UInt32(commonCases)
                                cases.appendByte(b << 4)
                                commonCases = 0
                            }
                            if c > UInt32(levelSeparator) {
                                c = (caseLowerFirstCommonHigh + (c >> 6)) << 4  // 14 or 15
                            }
                        } else {
                            // upperFirst: Compress common weights to nibbles 3..15, mixed=2, upper=1.
                            if commonCases != 0 {
                                commonCases -= 1
                                while commonCases >= caseUpperFirstCommonMaxCount {
                                    cases.appendByte(caseUpperFirstCommonLow << 4)
                                    commonCases -= caseUpperFirstCommonMaxCount
                                }
                                cases.appendByte((caseUpperFirstCommonLow + UInt32(commonCases)) << 4)
                                commonCases = 0
                            }
                            if c > UInt32(levelSeparator) {
                                c = (caseUpperFirstCommonLow - (c >> 6)) << 4  // 2 or 1
                            }
                        }
                        // c is a separator byte 01, or a left-shifted nibble 0x10..0xf0.
                        cases.appendByte(c)
                    }
                }
            }

            if (levels & tertiaryFlag) != 0 {
                var t = lower32 & tertiaryMask
                assert((lower32 & 0xc000) != 0xc000)
                if t == 0x0500 {  // COMMON_WEIGHT16
                    commonTertiaries += 1
                } else if (tertiaryMask & 0x8000) == 0 {
                    // Tertiary weights without case bits.
                    // Move lead bytes 06..3F to C6..FF for a large common-weight range.
                    if commonTertiaries != 0 {
                        commonTertiaries -= 1
                        while commonTertiaries >= terOnlyCommonMaxCount {
                            tertiaries.appendByte(terOnlyCommonMiddle)
                            commonTertiaries -= terOnlyCommonMaxCount
                        }
                        let b: UInt32 = t < 0x0500
                            ? terOnlyCommonLow + UInt32(commonTertiaries)
                            : terOnlyCommonHigh - UInt32(commonTertiaries)
                        tertiaries.appendByte(b)
                        commonTertiaries = 0
                    }
                    if t > 0x0500 { t += 0xc000 }
                    tertiaries.appendWeight16(t)
                } else if (options & CollationOptions.Bits.upperFirst) == 0 {
                    // Tertiary weights with caseFirst=lowerFirst.
                    // Move lead bytes 06..BF to 46..FF for the common-weight range.
                    if commonTertiaries != 0 {
                        commonTertiaries -= 1
                        while commonTertiaries >= terLowerFirstCommonMaxCount {
                            tertiaries.appendByte(terLowerFirstCommonMiddle)
                            commonTertiaries -= terLowerFirstCommonMaxCount
                        }
                        let b: UInt32 = t < 0x0500
                            ? terLowerFirstCommonLow + UInt32(commonTertiaries)
                            : terLowerFirstCommonHigh - UInt32(commonTertiaries)
                        tertiaries.appendByte(b)
                        commonTertiaries = 0
                    }
                    if t > 0x0500 { t += 0x4000 }
                    tertiaries.appendWeight16(t)
                } else {
                    // Tertiary weights with caseFirst=upperFirst.
                    // Separator         01 -> 01      (unchanged)
                    // Lowercase     02..04 -> 82..84  (includes uncased)
                    // Common weight     05 -> 85..C5  (common-weight compression range)
                    // Lowercase     06..3F -> C6..FF
                    // Mixed case    42..7F -> 42..7F
                    // Uppercase     82..BF -> 02..3F
                    // Tertiary CE   86..BF -> C6..FF
                    if t <= CollationConstants.noCEWeight16 {
                        // Keep separators unchanged.
                    } else if lower32 > 0xffff {
                        // Invert case bits of primary & secondary CEs.
                        t ^= 0xc000
                        if t < (terUpperFirstCommonHigh << 8) {
                            t &-= 0x4000
                        }
                    } else {
                        // Keep uppercase bits of tertiary CEs.
                        assert(0x8600 <= t && t <= 0xbfff)
                        t += 0x4000
                    }
                    if commonTertiaries != 0 {
                        commonTertiaries -= 1
                        while commonTertiaries >= terUpperFirstCommonMaxCount {
                            tertiaries.appendByte(terUpperFirstCommonMiddle)
                            commonTertiaries -= terUpperFirstCommonMaxCount
                        }
                        let b: UInt32 = t < (terUpperFirstCommonLow << 8)
                            ? terUpperFirstCommonLow + UInt32(commonTertiaries)
                            : terUpperFirstCommonHigh - UInt32(commonTertiaries)
                        tertiaries.appendByte(b)
                        commonTertiaries = 0
                    }
                    tertiaries.appendWeight16(t)
                }
            }

            if (levels & quaternaryFlag) != 0 {
                var q = lower32 & 0xffff
                if (q & 0xc0) == 0 && q > CollationConstants.noCEWeight16 {
                    commonQuaternaries += 1
                } else if q == CollationConstants.noCEWeight16
                    && (options & CollationOptions.Bits.alternateMask) == 0
                    && quaternaries.isEmpty {
                    // If alternate=non-ignorable and there are only common quaternary
                    // weights, then we need not write anything.
                    quaternaries.appendByte(UInt32(levelSeparator))
                } else {
                    if q == CollationConstants.noCEWeight16 {
                        q = UInt32(levelSeparator)
                    } else {
                        q = 0xfc + ((q >> 6) & 3)
                    }
                    if commonQuaternaries != 0 {
                        commonQuaternaries -= 1
                        while commonQuaternaries >= quatCommonMaxCount {
                            quaternaries.appendByte(quatCommonMiddle)
                            commonQuaternaries -= quatCommonMaxCount
                        }
                        let b: UInt32 = q < quatCommonLow
                            ? quatCommonLow + UInt32(commonQuaternaries)
                            : quatCommonHigh - UInt32(commonQuaternaries)
                        quaternaries.appendByte(b)
                        commonQuaternaries = 0
                    }
                    quaternaries.appendByte(q)
                }
            }

            if (lower32 >> 24) == UInt32(levelSeparator) { break }  // ce == NO_CE
        }

        // Flush any remaining batched primary bytes.
        if primCount > 0 {
            withUnsafePointer(to: &primBuf.0) { flushPrimaries($0, primCount, &key) }
        }

        // Append the beyond-primary levels.
        if (levels & secondaryFlag) != 0 {
            key.append(levelSeparator)
            secondaries.appendTo(&key)
        }
        if (levels & caseFlag) != 0 {
            key.append(levelSeparator)
            // Write pairs of nibbles as bytes, except separator bytes as themselves.
            var b: UInt8 = 0
            for c in cases.bytes.dropLast() {  // ignore the trailing NO_CE
                assert((c & 0xf) == 0 && c != 0)
                if b == 0 {
                    b = c
                } else {
                    key.append(b | (c >> 4))
                    b = 0
                }
            }
            if b != 0 { key.append(b) }
        }
        if (levels & tertiaryFlag) != 0 {
            key.append(levelSeparator)
            tertiaries.appendTo(&key)
        }
        if (levels & quaternaryFlag) != 0 {
            key.append(levelSeparator)
            quaternaries.appendTo(&key)
        }

        swap(&cases, &buffers.cases)
        swap(&secondaries, &buffers.secondaries)
        swap(&tertiaries, &buffers.tertiaries)
        swap(&quaternaries, &buffers.quaternaries)
    }

    // MARK: Identical level (BOCSU; i18n/bocsu.{h,cpp})

    private static let slopeMin: Int32 = 3
    private static let slopeMax: Int32 = 0xff
    private static let slopeMiddle: Int32 = 0x81
    private static let slopeTailCount = slopeMax - slopeMin + 1  // 253
    private static let slopeSingle: Int32 = 80
    private static let slopeLead2: Int32 = 42
    private static let slopeLead3: Int32 = 3
    private static let slopeReachPos1 = slopeSingle
    private static let slopeReachNeg1 = -slopeSingle
    private static let slopeReachPos2 = slopeLead2 * slopeTailCount + (slopeLead2 - 1)
    private static let slopeReachNeg2 = -slopeReachPos2 - 1
    private static let slopeReachPos3 =
        slopeLead3 * slopeTailCount * slopeTailCount + (slopeLead3 - 1) * slopeTailCount
        + (slopeTailCount - 1)
    private static let slopeReachNeg3 = -slopeReachPos3 - 1
    private static let slopeStartPos2 = slopeMiddle + slopeSingle + 1
    private static let slopeStartPos3 = slopeStartPos2 + slopeLead2
    private static let slopeStartNeg2 = slopeMiddle + slopeReachNeg1
    private static let slopeStartNeg3 = slopeStartNeg2 - slopeLead2

    /// Appends the identical-level run for NFD scalars. (u_writeIdenticalLevelRun.)
    static func writeIdenticalLevelRun<S: Sequence>(
        scalars: S, into key: inout [UInt8]
    ) where S.Element == UInt32 {
        var prev: Int32 = 0
        for scalar in scalars {
            if prev < 0x4e00 || prev >= 0xa000 {
                prev = (prev & ~0x7f) - slopeReachNeg1
            } else {
                // Unihan U+4E00..U+9FA5: double-bytes down from the upper end.
                prev = 0x9fff - slopeReachPos2
            }
            if scalar == 0xfffe {
                key.append(2)  // merge separator
                prev = 0
            } else {
                writeDiff(Int32(bitPattern: scalar) - prev, into: &key)
                prev = Int32(bitPattern: scalar)
            }
        }
    }

    /// Encodes one code point difference. (u_writeDiff.)
    private static func writeDiff(_ diffIn: Int32, into key: inout [UInt8]) {
        var diff = diffIn
        func byte(_ v: Int32) -> UInt8 { UInt8(truncatingIfNeeded: v) }
        // Floor division/modulo for negative diffs (NEGDIVMOD).
        func negDivMod() -> Int32 {
            var m = diff % slopeTailCount
            diff /= slopeTailCount
            if m < 0 {
                diff -= 1
                m += slopeTailCount
            }
            return m
        }
        if diff >= slopeReachNeg1 {
            if diff <= slopeReachPos1 {
                key.append(byte(slopeMiddle + diff))
            } else if diff <= slopeReachPos2 {
                key.append(byte(slopeStartPos2 + diff / slopeTailCount))
                key.append(byte(slopeMin + diff % slopeTailCount))
            } else if diff <= slopeReachPos3 {
                let b2 = byte(slopeMin + diff % slopeTailCount)
                diff /= slopeTailCount
                let b1 = byte(slopeMin + diff % slopeTailCount)
                key.append(byte(slopeStartPos3 + diff / slopeTailCount))
                key.append(b1)
                key.append(b2)
            } else {
                let b3 = byte(slopeMin + diff % slopeTailCount)
                diff /= slopeTailCount
                let b2 = byte(slopeMin + diff % slopeTailCount)
                diff /= slopeTailCount
                let b1 = byte(slopeMin + diff % slopeTailCount)
                key.append(byte(slopeMax))
                key.append(b1)
                key.append(b2)
                key.append(b3)
            }
        } else {
            if diff >= slopeReachNeg2 {
                let m = negDivMod()
                key.append(byte(slopeStartNeg2 + diff))
                key.append(byte(slopeMin + m))
            } else if diff >= slopeReachNeg3 {
                let m2 = negDivMod()
                let m1 = negDivMod()
                key.append(byte(slopeStartNeg3 + diff))
                key.append(byte(slopeMin + m1))
                key.append(byte(slopeMin + m2))
            } else {
                let m3 = negDivMod()
                let m2 = negDivMod()
                let m1 = negDivMod()
                key.append(byte(slopeMin))
                key.append(byte(slopeMin + m1))
                key.append(byte(slopeMin + m2))
                key.append(byte(slopeMin + m3))
            }
        }
    }
}
