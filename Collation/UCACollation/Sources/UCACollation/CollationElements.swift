// Produces the full 64-bit collation elements of a string, reading scalars
// through the incremental-NFD front end. CE32 tag dispatch mirrors
// CollationIterator::appendCEsFromCE32; numeric collation (CODAN) mirrors
// appendNumericCEs/appendNumericSegmentCEs.

struct CEIterator {
    let data: CollationData
    let numeric: Bool
    var scalars: NFDIterator
    /// One-scalar pushback used by digit-run collection.
    var pushedBack: UInt32?
    var ces: [Int64] = []

    init(data: CollationData, norm: NormalizationData, numeric: Bool, scalars: String.UnicodeScalarView) {
        self.data = data
        self.numeric = numeric
        self.scalars = NFDIterator(norm: norm, scalars: scalars)
    }

    private mutating func nextScalar() -> UInt32? {
        if let c = pushedBack {
            pushedBack = nil
            return c
        }
        return scalars.next()
    }

    /// All CEs of the string, terminated by NO_CE.
    mutating func collectAll() throws -> [Int64] {
        while let c = nextScalar() {
            try appendCEs(c: c, ce32: data.trie.get(c), depth: 0)
        }
        ces.append(Collation.noCE)
        return ces
    }

    private mutating func appendCEs(c: UInt32, ce32 initialCE32: UInt32, depth: Int) throws {
        // Specials never nest deeper than digit/u0000 -> expansion -> jamo in root data.
        guard depth <= 4 else { throw RootCollator.CollationError.malformedData }
        var ce32 = initialCE32
        while true {
            if !Collation.isSpecialCE32(ce32) {
                ces.append(Collation.ceFromCE32(ce32))
                return
            }
            switch Collation.tagFromCE32(ce32) {
            case .longPrimary, .longSecondary:
                ces.append(Collation.ceFromCE32(ce32))
                return
            case .latinExpansion:
                ces.append(Collation.latinCE0FromCE32(ce32))
                ces.append(Collation.latinCE1FromCE32(ce32))
                return
            case .expansion32:
                let index = Collation.indexFromCE32(ce32)
                for i in 0..<Collation.lengthFromCE32(ce32) {
                    ces.append(Collation.ceFromCE32(data.ce32s[index + i]))
                }
                return
            case .expansion:
                let index = Collation.indexFromCE32(ce32)
                for i in 0..<Collation.lengthFromCE32(ce32) {
                    ces.append(data.ces[index + i])
                }
                return
            case .prefix, .contraction:
                // Milestone 4 will match context; use the default CE32 for now.
                ce32 = data.readContextCE32(at: Collation.indexFromCE32(ce32))
            case .digit:
                if numeric {
                    try appendNumericCEs(firstCE32: ce32)
                    return
                }
                ce32 = data.ce32s[Collation.indexFromCE32(ce32)]
            case .u0000:
                ce32 = data.ce32s[0]
            case .hangul:
                // Unreachable behind the NFD front end (syllables decompose to
                // Jamo first), but kept for data completeness.
                try appendHangulCEs(syllable: c, depth: depth)
                return
            case .offset:
                let dataCE = data.ces[Collation.indexFromCE32(ce32)]
                ces.append(Collation.makeCE(Collation.threeBytePrimaryForOffsetData(c, dataCE)))
                return
            case .implicit:
                ces.append(Collation.makeCE(Collation.unassignedPrimaryFromCodePoint(c)))
                return
            case .fallback, .reserved3, .builderData, .leadSurrogate:
                throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: ce32 & 0xf)
            }
        }
    }

    private mutating func appendHangulCEs(syllable c: UInt32, depth: Int) throws {
        guard data.jamoCE32sStart >= 0, (0xac00...0xd7a3).contains(c) else {
            throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: Collation.Tag.hangul.rawValue)
        }
        let sIndex = Int(c) - 0xac00
        let jamo = data.jamoCE32sStart
        try appendCEs(c: c, ce32: data.ce32s[jamo + sIndex / 588], depth: depth + 1)
        try appendCEs(c: c, ce32: data.ce32s[jamo + 19 + (sIndex % 588) / 28], depth: depth + 1)
        let t = sIndex % 28
        if t != 0 {
            try appendCEs(c: c, ce32: data.ce32s[jamo + 19 + 21 + t - 1], depth: depth + 1)
        }
    }

    // MARK: Numeric collation (CODAN)

    /// Collects the digit run starting with `firstCE32` and appends numeric CEs.
    /// (CollationIterator::appendNumericCEs, forward direction.)
    private mutating func appendNumericCEs(firstCE32: UInt32) throws {
        var digits: [Int32] = [Collation.digitFromCE32(firstCE32)]
        while let c = nextScalar() {
            let ce32 = data.trie.get(c)
            if Collation.isSpecialCE32(ce32) && Collation.tagFromCE32(ce32) == .digit {
                digits.append(Collation.digitFromCE32(ce32))
            } else {
                pushedBack = c
                break
            }
        }
        var pos = 0
        repeat {
            // Skip leading zeros.
            while pos < digits.count - 1 && digits[pos] == 0 { pos += 1 }
            // Write a sequence of CEs for at most 254 digits at a time.
            let segmentLength = min(digits.count - pos, 254)
            appendNumericSegmentCEs(digits[pos..<(pos + segmentLength)])
            pos += segmentLength
        } while pos < digits.count
    }

    /// (CollationIterator::appendNumericSegmentCEs.)
    private mutating func appendNumericSegmentCEs(_ digitsSlice: ArraySlice<Int32>) {
        let digits = Array(digitsSlice)
        var length = digits.count
        let numericPrimary = data.numericPrimary
        // Note: We use primary byte values 2..255: digits are not compressible.
        if length <= 7 {
            // Very dense encoding for small numbers.
            var value = digits[0]
            for i in 1..<length { value = value * 10 + digits[i] }
            // Primary weight second byte values:
            //     74 byte values   2.. 75 for small numbers in two-byte primary weights.
            //     40 byte values  76..115 for medium numbers in three-byte primary weights.
            //     16 byte values 116..131 for large numbers in four-byte primary weights.
            //    124 byte values 132..255 for very large numbers with 4..127 digit pairs.
            var firstByte: Int32 = 2
            var numBytes: Int32 = 74
            if value < numBytes {
                ces.append(Collation.makeCE(numericPrimary | (UInt32(firstByte + value) << 16)))
                return
            }
            value -= numBytes
            firstByte += numBytes
            numBytes = 40
            if value < numBytes * 254 {
                let primary = numericPrimary
                    | (UInt32(firstByte + value / 254) << 16) | (UInt32(2 + value % 254) << 8)
                ces.append(Collation.makeCE(primary))
                return
            }
            value -= numBytes * 254
            firstByte += numBytes
            numBytes = 16
            if value < numBytes * 254 * 254 {
                var primary = numericPrimary | UInt32(2 + value % 254)
                value /= 254
                primary |= UInt32(2 + value % 254) << 8
                value /= 254
                primary |= UInt32(firstByte + value % 254) << 16
                ces.append(Collation.makeCE(primary))
                return
            }
            // original value > 1042489
        }

        // The second primary byte value 132..255 indicates the number of digit
        // pairs (4..127), then we generate primary bytes with those pairs.
        // Omit trailing 00 pairs. Decrement the value for the last pair.
        let numPairs = Int32((length + 1) / 2)
        var primary = numericPrimary | (UInt32(132 - 4 + numPairs) << 16)
        // Find the length without trailing 00 pairs.
        while digits[length - 1] == 0 && digits[length - 2] == 0 { length -= 2 }
        // Read the first pair.
        var pair: Int32
        var pos: Int
        if length & 1 == 1 {
            // Only "half a pair" if we have an odd number of digits.
            pair = digits[0]
            pos = 1
        } else {
            pair = digits[0] * 10 + digits[1]
            pos = 2
        }
        pair = 11 + 2 * pair
        // Add the pairs of digits between pos and length.
        var shift: Int32 = 8
        while pos < length {
            if shift == 0 {
                // Every three pairs/bytes we need to store a 4-byte-primary CE
                // and start with a new CE with the '0' primary lead byte.
                primary |= UInt32(pair)
                ces.append(Collation.makeCE(primary))
                primary = numericPrimary
                shift = 16
            } else {
                primary |= UInt32(pair) << shift
                shift -= 8
            }
            pair = 11 + 2 * (digits[pos] * 10 + digits[pos + 1])
            pos += 2
        }
        primary |= UInt32(pair - 1) << shift
        ces.append(Collation.makeCE(primary))
    }
}
