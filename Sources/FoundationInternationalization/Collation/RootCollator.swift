// String comparison against the CLDR root collation.
//
// Ported from ICU4C's "collation v2" design on the ICU4X architectural model:
// - input is incrementally NFD-decomposed and canonically reordered before CE lookup (the fused-decomposition front end), so arbitrary non-NFD input compares correctly
// - all strengths (primary..quaternary, identical) and settings: alternate shifted + maxVariable, case-first, case-level, backwards-secondary ("French"), numeric (CODAN)
// - full context-dependent mappings: contraction (suffix) matching including discontiguous contractions per UTS #10 S2.1, and prefix matching over the two preceding scalars (sufficient for all CLDR prefixes)
// - root plus compiled tailorings with script reordering; works against both the regular root data (with canonical closure) and the NFD-only variant

// @unchecked: the two stored views (fast Latin table, restart safety) point into the storage owned by `data`/`base`/`norm`, which the struct retains; everything is immutable after init.
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

    /// Trivial-field views for the static quick-CJK dispatch: everything `quickCJKPrimary` needs, resolved at init so the pinned-buffer closures can call a static function with plain parameters.
    struct QuickCJKSetup {
        let eligible: Bool
        let dataTrie: UTrie2
        let dataCEs: UnsafeBufferPointer<Int64>
        let hasBase: Bool
        let baseTrie: UTrie2
        let baseCEs: UnsafeBufferPointer<Int64>
    }

    /// All stored state lives behind one class reference so a RootCollator value is a single pointer. As a flat struct the collator was ~768 bytes; every method call materialized that copy on the stack (and a throwing call in a loop re-copied it per iteration — the optimizer cannot hoist the copy across a throwing call). Everything is immutable after init.
    final class Storage: @unchecked Sendable {
        let data: CollationData
        /// The base (root) data when `data` is a tailoring.
        let base: CollationData?
        let norm: NormalizationData
        /// Script reordering from the tailoring, if any.
        let reordering: Reordering?
        /// The tailoring's default options (e.g. backwards-secondary for fr-CA); plain defaults for the root collator.
        let defaultOptions: CollationOptions
        /// Thread-local buffer stash: each thread caches one ScratchBuffers instance, eliminating all locking and ARC on the take/give path.
        let threadLocal = ThreadLocalScratch()
        /// The most recently used fast-Latin setup (per options word) — fallback for non-default options.
        let fastLatinCache = FastLatinCache()
        /// Pre-baked fast-Latin setup for the default options: primaries and packed options resolved once at init. The fast path reads these directly — no lock, no cache, no ARC.
        let defaultFLPrimaries: UnsafeBufferPointer<UInt16>
        let defaultFLPackedOptions: Int32
        let defaultFLWord: Int32
        /// Owns the memory behind defaultFLPrimaries.
        let defaultFLStorage: DataStorage
        /// Pre-computed full 64-bit CEs for ASCII (0–127). Entry is 0 for characters needing full pipeline (digits, U+0000). Eliminates trie lookup + tag dispatch for common characters in the sort key path.
        let simpleCEs: UnsafeBufferPointer<Int64>
        let thaiCEs: UnsafeBufferPointer<Int64>
        /// The same two tables with DIGIT-tag characters resolved to the CE they produce when numeric collation is off. Only valid for numeric=off, so the CE iterator selects between the variants per reset; digit-bearing text (paths, filenames, version strings) then takes the table instead of the full pipeline.
        let simpleCEsWithDigits: UnsafeBufferPointer<Int64>
        let thaiCEsWithDigits: UnsafeBufferPointer<Int64>
        let simpleCEsStorage: DataStorage
        /// The fast Latin table: the tailoring's own, or the base's when the tailoring has none (CollationDataReader aliases the same way). Stored: rebuilding it per compare would retain `base` each time.
        let fastLatinTable: UnsafeBufferPointer<UInt16>
        /// Stored for the same reason; see RestartSafety.
        let restartSafety: RestartSafety
        /// Script-starts data: the root's when the tailoring omits it (resolved once — callers pass the same value used for the fast-Latin setup).
        let scriptsData: CollationData
        /// Compressible-lead-byte table: the tailoring's own, or the base's when the tailoring omits it (the fastLatinTable aliasing rule).
        let compressibleBytes: UnsafeBufferPointer<Bool>
        /// Trivial-field views for the static quick-CJK dispatch, heap-boxed so the hot path passes one pointer.
        let quickCJKSetupPtr: UnsafeMutablePointer<QuickCJKSetup>

        init(data: CollationData, base: CollationData?, norm: NormalizationData,
             reordering: Reordering?, defaultOptions: CollationOptions,
             fastLatinTable: UnsafeBufferPointer<UInt16>, scriptsData: CollationData) {
            self.data = data
            self.base = base
            self.norm = norm
            self.reordering = reordering
            self.defaultOptions = defaultOptions
            self.fastLatinTable = fastLatinTable
            self.restartSafety = RestartSafety(data: data, base: base, norm: norm)
            self.scriptsData = scriptsData
            if data.compressibleBytes.isEmpty {
                guard let base else {
                    preconditionFailure("collation data has neither its own compressible-byte table nor a base to inherit one from")
                }
                self.compressibleBytes = base.compressibleBytes
            } else {
                self.compressibleBytes = data.compressibleBytes
            }
            // Pre-bake the default-options fast-Latin setup.
            var prims: [UInt16] = []
            let packed = CollationFastLatin.getOptions(
                table: fastLatinTable, scriptsData: scriptsData, reordering: reordering,
                options: defaultOptions.icuOptions, primaries: &prims)
            let flStorage = DataStorage()
            self.defaultFLPrimaries = flStorage.store(prims)
            self.defaultFLPackedOptions = packed
            self.defaultFLWord = defaultOptions.icuOptions
            self.defaultFLStorage = flStorage
            // Pre-compute simple-CE tables: ASCII, and the Thai block (U+0E00–0E7F — the one non-Latin script whose hot scalars are mostly single simple CEs; profiling put ~200 ns of Thai compares in CE production). Same exclusion rules for both: specials (contractions, prefixes, digits) stay 0 and take the full path.
            let ceStorage = DataStorage()
            self.simpleCEs = RootCollator.buildSimpleCEs(data: data, base: base, storage: ceStorage)
            self.thaiCEs = RootCollator.buildSimpleCEs(data: data, base: base, storage: ceStorage, from: 0x0E00)
            self.simpleCEsWithDigits = RootCollator.buildSimpleCEs(
                data: data, base: base, storage: ceStorage, resolvingDigits: true)
            self.thaiCEsWithDigits = RootCollator.buildSimpleCEs(
                data: data, base: base, storage: ceStorage, from: 0x0E00, resolvingDigits: true)
            self.simpleCEsStorage = ceStorage
            // Quick-CJK dispatch setup: bare primary comparison is unsound under script reordering or a shifted default, so gate it off for those collators (compareBody handles them).
            let setup = QuickCJKSetup(
                eligible: reordering == nil && defaultOptions.alternate != .shifted,
                dataTrie: data.trie, dataCEs: data.ces,
                hasBase: base != nil,
                baseTrie: base?.trie ?? data.trie,
                baseCEs: base?.ces ?? data.ces)
            let box = UnsafeMutablePointer<QuickCJKSetup>.allocate(capacity: 1)
            box.initialize(to: setup)
            self.quickCJKSetupPtr = box
        }

        deinit {
            quickCJKSetupPtr.deinitialize(count: 1)
            quickCJKSetupPtr.deallocate()
        }
    }

    private let storage: Storage

    // Forwarders: same names the rest of the module already uses.
    var data: CollationData { storage.data }
    var base: CollationData? { storage.base }
    var norm: NormalizationData { storage.norm }
    var reordering: Reordering? { storage.reordering }
    public var defaultOptions: CollationOptions { storage.defaultOptions }
    private var threadLocal: ThreadLocalScratch { storage.threadLocal }
    private var fastLatinCache: FastLatinCache { storage.fastLatinCache }
    private var defaultFLPrimaries: UnsafeBufferPointer<UInt16> { storage.defaultFLPrimaries }
    private var defaultFLPackedOptions: Int32 { storage.defaultFLPackedOptions }
    private var defaultFLWord: Int32 { storage.defaultFLWord }
    var simpleCEs: UnsafeBufferPointer<Int64> { storage.simpleCEs }
    var thaiCEs: UnsafeBufferPointer<Int64> { storage.thaiCEs }
    var simpleCEsWithDigits: UnsafeBufferPointer<Int64> { storage.simpleCEsWithDigits }
    var thaiCEsWithDigits: UnsafeBufferPointer<Int64> { storage.thaiCEsWithDigits }
    var fastLatinTable: UnsafeBufferPointer<UInt16> { storage.fastLatinTable }
    var restartSafety: RestartSafety { storage.restartSafety }

    public init(data: CollationData, norm: NormalizationData) {
        self.storage = Storage(
            data: data, base: nil, norm: norm, reordering: nil,
            defaultOptions: CollationOptions(),
            fastLatinTable: data.fastLatinTable, scriptsData: data)
    }

    public init() throws {
        self.init(data: try CollationData.root(), norm: try NormalizationData.standard())
    }

    /// A collator for a bundled locale tailoring (e.g. "sv", "de-phonebook", "fr_CA", "ja", "zh"), based on the regular root data.
    public init(tailoringNamed name: String) throws {
        let tailoring = try CollationData.tailoring(bytes: CollationData.tailoring(named: name))
        let root = try CollationData.root()
        let data: CollationData
        let base: CollationData?
        if let tailoringData = tailoring.data {
            data = tailoringData
            base = root
        } else {
            // Settings-only tailoring (e.g. fr-CA): use the base data directly.
            data = root
            base = nil
        }
        let fastLatinTable = data.fastLatinTable.isEmpty
            ? (base?.fastLatinTable ?? data.fastLatinTable) : data.fastLatinTable
        self.storage = Storage(
            data: data, base: base, norm: try NormalizationData.standard(),
            reordering: tailoring.reordering,
            defaultOptions: CollationOptions(icuOptionsWord: tailoring.options),
            fastLatinTable: fastLatinTable,
            scriptsData: data.scriptStarts.isEmpty ? root : data)
    }

    // MARK: Comparison

    /// Compares two strings. When `options` is nil, the collator's own default options apply — the tailoring's settings (fr_CA backwards secondary, da upper-first, ...), plain tertiary defaults for root — matching a collator opened by ucol_open.
    ///
    /// Hot/cold split: the default-options fast-Latin byte path lives in a non-throwing function (it cannot fail), so the error-handling ABI is only paid when the CE pipeline actually runs. Measured on Intel: `throws` alone cost 10 ns/call on the fast path — two thirds of the entire mini-CE comparison.
    @inline(__always)
    public func compare(_ left: String, _ right: String) throws -> Order {
        try compare(left, right, options: defaultOptions)
    }

    /// Explicit-options variant; the no-options overload above forwards with the collator's defaults. Overloads, not an optional default parameter: the Optional wrap plus nil-resolution branch cost +2..3 ns on the hot entry (measured, EngineBench A/B).
    public func compare(
        _ left: String, _ right: String, options: CollationOptions
    ) throws -> Order {
        var skipWalk = false
        if let fast = compareFastPath(left, right, options: options, skipWalk: &skipWalk) {
            return fast
        }
        return try compareSlowPath(left, right, options: options, skipWalk: skipWalk)
    }

    /// The default-options UTF-8 fast-Latin byte path (the byte-level identical-prefix scan of ICU's UTF-8 doCompare + CollationFastLatin::compareUTF8): native Swift strings expose contiguous UTF-8, so characters are read as raw bytes with no scalar decoding. Returns nil when the options don't match the pre-baked default setup or the byte path bails (non-Latin text, unsafe restart, non-contiguous storage) — the caller then runs the throwing pipeline.
    private func compareFastPath(
        _ left: String, _ right: String, options: CollationOptions,
        skipWalk: inout Bool
    ) -> Order? {
        guard defaultFLPackedOptions >= 0, options.strength != .identical,
              options.icuOptions == defaultFLWord,
              !fastLatinTable.isEmpty else { return nil }
        var unsafeRestart = false
        let fast: Int32 = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                let f = RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: self.fastLatinTable,
                    primaries: self.defaultFLPrimaries,
                    options: self.defaultFLPackedOptions,
                    numeric: options.numeric, safety: self.restartSafety,
                    mismatch: &mismatch)
                if f != CollationFastLatin.bailOutResult { return f }
                let q = RootCollator.quickCJKDispatch(
                    lBytes, rBytes, at: mismatch,
                    setup: self.storage.quickCJKSetupPtr,
                    numeric: options.numeric, safety: self.restartSafety)
                if q != CollationFastLatin.bailOutResult { return q }
                // Headed for the pipeline: decide here — while the bytes are pinned — whether compareBody's identical-prefix walk would be discarded. STATIC helper with trivial parameters — instance methods or fat arguments called from these pinned-buffer closures regress every corpus.
                unsafeRestart = RootCollator.mismatchRestartIsUnsafe(
                    lBytes, rBytes, at: mismatch,
                    safety: self.restartSafety, numeric: options.numeric)
                return CollationFastLatin.bailOutResult
            } ?? CollationFastLatin.bailOutResult
        } ?? CollationFastLatin.bailOutResult
        if fast != CollationFastLatin.bailOutResult {
            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
        }
        skipWalk = unsafeRestart
        return nil
    }

    /// True when compareBody's identical-prefix walk is provably useless: the byte scan's mismatch offset locates the first differing scalars, and if either is an unsafe restart the walk always ends in the shared=0 fallback (88% of Thai dictionary pairs in probe statistics), so compareBody can reset from the start directly, which is exactly the behavior those pairs get today, minus the ~123 ns walk. Conservative false when the mismatch is at either string's end (a length-divergent pair keeps its walk) or out of view. STATIC with trivial parameters, like every helper called from the pinned-buffer closures.
    private static func mismatchRestartIsUnsafe(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        at mismatch: Int, safety: RestartSafety, numeric: Bool
    ) -> Bool {
        guard mismatch >= 0, mismatch < lBytes.count, mismatch < rBytes.count else {
            return false
        }
        // Back up to the scalar start: prefix bytes below the mismatch are equal on both sides, so both scalars start at the same offset and share the same lead byte (hence the same length, in bounds by UTF-8 validity of native Strings).
        var start = mismatch
        while start > 0, lBytes[start] & 0xc0 == 0x80 { start -= 1 }
        let lc = scalarAt(lBytes, start)
        let rc = scalarAt(rBytes, start)
        return safety.isUnsafe(lc, numeric: numeric) || safety.isUnsafe(rc, numeric: numeric)
    }

    /// Quick-primary CJK dispatch at the byte-scan's mismatch offset, called only after fastLatinUTF8 bails (CJK/Thai text) — Latin-resolved compares never evaluate it or its arguments. When both first-differing scalars are CJK ideographs with distinct single-CE primaries — the dominant case for CJK text — this decides the compare right here, skipping compareBody's fresh scalar iterators and re-decode (~21 ns against ~200 ns of machinery).
    ///
    /// STATIC with trivial parameters, deliberately: calling an instance method inside the contiguous-storage closures measurably degrades codegen for every corpus (+17-22% — measured twice, 07-06 and 07-13); the setup travels as one pointer for the same reason. The safety gate mirrors compareBody's: a mismatch at offset 0 has no preceding prefix, so restart safety is trivially met; deeper mismatches require both restart scalars to be safe.
    private static func quickCJKDispatch(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        at mismatch: Int,
        setup: UnsafePointer<QuickCJKSetup>,
        numeric: Bool, safety: RestartSafety
    ) -> Int32 {
        if setup.pointee.eligible, mismatch >= 0,
           mismatch < lBytes.count, mismatch < rBytes.count,
           // Lead-byte gate: all CJK-unified blocks start at U+3400, whose UTF-8 lead is 0xE3 (ext B+ uses 0xF0). One byte compare rejects Thai (0xE0) and most other non-CJK bail-outs before any decode.
           lBytes[mismatch] >= 0xE3, rBytes[mismatch] >= 0xE3 {
            let lc = scalarAt(lBytes, mismatch)
            let rc = scalarAt(rBytes, mismatch)
            if lc != rc, isCJKUnified(lc), isCJKUnified(rc) {
                let lp = quickCJKPrimary(lc, setup.pointee)
                if lp != 0 {
                    let rp = quickCJKPrimary(rc, setup.pointee)
                    if rp != 0, lp != rp,
                       mismatch == 0
                        || (!safety.isUnsafe(lc, numeric: numeric)
                            && !safety.isUnsafe(rc, numeric: numeric)) {
                        return lp < rp ? -1 : 1
                    }
                }
            }
        }
        return CollationFastLatin.bailOutResult
    }

    /// quickPrimary against the trivial init-resolved views (the static twin of the instance method below; the differential suites keep them in agreement). Returns 0 when the full pipeline must decide.
    private static func quickCJKPrimary(_ c: UInt32, _ q: QuickCJKSetup) -> UInt32 {
        var ce32 = q.dataTrie.get(c)
        var ces = q.dataCEs
        if ce32 == CollationConstants.fallbackCE32 {
            guard q.hasBase else { return 0 }
            ce32 = q.baseTrie.get(c)
            ces = q.baseCEs
        }
        guard CollationConstants.isSpecialCE32(ce32) else { return 0 }
        switch CollationConstants.tagFromCE32(ce32) {
        case .longPrimary:
            // long-primary form ppppppC1: the top three bytes are the primary.
            return ce32 & 0xffff_ff00
        case .offset:
            let idx = CollationConstants.indexFromCE32(ce32)
            guard idx < ces.count else { return 0 }
            return CollationConstants.threeBytePrimaryForOffsetData(c, ces[idx])
        case .implicit:
            return CollationConstants.unassignedPrimaryFromCodePoint(c)
        default:
            return 0
        }
    }

    /// The non-default-options byte path and the CE pipeline. `triedFastLatin` semantics: when the caller's fast path bailed, the byte scan already proved fast-Latin inapplicable, but compareBody re-derives that cheaply via its own eligibility checks, so no flag needs to be threaded.
    private func compareSlowPath(
        _ left: String, _ right: String, options: CollationOptions,
        skipWalk: Bool = false
    ) throws -> Order {
        var triedFastLatin = false
        if options.strength != .identical, case let table = fastLatinTable, !table.isEmpty {
            let word = options.icuOptions
            if word == defaultFLWord, defaultFLPackedOptions >= 0 {
                // The caller's fast path already ran for these options — but only if both strings had contiguous UTF-8 (bridged strings skip the byte path; compareBody's scalar fast-Latin should still get its chance on those).
                triedFastLatin = left.isContiguousUTF8 && right.isContiguousUTF8
            } else {
                let setup = resolveFastLatinSetup(word)
                if setup.packedOptions >= 0 {
                    let safety = restartSafety
                    let numeric = options.numeric
                    let fast: Int32? = left.utf8.withContiguousStorageIfAvailable { lBytes in
                        right.utf8.withContiguousStorageIfAvailable { rBytes in
                            setup.primaries.withUnsafeBufferPointer { pBuf in
                                var mismatch = -1
                                return RootCollator.fastLatinUTF8(
                                    lBytes, rBytes, table: table, primaries: pBuf,
                                    options: setup.packedOptions, numeric: numeric, safety: safety,
                                    mismatch: &mismatch)
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
            }
        }
        return try compareBody(
            left, right, options: options, triedFastLatin: triedFastLatin,
            skipWalk: skipWalk)
    }

    /// Shared compare body: identical-prefix skip, fast-Latin scalar path, CE pipeline, and identical level. Split out so compareClassic stays small.
    private func compareBody(
        _ left: String, _ right: String, options: CollationOptions, triedFastLatin: Bool,
        skipWalk: Bool = false
    ) throws -> Order {
        // No `if left == right` shortcut here. Swift's String == is canonical equivalence, which for non-binary-equal strings runs NFC normalization to prove (in)equality — measured at ~250–400 ns per call on text with combining marks (Thai, etc.), on *every* non-equal compare. Canonical equivalence is already handled correctly by the CE pipeline below (the NFD front end yields equal CEs for equivalent strings), so the shortcut was pure cost on the non-Latin path. The byte fast path above still settles binary equality cheaply for non-identical strengths.

        // Identical-prefix skip (RuleBasedCollator::doCompare): equal scalar prefixes produce identical CEs, so iteration can start at the first difference — when restarting there is provably equivalent to full iteration (see unsafeStart). On an unsafe boundary we compare from the start instead; ICU backs up partially, but skipping less is always sound and keeps the common path free of index arithmetic.
        var lIter = left.unicodeScalars.makeIterator()
        var rIter = right.unicodeScalars.makeIterator()
        var shared = 0
        var lNext: Unicode.Scalar? = nil
        var rNext: Unicode.Scalar? = nil
        var fellBack = false
        if skipWalk {
            // The byte scan already proved the first-differing scalar is an unsafe restart (mismatchRestartIsUnsafe): the walk below would end in the shared=0 fallback, so take that exit directly.
            fellBack = true
        } else {
            lNext = lIter.next()
            rNext = rIter.next()
            while let a = lNext, let b = rNext, a == b {
                shared += 1
                lNext = lIter.next()
                rNext = rIter.next()
            }
            if shared > 0,
               (lNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false)
                || (rNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false) {
                shared = 0
                fellBack = true
            }
        }

        // Quick primary comparison: if both first-differing scalars are in the CJK Unified Ideographs range and map to OFFSET/IMPLICIT CEs, the comparison is decided here without the CE pipeline.
        if !fellBack, let l = lNext, let r = rNext, l != r,
           options.strength != .identical,
           Self.isCJKUnified(l.value), Self.isCJKUnified(r.value) {
            let qp = quickPrimaryCompare(l.value, r.value, options: options)
            if qp != 0 { return qp < 0 ? .ascending : .descending }
        }

        // Fast Latin (CollationFastLatin): when both remainders start within the mini-CE table's range, compare on the precompiled table with no iterator pipeline (and no scratch buffers); any unsupported character or mapping bails out to the regular path. The skip walk's iterators are reusable unless an unsafe boundary forced the comparison back to the start.
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
            // CEs are generated lazily: the primary level usually decides the comparison after a few characters.
            let s = takeScratch()
            scratch = s
            if fellBack {
                // The skip was abandoned (unsafe boundary): iterate from start.
                s.left.reset(numeric: options.numeric, scalars: left.unicodeScalars)
                s.right.reset(numeric: options.numeric, scalars: right.unicodeScalars)
            } else {
                // Reuse the skip-walk iterators, already positioned past the shared prefix, with the first unequal scalar (lNext/rNext) pending. Saves two String-iterator builds and re-walking the prefix that reset(skippingFirst:) would do.
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
            // Identical level: compare NFD forms in code point order, with end-of-string below U+FFFE (merge separator) below all code points. (compareNFDIter: end = -2, U+FFFE = -1.)
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

    /// Searches for `pattern` within `text` at the given collation strength. Returns the range of the first match, or nil if not found.
    @inline(__always)
    public func search(for pattern: String, in text: String) -> Range<String.Index>? {
        search(for: pattern, in: text, options: defaultOptions)
    }

    public func search(
        for pattern: String, in text: String, options: CollationOptions
    ) -> Range<String.Index>? {
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        let searcher = CollationSearch(
            storage: storage, options: options,
            variableTopValue: variableTopValue(options)
        )
        return searcher.search(for: pattern, in: text, scratch: scratch)
    }

    /// Searches backwards for `pattern` in `text`. Returns the range of the last match, or nil if not found.
    @inline(__always)
    public func searchBackwards(for pattern: String, in text: String) -> Range<String.Index>? {
        searchBackwards(for: pattern, in: text, options: defaultOptions)
    }

    public func searchBackwards(
        for pattern: String, in text: String, options: CollationOptions
    ) -> Range<String.Index>? {
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        let searcher = CollationSearch(
            storage: storage, options: options,
            variableTopValue: variableTopValue(options)
        )
        return searcher.searchBackwards(for: pattern, in: text, scratch: scratch)
    }

    /// Returns true if `text` contains `pattern` at the given collation strength.
    @inline(__always)
    public func contains(pattern: String, in text: String) -> Bool {
        contains(pattern: pattern, in: text, options: defaultOptions)
    }

    public func contains(
        pattern: String, in text: String, options: CollationOptions
    ) -> Bool {
        // Reuse the thread-local scratch iterator across calls — searching one pattern over many strings (the localizedStandardContains case) then allocates no per-call CEIterator or CE buffer.
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        let searcher = CollationSearch(
            storage: storage, options: options,
            variableTopValue: variableTopValue(options)
        )
        return searcher.contains(pattern: pattern, in: text, scratch: scratch)
    }

    /// The sort key for a string: level bytes with 01 separators, optional identical level (BOCSU over NFD), 00 terminator. Byte-wise comparison of two sort keys equals compare() at the same options.
    @inline(__always)
    public func sortKey(for s: String) throws -> [UInt8] {
        try sortKey(for: s, options: defaultOptions)
    }

    public func sortKey(
        for s: String, options: CollationOptions
    ) throws -> [UInt8] {
        var key: [UInt8] = []
        try sortKey(for: s, into: &key, options: options)
        return key
    }

    /// Generates the sort key for a string into a caller-supplied buffer. The buffer is cleared and filled with the key bytes (level bytes with 01 separators, optional identical level, 00 terminator). Reusing the same buffer across calls avoids per-call allocation — the steady-state path is zero-alloc after the buffer has grown to working capacity.
    ///
    /// This is the ICU `ucol_getSortKey(dest, destCapacity)` model: the caller owns the output memory.
    @inline(__always)
    public func sortKey(for s: String, into key: inout [UInt8]) throws {
        try sortKey(for: s, into: &key, options: defaultOptions)
    }

    public func sortKey(
        for s: String, into key: inout [UInt8], options: CollationOptions
    ) throws {
        let scratch = takeScratch()
        defer { giveScratch(scratch) }
        scratch.left.reset(numeric: options.numeric, scalars: s.unicodeScalars)
        _ = try scratch.left.collectAll()
        let compressibleBytes = storage.compressibleBytes
        key.removeAll(keepingCapacity: true)
        // Single-pass writer: one traversal of the CE array, beyond-primary levels accumulated in one temporary region. The buffered writer stays as the reference implementation (the sk-ladder probe checks byte identity across the option matrix).
        CollationKeys.writeSortKeyUpToQuaternarySingle(
            ces: scratch.left.ces, compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, into: &key)
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
        threadLocal.take() ?? ScratchBuffers(data: data, base: base, norm: norm, simpleCEs: simpleCEs, thaiCEs: thaiCEs, simpleCEsWithDigits: simpleCEsWithDigits, thaiCEsWithDigits: thaiCEsWithDigits)
    }

    private func giveScratch(_ buffers: ScratchBuffers) {
        threadLocal.give(buffers)
    }

    /// True for CJK Unified Ideographs — characters that always map to a single CE with a unique primary via the OFFSET or IMPLICIT tag, have no canonical decomposition, and no canonical equivalents.
    @inline(__always)
    private static func isCJKUnified(_ c: UInt32) -> Bool {
        // CJK Unified Ideographs: U+4E00..U+9FFF CJK Extension A: U+3400..U+4DBF CJK Extension B+: U+20000..U+2A6DF (supplementary) CJK Compatibility Ideographs are NOT included (they decompose).
        (0x4E00...0x9FFF).contains(c) ||
        (0x3400...0x4DBF).contains(c) ||
        (0x20000...0x2A6DF).contains(c)
    }

    /// Builds a 128-entry table of pre-computed CEs for ASCII. Characters that map to a single simple CE (no expansion, no contraction, no prefix) get their full 64-bit CE stored; others get 0 (sentinel for "use full pipeline").
    ///
    /// With `resolvingDigits`, a DIGIT-tag character is followed through the one indirection that `appendCEs` takes when numeric collation is off, so digits get table entries too. Such a table is only valid for numeric=off — the CE iterator picks between the two variants per reset.
    private static func buildSimpleCEs(
        data: CollationData, base: CollationData?, storage: DataStorage,
        from start: UInt32 = 0, resolvingDigits: Bool = false
    ) -> UnsafeBufferPointer<Int64> {
        var table: [Int64] = Array(repeating: 0, count: 128)
        for i: UInt32 in 0..<128 {
            let c = start + i
            var owner = data
            var ce32 = data.trie.get(c)
            if ce32 == CollationConstants.fallbackCE32, let base {
                owner = base
                ce32 = base.trie.get(c)
            }
            if resolvingDigits, CollationConstants.isSpecialCE32(ce32),
               CollationConstants.tagFromCE32(ce32) == .digit {
                ce32 = owner.ce32s[CollationConstants.indexFromCE32(ce32)]
            }
            // Only handle the simple cases: non-special CE32s and long-primary/ long-secondary tags that produce exactly one CE.
            if !CollationConstants.isSpecialCE32(ce32) {
                table[Int(i)] = CollationConstants.ceFromCE32(ce32)
            } else {
                let tag = CollationConstants.tagFromCE32(ce32)
                switch tag {
                case .longPrimary, .longSecondary:
                    table[Int(i)] = CollationConstants.ceFromCE32(ce32)
                default:
                    // Expansions, contractions, digits, prefixes, u0000 — leave as 0.
                    break
                }
            }
        }
        return storage.store(table)
    }

    /// True if restarting CE iteration at `c` is not provably equivalent to full iteration (see RestartSafety).
    private func unsafeStart(_ c: UInt32, numeric: Bool) -> Bool {
        restartSafety.isUnsafe(c, numeric: numeric)
    }

    /// Attempts a quick primary-weight comparison of two scalars without entering the CE pipeline. Returns -1/0/1 if the primaries differ and the result is conclusive, or 0 if the full pipeline is needed (equal primaries, variable CEs, expansions, contractions, etc.).
    @inline(__always)
    private func quickPrimaryCompare(_ lc: UInt32, _ rc: UInt32, options: CollationOptions) -> Int {
        let lp = quickPrimary(lc)
        guard lp != 0 else { return 0 }
        let rp = quickPrimary(rc)
        guard rp != 0 else { return 0 }
        if lp == rp { return 0 }
        // Variable-weight check: if alternate=shifted and either primary is variable, we can't decide at primary level alone.
        if options.alternate == .shifted {
            let varTop = storage.scriptsData.lastPrimaryForGroup(
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

    /// Returns the primary weight for a scalar if it maps to a single CE (simple, LONG_PRIMARY, OFFSET, or IMPLICIT). Returns 0 for anything that needs the full pipeline (expansions, contractions, prefixes, etc.).
    @inline(__always)
    private func quickPrimary(_ c: UInt32) -> UInt32 {
        var ce32 = data.trie.get(c)
        var cesSource = data.ces
        if ce32 == CollationConstants.fallbackCE32 {
            guard let b = base else { return 0 }
            ce32 = b.trie.get(c)
            cesSource = b.ces
        }
        // Only handle tags that produce exactly ONE CE with a unique primary and common secondary/tertiary (CJK characters). Bail on anything else — simple CE32s can be case variants, Latin expansions, etc.
        guard CollationConstants.isSpecialCE32(ce32) else { return 0 }
        switch CollationConstants.tagFromCE32(ce32) {
        case .longPrimary:
            // long-primary form ppppppC1: the top three bytes are the primary. Single CE with common secondary/tertiary — safe to compare at the primary level (equal primaries fall through to the pipeline). This is the tag most REAL-WORLD Han carries; the offset/implicit tags below cover the rarer ideographs.
            return ce32 & 0xffff_ff00
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
        return storage.scriptsData.lastPrimaryForGroup(
            CollationData.reorderCodeFirst + options.maxVariable.rawValue)
    }



    /// The cached fast-Latin setup for an options word, computing and storing it on a cache miss.
    private func resolveFastLatinSetup(_ word: Int32) -> FastLatinSetup {
        if let cached = fastLatinCache.setup(for: word) {
            return cached
        }
        var primaries: [UInt16] = []
        let packed = CollationFastLatin.getOptions(
            table: fastLatinTable, scriptsData: storage.scriptsData, reordering: reordering,
            options: word, primaries: &primaries)
        let setup = FastLatinSetup(word: word, packedOptions: packed, primaries: primaries)
        fastLatinCache.store(setup)
        return setup
    }

    /// The byte fast path: identical-prefix scan on raw UTF-8, safety check, then CollationFastLatin.compareUTF8 from the restart offset. Returns -1/0/1, or bailOutResult when the regular path must run. Static with trivial parameters: it runs inside the contiguous-storage closures. (RuleBasedCollator::doCompare, UTF-8 variant.)
    private static func fastLatinUTF8(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        table: UnsafeBufferPointer<UInt16>, primaries: UnsafeBufferPointer<UInt16>,
        options packedOptions: Int32,
        numeric: Bool, safety: RestartSafety,
        mismatch: inout Int
    ) -> Int32 {
        // Identical-prefix scan on bytes: 8 at a time through unaligned UInt64 loads (XOR + trailing zeros finds the first differing byte on little-endian), byte-wise tail. Long shared prefixes (paths, thai) scan at word speed; a first-byte difference costs the same one comparison as the byte loop did.
        let lLength = lBytes.count
        let rLength = rBytes.count
        let minLength = min(lLength, rLength)
        var i = 0
        if minLength >= 8, let lBase = lBytes.baseAddress, let rBase = rBytes.baseAddress {
            let lRaw = UnsafeRawPointer(lBase)
            let rRaw = UnsafeRawPointer(rBase)
            let wordEnd = minLength & ~7
            while i < wordEnd {
                let lw = lRaw.loadUnaligned(fromByteOffset: i, as: UInt64.self)
                let rw = rRaw.loadUnaligned(fromByteOffset: i, as: UInt64.self)
                if lw != rw {
                    i += (lw ^ rw).trailingZeroBitCount >> 3
                    break
                }
                i += 8
            }
        }
        while i < minLength, lBytes[i] == rBytes[i] { i += 1 }
        if i == lLength && i == rLength { return 0 }  // binary equal
        // The restart offset for the caller's quick-CJK dispatch: valid whenever restarting at `i` is not known to be unsafe (-1 otherwise). Back up to the start of a partially-equal code point (trail bytes are 0x80..0xBF).
        if i > 0,
           (i != lLength && lBytes[i] & 0xc0 == 0x80) || (i != rLength && rBytes[i] & 0xc0 == 0x80) {
            repeat { i -= 1 } while i > 0 && lBytes[i] & 0xc0 == 0x80
        }
        mismatch = i
        if i > 0 {
            // The safety check below only decides whether to restart at `i` or at 0. If the bytes at `i` are not fast-path eligible AND the bytes at 0 are not either, both restart points bail — skip the isUnsafe binary searches entirely (every all-Thai/CJK compare with a shared prefix lands here).
            let lEligibleAtI = i == lLength || lBytes[i] <= CollationFastLatin.latinMaxUTF8Lead
            let rEligibleAtI = i == rLength || rBytes[i] <= CollationFastLatin.latinMaxUTF8Lead
            if !(lEligibleAtI && rEligibleAtI),
               lBytes[0] > CollationFastLatin.latinMaxUTF8Lead
                || rBytes[0] > CollationFastLatin.latinMaxUTF8Lead {
                return CollationFastLatin.bailOutResult
            }
            // Restarting at an unsafe scalar is not equivalent to full iteration: compare from the start instead (ICU backs up partially; skipping less is always sound).
            if (i != lLength && safety.isUnsafe(scalarAt(lBytes, i), numeric: numeric))
                || (i != rLength && safety.isUnsafe(scalarAt(rBytes, i), numeric: numeric)) {
                i = 0
                mismatch = -1
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

    /// Decodes the scalar at byte offset `i` (a lead byte of well-formed UTF-8, as produced by String).
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

    /// All primary weights (including ignorable zeros, excluding the NO_CE terminator) for a string. Test hook.
    func primaries(of s: String) throws -> [UInt32] {
        try collationElements(of: s).dropLast().map { UInt32(truncatingIfNeeded: $0 >> 32) }
    }

    /// The NFD form of a string as produced by the fused front end. Test hook.
    func nfd(_ s: String) -> String {
        var iter = NFDIterator(norm: norm, scalars: s.unicodeScalars)
        var result = ""
        while let c = iter.next() {
            guard let scalar = Unicode.Scalar(c) else {
                preconditionFailure("NFD iterator emitted an invalid scalar value \(c)")
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}

/// Trivial (ARC-free) capture of everything the restart-safety check needs: whether CE iteration restarted at a scalar is provably equivalent to full iteration. (CollationData::isUnsafeBackward, adapted: ICU's set folds in [:^lccc=0:] at load time, and ICU lets prefix (precontext) matching read back into the skipped prefix, which our streaming iterator cannot — so prefix-tagged characters are unsafe here instead.) Trivial so the byte fast path's closures can capture it without retaining the collator's storage; the collator must outlive it.
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
