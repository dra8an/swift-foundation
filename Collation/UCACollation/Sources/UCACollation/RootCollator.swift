// Primary-strength comparison against the CLDR root collation.
//
// Milestone-1 scope (see Docs/03-swift-strategy.md):
// - primary level only (UCOL_PRIMARY), default options (alternate=non-ignorable)
// - root data only, no tailorings
// - context-dependent mappings (prefixes/contractions) resolve to their
//   default CE32, i.e. suffix/prefix matching is NOT yet performed. This is
//   correct whenever the surrounding text does not actually form a contraction
//   or match a prefix condition (true for all-ASCII input against root data).

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

    public init(data: CollationData) {
        self.data = data
    }

    public init() throws {
        self.init(data: try CollationData.root())
    }

    // MARK: Comparison

    /// Compares two strings at primary strength under root collation.
    public func compare(_ left: String, _ right: String) throws -> Order {
        var l = PrimaryIterator(data: data, scalars: left.unicodeScalars)
        var r = PrimaryIterator(data: data, scalars: right.unicodeScalars)
        while true {
            let lp = try l.nextNonIgnorablePrimary()
            let rp = try r.nextNonIgnorablePrimary()
            if lp != rp {
                // nil (end of string) sorts before any non-ignorable primary,
                // which is never 0.
                return (lp ?? 0) < (rp ?? 0) ? .ascending : .descending
            }
            if lp == nil {
                return .same
            }
        }
    }

    /// All primary weights (including ignorable zeros) for a string. Test hook.
    func primaries(of s: String) throws -> [UInt32] {
        var iter = PrimaryIterator(data: data, scalars: s.unicodeScalars)
        var result: [UInt32] = []
        while let p = try iter.nextPrimary() {
            result.append(p)
        }
        return result
    }
}

/// Iterates the primary weights of a string's collation elements.
struct PrimaryIterator {
    let data: CollationData
    var scalars: String.UnicodeScalarView.Iterator
    /// Primaries pending from an expansion, in order; consumed before the next scalar.
    var pending: [UInt32] = []
    var pendingNext = 0

    init(data: CollationData, scalars: String.UnicodeScalarView) {
        self.data = data
        self.scalars = scalars.makeIterator()
    }

    /// Next primary weight that is not zero (primary-ignorable CEs are skipped),
    /// or nil at the end of the string.
    mutating func nextNonIgnorablePrimary() throws -> UInt32? {
        while let p = try nextPrimary() {
            if p != 0 { return p }
        }
        return nil
    }

    mutating func nextPrimary() throws -> UInt32? {
        if pendingNext < pending.count {
            let p = pending[pendingNext]
            pendingNext += 1
            return p
        }
        guard let scalar = scalars.next() else { return nil }
        pending.removeAll(keepingCapacity: true)
        pendingNext = 0
        let c = scalar.value
        try appendPrimaries(c: c, ce32: data.trie.get(c), depth: 0)
        pendingNext = 1
        return pending[0]
    }

    /// Resolves a CE32 to one or more primary weights, appending them to `pending`.
    /// Mirrors the tag dispatch of CollationIterator::appendCEsFromCE32.
    private mutating func appendPrimaries(c: UInt32, ce32 initialCE32: UInt32, depth: Int) throws {
        // Specials never nest deeper than digit/u0000 -> expansion -> jamo in root data.
        guard depth <= 4 else { throw RootCollator.CollationError.malformedData }
        var ce32 = initialCE32
        while true {
            if !Collation.isSpecialCE32(ce32) {
                pending.append(Collation.primaryFromSimpleCE32(ce32))
                return
            }
            switch Collation.tagFromCE32(ce32) {
            case .longPrimary:
                pending.append(Collation.primaryFromLongPrimaryCE32(ce32))
                return
            case .longSecondary:
                pending.append(0)
                return
            case .latinExpansion:
                pending.append(Collation.latinExpansionFirstPrimary(ce32))
                pending.append(0)
                return
            case .expansion32:
                let index = Collation.indexFromCE32(ce32)
                for i in 0..<Collation.lengthFromCE32(ce32) {
                    try appendPrimaries(c: c, ce32: data.ce32s[index + i], depth: depth + 1)
                }
                return
            case .expansion:
                let index = Collation.indexFromCE32(ce32)
                for i in 0..<Collation.lengthFromCE32(ce32) {
                    pending.append(Collation.primaryFromCE(data.ces[index + i]))
                }
                return
            case .prefix, .contraction:
                // Milestone 1: no context matching; use the default CE32
                // stored ahead of the context UCharsTrie.
                ce32 = data.readContextCE32(at: Collation.indexFromCE32(ce32))
            case .digit:
                // Numeric collation is off; use the regular CE32 for the digit.
                ce32 = data.ce32s[Collation.indexFromCE32(ce32)]
            case .u0000:
                ce32 = data.ce32s[0]
            case .hangul:
                try appendHangulPrimaries(syllable: c, depth: depth)
                return
            case .offset:
                let dataCE = data.ces[Collation.indexFromCE32(ce32)]
                pending.append(Collation.threeBytePrimaryForOffsetData(c, dataCE))
                return
            case .implicit:
                pending.append(Collation.unassignedPrimaryFromCodePoint(c))
                return
            case .fallback, .reserved3, .builderData, .leadSurrogate:
                // Fallback/builder data cannot occur in root data; lead surrogates
                // cannot occur when iterating Unicode scalars.
                throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: ce32 & 0xf)
            }
        }
    }

    /// Decomposes a Hangul syllable arithmetically and appends the Jamo primaries.
    /// (CollationIterator::appendCEsFromCE32, HANGUL_TAG case.)
    private mutating func appendHangulPrimaries(syllable c: UInt32, depth: Int) throws {
        guard data.jamoCE32sStart >= 0, (0xac00...0xd7a3).contains(c) else {
            throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: Collation.Tag.hangul.rawValue)
        }
        let sIndex = Int(c) - 0xac00
        let l = sIndex / 588          // leading consonant, 19 values
        let v = (sIndex % 588) / 28   // vowel, 21 values
        let t = sIndex % 28           // optional trailing consonant, 27 values (1..27)
        let jamo = data.jamoCE32sStart
        try appendPrimaries(c: c, ce32: data.ce32s[jamo + l], depth: depth + 1)
        try appendPrimaries(c: c, ce32: data.ce32s[jamo + 19 + v], depth: depth + 1)
        if t != 0 {
            try appendPrimaries(c: c, ce32: data.ce32s[jamo + 19 + 21 + t - 1], depth: depth + 1)
        }
    }
}
