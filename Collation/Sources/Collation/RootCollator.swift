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

public struct RootCollator: Sendable {
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
    /// Reusable per-call buffers, shared (thread-safely) by all copies of
    /// this collator so repeated compares run allocation-free.
    private let scratchPool = ScratchPool()

    public init(data: CollationData, norm: NormalizationData) {
        self.data = data
        self.base = nil
        self.norm = norm
        self.reordering = nil
        self.defaultOptions = CollationOptions()
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
    }

    // MARK: Comparison

    /// Compares two strings under root collation.
    /// Defaults to tertiary strength with all options off, like ICU.
    public func compare(
        _ left: String, _ right: String, options: CollationOptions = CollationOptions()
    ) throws -> Order {
        // Swift String equality is canonical equivalence, which implies equal
        // CEs and therefore equality at every strength including identical.
        if left == right { return .same }

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
        if shared > 0,
           (lNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false)
            || (rNext.map { unsafeStart($0.value, numeric: options.numeric) } ?? false) {
            shared = 0
        }

        let scratch = takeScratch()
        defer { scratchPool.give(scratch) }
        // CEs are generated lazily: the primary level usually decides the
        // comparison after a few characters.
        scratch.left.reset(numeric: options.numeric, scalars: left.unicodeScalars, skippingFirst: shared)
        scratch.right.reset(numeric: options.numeric, scalars: right.unicodeScalars, skippingFirst: shared)
        let result = try CollationCompare.compareUpToQuaternary(
            &scratch.left, &scratch.right, options: options.icuOptions,
            variableTopValue: variableTopValue(options), reordering: reordering)
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
            scratch.left.scalars.reset(scalars: left.unicodeScalars, skippingFirst: shared)
            scratch.right.scalars.reset(scalars: right.unicodeScalars, skippingFirst: shared)
            while true {
                let lc = scratch.left.scalars.next()
                let rc = scratch.right.scalars.next()
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
        let scratch = takeScratch()
        defer { scratchPool.give(scratch) }
        scratch.left.reset(numeric: options.numeric, scalars: s.unicodeScalars)
        _ = try scratch.left.collectAll()
        if !scratch.key.isEmpty { scratch.key.removeAll(keepingCapacity: true) }
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        CollationKeys.writeSortKeyUpToQuaternary(
            ces: scratch.left.ces, compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, into: &scratch.key, reusing: &scratch.levels)
        if options.strength == .identical {
            scratch.key.append(1)  // level separator
            scratch.left.scalars.reset(scalars: s.unicodeScalars)
            if !scratch.nfdScalars.isEmpty { scratch.nfdScalars.removeAll(keepingCapacity: true) }
            while let c = scratch.left.scalars.next() { scratch.nfdScalars.append(c) }
            CollationKeys.writeIdenticalLevelRun(scalars: scratch.nfdScalars, into: &scratch.key)
        }
        scratch.key.append(0)  // terminator
        // Copy out right-sized; returning the buffer itself would pin its
        // storage and defeat the reuse.
        var key: [UInt8] = []
        key.reserveCapacity(scratch.key.count)
        key.append(contentsOf: scratch.key)
        return key
    }

    private func takeScratch() -> ScratchBuffers {
        scratchPool.take() ?? ScratchBuffers(data: data, base: base, norm: norm)
    }

    /// True if restarting CE iteration at `c` is not provably equivalent to
    /// full iteration — `c`'s CEs or NFD form could depend on what precedes
    /// it. (CollationData::isUnsafeBackward, adapted: ICU's set folds in
    /// [:^lccc=0:] at load time, and ICU lets prefix (precontext) matching
    /// read back into the skipped prefix, which our streaming iterator
    /// cannot — so prefix-tagged characters are unsafe here instead.)
    private func unsafeStart(_ c: UInt32, numeric: Bool) -> Bool {
        if data.unsafeBackwardContains(c) { return true }
        if let base, base.unsafeBackwardContains(c) { return true }
        if norm.leadCCC(c) != 0 { return true }
        var ce32 = data.trie.get(c)
        if ce32 == CollationConstants.fallbackCE32, let base {
            ce32 = base.trie.get(c)
        }
        guard CollationConstants.isSpecialCE32(ce32) else { return false }
        let tag = CollationConstants.tagFromCE32(ce32)
        return tag == .prefix || (numeric && tag == .digit)
    }

    private func variableTopValue(_ options: CollationOptions) -> UInt32 {
        guard options.alternate == .shifted else { return 0 }
        // Scripts data lives in the root; tailorings usually omit it.
        let scriptsData = data.scriptStarts.isEmpty ? base! : data
        return scriptsData.lastPrimaryForGroup(
            CollationData.reorderCodeFirst + options.maxVariable.rawValue)
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
