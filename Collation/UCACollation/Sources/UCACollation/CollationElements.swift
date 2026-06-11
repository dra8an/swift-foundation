// Produces the full 64-bit collation elements of a string, reading scalars
// through the incremental-NFD front end. CE32 tag dispatch mirrors
// CollationIterator::appendCEsFromCE32; contraction matching (including
// discontiguous contractions per UTS #10 S2.1) mirrors
// nextCE32FromContraction/nextCE32FromDiscontiguousContraction; prefix
// matching mirrors getCE32FromPrefix; numeric collation (CODAN) mirrors
// appendNumericCEs/appendNumericSegmentCEs.
//
// Because the scalar stream is already fully NFD-normalized and canonically
// ordered, ICU's FCD16 lead/trail-ccc checks reduce to plain ccc checks, and
// discontiguous matching operates on discrete combining marks exactly as
// UTS #10 S2.1 describes. UCharsTrie being a value type makes trie-state
// snapshots a struct copy (replacing ICU's SkippedState machinery).

struct CEIterator {
    let data: CollationData
    let norm: NormalizationData
    let numeric: Bool
    var scalars: NFDIterator
    var ces: [Int64] = []

    /// Normalized scalars read ahead of the current position.
    private var lookahead: [UInt32] = []
    private var lookaheadStart = 0
    /// The two most recently processed scalars (most recent first), used for
    /// prefix (precontext) matching. Sufficient for all CLDR prefixes: a
    /// single starter, or a starter followed by a kana voicing mark.
    private var prev1: UInt32?
    private var prev2: UInt32?
    /// Scalars consumed as contraction suffixes / digit runs while processing
    /// the current character; pushed into prefix history after it.
    private var consumedExtras: [UInt32] = []

    init(data: CollationData, norm: NormalizationData, numeric: Bool, scalars: String.UnicodeScalarView) {
        self.data = data
        self.norm = norm
        self.numeric = numeric
        self.scalars = NFDIterator(norm: norm, scalars: scalars)
    }

    // MARK: Lookahead buffer

    /// The normalized scalar `i` positions ahead (0 = next), or nil at the end.
    private mutating func scalarAhead(_ i: Int) -> UInt32? {
        while lookahead.count - lookaheadStart <= i {
            guard let c = scalars.next() else { return nil }
            lookahead.append(c)
        }
        return lookahead[lookaheadStart + i]
    }

    /// Consumes `n` scalars, recording them for prefix history.
    private mutating func consumeAhead(_ n: Int) {
        for k in 0..<n {
            consumedExtras.append(lookahead[lookaheadStart + k])
        }
        discardAhead(n)
    }

    /// Consumes `n` scalars without recording history.
    private mutating func discardAhead(_ n: Int) {
        lookaheadStart += n
        if lookaheadStart > 32 {
            lookahead.removeFirst(lookaheadStart)
            lookaheadStart = 0
        }
    }

    /// Removes the scalar `i` positions ahead (UTS #10 S2.1.3 "remove C").
    private mutating func removeAhead(at i: Int) {
        lookahead.remove(at: lookaheadStart + i)
    }

    private mutating func pushHistory(_ c: UInt32) {
        prev2 = prev1
        prev1 = c
    }

    // MARK: Main loop

    /// All CEs of the string, terminated by NO_CE.
    mutating func collectAll() throws -> [Int64] {
        while let c = scalarAhead(0) {
            discardAhead(1)
            consumedExtras.removeAll(keepingCapacity: true)
            try appendCEs(c: c, ce32: data.trie.get(c), depth: 0)
            pushHistory(c)
            for extra in consumedExtras { pushHistory(extra) }
        }
        ces.append(Collation.noCE)
        return ces
    }

    private mutating func appendCEs(c: UInt32, ce32 initialCE32: UInt32, depth: Int) throws {
        // Specials never nest deeper than prefix -> contraction -> expansion
        // (plus digit/u0000 indirections) in root data.
        guard depth <= 6 else { throw RootCollator.CollationError.malformedData }
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
            case .prefix:
                ce32 = prefixCE32(ce32)
            case .contraction:
                ce32 = contractionCE32(ce32)
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

    // MARK: Prefix (precontext) matching

    /// Resolves a PREFIX_TAG CE32 by matching the preceding scalars against
    /// the prefix trie (stored last-character-first). (getCE32FromPrefix.)
    private mutating func prefixCE32(_ ce32: UInt32) -> UInt32 {
        let index = Collation.indexFromCE32(ce32)
        var result = data.readContextCE32(at: index)  // default if no prefix match
        guard let p1 = prev1 else { return result }
        var trie = UCharsTrie(units: data.contexts, offset: index + 2)
        var match = trie.firstForCodePoint(p1)
        if match.hasValue {
            result = UInt32(bitPattern: trie.getValue())
        }
        if match.hasNext, let p2 = prev2 {
            match = trie.nextForCodePoint(p2)
            if match.hasValue {
                result = UInt32(bitPattern: trie.getValue())
            }
            // Prefixes longer than two scalars do not occur in CLDR data
            // (see Docs/02-icu4x-strategy.md); deeper history is not kept.
        }
        return result
    }

    // MARK: Contraction (suffix) matching

    /// Resolves a CONTRACTION_TAG CE32 by matching following scalars against
    /// the suffix trie, including discontiguous contractions per UTS #10 S2.1.
    /// Matched scalars are consumed; marks skipped over by a discontiguous
    /// match stay in the lookahead and produce their own CEs afterwards.
    private mutating func contractionCE32(_ contractionCE32: UInt32) -> UInt32 {
        let index = Collation.indexFromCE32(contractionCE32)
        let defaultCE32 = data.readContextCE32(at: index)
        guard let first = scalarAhead(0) else { return defaultCE32 }
        if (contractionCE32 & Collation.contractNextCCC) != 0 && norm.ccc(first) == 0 {
            // Every suffix starts with a non-starter; a starter cannot match.
            return defaultCE32
        }

        // Longest contiguous match (UTS #10 S2.1 "longest initial substring S").
        var trie = UCharsTrie(units: data.contexts, offset: index + 2)
        var bestCE32 = defaultCE32
        var bestLength = 0
        var stateAfterBest = trie  // trie state after the matched part of S
        var i = 0
        var match = trie.firstForCodePoint(first)
        while match != .noMatch {
            i += 1
            if match.hasValue {
                bestCE32 = UInt32(bitPattern: trie.getValue())
                bestLength = i
                stateAfterBest = trie
            }
            guard match.hasNext, let s = scalarAhead(i) else { break }
            match = trie.nextForCodePoint(s)
        }

        // Discontiguous contractions (S2.1.1–S2.1.3): process the non-starters
        // following the match. The stream is canonically ordered, so a
        // candidate C is blocked iff some intervening mark has ccc >= ccc(C),
        // i.e. iff prevCC (the ccc of the last skipped mark) >= ccc(C).
        if (contractionCE32 & Collation.contractTrailingCCC) != 0
            // With CONTRACT_SINGLE_CP_NO_MATCH, discontiguous matching only
            // extends an existing match (ICU: sinceMatch < lookAhead).
            && ((contractionCE32 & Collation.contractSingleCpNoMatch) == 0 || bestLength > 0) {
            var matchedState = stateAfterBest
            var j = bestLength
            var prevCC: UInt8 = 0
            while let s = scalarAhead(j) {
                let cc = norm.ccc(s)
                if cc == 0 { break }  // S2.1.1: only non-starters following S
                if prevCC < cc {
                    // "If C is not blocked from S, find if S+C has a match." (S2.1.2)
                    var attempt = matchedState
                    let m = attempt.nextForCodePoint(s)
                    if m.hasValue {
                        // "If there is a match, replace S by S+C, and remove C." (S2.1.3)
                        bestCE32 = UInt32(bitPattern: attempt.getValue())
                        removeAhead(at: j)
                        matchedState = attempt
                        if !m.hasNext { break }
                        continue  // keep prevCC; the next mark shifted into j
                    }
                }
                prevCC = cc
                j += 1
            }
        }

        consumeAhead(bestLength)
        return bestCE32
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
        var count = 0
        while let c = scalarAhead(count) {
            let ce32 = data.trie.get(c)
            guard Collation.isSpecialCE32(ce32) && Collation.tagFromCE32(ce32) == .digit else { break }
            digits.append(Collation.digitFromCE32(ce32))
            count += 1
        }
        consumeAhead(count)
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
