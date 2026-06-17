// String comparison against the CLDR root collation.
//
// Milestone-4 scope (see Docs/04-milestone-plan.md):
// - input is incrementally NFD-decomposed and canonically reordered before CE
//   lookup (the fused-decomposition front end of the ICU4X model), so
//   arbitrary non-NFD input compares correctly
// - all strengths (primary..quaternary, identical) and settings: alternate
//   shifted + maxVariable, case-first, case-level, backwards-secondary
//   ("French"), numeric (CODAN)
// - full context-dependent mappings: contraction (suffix) matching including
//   discontiguous contractions per UTS #10 S2.1, and prefix matching over the
//   two preceding scalars (sufficient for all CLDR prefixes)
// - root data only, no tailorings, no script reordering (milestone 7); works
//   against both the regular root data (with canonical closure) and the
//   NFD-only ICU4X variant

// @unchecked: the two stored views (fast Latin table, restart safety) point
// into the storage owned by `data`/`base`/`norm`, which the struct retains;
// everything is immutable after init.
public struct RootCollator: @unchecked Sendable {
    public enum Order: Int, Sendable {
        case ascending = -1
        case same = 0
        case descending = 1
    }

    public enum CollationError: Error {
        case unsupportedMapping(scalar: UInt32, tag: UInt32)
        case malformedData
    }

    let data: CollationData
    /// The base (root) data when `data` is a tailoring.
    let base: CollationData?
    let norm: NormalizationData
    /// Script reordering from the tailoring, if any.
    let reordering: Reordering?
    /// The tailoring's default options (e.g. backwards-secondary for fr-CA);
    /// plain defaults for the root collator.
    public let defaultOptions: CollationOptions
    /// Thread-local buffer stash: each thread caches one ScratchBuffers
    /// instance, eliminating all locking and ARC on the take/give path.
    private let threadLocal = ThreadLocalScratch()
    /// The most recently used fast-Latin setup (per options word).
    private let fastLatinCache = FastLatinCache()
    /// The fast Latin table: the tailoring's own, or the base's when the
    /// tailoring has none (CollationDataReader aliases the same way).
    /// Stored: rebuilding it per compare would retain `base` each time.
    let fastLatinTable: UnsafeBufferPointer<UInt16>
    /// Stored for the same reason; see RestartSafety.
    let restartSafety: RestartSafety

    public init(data: CollationData, norm: NormalizationData) {
        self.data = data
        self.base = nil
        self.norm = norm
        self.reordering = nil
        self.defaultOptions = CollationOptions()
        self.fastLatinTable = data.fastLatinTable
        self.restartSafety = RestartSafety(data: data, base: nil, norm: norm)
    }

    public init() throws {
        self.init(data: try CollationData.root(), norm: try NormalizationData.standard())
    }

    /// A collator for a bundled locale tailoring (e.g. "sv", "de-phonebook",
    /// "fr_CA", "ja", "zh"), based on the regular root data.
    public init(tailoringNamed name: String) throws {
        let tailoring = try CollationData.tailoring(bytes: CollationData.tailoring(named: name))
        let root = try CollationData.root()
        if let tailoringData = tailoring.data {
            self.data = tailoringData
            self.base = root
        } else {
            // Settings-only tailoring (e.g. fr-CA): use the base data directly.
            self.data = root
            self.base = nil
        }
        self.norm = try NormalizationData.standard()
        self.reordering = tailoring.reordering
        self.defaultOptions = CollationOptions(icuOptionsWord: tailoring.options)
        self.fastLatinTable = data.fastLatinTable.isEmpty
            ? (base?.fastLatinTable ?? data.fastLatinTable) : data.fastLatinTable
        self.restartSafety = RestartSafety(data: data, base: base, norm: norm)
    }

    // MARK: Comparison

    /// Compares two strings under root collation.
    /// Defaults to tertiary strength with all options off, like ICU.
    public func compare(
        _ left: String, _ right: String, options: CollationOptions = CollationOptions()
    ) throws -> Order {
        // UTF-8 byte fast path (the byte-level identical-prefix scan of
        // ICU's UTF-8 doCompare + CollationFastLatin::compareUTF8): native
        // Swift strings expose contiguous UTF-8, so characters are read as
        // raw bytes with no scalar decoding. The identical strength level
        // needs the NFD pipeline, so it keeps to the scalar path below.
        var triedFastLatin = false
        if options.strength != .identical, case let table = fastLatinTable, !table.isEmpty {
            // The closures must capture only trivial values and the cache
            // reference: capturing self would retain the collator's storage
            // on every call. The per-options setup is looked up inside, only
            // after the eligibility checks pass (so ineligible text never
            // pays for it); a cache miss returns needsSetupResult and is
            // retried once after computing the setup out here.
            let safety = restartSafety
            let numeric = options.numeric
            let word = options.icuOptions
            let cache = fastLatinCache
            for _ in 0..<2 {
                let fast: Int32? = left.utf8.withContiguousStorageIfAvailable { lBytes in
                    right.utf8.withContiguousStorageIfAvailable { rBytes in
                        RootCollator.fastLatinUTF8(
                            lBytes, rBytes, table: table, cache: cache, word: word,
                            numeric: numeric, safety: safety)
                    } ?? nil
                } ?? nil
                guard let fast else { break }
                if fast == CollationFastLatin.needsSetupResult {
                    _ = resolveFastLatinSetup(word)
                    continue
                }
                if fast != CollationFastLatin.bailOutResult {
                    return fast < 0 ? .ascending : fast == 0 ? .same : .descending
                }
                triedFastLatin = true  // ran and bailed; the scalar fast path would too
                break
            }
        }

        // No `if left == right` shortcut here. Swift's String == is canonical
        // equivalence, which for non-binary-equal strings runs NFC
        // normalization to prove (in)equality — measured at ~250–400 ns per
        // call on text with combining marks (Thai, etc.), on *every* non-equal
        // compare. Canonical equivalence is already handled correctly by the
        // CE pipeline below (the NFD front end yields equal CEs for equivalent
        // strings), so the shortcut was pure cost on the non-Latin path. The
        // byte fast path above still settles binary equality cheaply for
        // non-identical strengths. (See Docs/13 §6.6.)

        // Identical-prefix skip (RuleBasedCollator::doCompare): equal scalar
        // prefixes produce identical CEs, so iteration can start at the first
        // difference — when restarting there is provably equivalent to full
        // iteration (see unsafeStart). On an unsafe boundary we compare from
        // the start instead; ICU backs up partially, but skipping less is
        // always sound and keeps the common path free of index arithmetic.
        //
        // Span-based byte-level prefix scan (macOS 26+): raw UTF-8 byte
        // comparison is faster than scalar decode-and-compare (no decoding in
        // the hot loop). Falls back to scalar iterators on older deployments.
        let shared: Int
        let lNextValue: UInt32?
        let rNextValue: UInt32?
        let fellBack: Bool
        if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            let lSpan = left.utf8Span.span
            let rSpan = right.utf8Span.span
            let r = RootCollator.spanPrefixSkip(
                lSpan, rSpan, numeric: options.numeric, safety: restartSafety)
            shared = r.shared
            lNextValue = r.lNext
            rNextValue = r.rNext
            fellBack = r.fellBack
        } else {
            var lIter = left.unicodeScalars.makeIterator()
            var rIter = right.unicodeScalars.makeIterator()
            var count = 0
            var lScalar = lIter.next()
            var rScalar = rIter.next()
            while let a = lScalar, let b = rScalar, a == b {
                count += 1
                lScalar = lIter.next()
                rScalar = rIter.next()
            }
            lNextValue = lScalar?.value
            rNextValue = rScalar?.value
            if count > 0,
               (lNextValue.map { unsafeStart($0, numeric: options.numeric) } ?? false)
                || (rNextValue.map { unsafeStart($0, numeric: options.numeric) } ?? false) {
                shared = 0
                fellBack = true
            } else {
                shared = count
                fellBack = false
            }
        }

        // Fast Latin (CollationFastLatin): when both remainders start within
        // the mini-CE table's range, compare on the precompiled table with no
        // iterator pipeline (and no scratch buffers); any unsupported
        // character or mapping bails out to the regular path. The skip
        // walk's iterators are reusable unless an unsafe boundary forced the
        // comparison back to the start.
        var fastResult = CollationFastLatin.bailOutResult
        let table = fastLatinTable
        if !table.isEmpty, !triedFastLatin {
            var lSide: CollationFastLatin.Side
            var rSide: CollationFastLatin.Side
            if !fellBack {
                // Build positioned iterators: advance past the shared prefix
                // plus the first unequal scalar (already decoded into
                // lNextValue/rNextValue). Side.rest must yield the scalar
                // AFTER the one in Side.next.
                var lIter = left.unicodeScalars.makeIterator()
                var rIter = right.unicodeScalars.makeIterator()
                for _ in 0..<shared { _ = lIter.next(); _ = rIter.next() }
                if lNextValue != nil { _ = lIter.next() }
                if rNextValue != nil { _ = rIter.next() }
                lSide = CollationFastLatin.Side(next: lNextValue, rest: lIter)
                rSide = CollationFastLatin.Side(next: rNextValue, rest: rIter)
            } else {
                var li = left.unicodeScalars.makeIterator()
                var ri = right.unicodeScalars.makeIterator()
                lSide = CollationFastLatin.Side(next: li.next()?.value, rest: li)
                rSide = CollationFastLatin.Side(next: ri.next()?.value, rest: ri)
            }
            if lSide.next.map({ $0 <= CollationFastLatin.latinMax }) ?? true,
               rSide.next.map({ $0 <= CollationFastLatin.latinMax }) ?? true {
                let setup = resolveFastLatinSetup(options.icuOptions)
                if setup.packedOptions >= 0 {
                    fastResult = CollationFastLatin.compare(
                        table: table, primaries: setup.primaries,
                        options: setup.packedOptions, left: lSide, right: rSide)
                }
            }
        }

        var scratch: ScratchBuffers?
        defer { if let scratch { giveScratch(scratch) } }
        let result: Int
        if fastResult != CollationFastLatin.bailOutResult {
            result = Int(fastResult)
        } else {
            // CEs are generated lazily: the primary level usually decides the
            // comparison after a few characters.
            let s = takeScratch()
            scratch = s
            if fellBack {
                // The skip was abandoned (unsafe boundary): iterate from start.
                s.left.reset(numeric: options.numeric, scalars: left.unicodeScalars)
                s.right.reset(numeric: options.numeric, scalars: right.unicodeScalars)
            } else {
                // Position past the shared prefix. The Span-based skip found
                // the scalar count; reset(skippingFirst:) advances the internal
                // iterator so the next read yields the first unequal scalar.
                s.left.reset(numeric: options.numeric, scalars: left.unicodeScalars, skippingFirst: shared)
                s.right.reset(numeric: options.numeric, scalars: right.unicodeScalars, skippingFirst: shared)
            }
            result = try CollationCompare.compareUpToQuaternary(
                &s.left, &s.right, options: options.icuOptions,
                variableTopValue: variableTopValue(options), reordering: reordering)
        }
        if result != 0 {
            return result < 0 ? .ascending : .descending
        }
        if options.strength == .identical {
            // Identical level: compare NFD forms in code point order, with
            // end-of-string below U+FFFE (merge separator) below all code
            // points. (compareNFDIter: end = -2, U+FFFE = -1.)
            func rank(_ c: UInt32?) -> Int64 {
                guard let c else { return -2 }
                return c == 0xfffe ? -1 : Int64(c)
            }
            // ICU also runs the identical level from the skip position.
            let s = scratch ?? takeScratch()
            scratch = s
            s.left.scalars.reset(scalars: left.unicodeScalars, skippingFirst: shared)
            s.right.scalars.reset(scalars: right.unicodeScalars, skippingFirst: shared)
            while true {
                let lc = s.left.scalars.next()
                let rc = s.right.scalars.next()
                if lc != rc {
                    return rank(lc) < rank(rc) ? .ascending : .descending
                }
                if lc == nil { return .same }
            }
        }
        return .same
    }

    /// The sort key for a string: level bytes with 01 separators, optional
    /// identical level (BOCSU over NFD), 00 terminator. Byte-wise comparison
    /// of two sort keys equals compare() at the same options.
    public func sortKey(
        for s: String, options: CollationOptions = CollationOptions()
    ) throws -> [UInt8] {
        var key: [UInt8] = []
        try sortKey(for: s, into: &key, options: options)
        return key
    }

    /// Generates the sort key for a string into a caller-supplied buffer.
    /// The buffer is cleared and filled with the key bytes (level bytes with
    /// 01 separators, optional identical level, 00 terminator). Reusing the
    /// same buffer across calls avoids per-call allocation — the steady-state
    /// path is zero-alloc after the buffer has grown to working capacity.
    ///
    /// This is the ICU `ucol_getSortKey(dest, destCapacity)` model: the caller
    /// owns the output memory.
    public func sortKey(
        for s: String, into key: inout [UInt8], options: CollationOptions = CollationOptions()
    ) throws {
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        scratch.left.reset(numeric: options.numeric, scalars: s.unicodeScalars)
        _ = try scratch.left.collectAll()
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        key.removeAll(keepingCapacity: true)
        CollationKeys.writeSortKeyUpToQuaternary(
            ces: scratch.left.ces, compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, into: &key, reusing: &scratch.levels)
        if options.strength == .identical {
            key.append(1)  // level separator
            scratch.left.scalars.reset(scalars: s.unicodeScalars)
            if !scratch.nfdScalars.isEmpty { scratch.nfdScalars.removeAll(keepingCapacity: true) }
            while let c = scratch.left.scalars.next() { scratch.nfdScalars.append(c) }
            CollationKeys.writeIdenticalLevelRun(scalars: scratch.nfdScalars, into: &key)
        }
        key.append(0)  // terminator
    }

    private func takeScratch() -> ScratchBuffers {
        threadLocal.take() ?? ScratchBuffers(data: data, base: base, norm: norm)
    }

    private func giveScratch(_ buffers: ScratchBuffers) {
        threadLocal.give(buffers)
    }

    /// True if restarting CE iteration at `c` is not provably equivalent to
    /// full iteration (see RestartSafety).
    private func unsafeStart(_ c: UInt32, numeric: Bool) -> Bool {
        restartSafety.isUnsafe(c, numeric: numeric)
    }

    private func variableTopValue(_ options: CollationOptions) -> UInt32 {
        guard options.alternate == .shifted else { return 0 }
        return scriptsData.lastPrimaryForGroup(
            CollationData.reorderCodeFirst + options.maxVariable.rawValue)
    }

    /// Scripts data lives in the root; tailorings usually omit it.
    private var scriptsData: CollationData {
        data.scriptStarts.isEmpty ? base! : data
    }

    /// The cached fast-Latin setup for an options word, computing and
    /// storing it on a cache miss.
    private func resolveFastLatinSetup(_ word: Int32) -> FastLatinSetup {
        if let cached = fastLatinCache.setup(for: word) {
            return cached
        }
        var primaries: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: fastLatinTable, scriptsData: scriptsData, reordering: reordering,
            options: word, primaries: &primaries)
        let setup = FastLatinSetup(word: word, packedOptions: packed, primaries: primaries)
        fastLatinCache.store(setup)
        return setup
    }

    /// The byte fast path: identical-prefix scan on raw UTF-8, safety check,
    /// then CollationFastLatin.compareUTF8 from the restart offset. Returns
    /// -1/0/1, or bailOutResult when the regular path must run. Static with
    /// trivial parameters: it runs inside the contiguous-storage closures.
    /// (RuleBasedCollator::doCompare, UTF-8 variant.)
    private static func fastLatinUTF8(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        table: UnsafeBufferPointer<UInt16>, cache: FastLatinCache, word: Int32,
        numeric: Bool, safety: RestartSafety
    ) -> Int32 {
        // Identical-prefix scan on bytes.
        let lLength = lBytes.count
        let rLength = rBytes.count
        let minLength = min(lLength, rLength)
        var i = 0
        while i < minLength, lBytes[i] == rBytes[i] { i += 1 }
        if i == lLength && i == rLength { return 0 }  // binary equal
        // Back up to the start of a partially-equal code point (trail bytes
        // are 0x80..0xBF).
        if i > 0,
           (i != lLength && lBytes[i] & 0xc0 == 0x80) || (i != rLength && rBytes[i] & 0xc0 == 0x80) {
            repeat { i -= 1 } while i > 0 && lBytes[i] & 0xc0 == 0x80
        }
        if i > 0 {
            // Restarting at an unsafe scalar is not equivalent to full
            // iteration: compare from the start instead (ICU backs up
            // partially; skipping less is always sound).
            if (i != lLength && safety.isUnsafe(scalarAt(lBytes, i), numeric: numeric))
                || (i != rLength && safety.isUnsafe(scalarAt(rBytes, i), numeric: numeric)) {
                i = 0
            }
        }
        // Both sides must resume with fast-path-eligible lead bytes.
        guard i == lLength || lBytes[i] <= CollationFastLatin.latinMaxUTF8Lead,
              i == rLength || rBytes[i] <= CollationFastLatin.latinMaxUTF8Lead
        else { return CollationFastLatin.bailOutResult }

        guard let setup = cache.setup(for: word) else {
            return CollationFastLatin.needsSetupResult
        }
        guard setup.packedOptions >= 0 else { return CollationFastLatin.bailOutResult }
        return CollationFastLatin.compareUTF8(
            table: table, primaries: setup.primaries, options: setup.packedOptions,
            left: lBytes, leftStart: i, right: rBytes, rightStart: i)
    }

    /// Decodes the scalar at byte offset `i` (a lead byte of well-formed
    /// UTF-8, as produced by String).
    private static func scalarAt(_ bytes: UnsafeBufferPointer<UInt8>, _ i: Int) -> UInt32 {
        let b0 = UInt32(bytes[i])
        if b0 < 0x80 { return b0 }
        if b0 < 0xe0 {
            return ((b0 & 0x1f) << 6) | (UInt32(bytes[i + 1]) & 0x3f)
        }
        if b0 < 0xf0 {
            return ((b0 & 0x0f) << 12) | ((UInt32(bytes[i + 1]) & 0x3f) << 6)
                | (UInt32(bytes[i + 2]) & 0x3f)
        }
        return ((b0 & 0x07) << 18) | ((UInt32(bytes[i + 1]) & 0x3f) << 12)
            | ((UInt32(bytes[i + 2]) & 0x3f) << 6) | (UInt32(bytes[i + 3]) & 0x3f)
    }

    /// Result of the Span-based identical-prefix skip.
    struct PrefixSkipResult {
        /// Number of shared scalars (0 when fell back due to unsafe boundary).
        let shared: Int
        /// First unequal scalar value from the left side, or nil at end.
        let lNext: UInt32?
        /// First unequal scalar value from the right side, or nil at end.
        let rNext: UInt32?
        /// True when shared bytes existed but an unsafe restart boundary
        /// forced the comparison back to the start.
        let fellBack: Bool
    }

    /// Span-based identical-prefix skip: compares raw UTF-8 bytes without
    /// scalar decoding in the hot loop, then counts scalars and decodes the
    /// boundary once. This is 8–25% faster than scalar-iterator comparison
    /// for strings with common prefixes.
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @inline(__always)
    private static func spanPrefixSkip(
        _ lSpan: Span<UInt8>, _ rSpan: Span<UInt8>,
        numeric: Bool, safety: RestartSafety
    ) -> PrefixSkipResult {
        let lLen = lSpan.count
        let rLen = rSpan.count
        let minLen = min(lLen, rLen)

        // Byte-level prefix scan (the hot loop — no decoding).
        var i = 0
        while i < minLen, lSpan[i] == rSpan[i] { i += 1 }

        // Back up to the start of a partially-equal code point: trail bytes
        // are 10xxxxxx (0x80..0xBF).
        if i > 0,
           (i < lLen && lSpan[i] & 0xC0 == 0x80)
            || (i < rLen && rSpan[i] & 0xC0 == 0x80) {
            repeat { i -= 1 } while i > 0 && lSpan[i] & 0xC0 == 0x80
        }

        // Count scalars in the shared byte prefix.
        var scalarCount = 0
        var j = 0
        while j < i {
            let b = lSpan[j]
            if b < 0x80 { j += 1 }
            else if b < 0xE0 { j += 2 }
            else if b < 0xF0 { j += 3 }
            else { j += 4 }
            scalarCount += 1
        }

        // Decode the first unequal scalar from each side.
        let lNextVal: UInt32? = i < lLen ? decodeScalarFromSpan(lSpan, at: i) : nil
        let rNextVal: UInt32? = i < rLen ? decodeScalarFromSpan(rSpan, at: i) : nil

        // Unsafe-start check: if restarting at either boundary scalar is not
        // provably equivalent to full iteration, fall back to the start.
        if scalarCount > 0,
           (lNextVal.map { safety.isUnsafe($0, numeric: numeric) } ?? false)
            || (rNextVal.map { safety.isUnsafe($0, numeric: numeric) } ?? false) {
            return PrefixSkipResult(shared: 0, lNext: lNextVal, rNext: rNextVal, fellBack: true)
        }

        return PrefixSkipResult(shared: scalarCount, lNext: lNextVal, rNext: rNextVal, fellBack: false)
    }

    /// Decodes a single scalar from a Span at the given byte offset (which
    /// must be a lead byte of well-formed UTF-8).
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @inline(__always)
    private static func decodeScalarFromSpan(_ span: Span<UInt8>, at i: Int) -> UInt32 {
        let b0 = UInt32(span[i])
        if b0 < 0x80 { return b0 }
        let b1 = UInt32(span[i + 1]) & 0x3F
        if b0 < 0xE0 {
            return ((b0 & 0x1F) << 6) | b1
        }
        let b2 = UInt32(span[i + 2]) & 0x3F
        if b0 < 0xF0 {
            return ((b0 & 0x0F) << 12) | (b1 << 6) | b2
        }
        let b3 = UInt32(span[i + 3]) & 0x3F
        return ((b0 & 0x07) << 18) | (b1 << 12) | (b2 << 6) | b3
    }

    /// All CEs of a string, terminated by NO_CE.
    func collationElements(of s: String, numeric: Bool = false) throws -> [Int64] {
        var iter = CEIterator(
            data: data, base: base, norm: norm, numeric: numeric, scalars: s.unicodeScalars)
        return try iter.collectAll()
    }

    /// All primary weights (including ignorable zeros, excluding the NO_CE
    /// terminator) for a string. Test hook.
    func primaries(of s: String) throws -> [UInt32] {
        try collationElements(of: s).dropLast().map { UInt32(truncatingIfNeeded: $0 >> 32) }
    }

    /// The NFD form of a string as produced by the fused front end. Test hook.
    func nfd(_ s: String) -> String {
        var iter = NFDIterator(norm: norm, scalars: s.unicodeScalars)
        var result = ""
        while let c = iter.next() {
            result.unicodeScalars.append(Unicode.Scalar(c)!)
        }
        return result
    }
}

/// Trivial (ARC-free) capture of everything the restart-safety check needs:
/// whether CE iteration restarted at a scalar is provably equivalent to full
/// iteration. (CollationData::isUnsafeBackward, adapted: ICU's set folds in
/// [:^lccc=0:] at load time, and ICU lets prefix (precontext) matching read
/// back into the skipped prefix, which our streaming iterator cannot — so
/// prefix-tagged characters are unsafe here instead.) Trivial so the byte
/// fast path's closures can capture it without retaining the collator's
/// storage; the collator must outlive it.
struct RestartSafety {
    let dataUnsafe: UnsafeBufferPointer<UInt32>
    let baseUnsafe: UnsafeBufferPointer<UInt32>
    let dataTrie: UTrie2
    let baseTrie: UTrie2?
    let norm: NormalizationDataView

    init(data: CollationData, base: CollationData?, norm: NormalizationData) {
        dataUnsafe = data.unsafeBackward
        baseUnsafe = base?.unsafeBackward ?? UnsafeBufferPointer(start: nil, count: 0)
        dataTrie = data.trie
        baseTrie = base?.trie
        self.norm = norm.view
    }

    func isUnsafe(_ c: UInt32, numeric: Bool) -> Bool {
        if CollationData.boundariesContain(dataUnsafe, c) { return true }
        if !baseUnsafe.isEmpty, CollationData.boundariesContain(baseUnsafe, c) { return true }
        if norm.leadCCC(c) != 0 { return true }
        var ce32 = dataTrie.get(c)
        if ce32 == CollationConstants.fallbackCE32, let baseTrie {
            ce32 = baseTrie.get(c)
        }
        guard CollationConstants.isSpecialCE32(ce32) else { return false }
        let tag = CollationConstants.tagFromCE32(ce32)
        return tag == .prefix || (numeric && tag == .digit)
    }
}
