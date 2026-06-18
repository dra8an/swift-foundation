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
    /// The tailoring data (or root when there is no tailoring).
    let data: CollationData
    /// The base (root) data when `data` is a tailoring; lookups fall back here
    /// when the tailoring maps a character to FALLBACK_CE32.
    let base: CollationData?
    let norm: NormalizationData
    var numeric: Bool
    var scalars: NFDIterator
    /// ARC-free views used by the per-scalar dispatch (see CollationDataView).
    private let dataView: CollationDataView
    private let baseView: CollationDataView?
    /// Pre-computed CEs for ASCII (0–127). Entry is 0 for characters that
    /// need full pipeline processing (digits in numeric mode, U+0000, etc.).
    let simpleCEs: UnsafeBufferPointer<Int64>
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

    init(data: CollationData, base: CollationData? = nil, norm: NormalizationData,
         numeric: Bool, scalars: String.UnicodeScalarView,
         simpleCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0)) {
        self.data = data
        self.base = base
        self.norm = norm
        self.numeric = numeric
        self.scalars = NFDIterator(norm: norm, scalars: scalars)
        self.dataView = CollationDataView(data)
        self.baseView = base.map(CollationDataView.init)
        self.simpleCEs = simpleCEs
    }

    /// Rewinds onto a new input, keeping all buffer storage so that reuse
    /// across compares runs allocation-free. Equivalent to a fresh iterator
    /// over the same collation data, positioned after `skippingFirst` scalars.
    mutating func reset(numeric: Bool, scalars view: String.UnicodeScalarView, skippingFirst: Int = 0) {
        self.numeric = numeric
        scalars.reset(scalars: view, skippingFirst: skippingFirst)
        clearState()
    }

    /// Resets onto an already-positioned scalar iterator plus one scalar the
    /// caller has already pulled from it — see NFDIterator.reset(source:first:).
    /// Avoids rebuilding a String iterator and re-walking the skipped prefix.
    mutating func reset(numeric: Bool, source iter: String.UnicodeScalarView.Iterator, first: UInt32?) {
        self.numeric = numeric
        scalars.reset(source: iter, first: first)
        clearState()
    }

    @inline(__always)
    private mutating func clearState() {
        // isEmpty guards: see appendMore.
        if !ces.isEmpty { ces.removeAll(keepingCapacity: true) }
        if !lookahead.isEmpty { lookahead.removeAll(keepingCapacity: true) }
        lookaheadStart = 0
        prev1 = nil
        prev2 = nil
        if !consumedExtras.isEmpty { consumedExtras.removeAll(keepingCapacity: true) }
        terminated = false
    }

    /// Looks up the CE32 for a code point, falling back from the tailoring to
    /// the base data. Returns the data view that owns the resulting CE32.
    @inline(__always)
    private func lookup(_ c: UInt32) -> (d: CollationDataView, ce32: UInt32) {
        let ce32 = dataView.trie.get(c)
        if ce32 == CollationConstants.fallbackCE32, let b = baseView {
            return (b, b.trie.get(c))
        }
        return (dataView, ce32)
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

    /// True once the NO_CE terminator has been appended.
    private(set) var terminated = false

    /// All CEs of the string, terminated by NO_CE.
    mutating func collectAll() throws -> [Int64] {
        while try appendMore() {}
        return ces
    }

    /// Pops the next scalar, bypassing the lookahead buffer when it is empty
    /// (the common case — the buffer fills only during context matching).
    @inline(__always)
    private mutating func popScalar() -> UInt32? {
        if lookaheadStart < lookahead.count {
            let c = lookahead[lookaheadStart]
            discardAhead(1)
            return c
        }
        return scalars.next()
    }

    /// Appends the CEs of the next character, or the NO_CE terminator at the
    /// end of input. Returns false once terminated. Enables lazy comparison:
    /// the primary level usually decides without generating all CEs.
    @inline(__always)
    mutating func appendMore() throws -> Bool {
        guard !terminated else { return false }
        guard let c = popScalar() else {
            ces.append(CollationConstants.noCE)
            terminated = true
            return false
        }
        // Fast path: pre-computed CE for simple ASCII characters.
        if c < 128, !simpleCEs.isEmpty {
            let ce = simpleCEs[Int(c)]
            if ce != 0 {
                ces.append(ce)
                pushHistory(c)
                return true
            }
        }
        // isEmpty guards: removeAll on a never-used array hits the shared
        // empty-singleton storage, which is never uniquely referenced, and
        // takes the copy-on-write slow path every time.
        if !consumedExtras.isEmpty { consumedExtras.removeAll(keepingCapacity: true) }
        let (d, ce32) = lookup(c)
        try appendCEs(d: d, c: c, ce32: ce32, depth: 0)
        pushHistory(c)
        for extra in consumedExtras { pushHistory(extra) }
        return true
    }

    /// The CE at index `i`, generating lazily as needed. `i` must not run
    /// past the NO_CE terminator (all level loops stop at NO_CE).
    mutating func ce(at i: Int) throws -> Int64 {
        while ces.count <= i {
            if try !appendMore() { break }
        }
        return ces[i]
    }

    private mutating func appendCEs(d: CollationDataView, c: UInt32, ce32 initialCE32: UInt32, depth: Int) throws {
        // Specials never nest deeper than prefix -> contraction -> expansion
        // (plus digit/u0000 indirections) in root data.
        guard depth <= 6 else { throw RootCollator.CollationError.malformedData }
        var ce32 = initialCE32
        while true {
            if !CollationConstants.isSpecialCE32(ce32) {
                ces.append(CollationConstants.ceFromCE32(ce32))
                return
            }
            switch CollationConstants.tagFromCE32(ce32) {
            case .longPrimary, .longSecondary:
                ces.append(CollationConstants.ceFromCE32(ce32))
                return
            case .latinExpansion:
                ces.append(CollationConstants.latinCE0FromCE32(ce32))
                ces.append(CollationConstants.latinCE1FromCE32(ce32))
                return
            case .expansion32:
                let index = CollationConstants.indexFromCE32(ce32)
                for i in 0..<CollationConstants.lengthFromCE32(ce32) {
                    ces.append(CollationConstants.ceFromCE32(d.ce32s[index + i]))
                }
                return
            case .expansion:
                let index = CollationConstants.indexFromCE32(ce32)
                for i in 0..<CollationConstants.lengthFromCE32(ce32) {
                    ces.append(d.ces[index + i])
                }
                return
            case .prefix:
                ce32 = prefixCE32(d: d, ce32)
            case .contraction:
                ce32 = contractionCE32(d: d, ce32)
            case .digit:
                if numeric {
                    try appendNumericCEs(d: d, firstCE32: ce32)
                    return
                }
                ce32 = d.ce32s[CollationConstants.indexFromCE32(ce32)]
            case .u0000:
                ce32 = d.ce32s[0]
            case .hangul:
                // Unreachable behind the NFD front end (syllables decompose to
                // Jamo first), but kept for data completeness.
                try appendHangulCEs(d: d, syllable: c, depth: depth)
                return
            case .offset:
                let dataCE = d.ces[CollationConstants.indexFromCE32(ce32)]
                ces.append(CollationConstants.makeCE(CollationConstants.threeBytePrimaryForOffsetData(c, dataCE)))
                return
            case .implicit:
                ces.append(CollationConstants.makeCE(CollationConstants.unassignedPrimaryFromCodePoint(c)))
                return
            case .fallback, .reserved3, .builderData, .leadSurrogate:
                throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: ce32 & 0xf)
            }
        }
    }

    // MARK: Prefix (precontext) matching

    /// Resolves a PREFIX_TAG CE32 by matching the preceding scalars against
    /// the prefix trie (stored last-character-first). (getCE32FromPrefix.)
    private mutating func prefixCE32(d: CollationDataView, _ ce32: UInt32) -> UInt32 {
        let index = CollationConstants.indexFromCE32(ce32)
        var result = d.readContextCE32(at: index)  // default if no prefix match
        guard let p1 = prev1 else { return result }
        var trie = UCharsTrie(units: d.contexts, offset: index + 2)
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
    private mutating func contractionCE32(d: CollationDataView, _ contractionCE32: UInt32) -> UInt32 {
        let index = CollationConstants.indexFromCE32(contractionCE32)
        let defaultCE32 = d.readContextCE32(at: index)
        guard let first = scalarAhead(0) else { return defaultCE32 }
        if (contractionCE32 & CollationConstants.contractNextCCC) != 0 && norm.ccc(first) == 0 {
            // Every suffix starts with a non-starter; a starter cannot match.
            return defaultCE32
        }

        // Longest contiguous match (UTS #10 S2.1 "longest initial substring S").
        var trie = UCharsTrie(units: d.contexts, offset: index + 2)
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
        if (contractionCE32 & CollationConstants.contractTrailingCCC) != 0
            // With CONTRACT_SINGLE_CP_NO_MATCH, discontiguous matching only
            // extends an existing match (ICU: sinceMatch < lookAhead).
            && ((contractionCE32 & CollationConstants.contractSingleCpNoMatch) == 0 || bestLength > 0) {
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

    private mutating func appendHangulCEs(d dIn: CollationDataView, syllable c: UInt32, depth: Int) throws {
        // Jamo CE32s normally live in the base (root) data.
        let d = dIn.jamoCE32sStart >= 0 ? dIn : (baseView ?? dIn)
        guard d.jamoCE32sStart >= 0, (0xac00...0xd7a3).contains(c) else {
            throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: CollationConstants.Tag.hangul.rawValue)
        }
        let sIndex = Int(c) - 0xac00
        let jamo = d.jamoCE32sStart
        try appendCEs(d: d, c: c, ce32: d.ce32s[jamo + sIndex / 588], depth: depth + 1)
        try appendCEs(d: d, c: c, ce32: d.ce32s[jamo + 19 + (sIndex % 588) / 28], depth: depth + 1)
        let t = sIndex % 28
        if t != 0 {
            try appendCEs(d: d, c: c, ce32: d.ce32s[jamo + 19 + 21 + t - 1], depth: depth + 1)
        }
    }

    // MARK: Numeric collation (CODAN)

    /// Collects the digit run starting with `firstCE32` and appends numeric CEs.
    /// (CollationIterator::appendNumericCEs, forward direction.)
    private mutating func appendNumericCEs(d: CollationDataView, firstCE32: UInt32) throws {
        var digits: [Int32] = [CollationConstants.digitFromCE32(firstCE32)]
        var count = 0
        while let c = scalarAhead(count) {
            let (_, ce32) = lookup(c)
            guard CollationConstants.isSpecialCE32(ce32) && CollationConstants.tagFromCE32(ce32) == .digit else { break }
            digits.append(CollationConstants.digitFromCE32(ce32))
            count += 1
        }
        consumeAhead(count)
        var pos = 0
        repeat {
            // Skip leading zeros.
            while pos < digits.count - 1 && digits[pos] == 0 { pos += 1 }
            // Write a sequence of CEs for at most 254 digits at a time.
            let segmentLength = min(digits.count - pos, 254)
            appendNumericSegmentCEs(d: d, digits[pos..<(pos + segmentLength)])
            pos += segmentLength
        } while pos < digits.count
    }

    /// (CollationIterator::appendNumericSegmentCEs.)
    private mutating func appendNumericSegmentCEs(d: CollationDataView, _ digitsSlice: ArraySlice<Int32>) {
        let digits = Array(digitsSlice)
        var length = digits.count
        let numericPrimary = d.numericPrimary
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
                ces.append(CollationConstants.makeCE(numericPrimary | (UInt32(firstByte + value) << 16)))
                return
            }
            value -= numBytes
            firstByte += numBytes
            numBytes = 40
            if value < numBytes * 254 {
                let primary = numericPrimary
                    | (UInt32(firstByte + value / 254) << 16) | (UInt32(2 + value % 254) << 8)
                ces.append(CollationConstants.makeCE(primary))
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
                ces.append(CollationConstants.makeCE(primary))
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
                ces.append(CollationConstants.makeCE(primary))
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
        ces.append(CollationConstants.makeCE(primary))
    }
}
