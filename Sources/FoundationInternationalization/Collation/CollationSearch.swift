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
/// decomposed anything — see `confirmMatch`). One array of structs, not
/// parallel arrays: a second array means a second per-call allocation, which
/// measurably regresses short-line corpora (see optimization-targets.md §20).
struct AnnotatedCE {
    let ce: Int64
    let nfdStart: Int
    let nfdEnd: Int
}

struct CollationSearch {
    let storage: RootCollator.Storage
    let options: CollationOptions
    let numeric: Bool
    /// Highest variable primary + 1 when alternate=shifted, else 0 — the same
    /// convention as CollationCompare, so `primary < variableTop` tests
    /// variable-ness and primary ignorables test out early.
    let variableTop: UInt32

    var data: CollationData { storage.data }
    var base: CollationData? { storage.base }
    var norm: NormalizationData { storage.norm }

    init(storage: RootCollator.Storage,
         options: CollationOptions, variableTopValue: UInt32 = 0) {
        self.storage = storage
        self.options = options
        self.numeric = options.numeric
        self.variableTop = options.alternate == .shifted ? variableTopValue + 1 : 0
    }

    /// Applies the strength mask to one CE, honoring alternate=shifted (UTS
    /// #10 S3.4, mirroring CollationCompare): a variable CE is shifted to the
    /// quaternary level — below every search mask — and drags any directly
    /// following primary-ignorable CEs (e.g. combining marks on a space) down
    /// with it. Returns nil when the CE contributes nothing at this strength
    /// (the caller skips it; it never enters the match buffer).
    @inline(__always)
    private func maskedCE(_ ce: Int64, mask: Int64, afterVariable: inout Bool) -> Int64? {
        if variableTop != 0 {
            let primary = UInt32(truncatingIfNeeded: ce >> 32)
            if primary < variableTop && primary > CollationConstants.mergeSeparatorPrimary {
                afterVariable = true
                return nil
            }
            if primary == 0 && afterVariable { return nil }
            afterVariable = false
        }
        let masked = ce & mask
        return masked != 0 ? masked : nil
    }

    /// Searches for `pattern` in `text` at the configured collation strength.
    /// Returns the range in `text` of the first match, or nil.
    /// Direct/test entry: allocates one-off buffers. The hot path
    /// (`RootCollator.search`) calls the buffer-reusing overload below.
    func search(for pattern: String, in text: String) -> Range<String.Index>? {
        return search(
            for: pattern, in: text,
            scratch: ScratchBuffers(data: data, base: base, norm: norm))
    }

    /// Reuses the caller's thread-local scratch (iterator + CE buffers) — no
    /// per-call allocations at all (§37: the per-call pattern and window
    /// arrays were the largest cost of the cjk range cells). The scratch
    /// travels as ONE class reference so the byte-scan fast path — which
    /// never touches it — pays no exclusivity scopes at the call boundary
    /// (three inout parameters here cost ascii/paths range +30..40 ns
    /// under -no-WMO; measured 2026-07-16).
    func search(
        for pattern: String, in text: String, scratch: ScratchBuffers
    ) -> Range<String.Index>? {
        if pattern.isEmpty { return text.startIndex..<text.startIndex }
        if text.isEmpty { return nil }

        if byteScanEligible {
            if let range = byteScanSearch(for: pattern, in: text) {
                return range
            }
        }

        let mask = strengthMask(for: options.strength)
        produceMaskedCEs(
            for: pattern, mask: mask, iter: &scratch.left, into: &scratch.patternCEs)
        if scratch.patternCEs.isEmpty { return nil }

        return searchForward(
            patternCEs: scratch.patternCEs, in: text, mask: mask,
            iter: &scratch.left, window: &scratch.annotatedCEs,
            nfdMap: &scratch.nfdSourceMap)
    }

    /// The byte-scan fast paths are sound only when every clean-ASCII byte is
    /// guaranteed a nonzero collation element: strength at least tertiary
    /// (case differences stay significant), numeric off (digit runs would
    /// collapse into single elements), and alternate=nonIgnorable (shifted
    /// drops spaces/punctuation below the mask).
    private var byteScanEligible: Bool {
        options.strength.rawValue >= CollationOptions.Strength.tertiary.rawValue
            && !numeric
            && options.alternate == .nonIgnorable
    }

    /// Searches backwards for `pattern` in `text` at the configured collation
    /// strength. Returns the range of the last match, or nil.
    /// Direct/test entry: allocates one-off buffers.
    func searchBackwards(for pattern: String, in text: String) -> Range<String.Index>? {
        return searchBackwards(
            for: pattern, in: text,
            scratch: ScratchBuffers(data: data, base: base, norm: norm))
    }

    /// Reuses the caller's thread-local scratch for backwards search — no
    /// per-call allocations (§37; one class reference, see `search`).
    func searchBackwards(
        for pattern: String, in text: String, scratch: ScratchBuffers
    ) -> Range<String.Index>? {
        if pattern.isEmpty { return text.startIndex..<text.startIndex }
        if text.isEmpty { return nil }

        if byteScanEligible {
            if let range = byteScanSearchBackwards(for: pattern, in: text) {
                return range
            }
        }

        let mask = strengthMask(for: options.strength)
        produceMaskedCEs(
            for: pattern, mask: mask, iter: &scratch.left, into: &scratch.patternCEs)
        if scratch.patternCEs.isEmpty { return nil }

        produceAnnotatedCEs(
            for: text, mask: mask, iter: &scratch.left, into: &scratch.annotatedCEs)
        if scratch.annotatedCEs.isEmpty { return nil }

        return searchBackwardMatch(
            patternCEs: scratch.patternCEs, annotated: scratch.annotatedCEs,
            text: text, sawDecomposition: scratch.left.sawDecomposition,
            nfdMap: &scratch.nfdSourceMap
        )
    }

    /// Returns true if `pattern` appears anywhere in `text`.
    /// Fast path: no position tracking, no array allocations for index/NFD maps.
    ///
    /// Direct/test entry: allocates a one-off iterator and buffers. The hot
    /// path (`RootCollator.contains`) calls the buffer-reusing overload below
    /// with the collator's thread-local scratch.
    func contains(pattern: String, in text: String) -> Bool {
        return contains(
            pattern: pattern, in: text,
            scratch: ScratchBuffers(data: data, base: base, norm: norm))
    }

    /// Reuses the caller's thread-local scratch for both the pattern and the
    /// text — no per-call allocations. `localizedStandardContains` over many
    /// strings reuses one scratch set across all calls (profiling showed
    /// fresh per-call iterators dominated `contains`; §37 removed the
    /// remaining per-call arrays).
    func contains(
        pattern: String, in text: String, scratch: ScratchBuffers
    ) -> Bool {
        if pattern.isEmpty { return true }
        if text.isEmpty { return false }

        let mask = strengthMask(for: options.strength)
        // Pattern CEs first, reusing scratch.left; then it is reset onto the
        // text. The rest of the body borrows them as locals once.
        produceMaskedCEs(
            for: pattern, mask: mask, iter: &scratch.left, into: &scratch.patternCEs)
        if scratch.patternCEs.isEmpty { return false }

        return containsScan(
            pattern: pattern, in: text, mask: mask,
            patternCEs: scratch.patternCEs,
            iter: &scratch.left, textCEs: &scratch.maskedTextCEs)
    }

    private func containsScan(
        pattern: String, in text: String, mask: Int64, patternCEs: [Int64],
        iter: inout CEIterator, textCEs buffer: inout [Int64]
    ) -> Bool {
        let patCount = patternCEs.count

        iter.reset(numeric: numeric, scalars: text.unicodeScalars)
        let textUTF8Count = text.utf8.count
        if textUTF8Count <= 32 {
            iter.ces.reserveCapacity(textUTF8Count + 1)
        }

        if !buffer.isEmpty { buffer.removeAll(keepingCapacity: true) }
        if textUTF8Count <= 32 {
            buffer.reserveCapacity(textUTF8Count)
        }
        var prevCECount = 0
        var nextMatchStart = 0
        var afterVariable = false

        do {
            while try iter.appendMore() {
                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    if let masked = maskedCE(ce, mask: mask, afterVariable: &afterVariable) {
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

    /// True for ASCII bytes that are guaranteed a nonzero collation element
    /// at tertiary strength with alternate=nonIgnorable: printable ASCII plus
    /// the TAB..CR whitespace controls. The other C0 controls and DEL are
    /// completely ignorable in the CLDR root (they produce no CE at all), so
    /// no byte-level conclusion is sound in their vicinity — "ab" collation-
    /// matches "a\u{01}b" even though the bytes differ.
    @inline(__always)
    private func isCleanASCIIByte(_ b: UInt8) -> Bool {
        (b >= 0x20 && b <= 0x7E) || (b >= 0x09 && b <= 0x0D)
    }

    /// Direct UTF-8 byte scan (see `byteScanEligible` for the option gates).
    /// Within a clean-ASCII region, byte equality is equivalent to collation
    /// equality (each clean byte maps to exactly one nonzero CE), so:
    /// - a byte match lying entirely inside the clean *prefix* of the text is
    ///   definitively the FIRST collation match;
    /// - "no byte match" over an entirely clean text and pattern is a
    ///   definitive no-match.
    /// Everything else falls through to the CE path — including byte matches
    /// past the first non-clean byte: such a match is real, but an *earlier*
    /// occurrence can hide in a different normalization form, so it is not
    /// provably first.
    private func byteScanSearch(for pattern: String, in text: String) -> Range<String.Index>?? {
        guard text.isContiguousUTF8, pattern.isContiguousUTF8 else { return nil }

        let patLen = pattern.utf8.count
        let textLen = text.utf8.count

        return text.utf8.withContiguousStorageIfAvailable { textBuf -> Range<String.Index>?? in
            pattern.utf8.withContiguousStorageIfAvailable { patBuf -> Range<String.Index>?? in
                for j in 0..<patLen where !isCleanASCIIByte(patBuf[j]) {
                    return nil  // pattern not clean — CE path
                }

                // Single pass: cleanliness is checked as the scan advances,
                // so a match is only ever returned from an all-clean prefix
                // (bytes before it were checked at earlier positions; the
                // window itself equals the clean pattern). A dirty byte ends
                // the fast path — any remaining match would start beyond it
                // and would not be provably first.
                if patLen <= textLen {
                    for i in 0...(textLen - patLen) {
                        let b = textBuf[i]
                        if b == patBuf[0] {
                            // b equals a clean pattern byte, so it is clean —
                            // no explicit check needed on this branch.
                            var matched = true
                            for j in 1..<patLen {
                                if textBuf[i + j] != patBuf[j] { matched = false; break }
                            }
                            if matched {
                                // End boundary: the byte after the match must
                                // be clean ASCII (or absent). A non-ASCII byte
                                // there could open a combining mark belonging
                                // to the match's last character — the CE path
                                // rejects such splits, so let it decide.
                                if i + patLen < textLen, !isCleanASCIIByte(textBuf[i + patLen]) {
                                    return nil
                                }
                                let startIdx = text.utf8.index(text.startIndex, offsetBy: i)
                                let endIdx = text.utf8.index(startIdx, offsetBy: patLen)
                                return .some(startIdx..<endIdx)
                            }
                        } else if !isCleanASCIIByte(b) {
                            return nil
                        }
                    }
                }
                // No match; conclusive only if the tail bytes (never visited
                // as window starts) are clean too.
                let tailStart = patLen <= textLen ? textLen - patLen + 1 : 0
                for k in tailStart..<textLen where !isCleanASCIIByte(textBuf[k]) {
                    return nil
                }
                return .some(nil)
            }!
        }!
    }

    /// Mirror of `byteScanSearch` for backward search: scans from the end of
    /// the text down to the last non-clean byte. A byte match entirely above
    /// that point is definitively the LAST collation match (no later match
    /// can hide in the clean suffix); "no byte match" over an entirely clean
    /// text and pattern is a definitive no-match. Everything else falls
    /// through to the CE path.
    private func byteScanSearchBackwards(for pattern: String, in text: String) -> Range<String.Index>?? {
        guard text.isContiguousUTF8, pattern.isContiguousUTF8 else { return nil }

        let patLen = pattern.utf8.count
        let textLen = text.utf8.count

        return text.utf8.withContiguousStorageIfAvailable { textBuf -> Range<String.Index>?? in
            pattern.utf8.withContiguousStorageIfAvailable { patBuf -> Range<String.Index>?? in
                for j in 0..<patLen where !isCleanASCIIByte(patBuf[j]) {
                    return nil  // pattern not clean — CE path
                }

                // Single pass from the end: cleanliness is checked as the
                // scan descends, so a match is only ever returned from an
                // all-clean suffix (no later match can hide in it). A dirty
                // byte ends the fast path.
                var i = textLen - 1
                while i >= 0 {
                    let b = textBuf[i]
                    if i <= textLen - patLen, b == patBuf[0] {
                        // b equals a clean pattern byte, so it is clean.
                        var matched = true
                        for j in 1..<patLen {
                            if textBuf[i + j] != patBuf[j] { matched = false; break }
                        }
                        if matched {
                            let startIdx = text.utf8.index(text.startIndex, offsetBy: i)
                            let endIdx = text.utf8.index(startIdx, offsetBy: patLen)
                            return .some(startIdx..<endIdx)
                        }
                    } else if !isCleanASCIIByte(b) {
                        return nil
                    }
                    i -= 1
                }
                // Whole text clean, no byte match — conclusive.
                return .some(nil)
            }!
        }!
    }

    // MARK: - Forward search (lazy CE production)

    /// Lazy CE scan with lazy position reporting. No per-call arrays at all:
    /// CEs are annotated with raw NFD offsets as they are produced into the
    /// caller-owned `window`, and the NFD→source conversion, boundary
    /// validation, and String.Index construction all happen in
    /// `confirmMatch`, only for candidates whose CEs already match
    /// (profiling showed the upfront index table + NFD map were most of
    /// `localizedStandardRange`; §37 showed the window's per-call
    /// malloc/free was most of the cjk range cells).
    private func searchForward(
        patternCEs: [Int64], in text: String, mask: Int64,
        iter: inout CEIterator, window buffer: inout [AnnotatedCE],
        nfdMap: inout [Int]
    ) -> Range<String.Index>? {
        let patCount = patternCEs.count

        iter.reset(numeric: numeric, scalars: text.unicodeScalars)
        // Reserve for the whole text (capped so huge inputs don't over-
        // allocate): growth reallocs of the 24-byte AnnotatedCE elements were
        // measurable on long lines (paths corpus), where the old <=32 gate
        // never fired. reserveCapacity on the retained-capacity buffer is a
        // no-op once warm.
        let textUTF8Count = text.utf8.count
        let reserve = min(textUTF8Count, 1024)
        iter.ces.reserveCapacity(reserve + 1)

        if !buffer.isEmpty { buffer.removeAll(keepingCapacity: true) }
        buffer.reserveCapacity(reserve)
        var prevCECount = 0
        var prevScalarsConsumed = 0
        var nextMatchStart = 0
        var nfdMapBuilt = false
        var afterVariable = false

        do {
            while try iter.appendMore() {
                let curScalarsConsumed = iter.scalarsConsumed
                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    if let masked = maskedCE(ce, mask: mask, afterVariable: &afterVariable) {
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
                                nfdMap: &nfdMap, nfdMapBuilt: &nfdMapBuilt
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
                nfdMap: &nfdMap, nfdMapBuilt: &nfdMapBuilt
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
    /// range in `text`. `nfdMap` is the scratch-owned map buffer;
    /// `nfdMapBuilt` tracks whether it holds THIS text's map yet (§41 —
    /// stale contents from a previous search must not be trusted).
    private func confirmMatch(
        buffer: [AnnotatedCE], at start: Int, patternCEs: [Int64],
        text: String, sawDecomposition: Bool,
        nfdMap: inout [Int], nfdMapBuilt: inout Bool
    ) -> Range<String.Index>? {
        // Hot head — runs at EVERY candidate position; the fail-fast CE
        // comparison must inline into the scan loops. The once-per-match
        // range construction lives in the @inline(never) tail below: with
        // it inline, the whole function grew past WMO's inlining threshold
        // and the scan loops paid an 11-argument call per candidate (§42 —
        // no-match scans +9%; the §29 hot/cold split shape).
        for patIx in 0..<patternCEs.count {
            if buffer[start + patIx].ce != patternCEs[patIx] {
                return nil
            }
        }
        return confirmedRange(
            buffer: buffer, at: start, patternCEs: patternCEs, text: text,
            sawDecomposition: sawDecomposition,
            nfdMap: &nfdMap, nfdMapBuilt: &nfdMapBuilt)
    }

    /// Cold tail of `confirmMatch`: NFD→source offset conversion, boundary
    /// validation, and String.Index construction for a candidate whose CEs
    /// fully matched. Runs once per successful search (plus rare
    /// boundary-rejected candidates), so it stays out of line by design.
    @inline(never)
    private func confirmedRange(
        buffer: [AnnotatedCE], at start: Int, patternCEs: [Int64],
        text: String, sawDecomposition: Bool,
        nfdMap: inout [Int], nfdMapBuilt: inout Bool
    ) -> Range<String.Index>? {
        let nfdStart = buffer[start].nfdStart
        let nfdEnd = buffer[start + patternCEs.count - 1].nfdEnd

        let startScalar: Int
        let endScalar: Int
        if !sawDecomposition {
            startScalar = nfdStart
            endScalar = nfdEnd
        } else {
            if !nfdMapBuilt {
                buildNFDSourceMap(for: text, into: &nfdMap)
                nfdMapBuilt = true
            }
            // One map entry per NFD scalar, holding its source scalar index;
            // the last entry is always the last source scalar.
            let scalarCount = nfdMap.isEmpty ? 0 : nfdMap[nfdMap.count - 1] + 1
            if nfdStart < nfdMap.count {
                startScalar = nfdMap[nfdStart]
            } else {
                startScalar = max(scalarCount - 1, 0)
            }
            // Clamp so the match always covers the last CE's own source
            // scalar even when its whole NFD window maps into one scalar.
            let lastNfdStart = buffer[start + patternCEs.count - 1].nfdStart
            let lastSrcStart = lastNfdStart < nfdMap.count
                ? nfdMap[lastNfdStart]
                : max(scalarCount - 1, 0)
            let srcEnd = nfdEnd < nfdMap.count ? nfdMap[nfdEnd] : scalarCount
            endScalar = max(srcEnd, lastSrcStart + 1)
        }

        // Boundary validation fused with index construction — ONE bounded
        // walk to startScalar plus the short hop to endScalar (§42). The old
        // shape (separate isValidStart/EndBoundary helpers) walked to each
        // offset separately AND paid a whole-string `scalars.count` walk per
        // confirmed match — the top remaining match-tax leaf after §41. A
        // boundary is valid when the scalar at it is a starter (ccc 0) or it
        // sits at the text's edge, so the match never splits a combining
        // sequence.
        let scalars = text.unicodeScalars
        guard let startIdx = scalars.index(
            scalars.startIndex, offsetBy: startScalar, limitedBy: scalars.endIndex
        ) else { return nil }
        if startScalar != 0 {
            guard startIdx != scalars.endIndex,
                  norm.ccc(scalars[startIdx].value) == 0 else { return nil }
        }
        let endIdx = scalars.index(
            startIdx, offsetBy: endScalar - startScalar, limitedBy: scalars.endIndex
        ) ?? scalars.endIndex
        if endIdx != scalars.endIndex {
            guard norm.ccc(scalars[endIdx].value) == 0 else { return nil }
        }
        return startIdx..<endIdx
    }

    // MARK: - Backward search (full pre-production)

    private func searchBackwardMatch(
        patternCEs: [Int64], annotated: [AnnotatedCE], text: String,
        sawDecomposition: Bool, nfdMap: inout [Int]
    ) -> Range<String.Index>? {
        let patCount = patternCEs.count
        guard patCount <= annotated.count else { return nil }

        var nfdMapBuilt = false
        for targetIx in stride(from: annotated.count - patCount, through: 0, by: -1) {
            if let range = confirmMatch(
                buffer: annotated, at: targetIx, patternCEs: patternCEs,
                text: text, sawDecomposition: sawDecomposition,
                nfdMap: &nfdMap, nfdMapBuilt: &nfdMapBuilt
            ) {
                return range
            }
        }

        return nil
    }

    // MARK: - CE production (pattern)

    /// Produces the masked CEs of `string` into the caller-owned `result`
    /// (cleared first, capacity retained) — no per-call allocation. Empties
    /// `result` on pipeline errors; callers treat empty as no-match.
    private func produceMaskedCEs(
        for string: String, mask: Int64, iter: inout CEIterator,
        into result: inout [Int64]
    ) {
        iter.reset(numeric: numeric, scalars: string.unicodeScalars)
        if !result.isEmpty { result.removeAll(keepingCapacity: true) }
        var afterVariable = false
        do {
            let allCEs = try iter.collectAll()
            for ce in allCEs {
                if ce == CollationConstants.noCE { break }
                if let masked = maskedCE(ce, mask: mask, afterVariable: &afterVariable) {
                    result.append(masked)
                }
            }
        } catch {
            result.removeAll(keepingCapacity: true)
        }
    }

    // MARK: - Annotated CE production (full, for backwards search)

    private func produceAnnotatedCEs(
        for text: String, mask: Int64, iter: inout CEIterator,
        into result: inout [AnnotatedCE]
    ) {
        iter.reset(numeric: numeric, scalars: text.unicodeScalars)
        let textUTF8Count = text.utf8.count
        let reserve = min(textUTF8Count, 1024)
        iter.ces.reserveCapacity(reserve + 1)

        if !result.isEmpty { result.removeAll(keepingCapacity: true) }
        result.reserveCapacity(reserve)
        var prevCECount = 0
        var prevScalarsConsumed = 0
        var afterVariable = false

        do {
            while try iter.appendMore() {
                let curScalarsConsumed = iter.scalarsConsumed
                for i in prevCECount..<iter.ces.count {
                    let ce = iter.ces[i]
                    if ce == CollationConstants.noCE { break }
                    if let masked = maskedCE(ce, mask: mask, afterVariable: &afterVariable) {
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
            result.removeAll(keepingCapacity: true)
        }
    }

    /// Fills `map` with each NFD scalar position's original source scalar
    /// index. Allocation-free (§41): the expansion counts come straight from
    /// the trie (`fullDecompositionCount`, the count-only twin of
    /// `appendDecomposition`) and the map is a scratch-owned buffer — the
    /// old per-call map plus two `[UInt32]` temporaries PER DECOMPOSING
    /// SCALAR were ~half of every matching search on accented text. The
    /// utf8 reserve replaces a `unicodeScalars.count` walk, which cost its
    /// own O(n) pass.
    private func buildNFDSourceMap(for text: String, into map: inout [Int]) {
        if !map.isEmpty { map.removeAll(keepingCapacity: true) }
        map.reserveCapacity(min(text.utf8.count, 1024))
        var i = 0
        for scalar in text.unicodeScalars {
            let n = norm.fullDecompositionCount(of: scalar.value)
            if n == 0 {
                map.append(i)
            } else {
                for _ in 0..<n { map.append(i) }
            }
            i += 1
        }
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
