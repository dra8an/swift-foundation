// Produces the full 64-bit collation elements of a string, reading scalars through the incremental-NFD front end. CE32 tag dispatch mirrors CollationIterator::appendCEsFromCE32; contraction matching (including discontiguous contractions per UTS #10 S2.1) mirrors nextCE32FromContraction/nextCE32FromDiscontiguousContraction; prefix matching mirrors getCE32FromPrefix; numeric collation (CODAN) mirrors appendNumericCEs/appendNumericSegmentCEs.
//
// Because the scalar stream is already fully NFD-normalized and canonically ordered, ICU's FCD16 lead/trail-ccc checks reduce to plain ccc checks, and discontiguous matching operates on discrete combining marks exactly as UTS #10 S2.1 describes. UCharsTrie being a value type makes trie-state snapshots a struct copy, which replaces the TRIE half of ICU's SkippedState machinery; the POSITION half is still needed, because a discontiguous match consumes a non-contiguous set of scalars (see `spanStart`).

/// The collation elements of one iteration: a growable buffer with an explicit count, like ICU's CEBuffer. An append is a capacity test and a store, and `removeAll()` sets the count to 0. As a Swift `Array`, every append called the runtime's uniqueness check out of line (13 times for a 12-letter key; the compiler cannot hoist it out of the per-character loop), and every clear ran the general `replaceSubrange` (~85 instructions) — together ~10% of a short sortKey's instructions (technique log §51).
///
/// Noncopyable: it owns its memory and frees it in `deinit`, so a copy would be a second owner. The compiler rejects copies; owners pass it `inout` or `borrowing`. Reads keep the bounds check that `Array` has.
struct CEBuffer: ~Copyable {
    private var storage: UnsafeMutablePointer<Int64>
    private var capacity: Int
    private(set) var count = 0

    init(capacity: Int = 32) {
        storage = .allocate(capacity: capacity)
        self.capacity = capacity
    }

    deinit {
        storage.deallocate()
    }

    var isEmpty: Bool { count == 0 }

    subscript(i: Int) -> Int64 {
        @inline(__always) get {
            precondition(i >= 0 && i < count, "CE index out of range")
            return storage[i]
        }
        @inline(__always) set {
            precondition(i >= 0 && i < count, "CE index out of range")
            storage[i] = newValue
        }
    }

    @inline(__always)
    mutating func append(_ ce: Int64) {
        if count == capacity { grow(to: capacity &* 2) }
        storage[count] = ce
        count &+= 1
    }

    /// Empties the buffer and keeps its memory.
    @inline(__always)
    mutating func removeAll() {
        count = 0
    }

    mutating func reserveCapacity(_ minimumCapacity: Int) {
        if minimumCapacity > capacity { grow(to: minimumCapacity) }
    }

    @inline(never)
    private mutating func grow(to newCapacity: Int) {
        let newStorage = UnsafeMutablePointer<Int64>.allocate(capacity: newCapacity)
        newStorage.update(from: storage, count: count)
        storage.deallocate()
        storage = newStorage
        capacity = newCapacity
    }

    /// A copy of the elements as an array (test hooks, search, tools).
    func toArray() -> [Int64] {
        Array(UnsafeBufferPointer(start: storage, count: count))
    }
}

/// Noncopyable because its CE buffer is (see CEBuffer).
struct CEIterator: ~Copyable {
    /// The tailoring data (or root when there is no tailoring).
    let data: CollationData
    /// The base (root) data when `data` is a tailoring; lookups fall back here when the tailoring maps a character to FALLBACK_CE32.
    let base: CollationData?
    let norm: NormalizationData
    var numeric: Bool
    var scalars: NFDIterator
    /// ARC-free views used by the per-scalar dispatch (see CollationDataView).
    private let dataView: CollationDataView
    private let baseView: CollationDataView?
    /// Pre-computed CEs for ASCII (0–127) for the CURRENT mode. Entry is 0 for characters that need full pipeline processing (U+0000, and digits when numeric collation is on).
    private(set) var simpleCEs: UnsafeBufferPointer<Int64>
    /// Pre-computed CEs for the Thai block (U+0E00–0E7F), same contract.
    private(set) var thaiCEs: UnsafeBufferPointer<Int64>
    /// The two table variants: `…Numeric` leaves DIGIT-tag characters as 0 sentinels, `…WithDigits` resolves them. `reset` selects between them, so a scratch buffer shared across numeric and non-numeric calls always reads the right one.
    private let simpleCEsNumeric: UnsafeBufferPointer<Int64>
    private let thaiCEsNumeric: UnsafeBufferPointer<Int64>
    private let simpleCEsWithDigits: UnsafeBufferPointer<Int64>
    private let thaiCEsWithDigits: UnsafeBufferPointer<Int64>
    /// Combining marks and Greek (U+0300–037F), one simple CE per entry, 0 for the full path (RootCollator.Storage.markCEs). The same in both numeric modes: no mark is a digit.
    private let markCEs: UnsafeBufferPointer<Int64>
    var ces = CEBuffer()

    /// Number of NFD scalars consumed so far. Every scalar is counted exactly once, including the ones a discontiguous contraction consumes out of order, so this always equals the number of scalars the NFD front end has yielded (PositionInvariantTests gates that).
    private(set) var scalarsConsumed = 0

    /// NFD position of the next scalar to be pulled from the front end.
    ///
    /// Positions are NOT the same thing as `scalarsConsumed`: a discontiguous contraction (UTS #10 S2.1.3) consumes a scalar from AHEAD of the marks it skipped, so after it the count has advanced past marks that have not been consumed yet. Search reports positions, so they are tracked separately.
    private var streamPos = 0

    /// The NFD position span of the scalars consumed by the current `appendMore()` call: `[spanStart, spanEnd)`. Every CE that call produced covers this span.
    ///
    /// For ordinary consumption the span is the scalar itself plus any contraction suffix or digit run, i.e. exactly the contiguous region. A discontiguous contraction widens `spanEnd` past the marks it skipped, because the CE really was built from a scalar on the far side of them: the consumed set is non-contiguous and the span is its convex hull. That is why the search range takes the MIN start and MAX end over a match's CEs rather than the first CE's start and the last CE's end — the skipped marks produce their own CEs afterwards, whose spans sit inside the contraction's.
    private(set) var spanStart = 0
    private(set) var spanEnd = 0

    /// True once the NFD front end has decomposed any input scalar. While false, NFD scalar offsets equal source scalar offsets, so CollationSearch can report positions without an NFD→source map.
    var sawDecomposition: Bool { scalars.sawDecomposition }

    /// Normalized scalars read ahead of the current position, each packed with its NFD position as `(position << 32) | scalar`. Packing keeps the read-ahead path to ONE array: a parallel `[Int]` of positions would double its allocation and bookkeeping, and the read-ahead buffer is on the contraction hot path.
    private var lookahead: [UInt64] = []
    private var lookaheadStart = 0
    /// The two most recently processed scalars (most recent first), used for prefix (precontext) matching. Sufficient for all CLDR prefixes: a single starter, or a starter followed by a kana voicing mark.
    private var prev1: UInt32?
    private var prev2: UInt32?
    /// Scalars consumed as contraction suffixes / digit runs while processing the current character; pushed into prefix history after it.
    private var consumedExtras: [UInt32] = []

    init(data: CollationData, base: CollationData? = nil, norm: NormalizationData,
         numeric: Bool, scalars: String.UnicodeScalarView,
         simpleCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         thaiCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         simpleCEsWithDigits: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         thaiCEsWithDigits: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         markCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0)) {
        self.data = data
        self.base = base
        self.norm = norm
        self.numeric = numeric
        self.scalars = NFDIterator(norm: norm, scalars: scalars)
        self.dataView = CollationDataView(data)
        self.baseView = base.map(CollationDataView.init)
        self.simpleCEsNumeric = simpleCEs
        self.thaiCEsNumeric = thaiCEs
        // An absent with-digits table (the search entries build iterators without tables) must not silently disable the plain tables.
        self.simpleCEsWithDigits = simpleCEsWithDigits.isEmpty ? simpleCEs : simpleCEsWithDigits
        self.thaiCEsWithDigits = thaiCEsWithDigits.isEmpty ? thaiCEs : thaiCEsWithDigits
        self.simpleCEs = numeric ? simpleCEs : self.simpleCEsWithDigits
        self.thaiCEs = numeric ? thaiCEs : self.thaiCEsWithDigits
        self.markCEs = markCEs
    }

    /// Rewinds onto a new input, keeping all buffer storage so that reuse across compares runs allocation-free. Equivalent to a fresh iterator over the same collation data, positioned after `skippingFirst` scalars.
    mutating func reset(numeric: Bool, scalars view: String.UnicodeScalarView, skippingFirst: Int = 0) {
        self.numeric = numeric
        selectTables(numeric: numeric)
        scalars.reset(scalars: view, skippingFirst: skippingFirst)
        clearState()
    }

    /// Resets onto an already-positioned scalar iterator plus one scalar the caller has already pulled from it — see NFDIterator.reset(source:first:). Avoids rebuilding a String iterator and re-walking the skipped prefix.
    mutating func reset(numeric: Bool, source iter: String.UnicodeScalarView.Iterator, first: UInt32?) {
        self.numeric = numeric
        selectTables(numeric: numeric)
        scalars.reset(source: iter, first: first)
        clearState()
    }

    /// Points the active simple-CE tables at the variant this mode may use. Once per reset, never per scalar.
    @inline(__always)
    private mutating func selectTables(numeric: Bool) {
        simpleCEs = numeric ? simpleCEsNumeric : simpleCEsWithDigits
        thaiCEs = numeric ? thaiCEsNumeric : thaiCEsWithDigits
    }

    @inline(__always)
    private mutating func clearState() {
        // isEmpty guards: see appendMore.
        ces.removeAll()
        if !lookahead.isEmpty { lookahead.removeAll(keepingCapacity: true) }
        lookaheadStart = 0
        prev1 = nil
        prev2 = nil
        if !consumedExtras.isEmpty { consumedExtras.removeAll(keepingCapacity: true) }
        terminated = false
        scalarsConsumed = 0
        streamPos = 0
        spanStart = 0
        spanEnd = 0
    }

    /// Looks up the CE32 for a code point, falling back from the tailoring to the base data. Returns the data view that owns the resulting CE32.
    @inline(__always)
    private func lookup(_ c: UInt32) -> (d: CollationDataView, ce32: UInt32) {
        let ce32 = dataView.trie.get(c)
        if ce32 == CollationConstants.fallbackCE32, let b = baseView {
            return (b, b.trie.get(c))
        }
        return (dataView, ce32)
    }

    /// CJK Unified Ideographs and Extensions A and B+ (the compatibility ideographs decompose and are not included) — the same ranges as RootCollator.isCJKUnified.
    @inline(__always)
    private static func isCJKUnified(_ c: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(c) || (0x3400...0x4DBF).contains(c) || (0x20000...0x2A6DF).contains(c)
    }

    /// The one primary of a CJK ideograph whose CE is computed from it — a long primary, or the OFFSET or IMPLICIT tag — or 0 when it needs the full path. The same cases as RootCollator.quickCJKPrimary (compare's fast path), and the same CE as `appendCEs` gives them: `makeCE(p)`.
    ///
    /// `mutating` only so that it gets the iterator's address: as a plain method, out of line, it received a copy of the data views per call (~220 bytes per CJK character, technique log §51 (v)).
    @inline(__always)
    private mutating func quickCJKPrimary(_ c: UInt32) -> UInt32 {
        var ce32 = dataView.trie.get(c)
        var ces = dataView.ces
        if ce32 == CollationConstants.fallbackCE32 {
            guard let b = baseView else { return 0 }
            ce32 = b.trie.get(c)
            ces = b.ces
        }
        guard CollationConstants.isSpecialCE32(ce32) else { return 0 }
        switch CollationConstants.tagFromCE32(ce32) {
        case .longPrimary:
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

    // MARK: Lookahead buffer

    @inline(__always)
    private static func packAhead(_ pos: Int, _ c: UInt32) -> UInt64 {
        (UInt64(UInt32(truncatingIfNeeded: pos)) << 32) | UInt64(c)
    }

    @inline(__always)
    private static func aheadScalar(_ entry: UInt64) -> UInt32 {
        UInt32(truncatingIfNeeded: entry)
    }

    @inline(__always)
    private static func aheadPos(_ entry: UInt64) -> Int {
        Int(entry >> 32)
    }

    /// Widens the current call's span to cover the scalar at `pos`.
    @inline(__always)
    private mutating func widenSpan(to pos: Int) {
        if pos < spanStart { spanStart = pos }
        if pos >= spanEnd { spanEnd = pos + 1 }
    }

    /// The normalized scalar `i` positions ahead (0 = next), or nil at the end.
    private mutating func scalarAhead(_ i: Int) -> UInt32? {
        while lookahead.count - lookaheadStart <= i {
            guard let c = scalars.next() else { return nil }
            lookahead.append(Self.packAhead(streamPos, c))
            streamPos += 1
        }
        return Self.aheadScalar(lookahead[lookaheadStart + i])
    }

    /// Consumes `n` scalars, recording them for prefix history.
    private mutating func consumeAhead(_ n: Int) {
        for k in 0..<n {
            let entry = lookahead[lookaheadStart + k]
            consumedExtras.append(Self.aheadScalar(entry))
            widenSpan(to: Self.aheadPos(entry))
        }
        scalarsConsumed += n
        discardAhead(n)
    }

    /// Consumes `n` scalars without recording history.
    private mutating func discardAhead(_ n: Int) {
        lookaheadStart += n
        if lookaheadStart > 32 {
            lookahead.removeFirst(lookaheadStart)
            lookaheadStart = 0
        }
    }

    /// Removes the scalar `i` positions ahead (UTS #10 S2.1.3 "remove C") and accounts for it: it is consumed by the CE under construction even though it is not contiguous with the matched prefix, so it counts once and widens this call's span past the marks that were skipped over.
    private mutating func removeAhead(at i: Int) {
        let entry = lookahead[lookaheadStart + i]
        widenSpan(to: Self.aheadPos(entry))
        scalarsConsumed += 1
        lookahead.remove(at: lookaheadStart + i)
    }

    private mutating func pushHistory(_ c: UInt32) {
        prev2 = prev1
        prev1 = c
    }

    // MARK: Main loop

    /// True once the NO_CE terminator has been appended.
    private(set) var terminated = false

    /// Produces all CEs of the string into `ces`, terminated by NO_CE. `bulkASCII`: take runs of simple ASCII scalars in one loop (`collectSimpleASCIIRun`). It pays on whole strings (sortKey); a short search pattern passes false, because a run of one or two scalars costs more than it saves.
    @inline(__always)
    mutating func collectAll(bulkASCII: Bool = true) throws {
        while try appendMoreBody(bulkASCII: bulkASCII) {}
    }

    /// Appends the CEs of the simple ASCII scalars that follow, pulled straight from the NFD front end's source, with the iterator's counters in locals. Per scalar it does exactly what the ASCII fast path of `appendMore()` does (an ASCII scalar is inert, so NFD passes it through unchanged); the per-scalar path kept every counter in memory, because the CE store through a raw pointer may alias any of them. The first scalar it cannot use goes back to the front end, which yields it next. Only `collectAll` uses it: `appendMore()` keeps its one-character-per-call contract for the lazy compare.
    @inline(never)  // one call per run; inlined, it pushed appendMore out of the collectAll loop
    private mutating func collectSimpleASCIIRun() {
        // Called from the ASCII fast path only: not terminated, and the table is not empty.
        guard lookaheadStart >= lookahead.count, scalars.isAtSource else { return }
        let table = simpleCEs
        // Swapped out, not copied: a copy retains the string's storage and releases it again.
        var source = "".unicodeScalars.makeIterator()
        swap(&source, &scalars.source)
        var count = 0
        var last1 = prev1
        var last2 = prev2
        var handBack: UInt32? = nil
        while let u = source.next() {
            let c = u.value
            if c < 128 {
                let ce = table[Int(c)]
                if ce != 0 {
                    ces.append(ce)
                    last2 = last1
                    last1 = c
                    count &+= 1
                    continue
                }
            }
            handBack = c
            break
        }
        scalars.source = source
        scalars.pendingFirst = handBack
        guard count > 0 else { return }
        streamPos &+= count
        scalarsConsumed &+= count
        spanStart = streamPos &- 1
        spanEnd = streamPos
        prev1 = last1
        prev2 = last2
    }

    /// Pops the next scalar, bypassing the lookahead buffer when it is empty (the common case — the buffer fills only during context matching). Starts a fresh span at the popped scalar's position.
    @inline(__always)
    private mutating func popScalar() -> UInt32? {
        if lookaheadStart < lookahead.count {
            let entry = lookahead[lookaheadStart]
            discardAhead(1)
            scalarsConsumed += 1
            let pos = Self.aheadPos(entry)
            spanStart = pos
            spanEnd = pos + 1
            return Self.aheadScalar(entry)
        }
        if let c = scalars.next() {
            // The lookahead is empty, so every scalar pulled so far has been consumed or removed: streamPos is this scalar's position.
            spanStart = streamPos
            spanEnd = streamPos + 1
            streamPos += 1
            scalarsConsumed += 1
            return c
        }
        return nil
    }

    /// Appends the CEs of the next character, or the NO_CE terminator at the end of input. Returns false once terminated. Enables lazy comparison: the primary level usually decides without generating all CEs.
    @inline(__always)
    mutating func appendMore() throws -> Bool {
        try appendMoreBody(bulkASCII: false)
    }

    /// The body of `appendMore()`. `bulkASCII` (collectAll only): after a simple ASCII scalar, also take the run of simple ASCII scalars that follows (`collectSimpleASCIIRun`). Only the ASCII branch tests it, so other scripts pay nothing. `appendMore()` passes false, so every other caller — the lazy compare, the search loops — compiles the code it had before, also in a build that does not inline across files.
    @inline(__always)
    private mutating func appendMoreBody(bulkASCII: Bool) throws -> Bool {
        guard !terminated else { return false }
        guard let c = popScalar() else {
            ces.append(CollationConstants.noCE)
            terminated = true
            return false
        }
        // Fast path: pre-computed CE for simple ASCII characters.
        if c < 128, !simpleCEs.isEmpty {
            let ce = simpleCEs[Int(c)]
            if ce != 0 {
                ces.append(ce)
                pushHistory(c)
                if bulkASCII { collectSimpleASCIIRun() }
                return true
            }
        }
        // Fast path: pre-computed CE for simple Thai-block scalars — consonants, sara aa, tone/vowel marks (profiling attributed ~200 ns of Thai compares to CE production). Prefix-vowel contractions and digits are 0 sentinels and take the full path, identical to the ASCII table's exclusion rules. ASCII returns above and never reaches this; other scripts pay one wrapped-subtract compare.
        if (c &- 0x0E00) < 128, !thaiCEs.isEmpty {
            let ce = thaiCEs[Int(c &- 0x0E00)]
            if ce != 0 {
                ces.append(ce)
                pushHistory(c)
                return true
            }
        }
        // Fast path: a combining mark (U+0300–037F) with one simple CE — the second half of a decomposed accented letter. A mark that reaches this point on its own was not consumed by a contraction of its starter, so the full path would give exactly this CE. Tailored or contracting marks are 0 in the table.
        if (c &- 0x0300) < 128, !markCEs.isEmpty {
            let ce = markCEs[Int(c &- 0x0300)]
            if ce != 0 {
                ces.append(ce)
                pushHistory(c)
                return true
            }
        }
        // Fast path: a CJK unified ideograph whose CE is one computed primary (root's Han: the OFFSET or IMPLICIT tag, or a long primary). Tailored, contracting and expanding ideographs get 0 and take the full path. Only with the fast tables, like the paths above, so that an iterator without tables is the reference for the tests. Other scripts pay one compare.
        if c >= 0x3400, !simpleCEs.isEmpty, Self.isCJKUnified(c) {
            let p = quickCJKPrimary(c)
            if p != 0 {
                ces.append(CollationConstants.makeCE(p))
                pushHistory(c)
                return true
            }
        }
        // isEmpty guards: removeAll on a never-used array hits the shared empty-singleton storage, which is never uniquely referenced, and takes the copy-on-write slow path every time.
        if !consumedExtras.isEmpty { consumedExtras.removeAll(keepingCapacity: true) }
        let (d, ce32) = lookup(c)
        try appendCEs(d: d, c: c, ce32: ce32, depth: 0)
        pushHistory(c)
        for extra in consumedExtras { pushHistory(extra) }
        return true
    }

    /// The CE at index `i`, generating lazily as needed. `i` must not run past the NO_CE terminator (all level loops stop at NO_CE).
    mutating func ce(at i: Int) throws -> Int64 {
        while ces.count <= i {
            if try !appendMore() { break }
        }
        return ces[i]
    }

    private mutating func appendCEs(d: CollationDataView, c: UInt32, ce32 initialCE32: UInt32, depth: Int) throws {
        // Specials never nest deeper than prefix -> contraction -> expansion (plus digit/u0000 indirections) in root data.
        guard depth <= 6 else { throw RootCollator.CollationError.malformedData }
        var ce32 = initialCE32
        while true {
            if !CollationConstants.isSpecialCE32(ce32) {
                ces.append(CollationConstants.ceFromCE32(ce32))
                return
            }
            switch CollationConstants.tagFromCE32(ce32) {
            case .longPrimary, .longSecondary:
                ces.append(CollationConstants.ceFromCE32(ce32))
                return
            case .latinExpansion:
                ces.append(CollationConstants.latinCE0FromCE32(ce32))
                ces.append(CollationConstants.latinCE1FromCE32(ce32))
                return
            case .expansion32:
                let index = CollationConstants.indexFromCE32(ce32)
                for i in 0..<CollationConstants.lengthFromCE32(ce32) {
                    ces.append(CollationConstants.ceFromCE32(d.ce32s[index + i]))
                }
                return
            case .expansion:
                let index = CollationConstants.indexFromCE32(ce32)
                for i in 0..<CollationConstants.lengthFromCE32(ce32) {
                    ces.append(d.ces[index + i])
                }
                return
            case .prefix:
                ce32 = prefixCE32(d: d, ce32)
            case .contraction:
                ce32 = contractionCE32(d: d, ce32)
            case .digit:
                if numeric {
                    try appendNumericCEs(d: d, firstCE32: ce32)
                    return
                }
                ce32 = d.ce32s[CollationConstants.indexFromCE32(ce32)]
            case .u0000:
                ce32 = d.ce32s[0]
            case .hangul:
                // Unreachable behind the NFD front end (syllables decompose to Jamo first), but kept for data completeness.
                try appendHangulCEs(d: d, syllable: c, depth: depth)
                return
            case .offset:
                let dataCE = d.ces[CollationConstants.indexFromCE32(ce32)]
                ces.append(CollationConstants.makeCE(CollationConstants.threeBytePrimaryForOffsetData(c, dataCE)))
                return
            case .implicit:
                ces.append(CollationConstants.makeCE(CollationConstants.unassignedPrimaryFromCodePoint(c)))
                return
            case .fallback, .reserved3, .builderData, .leadSurrogate:
                throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: ce32 & 0xf)
            }
        }
    }

    // MARK: Prefix (precontext) matching

    /// Resolves a PREFIX_TAG CE32 by matching the preceding scalars against the prefix trie (stored last-character-first). (getCE32FromPrefix.)
    private mutating func prefixCE32(d: CollationDataView, _ ce32: UInt32) -> UInt32 {
        let index = CollationConstants.indexFromCE32(ce32)
        var result = d.readContextCE32(at: index)  // default if no prefix match
        guard let p1 = prev1 else { return result }
        var trie = UCharsTrie(units: d.contexts, offset: index + 2)
        var match = trie.firstForCodePoint(p1)
        if match.hasValue {
            result = UInt32(bitPattern: trie.getValue())
        }
        if match.hasNext, let p2 = prev2 {
            match = trie.nextForCodePoint(p2)
            if match.hasValue {
                result = UInt32(bitPattern: trie.getValue())
            }
            // Prefixes longer than two scalars do not occur in CLDR data; deeper history is not kept.
        }
        return result
    }

    // MARK: Contraction (suffix) matching

    /// Resolves a CONTRACTION_TAG CE32 by matching following scalars against the suffix trie, including discontiguous contractions per UTS #10 S2.1. Matched scalars are consumed; marks skipped over by a discontiguous match stay in the lookahead and produce their own CEs afterwards.
    private mutating func contractionCE32(d: CollationDataView, _ contractionCE32: UInt32) -> UInt32 {
        let index = CollationConstants.indexFromCE32(contractionCE32)
        let defaultCE32 = d.readContextCE32(at: index)
        guard let first = scalarAhead(0) else { return defaultCE32 }
        if (contractionCE32 & CollationConstants.contractNextCCC) != 0 && norm.ccc(first) == 0 {
            // Every suffix starts with a non-starter; a starter cannot match.
            return defaultCE32
        }

        // Longest contiguous match (UTS #10 S2.1 "longest initial substring S").
        var trie = UCharsTrie(units: d.contexts, offset: index + 2)
        var bestCE32 = defaultCE32
        var bestLength = 0
        var stateAfterBest = trie  // trie state after the matched part of S
        var i = 0
        var match = trie.firstForCodePoint(first)
        while match != .noMatch {
            i += 1
            if match.hasValue {
                bestCE32 = UInt32(bitPattern: trie.getValue())
                bestLength = i
                stateAfterBest = trie
            }
            guard match.hasNext, let s = scalarAhead(i) else { break }
            match = trie.nextForCodePoint(s)
        }

        // Discontiguous contractions (S2.1.1–S2.1.3): process the non-starters following the match. The stream is canonically ordered, so a candidate C is blocked iff some intervening mark has ccc >= ccc(C), i.e. iff prevCC (the ccc of the last skipped mark) >= ccc(C).
        if (contractionCE32 & CollationConstants.contractTrailingCCC) != 0
            // With CONTRACT_SINGLE_CP_NO_MATCH, discontiguous matching only extends an existing match (ICU: sinceMatch < lookAhead).
            && ((contractionCE32 & CollationConstants.contractSingleCpNoMatch) == 0 || bestLength > 0) {
            var matchedState = stateAfterBest
            var j = bestLength
            var prevCC: UInt8 = 0
            while let s = scalarAhead(j) {
                let cc = norm.ccc(s)
                if cc == 0 { break }  // S2.1.1: only non-starters following S
                if prevCC < cc {
                    // "If C is not blocked from S, find if S+C has a match." (S2.1.2)
                    var attempt = matchedState
                    let m = attempt.nextForCodePoint(s)
                    if m.hasValue {
                        // "If there is a match, replace S by S+C, and remove C." (S2.1.3)
                        bestCE32 = UInt32(bitPattern: attempt.getValue())
                        // Consumes C and widens this call's span past the marks skipped over — see removeAhead. The trailing consumeAhead(bestLength) covers only the contiguous part of the match.
                        removeAhead(at: j)
                        matchedState = attempt
                        if !m.hasNext { break }
                        continue  // keep prevCC; the next mark shifted into j
                    }
                }
                prevCC = cc
                j += 1
            }
        }

        consumeAhead(bestLength)
        return bestCE32
    }

    private mutating func appendHangulCEs(d dIn: CollationDataView, syllable c: UInt32, depth: Int) throws {
        // Jamo CE32s normally live in the base (root) data.
        let d = dIn.jamoCE32sStart >= 0 ? dIn : (baseView ?? dIn)
        guard d.jamoCE32sStart >= 0, (0xac00...0xd7a3).contains(c) else {
            throw RootCollator.CollationError.unsupportedMapping(scalar: c, tag: CollationConstants.Tag.hangul.rawValue)
        }
        let sIndex = Int(c) - 0xac00
        let jamo = d.jamoCE32sStart
        try appendCEs(d: d, c: c, ce32: d.ce32s[jamo + sIndex / 588], depth: depth + 1)
        try appendCEs(d: d, c: c, ce32: d.ce32s[jamo + 19 + (sIndex % 588) / 28], depth: depth + 1)
        let t = sIndex % 28
        if t != 0 {
            try appendCEs(d: d, c: c, ce32: d.ce32s[jamo + 19 + 21 + t - 1], depth: depth + 1)
        }
    }

    // MARK: Numeric collation (CODAN)

    /// Scratch for digit runs with more than 7 significant digits (rare); reused across runs so the slow path allocates only once per iterator.
    private var numericDigits: [Int32] = []

    /// Collects the digit run starting with `firstCE32` and appends numeric CEs. (CollationIterator::appendNumericCEs, forward direction.)
    private mutating func appendNumericCEs(d: CollationDataView, firstCE32: UInt32) throws {
        // First pass over the run (through the lookahead buffer, nothing consumed yet): accumulate the value and count significant digits. Runs of <= 7 significant digits — practically every digit run in real text — encode as a single dense CE straight from the value: no digits array, no slice copy (profiling showed the two per-run array allocations were most of numeric mode's cost).
        var value = CollationConstants.digitFromCE32(firstCE32)
        var significant = value == 0 ? 0 : 1
        var count = 0
        var dense = true
        while let c = scalarAhead(count) {
            let (_, ce32) = lookup(c)
            guard CollationConstants.isSpecialCE32(ce32) && CollationConstants.tagFromCE32(ce32) == .digit else { break }
            let digit = CollationConstants.digitFromCE32(ce32)
            count += 1
            if significant == 0 && digit == 0 { continue }
            significant += 1
            if significant > 7 { dense = false; break }
            value = value * 10 + digit
        }

        // 7-digit values past the dense encoding's capacity (>= 1_042_490) use the pair encoding, exactly like ICU's length<=7 fall-through.
        if dense && value < 1_042_490 {
            consumeAhead(count)
            appendDenseNumericCE(value: value, numericPrimary: d.numericPrimary)
            return
        }

        // Slow path (> 7 significant digits): collect the digits into the reusable scratch and run the segmented pair encoding.
        if !numericDigits.isEmpty { numericDigits.removeAll(keepingCapacity: true) }
        numericDigits.append(CollationConstants.digitFromCE32(firstCE32))
        count = 0
        while let c = scalarAhead(count) {
            let (_, ce32) = lookup(c)
            guard CollationConstants.isSpecialCE32(ce32) && CollationConstants.tagFromCE32(ce32) == .digit else { break }
            numericDigits.append(CollationConstants.digitFromCE32(ce32))
            count += 1
        }
        consumeAhead(count)
        var pos = 0
        repeat {
            // Skip leading zeros.
            while pos < numericDigits.count - 1 && numericDigits[pos] == 0 { pos += 1 }
            // Write a sequence of CEs for at most 254 digits at a time.
            let segmentLength = min(numericDigits.count - pos, 254)
            appendNumericSegmentCEs(d: d, start: pos, length: segmentLength)
            pos += segmentLength
        } while pos < numericDigits.count
    }

    /// The dense single-CE encoding for a small segment value (callers guarantee value < 1_042_490). (The in-capacity part of the `length <= 7` branch of ICU's appendNumericSegmentCEs.)
    private mutating func appendDenseNumericCE(value: Int32, numericPrimary: UInt32) {
        var value = value
        // Primary weight second byte values:
        //     74 byte values   2.. 75 for small numbers in two-byte primary weights.
        //     40 byte values  76..115 for medium numbers in three-byte primary weights.
        //     16 byte values 116..131 for large numbers in four-byte primary weights.
        //    124 byte values 132..255 for very large numbers with 4..127 digit pairs.
        var firstByte: Int32 = 2
        var numBytes: Int32 = 74
        if value < numBytes {
            ces.append(CollationConstants.makeCE(numericPrimary | (UInt32(firstByte + value) << 16)))
            return
        }
        value -= numBytes
        firstByte += numBytes
        numBytes = 40
        if value < numBytes * 254 {
            let primary = numericPrimary
                | (UInt32(firstByte + value / 254) << 16) | (UInt32(2 + value % 254) << 8)
            ces.append(CollationConstants.makeCE(primary))
            return
        }
        value -= numBytes * 254
        firstByte += numBytes
        numBytes = 16
        // Callers guarantee the original value < 1_042_490 (= 74 + 40*254 + 16*254*254), the dense encoding's capacity; larger values take the pair encoding instead.
        precondition(value < numBytes * 254 * 254)
        var primary = numericPrimary | UInt32(2 + value % 254)
        value /= 254
        primary |= UInt32(2 + value % 254) << 8
        value /= 254
        primary |= UInt32(firstByte + value % 254) << 16
        ces.append(CollationConstants.makeCE(primary))
    }

    /// (CollationIterator::appendNumericSegmentCEs.) Operates on `numericDigits[start..<start+length]` in place — no slice copy.
    private mutating func appendNumericSegmentCEs(d: CollationDataView, start: Int, length segmentLength: Int) {
        var length = segmentLength
        let numericPrimary = d.numericPrimary
        // Note: We use primary byte values 2..255: digits are not compressible.
        if length <= 7 {
            // Very dense encoding for small numbers.
            var value = numericDigits[start]
            for i in 1..<length { value = value * 10 + numericDigits[start + i] }
            if value < 1_042_490 {
                appendDenseNumericCE(value: value, numericPrimary: numericPrimary)
                return
            }
            // value past the dense capacity — fall through to pair encoding.
        }

        // The second primary byte value 132..255 indicates the number of digit pairs (4..127), then we generate primary bytes with those pairs. Omit trailing 00 pairs. Decrement the value for the last pair.
        let numPairs = Int32((length + 1) / 2)
        var primary = numericPrimary | (UInt32(132 - 4 + numPairs) << 16)
        // Find the length without trailing 00 pairs.
        while numericDigits[start + length - 1] == 0 && numericDigits[start + length - 2] == 0 { length -= 2 }
        // Read the first pair.
        var pair: Int32
        var pos: Int
        if length & 1 == 1 {
            // Only "half a pair" if we have an odd number of digits.
            pair = numericDigits[start]
            pos = 1
        } else {
            pair = numericDigits[start] * 10 + numericDigits[start + 1]
            pos = 2
        }
        pair = 11 + 2 * pair
        // Add the pairs of digits between pos and length.
        var shift: Int32 = 8
        while pos < length {
            if shift == 0 {
                // Every three pairs/bytes we need to store a 4-byte-primary CE and start with a new CE with the '0' primary lead byte.
                primary |= UInt32(pair)
                ces.append(CollationConstants.makeCE(primary))
                primary = numericPrimary
                shift = 16
            } else {
                primary |= UInt32(pair) << shift
                shift -= 8
            }
            pair = 11 + 2 * (numericDigits[start + pos] * 10 + numericDigits[start + pos + 1])
            pos += 2
        }
        primary |= UInt32(pair - 1) << shift
        ces.append(CollationConstants.makeCE(primary))
    }
}
