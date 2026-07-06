// Collation-aware substring search: finds the first occurrence of a pattern
// string within a target string, respecting collation strength (e.g.,
// case-insensitive or accent-insensitive matching).
//
// Forward search uses lazy CE production — CEs are produced on demand and
// matched incrementally, stopping as soon as a match is found. Backwards
// search pre-produces all CEs then scans from the end.

/// Collation element annotated with the NFD-scalar window it was produced
/// from. Offsets are NFD-stream positions; they are converted to source
/// scalar offsets only when a candidate match needs boundary validation and
/// range reporting (an identity conversion when the iterator never
/// decomposed anything — see `confirmMatch`).
struct AnnotatedCE {
    let ce: Int64
    let nfdStart: Int
    let nfdEnd: Int
}

struct CollationSearch {
    let data: CollationData
    let base: CollationData?
    let norm: NormalizationData
    let options: CollationOptions
    let numeric: Bool

    init(data: CollationData, base: CollationData?, norm: NormalizationData,
         options: CollationOptions) {
        self.data = data
        self.base = base
        self.norm = norm
        self.options = options
        self.numeric = options.numeric
    }

    /// Searches for `pattern` in `text` at the configured collation strength.
    /// Returns the range in `text` of the first match, or nil.
    func search(for pattern: String, in text: String) -> Range<String.Index>? {
        if pattern.isEmpty { return text.startIndex..<text.startIndex }
        if text.isEmpty { return nil }

        let mask = strengthMask(for: options.strength)
        let patternCEs = produceMaskedCEs(for: pattern, mask: mask)
        if patternCEs.isEmpty { return nil }

        return searchForward(patternCEs: patternCEs, in: text, mask: mask)
    }

    /// Reuses a caller-owned iterator for pattern CE production, then resets it
    /// for the text scan — no per-call iterator allocation.
    func search(for pattern: String, in text: String, iter: inout CEIterator) -> Range<String.Index>? {
        if pattern.isEmpty { return text.startIndex..<text.startIndex }
        if text.isEmpty { return nil }

        if options.strength.rawValue >= CollationOptions.Strength.tertiary.rawValue && !numeric {
            if let range = byteScanSearch(for: pattern, in: text) {
                return range
            }
        }

        let mask = strengthMask(for: options.strength)
        let patternCEs = produceMaskedCEs(for: pattern, mask: mask, iter: &iter)
        if patternCEs.isEmpty { return nil }

        return searchForward(patternCEs: patternCEs, in: text, mask: mask, iter: &iter)
    }

    /// Searches backwards for `pattern` in `text` at the configured collation
    /// strength. Returns the range of the last match, or nil.
    func searchBackwards(for pattern: String, in text: String) -> Range<String.Index>? {
        if pattern.isEmpty { return text.startIndex..<text.startIndex }
        if text.isEmpty { return nil }

        let mask = strengthMask(for: options.strength)
        let patternCEs = produceMaskedCEs(for: pattern, mask: mask)
        if patternCEs.isEmpty { return nil }

        return searchBackwardFull(patternCEs: patternCEs, in: text, mask: mask)
    }

    /// Reuses a caller-owned iterator for backwards search.
    func searchBackwards(for pattern: String, in text: String, iter: inout CEIterator) -> Range<String.Index>? {
        if pattern.isEmpty { return text.startIndex..<text.startIndex }
        if text.isEmpty { return nil }

        let mask = strengthMask(for: options.strength)
        let patternCEs = produceMaskedCEs(for: pattern, mask: mask, iter: &iter)
        if patternCEs.isEmpty { return nil }

        return searchBackwardFull(patternCEs: patternCEs, in: text, mask: mask, iter: &iter)
    }

    /// Returns true if `pattern` appears anywhere in `text`.
    /// Fast path: no position tracking, no array allocations for index/NFD maps.
    ///
    /// Direct/test entry: allocates a one-off iterator. The hot path
    /// (`RootCollator.contains`) calls the iter-reusing overload below with the
    /// collator's thread-local scratch iterator.
    func contains(pattern: String, in text: String) -> Bool {
        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric, scalars: text.unicodeScalars
        )
        return contains(pattern: pattern, in: text, iter: &iter)
    }

    /// Reuses a caller-owned `CEIterator` for both the pattern and the text —
    /// no per-call `CEIterator` or CE-array allocation. `localizedStandard-
    /// Contains` over many strings reuses one scratch iterator across all calls
    /// (profiling showed fresh per-call iterators dominated `contains`).
    func contains(pattern: String, in text: String, iter: inout CEIterator) -> Bool {
        if pattern.isEmpty { return true }
        if text.isEmpty { return false }

        let mask = strengthMask(for: options.strength)
        // Pattern CEs first, reusing `iter`; then `iter` is reset onto the text.
        let patternCEs = produceMaskedCEs(for: pattern, mask: mask, iter: &iter)
        if patternCEs.isEmpty { return false }

        let patCount = patternCEs.count

        iter.reset(numeric: numeric, scalars: text.unicodeScalars)
        let textUTF8Count = text.utf8.count
        if textUTF8Count <= 32 {
            iter.ces.reserveCapacity(textUTF8Count + 1)
        }

        var buffer: [Int64] = []
        if textUTF8Count <= 32 {
            buffer.reserveCapacity(textUTF8Count)
        }
        var prevCECount = 0
        var nextMatchStart = 0

        do {
            while try iter.appendMore() {
                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    let masked = ce & mask
                    if masked != 0 {
                        buffer.append(masked)

                        while nextMatchStart + patCount <= buffer.count {
                            var matched = true
                            for patIx in 0..<patCount {
                                if buffer[nextMatchStart + patIx] != patternCEs[patIx] {
                                    matched = false
                                    break
                                }
                            }
                            if matched { return true }
                            nextMatchStart += 1
                        }
                    }
                }
                prevCECount = iter.ces.count
            }
        } catch {
            return false
        }

        return false
    }

    // MARK: - Byte-scan fast path

    /// Direct UTF-8 byte scan when strength >= tertiary and no numeric mode.
    /// For pure ASCII text: a definitive search (byte equality = collation equality,
    /// "not found" is conclusive). For non-ASCII: only returns early on match
    /// (byte match implies collation match), falls through on no-match since
    /// normalization could still produce a collation match via the CE path.
    private func byteScanSearch(for pattern: String, in text: String) -> Range<String.Index>?? {
        guard text.isContiguousUTF8, pattern.isContiguousUTF8 else { return nil }

        let patLen = pattern.utf8.count
        let textLen = text.utf8.count
        guard patLen <= textLen else {
            // Pattern longer than text — check if ASCII for definitive answer
            var isASCII = true
            text.utf8.withContiguousStorageIfAvailable { buf in
                for b in buf where b >= 0x80 { isASCII = false; break }
            }
            if isASCII {
                pattern.utf8.withContiguousStorageIfAvailable { buf in
                    for b in buf where b >= 0x80 { isASCII = false; break }
                }
            }
            return isASCII ? .some(nil) : nil
        }

        return text.utf8.withContiguousStorageIfAvailable { textBuf -> Range<String.Index>?? in
            pattern.utf8.withContiguousStorageIfAvailable { patBuf -> Range<String.Index>?? in
                var allASCII = true
                for j in 0..<patLen {
                    if patBuf[j] >= 0x80 { allASCII = false; break }
                }

                for i in 0...(textLen - patLen) {
                    if textBuf[i] != patBuf[0] {
                        if textBuf[i] >= 0x80 { allASCII = false }
                        continue
                    }
                    var matched = true
                    for j in 1..<patLen {
                        if textBuf[i + j] != patBuf[j] {
                            matched = false
                            break
                        }
                    }
                    if matched {
                        let startIdx = text.utf8.index(text.startIndex, offsetBy: i)
                        let endIdx = text.utf8.index(startIdx, offsetBy: patLen)
                        return .some(startIdx..<endIdx)
                    }
                }
                // No byte match found. If all bytes were ASCII, that's conclusive.
                if allASCII { return .some(nil) }
                // Non-ASCII present — can't rule out normalization match.
                return nil
            }!
        }!
    }

    // MARK: - Forward search (lazy CE production)

    private func searchForward(patternCEs: [Int64], in text: String, mask: Int64) -> Range<String.Index>? {
        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric,
            scalars: text.unicodeScalars
        )
        return searchForward(patternCEs: patternCEs, in: text, mask: mask, iter: &iter)
    }

    /// Lazy CE scan with lazy position reporting. No upfront per-call arrays:
    /// CEs are annotated with raw NFD offsets as they are produced, and the
    /// NFD→source conversion, boundary validation, and String.Index
    /// construction all happen in `confirmMatch`, only for candidates whose
    /// CEs already match (profiling showed the upfront index table + NFD map
    /// were most of `localizedStandardRange` — pure waste on no-match calls).
    private func searchForward(patternCEs: [Int64], in text: String, mask: Int64, iter: inout CEIterator) -> Range<String.Index>? {
        let patCount = patternCEs.count

        iter.reset(numeric: numeric, scalars: text.unicodeScalars)
        let textUTF8Count = text.utf8.count
        if textUTF8Count <= 32 {
            iter.ces.reserveCapacity(textUTF8Count + 1)
        }

        var buffer: [AnnotatedCE] = []
        if textUTF8Count <= 32 {
            buffer.reserveCapacity(textUTF8Count)
        }
        var prevCECount = 0
        var prevScalarsConsumed = 0
        var nextMatchStart = 0
        var nfdMap: [Int]? = nil

        do {
            while try iter.appendMore() {
                let curScalarsConsumed = iter.scalarsConsumed
                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    let masked = ce & mask
                    if masked != 0 {
                        buffer.append(AnnotatedCE(
                            ce: masked,
                            nfdStart: prevScalarsConsumed,
                            nfdEnd: curScalarsConsumed
                        ))

                        // Try matching at each position as soon as we have enough CEs
                        while nextMatchStart + patCount <= buffer.count {
                            if let range = confirmMatch(
                                buffer: buffer, at: nextMatchStart,
                                patternCEs: patternCEs, text: text,
                                sawDecomposition: iter.sawDecomposition,
                                nfdMap: &nfdMap
                            ) {
                                return range
                            }
                            nextMatchStart += 1
                        }
                    }
                }

                prevCECount = iter.ces.count
                prevScalarsConsumed = curScalarsConsumed
            }
        } catch {
            return nil
        }

        // Check any remaining positions after iteration completes
        while nextMatchStart + patCount <= buffer.count {
            if let range = confirmMatch(
                buffer: buffer, at: nextMatchStart,
                patternCEs: patternCEs, text: text,
                sawDecomposition: iter.sawDecomposition,
                nfdMap: &nfdMap
            ) {
                return range
            }
            nextMatchStart += 1
        }

        return nil
    }

    /// Checks the pattern CEs against `buffer` at `start`; on CE equality,
    /// converts the match's NFD offsets to source scalar offsets (building
    /// the NFD→source map lazily, and only when the iterator actually
    /// decomposed something — otherwise the streams are 1:1 and offsets
    /// carry over directly), validates the match boundaries, and returns the
    /// range in `text`.
    private func confirmMatch(
        buffer: [AnnotatedCE], at start: Int, patternCEs: [Int64],
        text: String, sawDecomposition: Bool, nfdMap: inout [Int]?
    ) -> Range<String.Index>? {
        for patIx in 0..<patternCEs.count {
            if buffer[start + patIx].ce != patternCEs[patIx] {
                return nil
            }
        }

        let nfdStart = buffer[start].nfdStart
        let nfdEnd = buffer[start + patternCEs.count - 1].nfdEnd

        let startScalar: Int
        let endScalar: Int
        if !sawDecomposition {
            startScalar = nfdStart
            endScalar = nfdEnd
        } else {
            if nfdMap == nil {
                nfdMap = buildNFDSourceMap(for: text)
            }
            let map = nfdMap!
            // One map entry per NFD scalar, holding its source scalar index;
            // the last entry is always the last source scalar.
            let scalarCount = map.isEmpty ? 0 : map[map.count - 1] + 1
            if nfdStart < map.count {
                startScalar = map[nfdStart]
            } else {
                startScalar = max(scalarCount - 1, 0)
            }
            // Clamp so the match always covers the last CE's own source
            // scalar even when its whole NFD window maps into one scalar.
            let lastNfdStart = buffer[start + patternCEs.count - 1].nfdStart
            let lastSrcStart = lastNfdStart < map.count
                ? map[lastNfdStart]
                : max(scalarCount - 1, 0)
            let srcEnd = nfdEnd < map.count ? map[nfdEnd] : scalarCount
            endScalar = max(srcEnd, lastSrcStart + 1)
        }

        guard isValidStartBoundary(at: startScalar, in: text),
              isValidEndBoundary(at: endScalar, in: text) else {
            return nil
        }

        let scalars = text.unicodeScalars
        guard let startIdx = scalars.index(
            scalars.startIndex, offsetBy: startScalar, limitedBy: scalars.endIndex
        ) else { return nil }
        let endIdx = scalars.index(
            startIdx, offsetBy: endScalar - startScalar, limitedBy: scalars.endIndex
        ) ?? scalars.endIndex
        return startIdx..<endIdx
    }

    // MARK: - Backward search (full pre-production)

    private func searchBackwardFull(patternCEs: [Int64], in text: String, mask: Int64) -> Range<String.Index>? {
        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric,
            scalars: text.unicodeScalars
        )
        return searchBackwardFull(patternCEs: patternCEs, in: text, mask: mask, iter: &iter)
    }

    private func searchBackwardFull(patternCEs: [Int64], in text: String, mask: Int64, iter: inout CEIterator) -> Range<String.Index>? {
        let annotated = produceAnnotatedCEs(for: text, mask: mask, iter: &iter)
        if annotated.isEmpty { return nil }

        return searchBackwardMatch(
            patternCEs: patternCEs, annotated: annotated, text: text,
            sawDecomposition: iter.sawDecomposition
        )
    }

    private func searchBackwardMatch(patternCEs: [Int64], annotated: [AnnotatedCE], text: String, sawDecomposition: Bool) -> Range<String.Index>? {
        let patCount = patternCEs.count
        guard patCount <= annotated.count else { return nil }

        var nfdMap: [Int]? = nil
        for targetIx in stride(from: annotated.count - patCount, through: 0, by: -1) {
            if let range = confirmMatch(
                buffer: annotated, at: targetIx, patternCEs: patternCEs,
                text: text, sawDecomposition: sawDecomposition, nfdMap: &nfdMap
            ) {
                return range
            }
        }

        return nil
    }

    // MARK: - CE production (pattern)

    private func produceMaskedCEs(for string: String, mask: Int64) -> [Int64] {
        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric,
            scalars: string.unicodeScalars
        )
        return produceMaskedCEs(for: string, mask: mask, iter: &iter)
    }

    /// As above, but reuses a caller-owned iterator (reset onto `string`) — no
    /// per-call iterator allocation for the pattern.
    private func produceMaskedCEs(for string: String, mask: Int64, iter: inout CEIterator) -> [Int64] {
        iter.reset(numeric: numeric, scalars: string.unicodeScalars)
        var result: [Int64] = []
        do {
            let allCEs = try iter.collectAll()
            for ce in allCEs {
                if ce == CollationConstants.noCE { break }
                let masked = ce & mask
                if masked != 0 {
                    result.append(masked)
                }
            }
        } catch {
            return []
        }
        return result
    }

    // MARK: - Annotated CE production (full, for backwards search)

    private func produceAnnotatedCEs(for text: String, mask: Int64, iter: inout CEIterator) -> [AnnotatedCE] {
        iter.reset(numeric: numeric, scalars: text.unicodeScalars)
        let textUTF8Count = text.utf8.count
        if textUTF8Count <= 32 {
            iter.ces.reserveCapacity(textUTF8Count + 1)
        }

        var result: [AnnotatedCE] = []
        if textUTF8Count <= 32 {
            result.reserveCapacity(textUTF8Count)
        }
        var prevCECount = 0
        var prevScalarsConsumed = 0

        do {
            while try iter.appendMore() {
                let curScalarsConsumed = iter.scalarsConsumed
                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    let masked = ce & mask
                    if masked != 0 {
                        result.append(AnnotatedCE(
                            ce: masked,
                            nfdStart: prevScalarsConsumed,
                            nfdEnd: curScalarsConsumed
                        ))
                    }
                }

                prevCECount = iter.ces.count
                prevScalarsConsumed = curScalarsConsumed
            }
        } catch {
            return []
        }

        return result
    }

    /// Maps each NFD scalar position to its original source scalar index.
    private func buildNFDSourceMap(for text: String) -> [Int] {
        var map: [Int] = []
        map.reserveCapacity(text.unicodeScalars.count)
        for (i, scalar) in text.unicodeScalars.enumerated() {
            let c = scalar.value
            if norm.hasDecomposition(c) {
                var decomposed: [UInt32] = []
                _ = norm.appendDecomposition(of: c, to: &decomposed)
                var fullyDecomposed: [UInt32] = []
                for d in decomposed {
                    if norm.hasDecomposition(d) {
                        _ = norm.appendDecomposition(of: d, to: &fullyDecomposed)
                    } else {
                        fullyDecomposed.append(d)
                    }
                }
                for _ in fullyDecomposed {
                    map.append(i)
                }
            } else {
                map.append(i)
            }
        }
        return map
    }

    // MARK: - Boundary validation

    private func isValidStartBoundary(at scalarOffset: Int, in text: String) -> Bool {
        if scalarOffset == 0 { return true }
        let scalars = text.unicodeScalars
        var idx = scalars.startIndex
        for _ in 0..<scalarOffset {
            idx = scalars.index(after: idx)
        }
        return norm.ccc(scalars[idx].value) == 0
    }

    private func isValidEndBoundary(at scalarOffset: Int, in text: String) -> Bool {
        let scalars = text.unicodeScalars
        if scalarOffset >= scalars.count { return true }
        var idx = scalars.startIndex
        for _ in 0..<scalarOffset {
            idx = scalars.index(after: idx)
        }
        return norm.ccc(scalars[idx].value) == 0
    }

    // MARK: - Strength mask

    private func strengthMask(for strength: CollationOptions.Strength) -> Int64 {
        switch strength {
        case .primary:
            return Int64(bitPattern: 0xFFFF_0000_0000_0000)
        case .secondary:
            return Int64(bitPattern: 0xFFFF_FFFF_0000_0000)
        case .tertiary, .quaternary, .identical:
            return Int64(bitPattern: 0xFFFF_FFFF_FFFF_0000)
        }
    }
}
