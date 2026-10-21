// Sort key generation: a single-pass writer that produces the same keys as ICU's CollationKeys::writeSortKeyUpToQuaternary (i18n/collationkeys.{h,cpp}), and the BOCSU identical-level encoder (i18n/bocsu.{h,cpp}). Two reference writers, which do not ship, live in Collation/Tools/sk-ladder/ReferenceWriters.swift.
//
// Operates on a NO_CE-terminated CE array. Script reordering hooks are omitted (milestone 7). The invariant: byte-wise comparison of two sort keys equals compare() at the same options.

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

    // MARK: Single-pass writer with in-region level buffers

    /// One level's bytes, carved out of the single-pass writer's temporary region: a base pointer plus a count, so an append is a plain store with no uniqueness check, no growth check and no ARC. ICU's SortKeyLevel is a `MaybeStackArray<uint8_t, 40>` per level — the same idea with one allocation instead of four.
    private struct RegionLevel {
        let base: UnsafeMutablePointer<UInt8>
        let capacity: Int
        /// The next free byte. A cursor, not a count: an append then needs one live value per level, not the base and the count, and the writer loop keeps five levels live at once.
        var cursor: UnsafeMutablePointer<UInt8>

        @inline(__always)
        init(_ base: UnsafeMutablePointer<UInt8>, _ capacity: Int) {
            self.base = base
            self.capacity = capacity
            self.cursor = base
        }

        var count: Int { cursor - base }
        var isEmpty: Bool { cursor == base }

        @inline(__always)
        mutating func appendByte(_ b: UInt32) {
            assert(count < capacity, "level buffer overflow — the per-CE byte bound is wrong")
            cursor.pointee = UInt8(truncatingIfNeeded: b)
            cursor += 1
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

        /// Copies this level's bytes — all but the trailing 01 from NO_CE — down to `dst`, and answers how many it wrote. `dst` must be at or below `base`; the caller guarantees that from the region's layout, so the copy runs forward without ever overwriting a byte it has still to read.
        @inline(__always)
        func compactTo(_ dst: UnsafeMutablePointer<UInt8>) -> Int {
            assert(count > 0 && base[count - 1] == 1)
            let n = count - 1
            if n <= 0 { return 0 }  // level compressed to nothing
            assert(dst <= base, "region compaction must move bytes DOWN")
            if dst != base {
                var i = 0
                while i < n {
                    dst[i] = base[i]
                    i += 1
                }
            }
            return n
        }
    }

    /// The common-run compression flush, for a level accumulating into the single-pass writer's region: emit full maxCount runs as middle bytes, then the directional boundary byte (low + remainder below the common weight, high - remainder above). The direct reference writer in the sk-ladder tool has the same helper; unifying these blocks was A/B-verified performance-neutral (technique log §46 / dcd82a5).
    @inline(__always)
    private static func flushCommon(
        _ count: inout Int, weight: UInt32, threshold: UInt32,
        low: UInt32, middle: UInt32, high: UInt32, maxCount: Int,
        level: inout RegionLevel
    ) {
        count -= 1
        while count >= maxCount {
            level.appendByte(middle)
            count -= maxCount
        }
        level.appendByte(weight < threshold ? low + UInt32(count) : high - UInt32(count))
        count = 0
    }

    // Worst-case bytes one consumed CE can contribute to each level, used to size the single-pass region. Per level: the primary block emits at most one separator byte (03 or ff) plus p1..p4; the secondary and tertiary levels at most a two-byte weight; the case level at most one nibble byte; the quaternary level at most a limit byte plus a four-byte shifted primary. The common-weight flushes need no extra room: a CE that only increments a run counter emits nothing, every flush zeroes its counter, and a flush of k counted CEs emits 1 + (k-1)/maxCount bytes with maxCount >= 7 — so one byte per counted CE covers every flush in the level. Each constant is therefore (weight bytes + 1); the loop asserts against it in debug builds.
    private static let primaryBytesPerCE = 6
    private static let secondaryBytesPerCE = 3
    private static let caseBytesPerCE = 3
    private static let tertiaryBytesPerCE = 3
    private static let quaternaryBytesPerCE = 6

    /// Writes the sort key for levels up to the strength in `options` — byte-identical to ICU's ucol_getSortKey (the key suites check that against ICU reference answers), produced in ONE traversal of the CE array with the beyond-primary levels accumulated in slices of a single temporary region (stack-allocated at the sizes real strings produce, heap above that — ICU's MaybeStackArray shape). The sk-ladder tool also checks it byte for byte against two reference writers.
    ///
    /// This is the third point in the writer design space: the buffered writer is single-pass with heap level buffers, the direct writer is multi-pass with none, and this one is single-pass with region level buffers. At the default tertiary strength the direct writer traverses the CE array three times and re-runs the variable-CE skip on each pass; this traverses once. Nothing is fused with CE production — the CE array is still materialized first (that fusion is rejected, technique log §15).
    static func writeSortKeyUpToQuaternarySingle(
        ces: borrowing CEBuffer, compressibleBytes: UnsafeBufferPointer<Bool>,
        options: Int32, variableTopValue: UInt32, reordering: Reordering? = nil,
        terminate: Bool = true, into key: inout [UInt8]
    ) {
        if reordering == nil
            && CollationOptions.strength(of: options) == CollationOptions.Strength.tertiary.rawValue
            && (options & (CollationOptions.Bits.alternateMask | CollationOptions.Bits.caseFirstAndUpperMask
                | CollationOptions.Bits.caseLevel | CollationOptions.Bits.backwardSecondary)) == 0 {
            writeSinglePass(
                ces: ces, compressibleBytes: compressibleBytes, config: DefaultSinglePassConfig(),
                terminate: terminate, into: &key)
        } else {
            writeSinglePass(
                ces: ces, compressibleBytes: compressibleBytes,
                config: RuntimeSinglePassConfig(
                    options: options, variableTopValue: variableTopValue, reordering: reordering),
                terminate: terminate, into: &key)
        }
    }

    /// The single-pass writer, generic over its option switches. The default options get a specialization in which the switches are constants, so the levels they leave unused (case, quaternary), their run counters, the variable-CE branch and the reordering do not exist in the loop, and it keeps fewer values live (technique log §51 (s)).
    private static func writeSinglePass<Config: SinglePassConfig>(
        ces: borrowing CEBuffer, compressibleBytes: UnsafeBufferPointer<Bool>,
        config: Config, terminate: Bool, into key: inout [UInt8]
    ) {
        let levels = config.levels
        let variableTop = config.variableTop
        let tertiaryMask = config.tertiaryMask
        let strengthIsPrimary = config.strengthIsPrimary
        let backwardSecondary = config.backwardSecondary
        let upperFirst = config.upperFirst
        let alternateNonIgnorable = config.alternateNonIgnorable
        let reordering = config.reordering

        let n = ces.count
        let capPrimaries = primaryBytesPerCE * n
        let capSecondaries = (levels & secondaryFlag) != 0 ? secondaryBytesPerCE * n : 0
        let capCases = (levels & caseFlag) != 0 ? caseBytesPerCE * n : 0
        let capTertiaries = (levels & tertiaryFlag) != 0 ? tertiaryBytesPerCE * n : 0
        let capQuaternaries = (levels & quaternaryFlag) != 0 ? quaternaryBytesPerCE * n : 0

        // Each level after the primary gets ONE byte of slack ahead of its data, which is where its 01 separator lands during assembly. That slack is what makes the in-place compaction provably safe: level i's data starts at sum(cap_j + 1) for j < i, and it is compacted to sum(actual_j + 1) for j < i, so the destination is always at or below the source (actual_j <= cap_j) and a forward copy per level cannot overwrite bytes it has yet to read. See the assembly block at the end of this function.
        let slack = 5  // one per level after the primary, plus the terminator
        withUnsafeTemporaryAllocation(
            of: UInt8.self,
            capacity: capPrimaries + capSecondaries + capCases + capTertiaries + capQuaternaries + slack
        ) { region in
            let start = region.baseAddress.unsafelyUnwrapped
            var primaries = RegionLevel(start, capPrimaries)
            var secondaries = RegionLevel(start + capPrimaries + 1, capSecondaries)
            var cases = RegionLevel(start + capPrimaries + capSecondaries + 2, capCases)
            var tertiaries = RegionLevel(
                start + capPrimaries + capSecondaries + capCases + 3, capTertiaries)
            var quaternaries = RegionLevel(
                start + capPrimaries + capSecondaries + capCases + capTertiaries + 4, capQuaternaries)

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
                            flushCommon(&commonSecondaries, weight: s, threshold: 0x0500,
                                        low: secCommonLow, middle: secCommonMiddle, high: secCommonHigh,
                                        maxCount: secCommonMaxCount, level: &secondaries)
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
                            flushCommon(&commonTertiaries, weight: t, threshold: 0x0500,
                                        low: terOnlyCommonLow, middle: terOnlyCommonMiddle, high: terOnlyCommonHigh,
                                        maxCount: terOnlyCommonMaxCount, level: &tertiaries)
                        }
                        if t > 0x0500 { t += 0xc000 }
                        tertiaries.appendWeight16(t)
                    } else if !upperFirst {
                        // Tertiary weights with caseFirst=lowerFirst. Move lead bytes 06..BF to 46..FF for the common-weight range.
                        if commonTertiaries != 0 {
                            flushCommon(&commonTertiaries, weight: t, threshold: 0x0500,
                                        low: terLowerFirstCommonLow, middle: terLowerFirstCommonMiddle,
                                        high: terLowerFirstCommonHigh,
                                        maxCount: terLowerFirstCommonMaxCount, level: &tertiaries)
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
                            flushCommon(&commonTertiaries, weight: t, threshold: terUpperFirstCommonLow << 8,
                                        low: terUpperFirstCommonLow, middle: terUpperFirstCommonMiddle,
                                        high: terUpperFirstCommonHigh,
                                        maxCount: terUpperFirstCommonMaxCount, level: &tertiaries)
                        }
                        tertiaries.appendWeight16(t)
                    }
                }

                if (levels & quaternaryFlag) != 0 {
                    var q = lower32 & 0xffff
                    if (q & 0xc0) == 0 && q > CollationConstants.noCEWeight16 {
                        commonQuaternaries += 1
                    } else if q == CollationConstants.noCEWeight16
                        && alternateNonIgnorable
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
                            flushCommon(&commonQuaternaries, weight: q, threshold: quatCommonLow,
                                        low: quatCommonLow, middle: quatCommonMiddle, high: quatCommonHigh,
                                        maxCount: quatCommonMaxCount, level: &quaternaries)
                        }
                        quaternaries.appendByte(q)
                    }
                }

                if (lower32 >> 24) == UInt32(levelSeparator) { break }  // ce == NO_CE
            }

            // Assemble the whole key in the region, then write it to `key` in ONE operation. The primary level already starts at the head of the region; the beyond-primary levels compact down right behind it — gaps closed, each one's trailing 01 from NO_CE dropped, separators inserted — and the terminator follows unless the caller adds an identical level. Every move is downward: level i's data begins at sum(cap_j + 1) for j < i and lands at sum(actual_j + 1), and actual_j <= cap_j, which the one byte of slack per level buys and `compactTo` asserts.
            //
            // One `replaceSubrange` replaces the old contents, where the caller's clear plus two appends plus the terminator's append each paid the general Array code and a uniqueness check (~260 instructions per short key; technique log §51).
            let tailStart = primaries.count
            var w = tailStart
            if (levels & secondaryFlag) != 0 {
                start[w] = levelSeparator
                w += 1
                w += secondaries.compactTo(start + w)
            }
            if (levels & caseFlag) != 0 {
                start[w] = levelSeparator
                w += 1
                // Pairs of nibbles pack into single bytes. Reads run ahead of writes (two inputs per output) and the destination is at or below the source, so this packs in place safely.
                var b: UInt8 = 0
                var i = 0
                let last = cases.count - 1  // ignore the trailing NO_CE
                while i < last {
                    let c = cases.base[i]
                    assert((c & 0xf) == 0 && c != 0)
                    if b == 0 {
                        b = c
                    } else {
                        assert(start + w <= cases.base + i)
                        start[w] = b | (c >> 4)
                        w += 1
                        b = 0
                    }
                    i += 1
                }
                if b != 0 {
                    start[w] = b
                    w += 1
                }
            }
            if (levels & tertiaryFlag) != 0 {
                start[w] = levelSeparator
                w += 1
                w += tertiaries.compactTo(start + w)
            }
            if (levels & quaternaryFlag) != 0 {
                start[w] = levelSeparator
                w += 1
                w += quaternaries.compactTo(start + w)
            }
            if terminate {
                start[w] = 0
                w += 1
            }
            key.replaceSubrange(key.startIndex..<key.endIndex, with: UnsafeBufferPointer(start: start, count: w))
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

/// The option switches of the single-pass writer (`CollationKeys.writeSinglePass`).
private protocol SinglePassConfig {
    var levels: UInt32 { get }
    /// 0 when alternate is non-ignorable; else the variable top + 1.
    var variableTop: UInt32 { get }
    var tertiaryMask: UInt32 { get }
    var strengthIsPrimary: Bool { get }
    var backwardSecondary: Bool { get }
    var upperFirst: Bool { get }
    var alternateNonIgnorable: Bool { get }
    var reordering: Reordering? { get }
}

extension CollationKeys {
    /// The default options: tertiary strength, no case level, non-ignorable, no backward secondary, no case-first, no reordering. Every switch is a constant.
    private struct DefaultSinglePassConfig: SinglePassConfig {
        var levels: UInt32 { 0x16 }  // primary, secondary, tertiary
        var variableTop: UInt32 { 0 }
        var tertiaryMask: UInt32 { CollationConstants.onlyTertiaryMask }
        var strengthIsPrimary: Bool { false }
        var backwardSecondary: Bool { false }
        var upperFirst: Bool { false }
        var alternateNonIgnorable: Bool { true }
        var reordering: Reordering? { nil }
    }

    /// Any other options, read from the options word at run time.
    private struct RuntimeSinglePassConfig: SinglePassConfig {
        let levels: UInt32
        let variableTop: UInt32
        let tertiaryMask: UInt32
        let strengthIsPrimary: Bool
        let backwardSecondary: Bool
        let upperFirst: Bool
        let alternateNonIgnorable: Bool
        let reordering: Reordering?

        init(options: Int32, variableTopValue: UInt32, reordering: Reordering?) {
            var levels = CollationKeys.levelFlags(strength: CollationOptions.strength(of: options))
            if (options & CollationOptions.Bits.caseLevel) != 0 {
                levels |= CollationKeys.caseFlag
            }
            self.levels = levels
            self.alternateNonIgnorable = (options & CollationOptions.Bits.alternateMask) == 0
            // +1 so that we can use "<" and primary ignorables test out early.
            self.variableTop = alternateNonIgnorable ? 0 : variableTopValue + 1
            self.tertiaryMask = CollationOptions.tertiaryMask(of: options)
            self.strengthIsPrimary =
                CollationOptions.strength(of: options) == CollationOptions.Strength.primary.rawValue
            self.backwardSecondary = (options & CollationOptions.Bits.backwardSecondary) != 0
            self.upperFirst = (options & CollationOptions.Bits.upperFirst) != 0
            self.reordering = reordering
        }
    }
}
