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
    /// The most recently used fast-Latin setup (per options word) — fallback
    /// for non-default options.
    private let fastLatinCache = FastLatinCache()
    /// Pre-baked fast-Latin setup for the default options: primaries and
    /// packed options resolved once at init. The fast path reads these
    /// directly — no lock, no cache, no class reference, no ARC.
    private let defaultFLPrimaries: UnsafeBufferPointer<UInt16>
    private let defaultFLPackedOptions: Int32
    private let defaultFLWord: Int32
    /// Owns the memory behind defaultFLPrimaries.
    private let defaultFLStorage: DataStorage
    /// Pre-computed full 64-bit CEs for ASCII (0–127). Entry is 0 for
    /// characters needing full pipeline (digits, U+0000). Eliminates trie
    /// lookup + tag dispatch for common characters in the sort key path.
    let simpleCEs: UnsafeBufferPointer<Int64>
    private let simpleCEsStorage: DataStorage
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
        let opts = CollationOptions()
        self.restartSafety = RestartSafety(data: data, base: nil, norm: norm)
        // Pre-bake the default-options fast-Latin setup.
        var prims: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: data.fastLatinTable, scriptsData: data, reordering: nil,
            options: opts.icuOptions, primaries: &prims)
        let flStorage = DataStorage()
        self.defaultFLPrimaries = flStorage.store(prims)
        self.defaultFLPackedOptions = packed
        self.defaultFLWord = opts.icuOptions
        self.defaultFLStorage = flStorage
        // Pre-compute ASCII CE table.
        let ceStorage = DataStorage()
        self.simpleCEs = Self.buildSimpleCEs(data: data, base: nil, storage: ceStorage)
        self.simpleCEsStorage = ceStorage
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
        // Pre-bake the default-options fast-Latin setup.
        let scriptsData = data.scriptStarts.isEmpty ? root : data
        var prims: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: fastLatinTable, scriptsData: scriptsData, reordering: reordering,
            options: defaultOptions.icuOptions, primaries: &prims)
        let flStorage = DataStorage()
        self.defaultFLPrimaries = flStorage.store(prims)
        self.defaultFLPackedOptions = packed
        self.defaultFLWord = defaultOptions.icuOptions
        self.defaultFLStorage = flStorage
        // Pre-compute ASCII CE table.
        let ceStorage = DataStorage()
        self.simpleCEs = Self.buildSimpleCEs(data: data, base: base, storage: ceStorage)
        self.simpleCEsStorage = ceStorage
    }

    // MARK: Comparison

    /// Compares two strings under root collation.
    /// Defaults to tertiary strength with all options off, like ICU.
    public func compare(
        _ left: String, _ right: String, options: CollationOptions = CollationOptions()
    ) throws -> Order {
        try compareClassic(left, right, options: options)
    }

    /// Classic compare entry: the UTF-8 fast-Latin byte path, then compareBody.
    /// Factored into its own (small) function so the fast-Latin path optimises
    /// independently of the heavier CE pipeline in compareBody.
    private func compareClassic(
        _ left: String, _ right: String, options: CollationOptions
    ) throws -> Order {
        // UTF-8 byte fast path (the byte-level identical-prefix scan of
        // ICU's UTF-8 doCompare + CollationFastLatin::compareUTF8): native
        // Swift strings expose contiguous UTF-8, so characters are read as
        // raw bytes with no scalar decoding. The identical strength level
        // needs the NFD pipeline, so it keeps to the scalar path below.
        var triedFastLatin = false
        if options.strength != .identical, case let table = fastLatinTable, !table.isEmpty {
            let safety = restartSafety
            let numeric = options.numeric
            let word = options.icuOptions
            // Use pre-baked setup if options match (the common case).
            // No lock, no cache, no class reference.
            let primaries: UnsafeBufferPointer<UInt16>
            let packedOptions: Int32
            if word == defaultFLWord, defaultFLPackedOptions >= 0 {
                primaries = defaultFLPrimaries
                packedOptions = defaultFLPackedOptions
            } else {
                let setup = resolveFastLatinSetup(word)
                if setup.packedOptions >= 0 {
                    let fast: Int32? = left.utf8.withContiguousStorageIfAvailable { lBytes in
                        right.utf8.withContiguousStorageIfAvailable { rBytes in
                            setup.primaries.withUnsafeBufferPointer { pBuf in
                                RootCollator.fastLatinUTF8(
                                    lBytes, rBytes, table: table, primaries: pBuf,
                                    options: setup.packedOptions, numeric: numeric, safety: safety)
                            }
                        } ?? nil
                    } ?? nil
                    if let fast {
                        if fast != CollationFastLatin.bailOutResult {
                            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
                        }
                        triedFastLatin = true
                    }
                }
                return try compareBody(left, right, options: options, triedFastLatin: triedFastLatin)
            }
            if packedOptions >= 0 {
                let fast: Int32? = left.utf8.withContiguousStorageIfAvailable { lBytes in
                    right.utf8.withContiguousStorageIfAvailable { rBytes in
                        RootCollator.fastLatinUTF8(
                            lBytes, rBytes, table: table, primaries: primaries,
                            options: packedOptions, numeric: numeric, safety: safety)
                    } ?? nil
                } ?? nil
                if let fast {
                    if fast != CollationFastLatin.bailOutResult {
                        return fast < 0 ? .ascending : fast == 0 ? .same : .descending
                    }
                    triedFastLatin = true
                }
            }
        }
        return try compareBody(left, right, options: options, triedFastLatin: triedFastLatin)
    }

    /// Shared compare body: identical-prefix skip, fast-Latin scalar path, CE
    /// pipeline, and identical level. Split out so compareClassic stays small.
    private func compareBody(
        _ left: String, _ right: String, options: CollationOptions, triedFastLatin: Bool
    ) throws -> Order {
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
        var lIter = left.unicodeScalars.makeIterator()
        var rIter = right.unicodeScalars.makeIterator()
        var shared = 0
        var lNext = lIter.next()
        var rNext = rIter.next()
        while let a = lNext, let b = rNext, a == b {
            shared += 1
            lNext = lIter.next()
            rNext = rIter.next()
        }
        var fellBack = false
        if shared > 0,
           (lNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false)
            || (rNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false) {
            shared = 0
            fellBack = true
        }

        // Quick primary comparison: if both first-differing scalars are in
        // the CJK Unified Ideographs range and map to OFFSET/IMPLICIT CEs,
        // the comparison is decided here without the CE pipeline.
        if !fellBack, let l = lNext, let r = rNext, l != r,
           options.strength != .identical,
           Self.isCJKUnified(l.value), Self.isCJKUnified(r.value) {
            let qp = quickPrimaryCompare(l.value, r.value, options: options)
            if qp != 0 { return qp < 0 ? .ascending : .descending }
        }
        if shared > 0,
           (lNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false)
            || (rNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false) {
            shared = 0
            fellBack = true
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
            if shared > 0 || !fellBack {
                lSide = CollationFastLatin.Side(next: lNext?.value, rest: lIter)
                rSide = CollationFastLatin.Side(next: rNext?.value, rest: rIter)
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
                // Reuse the skip-walk iterators, already positioned past the
                // shared prefix, with the first unequal scalar (lNext/rNext)
                // pending. Saves two String-iterator builds and re-walking the
                // prefix that reset(skippingFirst:) would do.
                s.left.reset(numeric: options.numeric, source: lIter, first: lNext?.value)
                s.right.reset(numeric: options.numeric, source: rIter, first: rNext?.value)
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

    // MARK: Search

    /// Searches for `pattern` within `text` at the given collation strength.
    /// Returns the range of the first match, or nil if not found.
    public func search(
        for pattern: String, in text: String, options: CollationOptions = CollationOptions()
    ) -> Range<String.Index>? {
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        let searcher = CollationSearch(
            data: data, base: base, norm: norm, options: options,
            variableTopValue: variableTopValue(options)
        )
        return searcher.search(for: pattern, in: text, iter: &scratch.left)
    }

    /// Searches backwards for `pattern` in `text`. Returns the range of the
    /// last match, or nil if not found.
    public func searchBackwards(
        for pattern: String, in text: String, options: CollationOptions = CollationOptions()
    ) -> Range<String.Index>? {
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        let searcher = CollationSearch(
            data: data, base: base, norm: norm, options: options,
            variableTopValue: variableTopValue(options)
        )
        return searcher.searchBackwards(for: pattern, in: text, iter: &scratch.left)
    }

    /// Returns true if `text` contains `pattern` at the given collation strength.
    public func contains(
        pattern: String, in text: String, options: CollationOptions = CollationOptions()
    ) -> Bool {
        // Reuse the thread-local scratch iterator across calls — searching one
        // pattern over many strings (the localizedStandardContains case) then
        // allocates no per-call CEIterator or CE buffer.
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        let searcher = CollationSearch(
            data: data, base: base, norm: norm, options: options,
            variableTopValue: variableTopValue(options)
        )
        return searcher.contains(pattern: pattern, in: text, iter: &scratch.left)
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
        threadLocal.take() ?? ScratchBuffers(data: data, base: base, norm: norm, simpleCEs: simpleCEs)
    }

    private func giveScratch(_ buffers: ScratchBuffers) {
        threadLocal.give(buffers)
    }

    /// True for CJK Unified Ideographs — characters that always map to a
    /// single CE with a unique primary via the OFFSET or IMPLICIT tag, have
    /// no canonical decomposition, and no canonical equivalents.
    @inline(__always)
    private static func isCJKUnified(_ c: UInt32) -> Bool {
        // CJK Unified Ideographs: U+4E00..U+9FFF
        // CJK Extension A: U+3400..U+4DBF
        // CJK Extension B+: U+20000..U+2A6DF (supplementary)
        // CJK Compatibility Ideographs are NOT included (they decompose).
        (0x4E00...0x9FFF).contains(c) ||
        (0x3400...0x4DBF).contains(c) ||
        (0x20000...0x2A6DF).contains(c)
    }

    /// Builds a 128-entry table of pre-computed CEs for ASCII. Characters that
    /// map to a single simple CE (no expansion, no contraction, no prefix) get
    /// their full 64-bit CE stored; others get 0 (sentinel for "use full pipeline").
    private static func buildSimpleCEs(
        data: CollationData, base: CollationData?, storage: DataStorage
    ) -> UnsafeBufferPointer<Int64> {
        var table: [Int64] = Array(repeating: 0, count: 128)
        for c: UInt32 in 0..<128 {
            var ce32 = data.trie.get(c)
            if ce32 == CollationConstants.fallbackCE32, let base {
                ce32 = base.trie.get(c)
            }
            // Only handle the simple cases: non-special CE32s and long-primary/
            // long-secondary tags that produce exactly one CE.
            if !CollationConstants.isSpecialCE32(ce32) {
                table[Int(c)] = CollationConstants.ceFromCE32(ce32)
            } else {
                let tag = CollationConstants.tagFromCE32(ce32)
                switch tag {
                case .longPrimary, .longSecondary:
                    table[Int(c)] = CollationConstants.ceFromCE32(ce32)
                default:
                    // Expansions, contractions, digits, prefixes, u0000 — leave as 0.
                    break
                }
            }
        }
        return storage.store(table)
    }

    /// True if restarting CE iteration at `c` is not provably equivalent to
    /// full iteration (see RestartSafety).
    private func unsafeStart(_ c: UInt32, numeric: Bool) -> Bool {
        restartSafety.isUnsafe(c, numeric: numeric)
    }

    /// Attempts a quick primary-weight comparison of two scalars without
    /// entering the CE pipeline. Returns -1/0/1 if the primaries differ and
    /// the result is conclusive, or 0 if the full pipeline is needed (equal
    /// primaries, variable CEs, expansions, contractions, etc.).
    @inline(__always)
    private func quickPrimaryCompare(_ lc: UInt32, _ rc: UInt32, options: CollationOptions) -> Int {
        let lp = quickPrimary(lc)
        guard lp != 0 else { return 0 }
        let rp = quickPrimary(rc)
        guard rp != 0 else { return 0 }
        if lp == rp { return 0 }
        // Variable-weight check: if alternate=shifted and either primary is
        // variable, we can't decide at primary level alone.
        if options.alternate == .shifted {
            let varTop = scriptsData.lastPrimaryForGroup(
                CollationData.reorderCodeFirst + options.maxVariable.rawValue) + 1
            if lp < varTop || rp < varTop { return 0 }
        }
        // Script reordering: apply the permutation before comparing.
        var lFinal = lp
        var rFinal = rp
        if let reordering {
            lFinal = reordering.reorder(lp)
            rFinal = reordering.reorder(rp)
        }
        return lFinal < rFinal ? -1 : 1
    }

    /// Returns the primary weight for a scalar if it maps to a single CE
    /// (simple, LONG_PRIMARY, OFFSET, or IMPLICIT). Returns 0 for anything
    /// that needs the full pipeline (expansions, contractions, prefixes, etc.).
    @inline(__always)
    private func quickPrimary(_ c: UInt32) -> UInt32 {
        var ce32 = data.trie.get(c)
        var cesSource = data.ces
        if ce32 == CollationConstants.fallbackCE32 {
            guard let b = base else { return 0 }
            ce32 = b.trie.get(c)
            cesSource = b.ces
        }
        // Only handle tags that produce exactly ONE CE with a unique primary
        // and common secondary/tertiary (CJK characters). Bail on anything
        // else — simple CE32s can be case variants, Latin expansions, etc.
        guard CollationConstants.isSpecialCE32(ce32) else { return 0 }
        switch CollationConstants.tagFromCE32(ce32) {
        case .offset:
            let idx = CollationConstants.indexFromCE32(ce32)
            guard idx < cesSource.count else { return 0 }
            let dataCE = cesSource[idx]
            return CollationConstants.threeBytePrimaryForOffsetData(c, dataCE)
        case .implicit:
            return CollationConstants.unassignedPrimaryFromCodePoint(c)
        default:
            return 0
        }
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
        table: UnsafeBufferPointer<UInt16>, primaries: UnsafeBufferPointer<UInt16>,
        options packedOptions: Int32,
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

        return CollationFastLatin.compareUTF8(
            table: table, primaries: primaries, options: packedOptions,
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
    let safeBelowCP: UInt32
    let safeBelowCPNumeric: UInt32

    init(data: CollationData, base: CollationData?, norm: NormalizationData) {
        dataUnsafe = data.unsafeBackward
        baseUnsafe = base?.unsafeBackward ?? UnsafeBufferPointer(start: nil, count: 0)
        dataTrie = data.trie
        baseTrie = base?.trie
        self.norm = norm.view

        safeBelowCP = Self.computeSafeThreshold(
            dataUnsafe: dataUnsafe, baseUnsafe: baseUnsafe,
            dataTrie: dataTrie, baseTrie: baseTrie, norm: norm.view, numeric: false)
        safeBelowCPNumeric = Self.computeSafeThreshold(
            dataUnsafe: dataUnsafe, baseUnsafe: baseUnsafe,
            dataTrie: dataTrie, baseTrie: baseTrie, norm: norm.view, numeric: true)
    }

    private static func computeSafeThreshold(
        dataUnsafe: UnsafeBufferPointer<UInt32>,
        baseUnsafe: UnsafeBufferPointer<UInt32>,
        dataTrie: UTrie2, baseTrie: UTrie2?,
        norm: NormalizationDataView, numeric: Bool
    ) -> UInt32 {
        var cp: UInt32 = 0
        let limit: UInt32 = 0x0300
        while cp < limit {
            if CollationData.boundariesContain(dataUnsafe, cp) { break }
            if !baseUnsafe.isEmpty, CollationData.boundariesContain(baseUnsafe, cp) { break }
            if norm.leadCCC(cp) != 0 { break }
            var ce32 = dataTrie.get(cp)
            if ce32 == CollationConstants.fallbackCE32, let baseTrie {
                ce32 = baseTrie.get(cp)
            }
            if CollationConstants.isSpecialCE32(ce32) {
                let tag = CollationConstants.tagFromCE32(ce32)
                if tag == .prefix || (numeric && tag == .digit) { break }
            }
            cp += 1
        }
        return cp
    }

    @inline(__always)
    func isUnsafe(_ c: UInt32, numeric: Bool) -> Bool {
        let threshold = numeric ? safeBelowCPNumeric : safeBelowCP
        if c < threshold { return false }
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
