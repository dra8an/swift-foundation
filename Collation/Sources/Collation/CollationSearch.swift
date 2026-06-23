// Collation-aware substring search: finds the first occurrence of a pattern
// string within a target string, respecting collation strength (e.g.,
// case-insensitive or accent-insensitive matching).
//
// Algorithm follows ICU's usearch_search: linear scan in CE space with
// position annotation and boundary validation.

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

        let textIndices = buildIndexTable(for: text)
        let annotated = produceAnnotatedCEs(for: text, mask: mask)
        if annotated.isEmpty { return nil }

        let patCount = patternCEs.count

        var targetIx = 0
        while targetIx + patCount <= annotated.count {
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

            targetIx += 1
        }

        return nil
    }

    /// Returns true if `pattern` appears anywhere in `text`.
    func contains(pattern: String, in text: String) -> Bool {
        return search(for: pattern, in: text) != nil
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

    // MARK: - Annotated CE production (text)

    /// Produces CEs for the text with source position annotations.
    /// Uses the standard CE pipeline (appendMore) and tracks source positions
    /// via CEIterator.scalarsConsumed, which counts every NFD scalar consumed
    /// including contraction suffixes.
    private func produceAnnotatedCEs(for text: String, mask: Int64) -> [AnnotatedCE] {
        let nfdMap = buildNFDSourceMap(for: text)
        let scalarCount = text.unicodeScalars.count

        var iter = CEIterator(
            data: data, base: base, norm: norm,
            numeric: numeric,
            scalars: text.unicodeScalars
        )

        var result: [AnnotatedCE] = []
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
                    // Ensure end > start
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
    /// NFD can expand one source scalar into multiple — all map to the same source.
    private func buildNFDSourceMap(for text: String) -> [Int] {
        var map: [Int] = []
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

    /// A match can only start at a starter boundary (ccc == 0 in the original text).
    private func isValidStartBoundary(at scalarOffset: Int, in text: String) -> Bool {
        if scalarOffset == 0 { return true }
        let scalars = text.unicodeScalars
        var idx = scalars.startIndex
        for _ in 0..<scalarOffset {
            idx = scalars.index(after: idx)
        }
        return norm.ccc(scalars[idx].value) == 0
    }

    /// A match can only end at a starter boundary.
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

    /// Maps scalar offset (0-based) to String.Index for the text.
    private func buildIndexTable(for text: String) -> [String.Index] {
        var indices: [String.Index] = []
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
