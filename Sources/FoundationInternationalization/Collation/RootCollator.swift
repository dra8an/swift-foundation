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

    /// The default-options fast-Latin setup, resolved at init and heap-boxed, so that compareFastPath reads its setup through ONE pointer instead of separate fields of the storage object. The compare ladder (technique log §50) put the entry's guard and those field loads at ~2.7 ns of a ~15 ns ascii compare, and the core it feeds at ~9 ns.
    ///
    /// RestartSafety is deliberately NOT a field of this box. It is a large struct (~190 bytes), and read here as a VALUE (`setup.pointee.safety`) it has to be copied before every use, because the memory behind the pointer could change — that variant cost paths compare +2.7%, 5 of 5 rounds. It has its own box instead (Storage.restartSafetyPtr), and the fast-Latin path passes a POINTER to it and calls `isUnsafe` on `pointee` in place, so its fields are read only where the core consults them: after a shared prefix (technique log §50).
    struct DefaultFastLatinSetup {
        /// The facts the entry guard needs that are fixed at init — packed options >= 0 (the options are fast-Latin-compatible), a non-empty table, and a default strength other than identical — folded into one flag.
        let eligible: Bool
        /// The default options as a bit pattern (see `bits(of:)`): the guard compares the caller's options with it in one masked 64-bit compare, 6 instructions, where computing and comparing the options word cost 22 per call (technique log §51).
        let optionBits: UInt64
        let packedOptions: Int32
        let table: UnsafeBufferPointer<UInt16>
        let primaries: UnsafeBufferPointer<UInt16>
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
        /// Combining marks and Greek (U+0300–037F): the one simple CE of a mark, else 0. A mark that reaches the CE iterator on its own (no contraction consumed it with its starter) takes this instead of the full pipeline — the second half of every decomposed accented letter (technique log §51).
        let markCEs: UnsafeBufferPointer<Int64>
        let simpleCEsStorage: DataStorage
        /// The fast Latin table: the tailoring's own, or the base's when the tailoring has none (CollationDataReader aliases the same way). Stored: rebuilding it per compare would retain `base` each time.
        let fastLatinTable: UnsafeBufferPointer<UInt16>
        /// Stored for the same reason; see RestartSafety.
        let restartSafety: RestartSafety
        /// Owns the memory behind restartSafety's latin table.
        let restartSafetyStorage: DataStorage
        /// The same RestartSafety, heap-boxed so the fast-Latin path can take ONE pointer to it and read its fields only where it consults them. Passed by value (or read from the `let` above inside the closures), the compiler loaded all its fields at the top of compareFastPath on EVERY call — about 18 loads and the stores to spill them — although the core consults it only when the two strings share a prefix (technique log §50).
        let restartSafetyPtr: UnsafeMutablePointer<RestartSafety>
        /// Script-starts data: the root's when the tailoring omits it (resolved once — callers pass the same value used for the fast-Latin setup).
        let scriptsData: CollationData
        /// Compressible-lead-byte table: the tailoring's own, or the base's when the tailoring omits it (the fastLatinTable aliasing rule).
        let compressibleBytes: UnsafeBufferPointer<Bool>
        /// Trivial-field views for the static quick-CJK dispatch, heap-boxed so the hot path passes one pointer.
        let quickCJKSetupPtr: UnsafeMutablePointer<QuickCJKSetup>
        /// The default-options fast-Latin setup in one box; see DefaultFastLatinSetup.
        let defaultFLSetupPtr: UnsafeMutablePointer<DefaultFastLatinSetup>

        init(data: CollationData, base: CollationData?, norm: NormalizationData,
             reordering: Reordering?, defaultOptions: CollationOptions,
             fastLatinTable: UnsafeBufferPointer<UInt16>, scriptsData: CollationData) {
            self.data = data
            self.base = base
            self.norm = norm
            self.reordering = reordering
            self.defaultOptions = defaultOptions
            self.fastLatinTable = fastLatinTable
            let safetyStorage = DataStorage()
            self.restartSafetyStorage = safetyStorage
            let safety = RestartSafety(data: data, base: base, norm: norm, storage: safetyStorage)
            self.restartSafety = safety
            let safetyBox = UnsafeMutablePointer<RestartSafety>.allocate(capacity: 1)
            safetyBox.initialize(to: safety)
            self.restartSafetyPtr = safetyBox
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
            let flPrimaries = flStorage.store(prims)
            self.defaultFLPrimaries = flPrimaries
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
            self.markCEs = RootCollator.buildSimpleCEs(data: data, base: base, storage: ceStorage, from: 0x0300)
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
            // The default fast-Latin setup in one box: the same values as the separate fields above, resolved once.
            let flBox = UnsafeMutablePointer<DefaultFastLatinSetup>.allocate(capacity: 1)
            flBox.initialize(to: DefaultFastLatinSetup(
                eligible: packed >= 0 && !fastLatinTable.isEmpty && defaultOptions.strength != .identical
                    && RootCollator.optionBitsAreExact,
                optionBits: RootCollator.bits(of: defaultOptions), packedOptions: packed,
                table: fastLatinTable, primaries: flPrimaries))
            self.defaultFLSetupPtr = flBox
        }

        deinit {
            quickCJKSetupPtr.deinitialize(count: 1)
            quickCJKSetupPtr.deallocate()
            defaultFLSetupPtr.deinitialize(count: 1)
            defaultFLSetupPtr.deallocate()
            restartSafetyPtr.deinitialize(count: 1)
            restartSafetyPtr.deallocate()
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
    private var defaultFLSetupPtr: UnsafeMutablePointer<DefaultFastLatinSetup> { storage.defaultFLSetupPtr }
    var simpleCEs: UnsafeBufferPointer<Int64> { storage.simpleCEs }
    var thaiCEs: UnsafeBufferPointer<Int64> { storage.thaiCEs }
    var simpleCEsWithDigits: UnsafeBufferPointer<Int64> { storage.simpleCEsWithDigits }
    var thaiCEsWithDigits: UnsafeBufferPointer<Int64> { storage.thaiCEsWithDigits }
    var markCEs: UnsafeBufferPointer<Int64> { storage.markCEs }
    var fastLatinTable: UnsafeBufferPointer<UInt16> { storage.fastLatinTable }
    var restartSafety: RestartSafety { storage.restartSafety }
    private var restartSafetyPtr: UnsafePointer<RestartSafety> { UnsafePointer(storage.restartSafetyPtr) }

    /// A collator over the given data. Not cached: every call builds its own storage (custom data, tests).
    public init(data: CollationData, norm: NormalizationData) {
        self.storage = Self.makeRootStorage(data: data, norm: norm)
    }

    /// The root collator. Its storage is built once per process and shared (it is immutable; the per-thread scratch buffers stay per thread), as ICU builds its root collator once. Building it took ~490 µs on every call (technique log §51).
    public init() throws {
        self.storage = try Self.rootStorage.get()
    }

    /// A collator for a bundled locale tailoring (e.g. "sv", "de-phonebook", "fr_CA", "ja", "zh"), based on the regular root data. Its storage is built once per process and name and shared, as ICU's UnifiedCache does for tailorings.
    public init(tailoringNamed name: String) throws {
        self.storage = try Self.tailoringStorages.storage(named: name)
    }

    private static let rootStorage = Result {
        makeRootStorage(data: try CollationData.root(), norm: try NormalizationData.standard())
    }

    private static let tailoringStorages = StorageCache()

    private static func makeRootStorage(data: CollationData, norm: NormalizationData) -> Storage {
        Storage(
            data: data, base: nil, norm: norm, reordering: nil,
            defaultOptions: CollationOptions(),
            fastLatinTable: data.fastLatinTable, scriptsData: data)
    }

    fileprivate static func makeTailoringStorage(named name: String) throws -> Storage {
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
        return Storage(
            data: data, base: base, norm: try NormalizationData.standard(),
            reordering: tailoring.reordering,
            defaultOptions: CollationOptions(icuOptionsWord: tailoring.options),
            fastLatinTable: fastLatinTable,
            scriptsData: data.scriptStarts.isEmpty ? root : data)
    }

    /// The tailoring storages built so far, by name. At most one entry per bundled tailoring; a process usually uses one or two. The lock is NOT held during a build (~0.2 ms): two threads that miss at the same time may both build, and the first insert wins, so every caller gets the same storage. A name that fails to load throws and is not stored.
    private final class StorageCache: @unchecked Sendable {
        private let lock = PoolLock()
        private var storages: [String: Storage] = [:]

        func storage(named name: String) throws -> Storage {
            lock.acquire()
            let cached = storages[name]
            lock.release()
            if let cached { return cached }
            let built = try RootCollator.makeTailoringStorage(named: name)
            lock.acquire()
            defer { lock.release() }
            if let winner = storages[name] { return winner }
            storages[name] = built
            return built
        }
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
        var restart = -1
        if let fast = compareFastPath(left, right, options: options, restart: &restart) {
            return fast
        }
        return try compareSlowPath(left, right, options: options, restart: restart)
    }

    /// The bytes of `options`, padded with a zero byte to 64 bits. Two option values are equal exactly when their patterns are equal: all seven fields are one byte (enum tags and Bools, which the compiler keeps canonical), so the 7-byte struct has no padding. A field-by-field `==` compiled to 13 more instructions than the options word, because the compiler rebuilt the stored value byte by byte. `CollationOptionsBitsTests` checks the claim over all 960 option combinations.
    @inline(__always)
    static func bits(of options: CollationOptions) -> UInt64 {
        var padded: (CollationOptions, UInt8) = (options, 0)
        return withUnsafeBytes(of: &padded) { $0.loadUnaligned(as: UInt64.self) }
    }

    /// False if CollationOptions ever outgrows 7 bytes: the pattern would then miss a field, so the default fast path turns itself off rather than match wrong options. A compile-time constant.
    static var optionBitsAreExact: Bool { MemoryLayout<(CollationOptions, UInt8)>.size == MemoryLayout<UInt64>.size }

    /// The default-options UTF-8 fast-Latin byte path (the byte-level identical-prefix scan of ICU's UTF-8 doCompare + CollationFastLatin::compareUTF8): native Swift strings expose contiguous UTF-8, so characters are read as raw bytes with no scalar decoding. Returns nil when the options don't match the pre-baked default setup or the byte path bails (non-Latin text, unsafe restart, non-contiguous storage) — the caller then runs the throwing pipeline.
    ///
    /// Force-inlined into `compare(_:_:options:)`: out of line, it was a second frame that saved and restored 12 registers on every call, with the restart flag passed through the stack and the `Order?` result tested again by the caller — 9 to 16 instructions per compare. Inlining `compareUTF8` as well was 2–3 instructions worse (more spills) (technique log §51).
    ///
    /// When it returns nil after the byte scan, `restart` holds the number of leading scalars that the CE pipeline may skip (see restartScalarCount), or -1 when the scan gave no position.
    @inline(__always)
    private func compareFastPath(
        _ left: String, _ right: String, options: CollationOptions,
        restart: inout Int
    ) -> Order? {
        // One pointer for the default setup, loaded once (see DefaultFastLatinSetup); the CJK setup pointer and the storage object likewise, so the closures below capture plain values, not self.
        let setup = defaultFLSetupPtr
        let st = storage
        let cjkSetup = st.quickCJKSetupPtr
        let safety = UnsafePointer(st.restartSafetyPtr)
        guard setup.pointee.eligible, Self.bits(of: options) == setup.pointee.optionBits else { return nil }
        // The setup values the core reads, taken out of the box once.
        let table = setup.pointee.table
        let primaries = setup.pointee.primaries
        let packed = setup.pointee.packedOptions
        var restartScalars = -1
        let fast: Int32 = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                // RestartSafety by POINTER to its own box (see Storage.restartSafetyPtr), not by value — see DefaultFastLatinSetup.
                let f = RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: table, primaries: primaries,
                    options: packed,
                    numeric: options.numeric, safety: safety,
                    mismatch: &mismatch)
                if f != CollationFastLatin.bailOutResult { return f }
                let q = RootCollator.quickCJKDispatch(
                    lBytes, rBytes, at: mismatch,
                    setup: cjkSetup,
                    numeric: options.numeric, safety: safety)
                if q != CollationFastLatin.bailOutResult { return q }
                // Headed for the pipeline: decide here — while the bytes are pinned — where compareBody may restart CE iteration, so it needs no identical-prefix walk of its own. STATIC helper with trivial parameters — instance methods or fat arguments called from these pinned-buffer closures regress every corpus.
                restartScalars = RootCollator.restartScalarCount(
                    lBytes, rBytes, at: mismatch,
                    safety: safety, numeric: options.numeric)
                return CollationFastLatin.bailOutResult
            } ?? CollationFastLatin.bailOutResult
        } ?? CollationFastLatin.bailOutResult
        if fast != CollationFastLatin.bailOutResult {
            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
        }
        restart = restartScalars
        return nil
    }

    /// The number of leading scalars that the CE pipeline may skip, from the byte scan's mismatch offset — ICU's backup rule (RuleBasedCollator::doCompare): if either first-differing scalar is unsafe to restart at, step back over the shared prefix while the scalar at the new position is unsafe. The scalar at the restart point is then safe, so no contraction, prefix match or canonical reordering crosses it — the same argument that already allows a restart at a safe mismatch. A mismatch at the end of one string counts the other string's next scalar only. Returns -1 when the scan gave no position (the Latin path's own unsafe reset); compareBody then walks the prefix itself.
    ///
    /// Before this, an unsafe mismatch restarted at 0, and a mismatch at a string end (one word a prefix of the next) went through compareBody's String-iterator walk and then usually restarted at 0 too: on the thai dictionary, ICU's rule restarts later on 39% of adjacent pairs (mean restart 1.15 against 0.40 scalars), and 20% of the pairs paid the walk (technique log §51). STATIC with trivial parameters, like every helper called from the pinned-buffer closures.
    ///
    /// Out of line on purpose: it runs only after the fast path bails, so its body may inline the scalar decode and the restart-safety table lookup (one step back cost two out-of-line calls) without adding register pressure to compareFastPath.
    @inline(never)
    private static func restartScalarCount(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        at mismatch: Int, safety: UnsafePointer<RestartSafety>, numeric: Bool
    ) -> Int {
        guard mismatch >= 0, mismatch <= lBytes.count, mismatch <= rBytes.count else { return -1 }
        // The scan leaves the mismatch at a scalar start; the bytes below it are equal on both sides.
        @inline(__always)
        func unsafe(_ bytes: UnsafeBufferPointer<UInt8>, _ i: Int) -> Bool {
            RestartSafety.isUnsafeInline(safety, decodeScalar(bytes, i), numeric: numeric)
        }
        var q = mismatch
        if q > 0, (q < lBytes.count && unsafe(lBytes, q)) || (q < rBytes.count && unsafe(rBytes, q)) {
            // while (--equalPrefixLength > 0 && isUnsafeBackward(left[equalPrefixLength])). Backwards, as ICU does: a forward pass that finds the last safe scalar and counts in one go measured 24 instructions worse per compare on thai (it must walk the whole prefix; this stops at the first safe scalar).
            repeat {
                q -= 1
                while q > 0, lBytes[q] & 0xc0 == 0x80 { q -= 1 }
            } while q > 0 && unsafe(lBytes, q)
        }
        var scalars = 0
        for k in 0..<q where lBytes[k] & 0xc0 != 0x80 { scalars += 1 }
        return scalars
    }

    /// Quick-primary CJK dispatch at the byte-scan's mismatch offset, called only after fastLatinUTF8 bails (CJK/Thai text) — Latin-resolved compares never evaluate it or its arguments. When both first-differing scalars are CJK ideographs with distinct single-CE primaries — the dominant case for CJK text — this decides the compare right here, skipping compareBody's fresh scalar iterators and re-decode (~21 ns against ~200 ns of machinery).
    ///
    /// STATIC with trivial parameters, deliberately: calling an instance method inside the contiguous-storage closures measurably degrades codegen for every corpus (+17-22% — measured twice, 07-06 and 07-13); the setup travels as one pointer for the same reason. The safety gate mirrors compareBody's: a mismatch at offset 0 has no preceding prefix, so restart safety is trivially met; deeper mismatches require both restart scalars to be safe.
    private static func quickCJKDispatch(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        at mismatch: Int,
        setup: UnsafePointer<QuickCJKSetup>,
        numeric: Bool, safety: UnsafePointer<RestartSafety>
    ) -> Int32 {
        if setup.pointee.eligible, mismatch >= 0,
           mismatch < lBytes.count, mismatch < rBytes.count,
           // Lead-byte gate: all CJK-unified blocks start at U+3400, whose UTF-8 lead is 0xE3 (ext B+ uses 0xF0). One byte compare rejects Thai (0xE0) and most other non-CJK bail-outs before any decode.
           lBytes[mismatch] >= 0xE3, rBytes[mismatch] >= 0xE3 {
            let lc = scalarAt(lBytes, mismatch)
            let rc = scalarAt(rBytes, mismatch)
            if lc != rc, isCJKUnified(lc), isCJKUnified(rc) {
                let lp = quickCJKPrimary(lc, setup)
                if lp != 0 {
                    let rp = quickCJKPrimary(rc, setup)
                    if rp != 0, lp != rp,
                       mismatch == 0
                        || (!RestartSafety.isUnsafe(safety, lc, numeric: numeric)
                            && !RestartSafety.isUnsafe(safety, rc, numeric: numeric)) {
                        return lp < rp ? -1 : 1
                    }
                }
            }
        }
        return CollationFastLatin.bailOutResult
    }

    /// quickPrimary against the trivial init-resolved views (the static twin of the instance method below; the differential suites keep them in agreement). Returns 0 when the full pipeline must decide.
    ///
    /// The setup comes BY POINTER and its fields are read in place. Passed by value out of the box (`setup.pointee`), the compiler copied all 144 bytes of QuickCJKSetup to the stack before each of the two calls — 20 instructions per CJK compare — because the memory behind the pointer could change (technique log §51).
    private static func quickCJKPrimary(_ c: UInt32, _ q: UnsafePointer<QuickCJKSetup>) -> UInt32 {
        var ce32 = q.pointee.dataTrie.get(c)
        var ces = q.pointee.dataCEs
        if ce32 == CollationConstants.fallbackCE32 {
            guard q.pointee.hasBase else { return 0 }
            ce32 = q.pointee.baseTrie.get(c)
            ces = q.pointee.baseCEs
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
        restart: Int = -1
    ) throws -> Order {
        // The options word, computed once for the whole slow path (22 instructions; compareBody used to compute it again — technique log §51).
        let word = options.icuOptions
        var triedFastLatin = false
        var restart = restart
        // The gate is checked here, before the call: computing the setup and pinning the strings first cost CJK sorts +2–4% for a pass that always bails on them.
        if options.strength == .identical,
           (left.utf8.first ?? 0) <= CollationFastLatin.latinMaxUTF8Lead,
           (right.utf8.first ?? 0) <= CollationFastLatin.latinMaxUTF8Lead,
           let decided = identicalStrengthTertiaryPass(left, right, options: options) {
            return decided
        }
        if options.strength != .identical, case let table = fastLatinTable, !table.isEmpty {
            if word == defaultFLWord, defaultFLPackedOptions >= 0 {
                // The caller's fast path already ran for these options — but only if both strings had contiguous UTF-8 (bridged strings skip the byte path; compareBody's scalar fast-Latin should still get its chance on those).
                triedFastLatin = left.isContiguousUTF8 && right.isContiguousUTF8
            } else {
                if let setup = resolveFastLatinSetup(word), setup.packedOptions >= 0 {
                    let safety = restartSafetyPtr
                    let numeric = options.numeric
                    let fast: Int32? = left.utf8.withContiguousStorageIfAvailable { lBytes in
                        right.utf8.withContiguousStorageIfAvailable { rBytes in
                            var mismatch = -1
                            return RootCollator.fastLatinUTF8(
                                lBytes, rBytes, table: table, primaries: setup.primaries,
                                options: setup.packedOptions, numeric: numeric, safety: safety,
                                mismatch: &mismatch)
                        } ?? nil
                    } ?? nil
                    if let fast {
                        if fast != CollationFastLatin.bailOutResult {
                            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
                        }
                        triedFastLatin = true
                        // The restart is placed later, in compareAfterOptionsPass: this pass decides the Latin compares, and any more code here made compareSlowPath too large to inline into `compare` (+76 instructions per ascii options compare in the `-no-WMO` build; technique log §51 (ac)).
                        restart = Self.optionsPassBailed
                    }
                }
            }
        }
        return try compareBody(
            left, right, options: options, word: word, triedFastLatin: triedFastLatin,
            restart: restart)
    }

    /// Identical strength — `.forcedOrdering`, and so `String.StandardComparator.localizedStandard` — skips the byte fast-Latin path. The levels are compared in order and the first difference decides, so a non-zero result at tertiary strength IS the identical-strength result; only ties need the quaternary and identical levels. This byte fast-Latin pass at tertiary settles almost every compare of distinct Latin strings; nil (a tie, a bail-out, no contiguous UTF-8) sends the caller on to the full path, unchanged. (`.localizedStandard` compares were ~22 ns and ~220 instructions slower than `localizedStandardCompare`; technique log §51.)
    ///
    /// Out of line, with its own fastLatinUTF8 call site: merged into compareSlowPath's byte pass, it changed the code of every non-default-options compare (+1–3% on `localizedStandardCompare` and the options compares). The caller runs it only when both strings start with a fast-Latin lead byte: CJK and Thai text always bailed here and paid for the attempt; a non-Latin start loses only this optimization.
    @inline(never)
    private func identicalStrengthTertiaryPass(_ left: String, _ right: String, options: CollationOptions) -> Order? {
        let table = fastLatinTable
        guard !table.isEmpty else { return nil }
        var tertiary = options
        tertiary.strength = .tertiary
        guard let setup = resolveFastLatinSetup(tertiary.icuOptions), setup.packedOptions >= 0 else { return nil }
        let safety = restartSafetyPtr
        let numeric = options.numeric
        let fast: Int32? = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                return RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: table, primaries: setup.primaries,
                    options: setup.packedOptions, numeric: numeric, safety: safety,
                    mismatch: &mismatch)
            } ?? nil
        } ?? nil
        guard let fast, fast != CollationFastLatin.bailOutResult, fast != 0 else { return nil }
        return fast < 0 ? .ascending : .descending
    }

    /// Shared compare body: identical-prefix skip, fast-Latin scalar path, CE pipeline, and identical level. Split out so compareClassic stays small. `word` is `options.icuOptions`, computed once by the caller. `restart` is the scalar count from the byte scan (restartScalarCount), or -1: then the body walks the prefix itself.
    private func compareBody(
        _ left: String, _ right: String, options: CollationOptions, word: Int32, triedFastLatin: Bool,
        restart: Int = -1
    ) throws -> Order {
        // No `if left == right` shortcut here. Swift's String == is canonical equivalence, which for non-binary-equal strings runs NFC normalization to prove (in)equality — measured at ~250–400 ns per call on text with combining marks (Thai, etc.), on *every* non-equal compare. Canonical equivalence is already handled correctly by the CE pipeline below (the NFD front end yields equal CEs for equivalent strings), so the shortcut was pure cost on the non-Latin path. The byte fast path above still settles binary equality cheaply for non-identical strengths.

        if restart >= 0 {
            return try compareFromRestart(left, right, options: options, word: word, restart: restart)
        }
        if restart == Self.optionsPassBailed, let decided = try compareAfterOptionsPass(left, right, options: options, word: word) {
            return decided
        }

        // Identical-prefix skip (RuleBasedCollator::doCompare): equal scalar prefixes produce identical CEs, so iteration can start at the first difference — when restarting there is provably equivalent to full iteration (see unsafeStart). When the byte scan already placed the restart (ICU's backup rule, restartScalarCount), compareFromRestart above runs instead. Here (non-default options, bridged strings) the walk finds the difference, and an unsafe boundary restarts at 0 — skipping less is always sound.
        var lIter = left.unicodeScalars.makeIterator()
        var rIter = right.unicodeScalars.makeIterator()
        var shared = 0
        var lNext: Unicode.Scalar? = lIter.next()
        var rNext: Unicode.Scalar? = rIter.next()
        var fellBack = false
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
                if let setup = resolveFastLatinSetup(word), setup.packedOptions >= 0 {
                    fastResult = CollationFastLatin.compare(
                        table: table, primaries: setup.primaries,
                        options: setup.packedOptions, left: lSide, right: rSide)
                }
            }
        }

        var scratch: ScratchBuffers?
        defer { if let scratch { giveScratch(scratch) } }
        var result: Int
        if fastResult != CollationFastLatin.bailOutResult {
            result = Int(fastResult)
        } else {
            // CEs are generated lazily: the primary level usually decides the comparison after a few characters.
            let s = takeScratch()
            scratch = s
            // Resets + comparison under one call; see resetBothAndCompare.
            if fellBack {
                // The skip was abandoned (unsafe boundary): iterate from start.
                result = try s.resetBothAndCompare(
                    numeric: options.numeric,
                    leftScalars: left.unicodeScalars, rightScalars: right.unicodeScalars,
                    options: word,
                    variableTopValue: variableTopValue(options), reordering: reordering)
            } else {
                // Reuse the skip-walk iterators, already positioned past the shared prefix, with the first unequal scalar (lNext/rNext) pending. Saves two String-iterator builds and re-walking the prefix that reset(skippingFirst:) would do.
                result = try s.resetBothAndCompare(
                    numeric: options.numeric,
                    leftSource: lIter, leftFirst: lNext?.value,
                    rightSource: rIter, rightFirst: rNext?.value,
                    prefixSkipped: shared > 0,
                    options: word,
                    variableTopValue: variableTopValue(options), reordering: reordering)
                if result == CollationCompare.prefixDependent {
                    // The skipped prefix can change the result (shifted, backward secondary): compare from the start.
                    result = try s.resetBothAndCompare(
                        numeric: options.numeric,
                        leftScalars: left.unicodeScalars, rightScalars: right.unicodeScalars,
                        options: word,
                        variableTopValue: variableTopValue(options), reordering: reordering)
                }
            }
        }
        if result != 0 {
            return result < 0 ? .ascending : .descending
        }
        if options.strength == .identical {
            // Identical level: compare NFD forms in code point order. The whole drain runs under two access scopes rather than two per scalar; see compareIdenticalLevel.
            let s = scratch ?? takeScratch()
            scratch = s
            return s.compareIdenticalLevel(
                left: left.unicodeScalars, right: right.unicodeScalars, skippingFirst: shared)
        }
        return .same
    }

    /// The `restart` marker from compareSlowPath: its options byte pass ran on both strings' contiguous bytes and bailed (non-Latin text). compareBody then calls compareAfterOptionsPass.
    static var optionsPassBailed: Int { -2 }

    /// The rest of compareSlowPath's options byte pass after a bail, as compareFastPath does it for the default options: the quick CJK primary compare (not for shifted options), else the restart (ICU's backup rule, `restartScalarCount`) and compareFromRestart (the bytes path), not compareBody's String-iterator walk. Sound for every non-identical option set: the restart scalar is safe, and the CE compare reports the two settings where the skipped prefix still matters (CollationCompare.prefixDependent; technique log §51 (z)). nil only if the strings are not contiguous (compareBody then walks).
    ///
    /// Apart from the options pass on purpose: the pass decides the Latin compares, and this work inside it made compareSlowPath too large to inline into `compare` (+76 instructions per ascii options compare in the `-no-WMO` build, ascii / latin / paths +4..+8%). Here the bailed compares pay a second pinning and a scan of the identical prefix instead (technique log §51 (ac)).
    @inline(never)
    private func compareAfterOptionsPass(
        _ left: String, _ right: String, options: CollationOptions, word: Int32
    ) throws -> Order? {
        let safety = UnsafePointer(restartSafetyPtr)
        let numeric = options.numeric
        // The quick CJK primary compare decides at the primary level, which comes first for any options; its setup is off under reordering and for a shifted default, and nil skips it for shifted options. Read from the options word: in the `-no-WMO` build, `options.alternate != .shifted` called the generic Equatable witness.
        let cjkSetup: UnsafePointer<QuickCJKSetup>? =
            word & CollationOptions.Bits.alternateMask == 0 ? UnsafePointer(storage.quickCJKSetupPtr) : nil
        let scanned = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                RootCollator.optionsPassRestart(lBytes, rBytes, cjkSetup: cjkSetup, safety: safety, numeric: numeric)
            }
        }
        guard let inner = scanned, let (decided, restart) = inner else { return nil }
        if decided != CollationFastLatin.bailOutResult {
            return decided < 0 ? .ascending : .descending
        }
        guard restart >= 0 else { return nil }
        return try compareFromRestart(left, right, options: options, word: word, restart: restart)
    }

    /// The identical-prefix scan of fastLatinUTF8 (the mismatch backed up to a scalar start), then the quick CJK primary compare (skipped when `cjkSetup` is nil) and `restartScalarCount`. Returns the CJK result with -1, or bailOutResult with the restart. Static with trivial parameters, like every helper called from the pinned-buffer closures.
    private static func optionsPassRestart(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        cjkSetup: UnsafePointer<QuickCJKSetup>?, safety: UnsafePointer<RestartSafety>, numeric: Bool
    ) -> (Int32, Int) {
        let minLength = min(lBytes.count, rBytes.count)
        var i = 0
        while i < minLength, lBytes[i] == rBytes[i] { i += 1 }
        if i > 0,
           (i != lBytes.count && lBytes[i] & 0xc0 == 0x80) || (i != rBytes.count && rBytes[i] & 0xc0 == 0x80) {
            repeat { i -= 1 } while i > 0 && lBytes[i] & 0xc0 == 0x80
        }
        if let cjkSetup {
            let q = quickCJKDispatch(lBytes, rBytes, at: i, setup: cjkSetup, numeric: numeric, safety: safety)
            if q != CollationFastLatin.bailOutResult { return (q, -1) }
        }
        return (CollationFastLatin.bailOutResult, restartScalarCount(lBytes, rBytes, at: i, safety: safety, numeric: numeric))
    }

    /// compareBody for a restart that the byte scan already placed (ICU's backup rule, `restartScalarCount`): no skip walk, and no fast Latin (the byte scan tried it). The pipeline reads both strings' pinned UTF-8 bytes (ScalarSource), so neither string is retained or walked again through a String iterator; a non-contiguous (bridged) string takes the String iterators as before.
    private func compareFromRestart(
        _ left: String, _ right: String, options: CollationOptions, word: Int32, restart: Int
    ) throws -> Order {
        let s = takeScratch()
        defer { giveScratch(s) }
        let numeric = options.numeric
        let vt = variableTopValue(options)
        let reordering = self.reordering
        let pinned = try left.utf8.withContiguousStorageIfAvailable { lb in
            try right.utf8.withContiguousStorageIfAvailable { rb in
                try s.resetBothAndCompare(
                    numeric: numeric, leftUTF8: lb, rightUTF8: rb, skippingFirst: restart,
                    options: word, variableTopValue: vt, reordering: reordering)
            }
        }
        var result: Int
        if let r = pinned ?? nil {
            result = r
        } else {
            result = try s.resetBothAndCompare(
                numeric: numeric,
                leftScalars: left.unicodeScalars, rightScalars: right.unicodeScalars,
                skippingFirst: restart,
                options: word, variableTopValue: vt, reordering: reordering)
        }
        if result == CollationCompare.prefixDependent {
            // The skipped prefix can change the result (shifted, backward secondary; rare): compare from the start, outside the pinned scope.
            result = try s.resetBothAndCompare(
                numeric: numeric,
                leftScalars: left.unicodeScalars, rightScalars: right.unicodeScalars,
                options: word, variableTopValue: vt, reordering: reordering)
        }
        if result != 0 {
            return result < 0 ? .ascending : .descending
        }
        if options.strength == .identical {
            return s.compareIdenticalLevel(
                left: left.unicodeScalars, right: right.unicodeScalars, skippingFirst: restart)
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
        // One access scope for reset + CE production + the writer; see resetCollectAndWriteKey. The writer is single-pass: one traversal of the CE array, beyond-primary levels accumulated in one temporary region. Two reference writers in Collation/Tools/sk-ladder/ReferenceWriters.swift do not ship; the sk-ladder probe checks byte identity against them across the option matrix.
        let numeric = options.numeric
        let word = options.icuOptions
        let vt = variableTopValue(options)
        let reordering = self.reordering
        let terminate = options.strength != .identical
        let compressible = storage.compressibleBytes
        // The pinned UTF-8 bytes when the string is contiguous (ScalarSource: no reference counting); the String iterator otherwise.
        let pinned: Void? = try s.utf8.withContiguousStorageIfAvailable { bytes in
            try Self.sortKey(
                scratch, utf8: bytes, numeric: numeric, compressibleBytes: compressible,
                options: word, variableTopValue: vt,
                reordering: reordering, terminate: terminate, into: &key)
        }
        if pinned == nil {
            try scratch.resetCollectAndWriteKey(
                numeric: numeric, scalars: s.unicodeScalars, compressibleBytes: compressible,
                options: word, variableTopValue: vt,
                reordering: reordering, terminate: terminate, into: &key)
        }
        if options.strength == .identical {
            key.append(1)  // level separator
            // Two access scopes for the whole drain, not two per scalar; see collectNFDScalars.
            scratch.collectNFDScalars(scalars: s.unicodeScalars)
            CollationKeys.writeIdenticalLevelRun(scalars: scratch.nfdScalars, into: &key)
            key.append(0)  // terminator (the writer adds it for the other strengths)
        }
    }

    /// The body of `sortKey` on pinned bytes, out of line with plain parameters: inside the `withContiguousStorageIfAvailable` closure, the CE loop (`collectAll`) did not inline and the call cost ~30 instructions per key (technique log §51).
    @inline(never)
    private static func sortKey(
        _ scratch: ScratchBuffers, utf8: UnsafeBufferPointer<UInt8>, numeric: Bool,
        compressibleBytes: UnsafeBufferPointer<Bool>, options: Int32, variableTopValue: UInt32,
        reordering: Reordering?, terminate: Bool, into key: inout [UInt8]
    ) throws {
        try scratch.resetCollectAndWriteKey(
            numeric: numeric, utf8: utf8, compressibleBytes: compressibleBytes,
            options: options, variableTopValue: variableTopValue,
            reordering: reordering, terminate: terminate, into: &key)
    }

    private func takeScratch() -> ScratchBuffers {
        threadLocal.take() ?? ScratchBuffers(data: data, base: base, norm: norm, simpleCEs: simpleCEs, thaiCEs: thaiCEs, simpleCEsWithDigits: simpleCEsWithDigits, thaiCEsWithDigits: thaiCEsWithDigits, markCEs: markCEs)
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



    /// The fast-Latin setup for an options word. The cache holds one entry per primaries key (see CollationFastLatin.primariesKey), computed and published on a miss; the packed options for this word are that entry's miniVarTop (bits 31..16) with this word in bits 15..0 — exactly what getOptions returns for the word itself. nil only if the cache is full, which 10 possible keys never make it (the caller would take the CE pipeline).
    private func resolveFastLatinSetup(_ word: Int32) -> FastLatinSetup? {
        let key = CollationFastLatin.primariesKey(word)
        guard let entry = fastLatinCache.setup(for: key) ?? fastLatinCache.insert(word: key, {
            var primaries: [UInt16] = []
            let packed = CollationFastLatin.getOptions(
                table: fastLatinTable, scriptsData: storage.scriptsData, reordering: reordering,
                options: key, primaries: &primaries)
            return (packed, primaries)
        }) else { return nil }
        let packed = entry.packedOptions < 0 ? entry.packedOptions : (entry.packedOptions & ~0xffff) | word
        return FastLatinSetup(word: word, packedOptions: packed, primaries: entry.primaries)
    }

    /// The byte fast path: identical-prefix scan on raw UTF-8, safety check, then CollationFastLatin.compareUTF8 from the restart offset. Returns -1/0/1, or bailOutResult when the regular path must run. Static with trivial parameters: it runs inside the contiguous-storage closures. (RuleBasedCollator::doCompare, UTF-8 variant.)
    private static func fastLatinUTF8(
        _ lBytes: UnsafeBufferPointer<UInt8>, _ rBytes: UnsafeBufferPointer<UInt8>,
        table: UnsafeBufferPointer<UInt16>, primaries: UnsafeBufferPointer<UInt16>,
        options packedOptions: Int32,
        numeric: Bool, safety: UnsafePointer<RestartSafety>,
        mismatch: inout Int
    ) -> Int32 {
        // Identical-prefix scan on bytes: 8 at a time through unaligned UInt64 loads (XOR, then a zero count from the low or high end depending on byte order, finds the first differing byte), byte-wise tail. Long shared prefixes (paths, thai) scan at word speed; a first-byte difference costs the same one comparison as the byte loop did.
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
                    // First differing BYTE within the word. The lowest-addressed byte is the least significant on little-endian and the most significant on big-endian, so the zero count runs from the opposite end. Without the gate this silently yields a WRONG shared-prefix length on big-endian (a mis-skip, not a crash) — and swift-foundation does support big-endian targets, which is why this is gated rather than assumed away.
                    #if _endian(big)
                    i += (lw ^ rw).leadingZeroBitCount >> 3
                    #else
                    i += (lw ^ rw).trailingZeroBitCount >> 3
                    #endif
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
            if (i != lLength && RestartSafety.isUnsafe(safety, scalarAt(lBytes, i), numeric: numeric))
                || (i != rLength && RestartSafety.isUnsafe(safety, scalarAt(rBytes, i), numeric: numeric)) {
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

    /// scalarAt, force-inlined, for restartScalarCount's out-of-line body (scalarAt itself stays out of line: the hot fast path calls it).
    @inline(__always)
    private static func decodeScalar(_ bytes: UnsafeBufferPointer<UInt8>, _ i: Int) -> UInt32 {
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
        try iter.collectAll()
        return iter.ces.toArray()
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
    /// The answer of `isUnsafe` for every code point below `latinTableLimit`, resolved at init: bit 0 with numeric off, bit 1 with numeric on. Replaces a "safe below" threshold, which root data set at U+0034 — the first unsafe code point ("4", in the unsafe-backward list; "L", U+00A0 and U+00B7 follow) — so every letter took the slow path: two binary searches over the boundary lists, a ccc lookup and a trie lookup. An instruction count put that at ~100 instructions per checked character, against ICU's Latin-1 table (BMPSet) (technique log §50).
    let latinTable: UnsafeBufferPointer<UInt8>
    static let latinTableLimit: UInt32 = 0x0300
    /// The answer of `isUnsafe` for the rest of the BMP (from `latinTableLimit` to U+FFFF), resolved at init, in two levels: `bmpBlocks` has one entry per 64 code points, the number of that block's two words in `bmpWords` (numeric off, then numeric on; bit `c & 63`). Block 0 is all zero and stands for every block with no unsafe code point — 905 of the 1024 in root data. Without it, every check at or above U+0300 (Thai, CJK, Cyrillic, ... after a shared prefix) took the slow path: ~180 instructions per thai compare (technique log §51).
    let bmpBlocks: UnsafeBufferPointer<UInt16>
    let bmpWords: UnsafeBufferPointer<UInt64>

    /// `storage` owns the two tables; the caller keeps it alive as long as this value.
    init(data: CollationData, base: CollationData?, norm: NormalizationData, storage: DataStorage) {
        dataUnsafe = data.unsafeBackward
        baseUnsafe = base?.unsafeBackward ?? UnsafeBufferPointer(start: nil, count: 0)
        dataTrie = data.trie
        baseTrie = base?.trie
        self.norm = norm.view

        var table = [UInt8](repeating: 0, count: Int(Self.latinTableLimit))
        for cp in 0..<Self.latinTableLimit {
            if Self.slowIsUnsafe(cp, numeric: false, dataUnsafe: dataUnsafe, baseUnsafe: baseUnsafe,
                                 dataTrie: dataTrie, baseTrie: baseTrie, norm: norm.view) {
                table[Int(cp)] |= 1
            }
            if Self.slowIsUnsafe(cp, numeric: true, dataUnsafe: dataUnsafe, baseUnsafe: baseUnsafe,
                                 dataTrie: dataTrie, baseTrie: baseTrie, norm: norm.view) {
                table[Int(cp)] |= 2
            }
        }
        latinTable = storage.store(table)

        let (blocks, words) = Self.buildBMPTable(
            dataUnsafe: dataUnsafe, baseUnsafe: baseUnsafe,
            dataTrie: dataTrie, baseTrie: baseTrie, norm: norm.view)
        bmpBlocks = storage.store(blocks)
        bmpWords = storage.store(words)
    }

    /// Builds the BMP table from the structures that `slowIsUnsafe` reads, not one code point at a time: calling `slowIsUnsafe` for all 2 × 64,768 code points costs ~1.7 ms, against ~0.02 ms for the whole root collator init. Each part below is the union term of `slowIsUnsafe`; `RestartSafetyTests` checks the result against it for every BMP code point.
    private static func buildBMPTable(
        dataUnsafe: UnsafeBufferPointer<UInt32>, baseUnsafe: UnsafeBufferPointer<UInt32>,
        dataTrie: UTrie2, baseTrie: UTrie2?, norm: NormalizationDataView
    ) -> (blocks: [UInt16], words: [UInt64]) {
        let blockCount = 0x10000 >> 6
        let firstBlock = Int(latinTableLimit >> 6)  // latinTableLimit is a multiple of 64
        let firstCode = UInt32(firstBlock << 6)
        // Bits for both numeric modes, and bits for numeric on only.
        var both = [UInt64](repeating: 0, count: blockCount)
        var numericOnly = [UInt64](repeating: 0, count: blockCount)

        // 1. The unsafe-backward lists: boundaries [b0, b1), [b2, b3), ...; an odd count leaves the last range open.
        for list in [dataUnsafe, baseUnsafe] {
            var k = 0
            while k < list.count {
                let start = max(list[k], firstCode)
                let limit = min(k + 1 < list.count ? list[k + 1] : 0x110000, 0x10000)
                if start < limit {
                    for c in start..<limit { both[Int(c >> 6)] |= 1 << UInt64(c & 63) }
                }
                k += 2
            }
        }

        // 2. Lead ccc != 0, one normalization data block (64 code points, the same blocking) at a time, each block computed once.
        // The cache is an array indexed by norm block (113 distinct in the BMP), not a dictionary: dictionary operations made the build cost several times the rest of the root collator init.
        var leadMasks = [UInt64?](repeating: nil, count: norm.data.count >> 6)
        for b in firstBlock..<blockCount {
            let normBlock = Int(norm.index[b])
            if leadMasks[normBlock] == nil {
                var m: UInt64 = 0
                let base = normBlock << 6
                for i in 0..<64 where (norm.data[base + i] >> 8) & 0xff != 0 { m |= 1 << UInt64(i) }
                leadMasks[normBlock] = m
            }
            both[b] |= leadMasks[normBlock] ?? 0
        }

        // 3. The CE32 tags: prefix (both modes) and digit (numeric on), with the base data's tags where the tailoring has FALLBACK_CE32 — one 32-value trie block at a time. No cache: 1317 of root's 2024 BMP trie blocks are distinct, and a cache array over the trie data (~125k values) cost more to allocate than the scan. Branch-free, so the loop vectorizes.
        func tagMasks(_ trie: UTrie2, _ offset: Int) -> (prefix: UInt32, digit: UInt32, fallback: UInt32) {
            var prefix: UInt32 = 0, digit: UInt32 = 0, fallback: UInt32 = 0
            for i in 0..<32 {
                let ce32 = trie.data[offset + i]
                let special = (ce32 & 0xff) >= CollationConstants.specialCE32LowByte
                let tag = ce32 & 0xf
                prefix |= (special && tag == CollationConstants.Tag.prefix.rawValue ? 1 : 0) << UInt32(i)
                digit |= (special && tag == CollationConstants.Tag.digit.rawValue ? 1 : 0) << UInt32(i)
                fallback |= (ce32 == CollationConstants.fallbackCE32 ? 1 : 0) << UInt32(i)
            }
            return (prefix, digit, fallback)
        }
        for chunk in (firstBlock << 1)..<(blockCount << 1) {
            let c = UInt32(chunk << 5)
            let d = tagMasks(dataTrie, dataTrie.bmpBlockOffset(c))
            var prefix = d.prefix
            var digit = d.digit
            if let baseTrie, d.fallback != 0 {
                let b = tagMasks(baseTrie, baseTrie.bmpBlockOffset(c))
                prefix |= d.fallback & b.prefix
                digit |= d.fallback & b.digit
            }
            let shift = UInt64((chunk & 1) << 5)
            both[chunk >> 1] |= UInt64(prefix) << shift
            numericOnly[chunk >> 1] |= UInt64(digit) << shift
        }

        // Block 0 = no unsafe code point; every other block gets its own pair of words.
        var blocks = [UInt16](repeating: 0, count: blockCount)
        var words: [UInt64] = [0, 0]
        for b in firstBlock..<blockCount where both[b] | numericOnly[b] != 0 {
            blocks[b] = UInt16(words.count >> 1)
            words.append(both[b])
            words.append(both[b] | numericOnly[b])
        }
        return (blocks, words)
    }

    /// The full check: the reference for both tables, and the answer for supplementary code points. Internal for RestartSafetyTests.
    static func slowIsUnsafe(
        _ c: UInt32, numeric: Bool,
        dataUnsafe: UnsafeBufferPointer<UInt32>, baseUnsafe: UnsafeBufferPointer<UInt32>,
        dataTrie: UTrie2, baseTrie: UTrie2?, norm: NormalizationDataView
    ) -> Bool {
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

    @inline(__always)
    func isUnsafe(_ c: UInt32, numeric: Bool) -> Bool {
        if c < Self.latinTableLimit {
            return latinTable[Int(c)] & (numeric ? 2 : 1) != 0
        }
        return isUnsafeAboveLatin(c, numeric: numeric)
    }

    /// `isUnsafe` for a caller that holds the value BY POINTER (the fast-Latin path). It reads only the fields it needs through the pointer. A method call on `pointee` copies the whole struct to the stack before each call instead — the memory behind the pointer could change during the call — and that copy ran twice in every shared-prefix compare (all of paths), before AND after this table (technique log §51).
    @inline(__always)
    static func isUnsafe(_ s: UnsafePointer<RestartSafety>, _ c: UInt32, numeric: Bool) -> Bool {
        if c < latinTableLimit {
            return s.pointee.latinTable[Int(c)] & (numeric ? 2 : 1) != 0
        }
        return isUnsafeAboveLatin(s, c, numeric: numeric)
    }

    /// `isUnsafe(_:_:numeric:)` with the BMP table lookup inlined too, for callers off the hot path that may grow (restartScalarCount); supplementary code points still take the full check.
    @inline(__always)
    static func isUnsafeInline(_ s: UnsafePointer<RestartSafety>, _ c: UInt32, numeric: Bool) -> Bool {
        if c < latinTableLimit {
            return s.pointee.latinTable[Int(c)] & (numeric ? 2 : 1) != 0
        }
        if c < 0x10000 {
            let block = Int(s.pointee.bmpBlocks[Int(c >> 6)])
            return (s.pointee.bmpWords[block &* 2 &+ (numeric ? 1 : 0)] >> UInt64(c & 63)) & 1 != 0
        }
        return isUnsafeAboveLatin(s, c, numeric: numeric)
    }

    /// The pointer twin of the instance method below.
    @inline(never)
    static func isUnsafeAboveLatin(_ s: UnsafePointer<RestartSafety>, _ c: UInt32, numeric: Bool) -> Bool {
        if c < 0x10000 {
            let block = Int(s.pointee.bmpBlocks[Int(c >> 6)])
            return (s.pointee.bmpWords[block &* 2 &+ (numeric ? 1 : 0)] >> UInt64(c & 63)) & 1 != 0
        }
        return slowIsUnsafe(c, numeric: numeric, dataUnsafe: s.pointee.dataUnsafe, baseUnsafe: s.pointee.baseUnsafe,
                            dataTrie: s.pointee.dataTrie, baseTrie: s.pointee.baseTrie, norm: s.pointee.norm)
    }

    /// `isUnsafe` from `latinTableLimit` up. Out of line on purpose: inlined, the BMP lookup grew compareFastPath enough that the inliner left `min` there as a call, with extra spills — paths compare +3.2% (technique log §51). Here, `self` is passed by address.
    @inline(never)
    func isUnsafeAboveLatin(_ c: UInt32, numeric: Bool) -> Bool {
        if c < 0x10000 {
            let block = Int(bmpBlocks[Int(c >> 6)])
            return (bmpWords[block &* 2 &+ (numeric ? 1 : 0)] >> UInt64(c & 63)) & 1 != 0
        }
        return Self.slowIsUnsafe(c, numeric: numeric, dataUnsafe: dataUnsafe, baseUnsafe: baseUnsafe,
                                 dataTrie: dataTrie, baseTrie: baseTrie, norm: norm)
    }
}
