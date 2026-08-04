// Sort key generation: faithful port of CollationKeys::writeSortKeyUpToQuaternary (i18n/collationkeys.{h,cpp}) and the BOCSU identical-level encoder (i18n/bocsu.{h,cpp}).
//
// Operates on a NO_CE-terminated CE array. Script reordering hooks are omitted (milestone 7). The invariant: byte-wise comparison of two sort keys equals compare() at the same options.

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

    /// Appends a 16-bit weight byte-reversed (for the backwards-secondary level, which is re-reversed segment-wise later).
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
        // Copy from a contiguous buffer pointer so the append takes Array's memcpy fast path, not the slice/Collection iteration path.
        bytes.withUnsafeBufferPointer { p in
            key.append(contentsOf: UnsafeBufferPointer(start: p.baseAddress, count: n))
        }
    }
}

/// Reusable storage for the four per-level buffers (lives in ScratchBuffers; writeSortKeyUpToQuaternary borrows and returns it).
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

    /// Map from strength to the level-flag set to write (CASE_LEVEL is independent; IDENTICAL_LEVEL is written separately).
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

    /// Writes the sort key for levels up to the strength in `options` (without identical level and without the 00 terminator). (CollationKeys::writeSortKeyUpToQuaternary.)
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

        // Borrow the reusable level buffers by swapping (not copying, so the appends below never copy-on-write); swapped back, grown, at the end.
        var cases = SortKeyLevel()
        var secondaries = SortKeyLevel()
        var tertiaries = SortKeyLevel()
        var quaternaries = SortKeyLevel()
        swap(&cases, &buffers.cases)
        swap(&secondaries, &buffers.secondaries)
        swap(&tertiaries, &buffers.tertiaries)
        swap(&quaternaries, &buffers.quaternaries)
        // isEmpty guards: removeAll on a never-used array hits the shared empty-singleton storage and takes the copy-on-write slow path.
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

        // Batch primary bytes: accumulate into a fixed stack buffer and flush to `key` periodically. Converts many individual append() calls (each with an Array growth check) into fewer bulk copies.
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
                // Variable CE, shift it to quaternary level. Ignore all following primary ignorables, and shift further variable CEs.
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
                            // Prevent shifted primary lead bytes from overlapping with the common compression range.
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
            // ce could be primary ignorable, or NO_CE, or the merge separator, or a regular primary CE, but it is not variable. If ce==NO_CE, then write nothing for the primary level but terminate compression on all levels and then exit the loop.
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
                    // Backwards secondary: weights are appended byte-reversed; each merge-separated segment is reversed at its end.
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
                            // lowerFirst: Compress common weights to nibbles 1..7..13, mixed=14, upper=15. If there are only common (=lowest) weights in the whole level, then we need not write anything.
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
                    // Tertiary weights without case bits. Move lead bytes 06..3F to C6..FF for a large common-weight range.
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
                    // Tertiary weights with caseFirst=lowerFirst. Move lead bytes 06..BF to 46..FF for the common-weight range.
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
                    // If alternate=non-ignorable and there are only common quaternary weights, then we need not write anything.
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

    // MARK: Direct multi-pass writer

    /// 64-byte stack batch: turns per-byte Array appends into pointer stores with bulk flushes — the idiom the primary level has always used, generalized to every level pass.
    private struct ByteBatch {
        var storage = (
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
        )
        var count = 0

        @inline(__always)
        mutating func put(_ b: UInt8, _ key: inout [UInt8]) {
            withUnsafeMutablePointer(to: &storage.0) { $0[count] = b }
            count += 1
            if count >= 58 { flush(&key) }
        }

        @inline(__always)
        mutating func putWeight16(_ w: UInt32, _ key: inout [UInt8]) {
            put(UInt8(truncatingIfNeeded: w >> 8), &key)
            let b1 = UInt8(truncatingIfNeeded: w)
            if b1 != 0 { put(b1, &key) }
        }

        @inline(__always)
        mutating func putWeight32(_ w: UInt32, _ key: inout [UInt8]) {
            put(UInt8(truncatingIfNeeded: w >> 24), &key)
            let b1 = UInt8(truncatingIfNeeded: w >> 16)
            if b1 != 0 {
                put(b1, &key)
                let b2 = UInt8(truncatingIfNeeded: w >> 8)
                if b2 != 0 {
                    put(b2, &key)
                    let b3 = UInt8(truncatingIfNeeded: w)
                    if b3 != 0 { put(b3, &key) }
                }
            }
        }

        @inline(__always)
        mutating func flush(_ key: inout [UInt8]) {
            if count > 0 {
                withUnsafePointer(to: &storage.0) {
                    key.append(contentsOf: UnsafeBufferPointer(start: $0, count: count))
                }
                count = 0
            }
        }
    }

    /// Consumes a variable CE and everything it drags down (further variable CEs and their trailing primary ignorables) exactly as the buffered writer's variable block does, WITHOUT emitting anything. Every non-quaternary pass uses this to keep its CE cursor in lockstep. On return, `ce`/`p` hold the first non-variable CE.
    @inline(__always)
    private static func skipVariable(
        _ ces: borrowing [Int64], _ cesIndex: inout Int,
        _ ce: inout Int64, _ p: inout UInt32, variableTop: UInt32
    ) {
        repeat {
            repeat {
                ce = ces[cesIndex]
                cesIndex += 1
                p = UInt32(truncatingIfNeeded: ce >> 32)
            } while p == 0
        } while p < variableTop && p > CollationConstants.mergeSeparatorPrimary
    }

    /// Flushes a run of common weights into the batch using the standard compression pattern: emit full maxCount runs as middle bytes, then emit the directional boundary byte (low + remainder for weights below common, high - remainder for weights above).
    @inline(__always)
    private static func flushCommon(
        _ count: inout Int, weight: UInt32, threshold: UInt32,
        low: UInt32, middle: UInt32, high: UInt32, maxCount: Int,
        batch: inout ByteBatch, key: inout [UInt8]
    ) {
        count -= 1
        while count >= maxCount {
            batch.put(UInt8(truncatingIfNeeded: middle), &key)
            count -= maxCount
        }
        let b: UInt32 = weight < threshold
            ? low + UInt32(count)
            : high - UInt32(count)
        batch.put(UInt8(truncatingIfNeeded: b), &key)
        count = 0
    }

    /// Primary level, written directly (same emission as the buffered writer's primary block — that one was already direct since the primary-byte batching round).
    private static func writePrimaryDirect(
        _ ces: borrowing [Int64], compressibleBytes: UnsafeBufferPointer<Bool>,
        variableTop: UInt32, reordering: Reordering?, into key: inout [UInt8]
    ) {
        var batch = ByteBatch()
        var prevReorderedPrimary: UInt32 = 0
        var cesIndex = 0
        while true {
            var ce = ces[cesIndex]
            cesIndex += 1
            var p = UInt32(truncatingIfNeeded: ce >> 32)
            if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                skipVariable(ces, &cesIndex, &ce, &p, variableTop: variableTop)
            }
            if p > CollationConstants.noCEPrimary {
                let isCompressible = compressibleBytes[Int(p >> 24)]
                if let reordering { p = reordering.reorder(p) }
                let p1 = p >> 24
                if !isCompressible || p1 != (prevReorderedPrimary >> 24) {
                    if prevReorderedPrimary != 0 {
                        if p < prevReorderedPrimary {
                            if p1 > UInt32(CollationConstants.mergeSeparatorPrimary >> 24) {
                                batch.put(3, &key)
                            }
                        } else {
                            batch.put(0xff, &key)
                        }
                    }
                    batch.put(UInt8(truncatingIfNeeded: p1), &key)
                    prevReorderedPrimary = isCompressible ? p : 0
                }
                let p2 = UInt8(truncatingIfNeeded: p >> 16)
                if p2 != 0 {
                    batch.put(p2, &key)
                    let p3 = UInt8(truncatingIfNeeded: p >> 8)
                    if p3 != 0 {
                        batch.put(p3, &key)
                        let p4 = UInt8(truncatingIfNeeded: p)
                        if p4 != 0 { batch.put(p4, &key) }
                    }
                }
            }
            let lower32 = UInt32(truncatingIfNeeded: ce)
            if lower32 == 0 { continue }
            if (lower32 >> 24) == UInt32(levelSeparator) { break }
        }
        batch.flush(&key)
    }

    /// Secondary level, forward mode. The buffered writer's trailing 01 (from NO_CE, dropped by appendTo) is simply never emitted here: at NO_CE the common-run flush still runs (same direction — the NO_CE weight 0x0100 is below common), then the pass ends.
    private static func writeSecondaryDirect(
        _ ces: borrowing [Int64], variableTop: UInt32, into key: inout [UInt8]
    ) {
        var batch = ByteBatch()
        var commonSecondaries = 0
        var cesIndex = 0
        while true {
            var ce = ces[cesIndex]
            cesIndex += 1
            var p = UInt32(truncatingIfNeeded: ce >> 32)
            if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                skipVariable(ces, &cesIndex, &ce, &p, variableTop: variableTop)
            }
            let lower32 = UInt32(truncatingIfNeeded: ce)
            if lower32 == 0 { continue }
            let isNoCE = (lower32 >> 24) == UInt32(levelSeparator)
            let s = lower32 >> 16
            if s == 0 {
                // secondary ignorable
            } else if s == 0x0500 && !isNoCE {
                commonSecondaries += 1
            } else {
                if commonSecondaries != 0 {
                    flushCommon(&commonSecondaries, weight: s, threshold: 0x0500,
                               low: secCommonLow, middle: secCommonMiddle, high: secCommonHigh,
                               maxCount: secCommonMaxCount, batch: &batch, key: &key)
                }
                if isNoCE { break }
                batch.putWeight16(s, &key)
            }
            if isNoCE { break }
        }
        batch.flush(&key)
    }

    /// Secondary level, backwards (French) mode: written per byte straight into the key, with merge-separated segments reversed IN PLACE in the key — the level buffer becomes unnecessary. Rare path; not batched.
    private static func writeSecondaryBackwardDirect(
        _ ces: borrowing [Int64], variableTop: UInt32, into key: inout [UInt8]
    ) {
        var commonSecondaries = 0
        var prevSecondary: UInt32 = 0
        var secSegmentStart = key.count
        var cesIndex = 0
        while true {
            var ce = ces[cesIndex]
            cesIndex += 1
            var p = UInt32(truncatingIfNeeded: ce >> 32)
            if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                skipVariable(ces, &cesIndex, &ce, &p, variableTop: variableTop)
            }
            let lower32 = UInt32(truncatingIfNeeded: ce)
            if lower32 == 0 { continue }
            let isNoCE = (lower32 >> 24) == UInt32(levelSeparator)
            let s = lower32 >> 16
            if s == 0 {
                // secondary ignorable
            } else if s == 0x0500 && p != CollationConstants.mergeSeparatorPrimary {
                commonSecondaries += 1
            } else {
                if commonSecondaries != 0 {
                    commonSecondaries -= 1
                    let remainder = commonSecondaries % secCommonMaxCount
                    let b: UInt32 = prevSecondary < 0x0500
                        ? secCommonLow + UInt32(remainder)
                        : secCommonHigh - UInt32(remainder)
                    key.append(UInt8(truncatingIfNeeded: b))
                    commonSecondaries -= remainder
                    while commonSecondaries > 0 {
                        key.append(UInt8(truncatingIfNeeded: secCommonMiddle))
                        commonSecondaries -= secCommonMaxCount
                    }
                }
                if p > 0 && p <= CollationConstants.mergeSeparatorPrimary {
                    // The merge separator or NO_CE: reverse the segment.
                    if secSegmentStart < key.count - 1 {
                        key[secSegmentStart...].reverse()
                    }
                    if isNoCE { break }
                    key.append(UInt8(CollationConstants.mergeSeparatorPrimary >> 24))
                    prevSecondary = 0
                    secSegmentStart = key.count
                } else {
                    // Append the weight byte-reversed; re-reversed above.
                    let b0 = UInt8(truncatingIfNeeded: s >> 8)
                    let b1 = UInt8(truncatingIfNeeded: s)
                    if b1 == 0 {
                        key.append(b0)
                    } else {
                        key.append(b1)
                        key.append(b0)
                    }
                    prevSecondary = s
                }
            }
            if isNoCE { break }
        }
    }

    /// Case level, with the nibble pairing done inline (the buffered writer packed nibbles during assembly).
    private static func writeCaseDirect(
        _ ces: borrowing [Int64], options: Int32, variableTop: UInt32,
        into key: inout [UInt8]
    ) {
        let strengthIsPrimary =
            CollationOptions.strength(of: options) == CollationOptions.Strength.primary.rawValue
        let upperFirst = (options & CollationOptions.Bits.upperFirst) != 0
        var commonCases = 0
        var pendingNibble: UInt8 = 0
        var emitted = false
        var cesIndex = 0

        @inline(__always)
        func packCaseByte(_ c: UInt8, _ key: inout [UInt8]) {
            if pendingNibble == 0 {
                pendingNibble = c
            } else {
                key.append(pendingNibble | (c >> 4))
                pendingNibble = 0
            }
            emitted = true
        }

        while true {
            var ce = ces[cesIndex]
            cesIndex += 1
            var p = UInt32(truncatingIfNeeded: ce >> 32)
            if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                skipVariable(ces, &cesIndex, &ce, &p, variableTop: variableTop)
            }
            let lower32 = UInt32(truncatingIfNeeded: ce)
            if lower32 == 0 { continue }
            let isNoCE = (lower32 >> 24) == UInt32(levelSeparator)
            let ignore: Bool = strengthIsPrimary ? p == 0 : lower32 <= 0xffff
            if !ignore {
                var c = (lower32 >> 8) & 0xff
                assert((c & 0xc0) != 0xc0)
                if (c & 0xc0) == 0 && c > UInt32(levelSeparator) {
                    commonCases += 1
                } else {
                    if !upperFirst {
                        if commonCases != 0 && (c > UInt32(levelSeparator) || emitted) {
                            commonCases -= 1
                            while commonCases >= caseLowerFirstCommonMaxCount {
                                packCaseByte(UInt8(truncatingIfNeeded: caseLowerFirstCommonMiddle << 4), &key)
                                commonCases -= caseLowerFirstCommonMaxCount
                            }
                            let b: UInt32 = c <= UInt32(levelSeparator)
                                ? caseLowerFirstCommonLow + UInt32(commonCases)
                                : caseLowerFirstCommonHigh - UInt32(commonCases)
                            packCaseByte(UInt8(truncatingIfNeeded: b << 4), &key)
                            commonCases = 0
                        }
                        if c > UInt32(levelSeparator) {
                            c = (caseLowerFirstCommonHigh + (c >> 6)) << 4
                        }
                    } else {
                        if commonCases != 0 {
                            commonCases -= 1
                            while commonCases >= caseUpperFirstCommonMaxCount {
                                packCaseByte(UInt8(truncatingIfNeeded: caseUpperFirstCommonLow << 4), &key)
                                commonCases -= caseUpperFirstCommonMaxCount
                            }
                            packCaseByte(UInt8(truncatingIfNeeded: (caseUpperFirstCommonLow + UInt32(commonCases)) << 4), &key)
                            commonCases = 0
                        }
                        if c > UInt32(levelSeparator) {
                            c = (caseUpperFirstCommonLow - (c >> 6)) << 4
                        }
                    }
                    // The buffered writer appends the NO_CE's separator byte here and drops it during nibble packing — skip it.
                    if !isNoCE {
                        packCaseByte(UInt8(truncatingIfNeeded: c), &key)
                    }
                }
            }
            if isNoCE { break }
        }
        if pendingNibble != 0 { key.append(pendingNibble) }
    }

    /// Tertiary level. Same trailing-01 rule as the secondary pass.
    private static func writeTertiaryDirect(
        _ ces: borrowing [Int64], options: Int32, tertiaryMask: UInt32,
        variableTop: UInt32, into key: inout [UInt8]
    ) {
        let upperFirst = (options & CollationOptions.Bits.upperFirst) != 0
        var batch = ByteBatch()
        var commonTertiaries = 0
        var cesIndex = 0
        while true {
            var ce = ces[cesIndex]
            cesIndex += 1
            var p = UInt32(truncatingIfNeeded: ce >> 32)
            if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                skipVariable(ces, &cesIndex, &ce, &p, variableTop: variableTop)
            }
            let lower32 = UInt32(truncatingIfNeeded: ce)
            if lower32 == 0 { continue }
            let isNoCE = (lower32 >> 24) == UInt32(levelSeparator)
            var t = lower32 & tertiaryMask
            assert((lower32 & 0xc000) != 0xc000)
            if t == 0x0500 {
                commonTertiaries += 1
            } else if (tertiaryMask & 0x8000) == 0 {
                if commonTertiaries != 0 {
                    flushCommon(&commonTertiaries, weight: t, threshold: 0x0500,
                               low: terOnlyCommonLow, middle: terOnlyCommonMiddle, high: terOnlyCommonHigh,
                               maxCount: terOnlyCommonMaxCount, batch: &batch, key: &key)
                }
                if isNoCE { break }
                if t > 0x0500 { t += 0xc000 }
                batch.putWeight16(t, &key)
            } else if !upperFirst {
                if commonTertiaries != 0 {
                    flushCommon(&commonTertiaries, weight: t, threshold: 0x0500,
                               low: terLowerFirstCommonLow, middle: terLowerFirstCommonMiddle, high: terLowerFirstCommonHigh,
                               maxCount: terLowerFirstCommonMaxCount, batch: &batch, key: &key)
                }
                if isNoCE { break }
                if t > 0x0500 { t += 0x4000 }
                batch.putWeight16(t, &key)
            } else {
                if t <= CollationConstants.noCEWeight16 {
                    // Keep separators unchanged.
                } else if lower32 > 0xffff {
                    t ^= 0xc000
                    if t < (terUpperFirstCommonHigh << 8) {
                        t &-= 0x4000
                    }
                } else {
                    assert(0x8600 <= t && t <= 0xbfff)
                    t += 0x4000
                }
                if commonTertiaries != 0 {
                    flushCommon(&commonTertiaries, weight: t, threshold: terUpperFirstCommonLow << 8,
                               low: terUpperFirstCommonLow, middle: terUpperFirstCommonMiddle, high: terUpperFirstCommonHigh,
                               maxCount: terUpperFirstCommonMaxCount, batch: &batch, key: &key)
                }
                if isNoCE { break }
                batch.putWeight16(t, &key)
            }
            if isNoCE { break }
        }
        batch.flush(&key)
    }

    /// Quaternary level — the one pass where the variable-CE block EMITS (shifted primaries land here).
    private static func writeQuaternaryDirect(
        _ ces: borrowing [Int64], options: Int32, variableTop: UInt32,
        reordering: Reordering?, into key: inout [UInt8]
    ) {
        let alternateOff = (options & CollationOptions.Bits.alternateMask) == 0
        var batch = ByteBatch()
        var commonQuaternaries = 0
        var emitted = false
        var cesIndex = 0
        while true {
            var ce = ces[cesIndex]
            cesIndex += 1
            var p = UInt32(truncatingIfNeeded: ce >> 32)
            if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                if commonQuaternaries != 0 {
                    commonQuaternaries -= 1
                    while commonQuaternaries >= quatCommonMaxCount {
                        batch.put(UInt8(truncatingIfNeeded: quatCommonMiddle), &key)
                        commonQuaternaries -= quatCommonMaxCount
                    }
                    batch.put(UInt8(truncatingIfNeeded: quatCommonLow + UInt32(commonQuaternaries)), &key)
                    commonQuaternaries = 0
                    emitted = true
                }
                repeat {
                    if let reordering { p = reordering.reorder(p) }
                    if (p >> 24) >= quatShiftedLimitByte {
                        batch.put(UInt8(truncatingIfNeeded: quatShiftedLimitByte), &key)
                    }
                    batch.putWeight32(p, &key)
                    emitted = true
                    repeat {
                        ce = ces[cesIndex]
                        cesIndex += 1
                        p = UInt32(truncatingIfNeeded: ce >> 32)
                    } while p == 0
                } while p < variableTop && p > CollationConstants.mergeSeparatorPrimary
            }
            let lower32 = UInt32(truncatingIfNeeded: ce)
            if lower32 == 0 { continue }
            let isNoCE = (lower32 >> 24) == UInt32(levelSeparator)
            var q = lower32 & 0xffff
            if (q & 0xc0) == 0 && q > CollationConstants.noCEWeight16 {
                commonQuaternaries += 1
            } else if q == CollationConstants.noCEWeight16 && alternateOff && !emitted {
                // Only common quaternary weights in the whole level: the buffered writer appends the lone separator that appendTo then drops — emit nothing.
            } else {
                if q == CollationConstants.noCEWeight16 {
                    q = UInt32(levelSeparator)
                } else {
                    q = 0xfc + ((q >> 6) & 3)
                }
                if commonQuaternaries != 0 {
                    flushCommon(&commonQuaternaries, weight: q, threshold: quatCommonLow,
                               low: quatCommonLow, middle: quatCommonMiddle, high: quatCommonHigh,
                               maxCount: quatCommonMaxCount, batch: &batch, key: &key)
                }
                if !isNoCE {
                    batch.put(UInt8(truncatingIfNeeded: q), &key)
                    emitted = true
                }
            }
            if isNoCE { break }
        }
        batch.flush(&key)
    }

    /// Writes the sort key for levels up to the strength in `options` — byte-identical output to `writeSortKeyUpToQuaternary`, produced by one direct pass per level with NO intermediate level buffers and no assembly copies. The CE array is small and cache-hot; re-scanning it per level is cheaper than buffering every level's bytes twice.
    static func writeSortKeyUpToQuaternaryDirect(
        ces: borrowing [Int64], compressibleBytes: UnsafeBufferPointer<Bool>,
        options: Int32, variableTopValue: UInt32, reordering: Reordering? = nil,
        into key: inout [UInt8]
    ) {
        var levels = levelFlags(strength: CollationOptions.strength(of: options))
        if (options & CollationOptions.Bits.caseLevel) != 0 {
            levels |= caseFlag
        }
        let variableTop: UInt32
        if (options & CollationOptions.Bits.alternateMask) == 0 {
            variableTop = 0
        } else {
            variableTop = variableTopValue + 1
        }
        let tertiaryMask = CollationOptions.tertiaryMask(of: options)

        // No withUnsafeBufferPointer closure here: that call-site shape blocks WMO inlining of the writer chain and costs paths sortKey ~+8% (measured independently on two occasions); borrowing-array passes compile clean.
        writePrimaryDirect(
            ces, compressibleBytes: compressibleBytes,
            variableTop: variableTop, reordering: reordering, into: &key)
        if (levels & secondaryFlag) != 0 {
            key.append(levelSeparator)
            if (options & CollationOptions.Bits.backwardSecondary) == 0 {
                writeSecondaryDirect(ces, variableTop: variableTop, into: &key)
            } else {
                writeSecondaryBackwardDirect(ces, variableTop: variableTop, into: &key)
            }
        }
        if (levels & caseFlag) != 0 {
            key.append(levelSeparator)
            writeCaseDirect(ces, options: options, variableTop: variableTop, into: &key)
        }
        if (levels & tertiaryFlag) != 0 {
            key.append(levelSeparator)
            writeTertiaryDirect(
                ces, options: options, tertiaryMask: tertiaryMask,
                variableTop: variableTop, into: &key)
        }
        if (levels & quaternaryFlag) != 0 {
            key.append(levelSeparator)
            writeQuaternaryDirect(
                ces, options: options, variableTop: variableTop,
                reordering: reordering, into: &key)
        }
    }

    // MARK: Single-pass writer with in-region level buffers

    /// One level's bytes, carved out of the single-pass writer's temporary region: a base pointer plus a count, so an append is a plain store with no uniqueness check, no growth check and no ARC. ICU's SortKeyLevel is a `MaybeStackArray<uint8_t, 40>` per level — the same idea with one allocation instead of four.
    private struct RegionLevel {
        let base: UnsafeMutablePointer<UInt8>
        let capacity: Int
        var count = 0

        @inline(__always)
        init(_ base: UnsafeMutablePointer<UInt8>, _ capacity: Int) {
            self.base = base
            self.capacity = capacity
        }

        var isEmpty: Bool { count == 0 }

        @inline(__always)
        mutating func appendByte(_ b: UInt32) {
            assert(count < capacity, "level buffer overflow — the per-CE byte bound is wrong")
            base[count] = UInt8(truncatingIfNeeded: b)
            count += 1
        }

        /// Appends the non-zero bytes of a 16-bit weight.
        @inline(__always)
        mutating func appendWeight16(_ w: UInt32) {
            assert((w & 0xffff) != 0)
            appendByte(w >> 8)
            let b1 = UInt8(truncatingIfNeeded: w)
            if b1 != 0 { appendByte(UInt32(b1)) }
        }

        /// Appends the non-zero prefix of a 32-bit weight.
        @inline(__always)
        mutating func appendWeight32(_ w: UInt32) {
            assert(w != 0)
            appendByte(w >> 24)
            let b1 = UInt8(truncatingIfNeeded: w >> 16)
            if b1 != 0 {
                appendByte(UInt32(b1))
                let b2 = UInt8(truncatingIfNeeded: w >> 8)
                if b2 != 0 {
                    appendByte(UInt32(b2))
                    let b3 = UInt8(truncatingIfNeeded: w)
                    if b3 != 0 { appendByte(UInt32(b3)) }
                }
            }
        }

        /// Appends a 16-bit weight byte-reversed (for the backwards-secondary level, which is re-reversed segment-wise later).
        @inline(__always)
        mutating func appendReverseWeight16(_ w: UInt32) {
            assert((w & 0xffff) != 0)
            let b0 = UInt8(truncatingIfNeeded: w >> 8)
            let b1 = UInt8(truncatingIfNeeded: w)
            if b1 == 0 {
                appendByte(UInt32(b0))
            } else {
                appendByte(UInt32(b1))
                appendByte(UInt32(b0))
            }
        }

        /// Reverses the bytes from `from` to the end (one merge-separated backwards-secondary segment).
        func reverse(from: Int) {
            var i = from
            var j = count - 1
            while i < j {
                let t = base[i]
                base[i] = base[j]
                base[j] = t
                i += 1
                j -= 1
            }
        }

        /// Appends all but the last byte (the trailing 01 from NO_CE) to the key.
        func appendTo(_ key: inout [UInt8]) {
            assert(count > 0 && base[count - 1] == 1)
            let n = count - 1
            if n <= 0 { return }  // level compressed to nothing — skip the copy entirely
            key.append(contentsOf: UnsafeBufferPointer(start: base, count: n))
        }
    }

    // Worst-case bytes one consumed CE can contribute to each level, used to size the single-pass region. Per level: the primary block emits at most one separator byte (03 or ff) plus p1..p4; the secondary and tertiary levels at most a two-byte weight; the case level at most one nibble byte; the quaternary level at most a limit byte plus a four-byte shifted primary. The common-weight flushes need no extra room: a CE that only increments a run counter emits nothing, every flush zeroes its counter, and a flush of k counted CEs emits 1 + (k-1)/maxCount bytes with maxCount >= 7 — so one byte per counted CE covers every flush in the level. Each constant is therefore (weight bytes + 1); the loop asserts against it in debug builds.
    private static let primaryBytesPerCE = 6
    private static let secondaryBytesPerCE = 3
    private static let caseBytesPerCE = 3
    private static let tertiaryBytesPerCE = 3
    private static let quaternaryBytesPerCE = 6

    /// Writes the sort key for levels up to the strength in `options` — byte-identical output to `writeSortKeyUpToQuaternary` and to `writeSortKeyUpToQuaternaryDirect`, produced in ONE traversal of the CE array with the beyond-primary levels accumulated in slices of a single temporary region (stack-allocated at the sizes real strings produce, heap above that — ICU's MaybeStackArray shape).
    ///
    /// This is the third point in the writer design space: the buffered writer is single-pass with heap level buffers, the direct writer is multi-pass with none, and this one is single-pass with region level buffers. At the default tertiary strength the direct writer traverses the CE array three times and re-runs the variable-CE skip on each pass; this traverses once. Nothing is fused with CE production — the CE array is still materialized first (that fusion is rejected, technique log §15).
    static func writeSortKeyUpToQuaternarySingle(
        ces: borrowing [Int64], compressibleBytes: UnsafeBufferPointer<Bool>,
        options: Int32, variableTopValue: UInt32, reordering: Reordering? = nil,
        into key: inout [UInt8]
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
        let strengthIsPrimary =
            CollationOptions.strength(of: options) == CollationOptions.Strength.primary.rawValue
        let backwardSecondary = (options & CollationOptions.Bits.backwardSecondary) != 0
        let upperFirst = (options & CollationOptions.Bits.upperFirst) != 0

        let n = ces.count
        let capPrimaries = primaryBytesPerCE * n
        let capSecondaries = (levels & secondaryFlag) != 0 ? secondaryBytesPerCE * n : 0
        let capCases = (levels & caseFlag) != 0 ? caseBytesPerCE * n : 0
        let capTertiaries = (levels & tertiaryFlag) != 0 ? tertiaryBytesPerCE * n : 0
        let capQuaternaries = (levels & quaternaryFlag) != 0 ? quaternaryBytesPerCE * n : 0

        withUnsafeTemporaryAllocation(
            of: UInt8.self,
            capacity: capPrimaries + capSecondaries + capCases + capTertiaries + capQuaternaries
        ) { region in
            let start = region.baseAddress.unsafelyUnwrapped
            var primaries = RegionLevel(start, capPrimaries)
            var secondaries = RegionLevel(start + capPrimaries, capSecondaries)
            var cases = RegionLevel(start + capPrimaries + capSecondaries, capCases)
            var tertiaries = RegionLevel(
                start + capPrimaries + capSecondaries + capCases, capTertiaries)
            var quaternaries = RegionLevel(
                start + capPrimaries + capSecondaries + capCases + capTertiaries, capQuaternaries)

            var prevReorderedPrimary: UInt32 = 0  // 0==no compression
            var commonCases = 0
            var commonSecondaries = 0
            var commonTertiaries = 0
            var commonQuaternaries = 0

            var prevSecondary: UInt32 = 0
            var secSegmentStart = 0

            var cesIndex = 0
            while true {
                var ce = ces[cesIndex]
                cesIndex += 1
                var p = UInt32(truncatingIfNeeded: ce >> 32)
                if p < variableTop && p > CollationConstants.mergeSeparatorPrimary {
                    // Variable CE, shift it to quaternary level. Ignore all following primary ignorables, and shift further variable CEs.
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
                                // Prevent shifted primary lead bytes from overlapping with the common compression range.
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
                // ce could be primary ignorable, or NO_CE, or the merge separator, or a regular primary CE, but it is not variable. If ce==NO_CE, then write nothing for the primary level but terminate compression on all levels and then exit the loop.
                if p > CollationConstants.noCEPrimary && (levels & primaryFlag) != 0 {
                    // Test the un-reordered primary for compressibility.
                    let isCompressible = compressibleBytes[Int(p >> 24)]
                    if let reordering { p = reordering.reorder(p) }
                    let p1 = p >> 24
                    if !isCompressible || p1 != (prevReorderedPrimary >> 24) {
                        if prevReorderedPrimary != 0 {
                            if p < prevReorderedPrimary {
                                if p1 > UInt32(CollationConstants.mergeSeparatorPrimary >> 24) {
                                    primaries.appendByte(3)
                                }
                            } else {
                                primaries.appendByte(0xff)
                            }
                        }
                        primaries.appendByte(p1)
                        prevReorderedPrimary = isCompressible ? p : 0
                    }
                    let p2 = UInt8(truncatingIfNeeded: p >> 16)
                    if p2 != 0 {
                        primaries.appendByte(UInt32(p2))
                        let p3 = UInt8(truncatingIfNeeded: p >> 8)
                        if p3 != 0 {
                            primaries.appendByte(UInt32(p3))
                            let p4 = UInt8(truncatingIfNeeded: p)
                            if p4 != 0 { primaries.appendByte(UInt32(p4)) }
                        }
                    }
                }

                let lower32 = UInt32(truncatingIfNeeded: ce)
                if lower32 == 0 { continue }  // completely ignorable

                if (levels & secondaryFlag) != 0 {
                    let s = lower32 >> 16
                    if s == 0 {
                        // secondary ignorable
                    } else if s == 0x0500  // COMMON_WEIGHT16
                        && (!backwardSecondary || p != CollationConstants.mergeSeparatorPrimary) {
                        commonSecondaries += 1
                    } else if !backwardSecondary {
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
                        // Backwards secondary: weights are appended byte-reversed; each merge-separated segment is reversed at its end.
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
                            if secSegmentStart < secondaries.count - 1 {
                                secondaries.reverse(from: secSegmentStart)
                            }
                            secondaries.appendByte(
                                p == CollationConstants.noCEPrimary
                                    ? UInt32(levelSeparator) : UInt32(CollationConstants.mergeSeparatorPrimary >> 24))
                            prevSecondary = 0
                            secSegmentStart = secondaries.count
                        } else {
                            secondaries.appendReverseWeight16(s)
                            prevSecondary = s
                        }
                    }
                }

                if (levels & caseFlag) != 0 {
                    let ignore: Bool = strengthIsPrimary ? p == 0 : lower32 <= 0xffff
                    if !ignore {
                        var c = (lower32 >> 8) & 0xff  // case bits & tertiary lead byte
                        assert((c & 0xc0) != 0xc0)
                        if (c & 0xc0) == 0 && c > UInt32(levelSeparator) {
                            commonCases += 1
                        } else {
                            if !upperFirst {
                                // lowerFirst: Compress common weights to nibbles 1..7..13, mixed=14, upper=15. If there are only common (=lowest) weights in the whole level, then we need not write anything.
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
                        // Tertiary weights without case bits. Move lead bytes 06..3F to C6..FF for a large common-weight range.
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
                    } else if !upperFirst {
                        // Tertiary weights with caseFirst=lowerFirst. Move lead bytes 06..BF to 46..FF for the common-weight range.
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
                        // Tertiary weights with caseFirst=upperFirst. (Byte mapping table in the buffered writer.)
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
                        // If alternate=non-ignorable and there are only common quaternary weights, then we need not write anything.
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

            // Assemble: the primary level has no trailing separator to drop, the others do (the NO_CE iteration wrote one into each).
            if primaries.count > 0 {
                key.append(contentsOf: UnsafeBufferPointer(start: start, count: primaries.count))
            }
            if (levels & secondaryFlag) != 0 {
                key.append(levelSeparator)
                secondaries.appendTo(&key)
            }
            if (levels & caseFlag) != 0 {
                key.append(levelSeparator)
                // Write pairs of nibbles as bytes, except separator bytes as themselves.
                var b: UInt8 = 0
                var i = 0
                let last = cases.count - 1  // ignore the trailing NO_CE
                while i < last {
                    let c = cases.base[i]
                    assert((c & 0xf) == 0 && c != 0)
                    if b == 0 {
                        b = c
                    } else {
                        key.append(b | (c >> 4))
                        b = 0
                    }
                    i += 1
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
        }
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
