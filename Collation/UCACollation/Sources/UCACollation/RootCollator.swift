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
    let norm: NormalizationData

    public init(data: CollationData, norm: NormalizationData) {
        self.data = data
        self.norm = norm
    }

    public init() throws {
        self.init(data: try CollationData.root(), norm: try NormalizationData.standard())
    }

    // MARK: Comparison

    /// Compares two strings under root collation.
    /// Defaults to tertiary strength with all options off, like ICU.
    public func compare(
        _ left: String, _ right: String, options: CollationOptions = CollationOptions()
    ) throws -> Order {
        // CEs are generated lazily: the primary level usually decides the
        // comparison after a few characters.
        var leftCEs = CEIterator(
            data: data, norm: norm, numeric: options.numeric, scalars: left.unicodeScalars)
        var rightCEs = CEIterator(
            data: data, norm: norm, numeric: options.numeric, scalars: right.unicodeScalars)
        let result = try CollationCompare.compareUpToQuaternary(
            &leftCEs, &rightCEs, options: options.icuOptions,
            variableTopValue: variableTopValue(options))
        if result != 0 {
            return result < 0 ? .ascending : .descending
        }
        if options.strength == .identical {
            // Identical level: compare NFD forms in code point order.
            var l = NFDIterator(norm: norm, scalars: left.unicodeScalars)
            var r = NFDIterator(norm: norm, scalars: right.unicodeScalars)
            while true {
                let lc = l.next()
                let rc = r.next()
                if lc != rc {
                    return (lc ?? 0) < (rc ?? 0) ? .ascending : .descending
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
        let ces = try collationElements(of: s, numeric: options.numeric)
        var key: [UInt8] = []
        CollationKeys.writeSortKeyUpToQuaternary(
            ces: ces, compressibleBytes: data.compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            into: &key)
        if options.strength == .identical {
            key.append(1)  // level separator
            var iter = NFDIterator(norm: norm, scalars: s.unicodeScalars)
            var nfdScalars: [UInt32] = []
            while let c = iter.next() { nfdScalars.append(c) }
            CollationKeys.writeIdenticalLevelRun(scalars: nfdScalars, into: &key)
        }
        key.append(0)  // terminator
        return key
    }

    private func variableTopValue(_ options: CollationOptions) -> UInt32 {
        guard options.alternate == .shifted else { return 0 }
        return data.lastPrimaryForGroup(
            CollationData.reorderCodeFirst + options.maxVariable.rawValue)
    }

    /// All CEs of a string, terminated by NO_CE.
    func collationElements(of s: String, numeric: Bool = false) throws -> [Int64] {
        var iter = CEIterator(data: data, norm: norm, numeric: numeric, scalars: s.unicodeScalars)
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
