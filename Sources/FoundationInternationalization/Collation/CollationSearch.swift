// Collation-aware substring search: finds the first occurrence of a pattern
// string within a target string, respecting collation strength (e.g.,
// case-insensitive or accent-insensitive matching).
//
// Forward search uses lazy CE production — CEs are produced on demand and
// matched incrementally, stopping as soon as a match is found. Backwards
// search pre-produces all CEs then scans from the end.

/// Position-annotated collation element.
struct AnnotatedCE {
    let ce: Int64
    let sourceStart: Int
    let sourceEnd: Int
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

    /// Returns true if `pattern` appears anywhere in `text`.
    /// Fast path: no position tracking, no array allocations for index/NFD maps.
    func contains(pattern: String, in text: String) -> Bool {
        if pattern.isEmpty { return true }
        if text.isEmpty { return false }

        let mask = strengthMask(for: options.strength)
        let patternCEs = produceMaskedCEs(for: pattern, mask: mask)
        if patternCEs.isEmpty { return false }

        let patCount = patternCEs.count

        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric,
            scalars: text.unicodeScalars
        )
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

    // MARK: - Forward search (lazy CE production)

    private func searchForward(patternCEs: [Int64], in text: String, mask: Int64) -> Range<String.Index>? {
        let textIndices = buildIndexTable(for: text)
        let scalarCount = text.unicodeScalars.count
        let nfdMap = buildNFDSourceMap(for: text)
        let patCount = patternCEs.count

        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric,
            scalars: text.unicodeScalars
        )
        // A fresh iterator/buffers are built per search call; pre-size the CE and
        // annotated buffers to the scalar count (CEs ≈ scalars) so the append
        // loop over long text doesn't repeatedly reallocate — Array growth
        // reallocation was the dominant cost on the paths corpus.
        iter.ces.reserveCapacity(scalarCount + 1)

        var buffer: [AnnotatedCE] = []
        buffer.reserveCapacity(scalarCount)
        var prevCECount = 0
        var prevScalarsConsumed = 0
        var nextMatchStart = 0

        do {
            while try iter.appendMore() {
                let curScalarsConsumed = iter.scalarsConsumed
                let nfdStart = prevScalarsConsumed
                let nfdEnd = curScalarsConsumed

                let srcStart: Int
                let srcEnd: Int
                if nfdStart < nfdMap.count {
                    srcStart = nfdMap[nfdStart]
                    srcEnd = (nfdEnd < nfdMap.count)
                        ? nfdMap[nfdEnd]
                        : scalarCount
                } else {
                    srcStart = max(scalarCount - 1, 0)
                    srcEnd = scalarCount
                }

                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    let masked = ce & mask
                    if masked != 0 {
                        buffer.append(AnnotatedCE(
                            ce: masked,
                            sourceStart: srcStart,
                            sourceEnd: max(srcEnd, srcStart + 1)
                        ))

                        // Try matching at each position as soon as we have enough CEs
                        while nextMatchStart + patCount <= buffer.count {
                            if tryMatch(buffer: buffer, at: nextMatchStart, patternCEs: patternCEs, text: text, textIndices: textIndices) {
                                let startScalar = buffer[nextMatchStart].sourceStart
                                let endScalar = buffer[nextMatchStart + patCount - 1].sourceEnd
                                let startIdx = textIndices[startScalar]
                                let endIdx = endScalar < textIndices.count
                                    ? textIndices[endScalar]
                                    : text.endIndex
                                return startIdx..<endIdx
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
            if tryMatch(buffer: buffer, at: nextMatchStart, patternCEs: patternCEs, text: text, textIndices: textIndices) {
                let startScalar = buffer[nextMatchStart].sourceStart
                let endScalar = buffer[nextMatchStart + patCount - 1].sourceEnd
                let startIdx = textIndices[startScalar]
                let endIdx = endScalar < textIndices.count
                    ? textIndices[endScalar]
                    : text.endIndex
                return startIdx..<endIdx
            }
            nextMatchStart += 1
        }

        return nil
    }

    private func tryMatch(buffer: [AnnotatedCE], at start: Int, patternCEs: [Int64], text: String, textIndices: [String.Index]) -> Bool {
        for patIx in 0..<patternCEs.count {
            if buffer[start + patIx].ce != patternCEs[patIx] {
                return false
            }
        }
        let startScalar = buffer[start].sourceStart
        let endScalar = buffer[start + patternCEs.count - 1].sourceEnd
        return isValidStartBoundary(at: startScalar, in: text) &&
               isValidEndBoundary(at: endScalar, in: text)
    }

    // MARK: - Backward search (full pre-production)

    private func searchBackwardFull(patternCEs: [Int64], in text: String, mask: Int64) -> Range<String.Index>? {
        let textIndices = buildIndexTable(for: text)
        let annotated = produceAnnotatedCEs(for: text, mask: mask)
        if annotated.isEmpty { return nil }

        let patCount = patternCEs.count
        guard patCount <= annotated.count else { return nil }

        for targetIx in stride(from: annotated.count - patCount, through: 0, by: -1) {
            var matched = true
            for patIx in 0..<patCount {
                if annotated[targetIx + patIx].ce != patternCEs[patIx] {
                    matched = false
                    break
                }
            }

            if matched {
                let startScalar = annotated[targetIx].sourceStart
                let endScalar = annotated[targetIx + patCount - 1].sourceEnd

                if isValidStartBoundary(at: startScalar, in: text) &&
                   isValidEndBoundary(at: endScalar, in: text) {
                    let startIdx = textIndices[startScalar]
                    let endIdx = endScalar < textIndices.count
                        ? textIndices[endScalar]
                        : text.endIndex
                    return startIdx..<endIdx
                }
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

    private func produceAnnotatedCEs(for text: String, mask: Int64) -> [AnnotatedCE] {
        let nfdMap = buildNFDSourceMap(for: text)
        let scalarCount = text.unicodeScalars.count

        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric,
            scalars: text.unicodeScalars
        )
        iter.ces.reserveCapacity(scalarCount + 1)

        var result: [AnnotatedCE] = []
        result.reserveCapacity(scalarCount)
        var prevCECount = 0
        var prevScalarsConsumed = 0

        do {
            while try iter.appendMore() {
                let curScalarsConsumed = iter.scalarsConsumed
                let nfdStart = prevScalarsConsumed
                let nfdEnd = curScalarsConsumed

                let srcStart: Int
                let srcEnd: Int
                if nfdStart < nfdMap.count {
                    srcStart = nfdMap[nfdStart]
                    srcEnd = (nfdEnd < nfdMap.count)
                        ? nfdMap[nfdEnd]
                        : scalarCount
                } else {
                    srcStart = max(scalarCount - 1, 0)
                    srcEnd = scalarCount
                }

                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    let masked = ce & mask
                    if masked != 0 {
                        result.append(AnnotatedCE(
                            ce: masked,
                            sourceStart: srcStart,
                            sourceEnd: max(srcEnd, srcStart + 1)
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

    // MARK: - Index table

    private func buildIndexTable(for text: String) -> [String.Index] {
        var indices: [String.Index] = []
        indices.reserveCapacity(text.unicodeScalars.count)
        for idx in text.unicodeScalars.indices {
            indices.append(idx)
        }
        return indices
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
