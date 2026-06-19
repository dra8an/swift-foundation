// Incremental NFD: adapts a Unicode scalar stream into its canonical
// decomposition with canonical ordering applied — the "fused decomposition"
// front end of the ICU4X collator model (Docs/02-icu4x-strategy.md).
//
// Each refill produces one reorderable unit: a starter (or the string-initial
// run of non-starters) plus all following combining marks, with the marks
// stably sorted by canonical combining class (the Canonical Ordering
// Algorithm, UAX #15).

struct NFDIterator {
    let norm: NormalizationData
    var source: String.UnicodeScalarView.Iterator
    /// A scalar already pulled from the input (by the caller's identical-prefix
    /// skip walk) to be yielded before `source`. Lets a compare reuse the skip
    /// walk's iterator — already positioned past the shared prefix — instead of
    /// building a fresh String iterator and re-walking that prefix.
    var pendingFirst: UInt32? = nil
    /// Decomposed scalars of the next input scalar, carried over when it
    /// started a new reorderable unit and ended the previous refill.
    var carried: [UInt32] = []
    /// Current normalized output unit.
    var unit: [UInt32] = []
    var unitNext = 0
    /// Combining marks (ccc > 0) of the unit being built, sorted on flush.
    var marks: [UInt32] = []

    init(norm: NormalizationData, scalars: String.UnicodeScalarView) {
        self.norm = norm
        self.source = scalars.makeIterator()
    }

    /// Rewinds onto a new input, keeping the buffers' storage so that reuse
    /// across compares runs allocation-free. `skippingFirst` positions the
    /// iterator after the first `n` scalars (for the identical-prefix skip;
    /// the caller guarantees that position is a clean restart boundary).
    mutating func reset(scalars: String.UnicodeScalarView, skippingFirst n: Int = 0) {
        source = scalars.makeIterator()
        for _ in 0..<n { _ = source.next() }
        pendingFirst = nil
        clearBuffers()
    }

    /// Rewinds onto an already-positioned scalar iterator plus one scalar the
    /// caller has already pulled from it (`first`). Equivalent to resetting onto
    /// the suffix `first` followed by the rest of `iter`, but without building a
    /// new String iterator or re-walking the skipped prefix.
    mutating func reset(source iter: String.UnicodeScalarView.Iterator, first: UInt32?) {
        source = iter
        pendingFirst = first
        clearBuffers()
    }

    @inline(__always)
    private mutating func clearBuffers() {
        // isEmpty guards: removeAll on a never-used array hits the shared
        // empty-singleton storage, which is never uniquely referenced, and
        // takes the copy-on-write slow path every time.
        if !carried.isEmpty { carried.removeAll(keepingCapacity: true) }
        if !unit.isEmpty { unit.removeAll(keepingCapacity: true) }
        unitNext = 0
        if !marks.isEmpty { marks.removeAll(keepingCapacity: true) }
    }

    /// Next raw scalar of the input: the caller-supplied pending scalar first,
    /// then the underlying iterator.
    @inline(__always)
    private mutating func nextSourceScalar() -> UInt32? {
        if let p = pendingFirst {
            pendingFirst = nil
            return p
        }
        return source.next()?.value
    }

    /// Scratch buffer for one scalar's decomposition, reused across refills.
    private var decomposed: [UInt32] = []

    /// Next scalar of the NFD form of the input, or nil at the end.
    @inline(__always)
    mutating func next() -> UInt32? {
        if unitNext < unit.count {
            let c = unit[unitNext]
            unitNext += 1
            return c
        }
        if carried.isEmpty {
            // Fast path: between reorderable units, a bare starter with no
            // decomposition can be emitted without any buffering (it is a
            // hard reordering boundary; following marks form the next unit).
            guard let c = nextSourceScalar() else { return nil }
            if norm.isInert(c) {
                return c
            }
            refill(startingWith: c)
        } else {
            refill(startingWith: nil)
        }
        if unit.isEmpty { return nil }
        unitNext = 1
        return unit[0]
    }

    private mutating func refill(startingWith first: UInt32?) {
        unit.removeAll(keepingCapacity: true)
        unitNext = 0
        if !carried.isEmpty {
            // Fast exit: single inert carried scalar — emit it directly as a
            // one-element unit without consuming the next source scalar into
            // carried (breaks the cascade where every post-accent starter
            // triggers a full refill).
            if carried.count == 1, norm.isInert(carried[0]) {
                unit.append(carried[0])
                carried.removeAll(keepingCapacity: true)
                return
            }
            for c in carried { absorb(c) }
            carried.removeAll(keepingCapacity: true)
        }
        if let first {
            if norm.hasDecomposition(first) {
                decomposed.removeAll(keepingCapacity: true)
                _ = norm.appendDecomposition(of: first, to: &decomposed)
                for c in decomposed { absorb(c) }
            } else {
                absorb(first)
            }
        }
        while let v = nextSourceScalar() {
            // Common case: the scalar maps to itself (no decomposition). Skip
            // the `decomposed` scratch buffer entirely — no clear, no append,
            // no copy loop — which is the bulk of refill's per-scalar work.
            if !norm.hasDecomposition(v) {
                // A starter begins a new reorderable unit: finish the current
                // one and carry the scalar over.
                if (!unit.isEmpty || !marks.isEmpty) && norm.ccc(v) == 0 {
                    carried.append(v)
                    flushMarks()
                    return
                }
                absorb(v)
                continue
            }
            decomposed.removeAll(keepingCapacity: true)
            _ = norm.appendDecomposition(of: v, to: &decomposed)
            // A decomposition starting with a starter begins a new reorderable
            // unit: finish the current one and carry the new scalars over.
            if (!unit.isEmpty || !marks.isEmpty) && norm.ccc(decomposed[0]) == 0 {
                carried.append(contentsOf: decomposed)
                flushMarks()
                return
            }
            for c in decomposed { absorb(c) }
        }
        flushMarks()
    }

    private mutating func absorb(_ c: UInt32) {
        if norm.ccc(c) == 0 {
            flushMarks()
            unit.append(c)
        } else {
            marks.append(c)
        }
    }

    /// Stable sort of the pending combining marks by ccc (Canonical Ordering).
    private mutating func flushMarks() {
        switch marks.count {
        case 0:
            return
        case 1:
            unit.append(marks[0])
        default:
            // Stable insertion sort by ccc, in place on `marks`. Done with
            // element shifts (no insert/remove, so no replaceSubrange/memmove)
            // and no temporary arrays — mark runs are short, so recomputing
            // ccc during the shift is cheaper than allocating a parallel buffer.
            for k in 1..<marks.count {
                let c = marks[k]
                let cc = norm.ccc(c)
                var j = k
                while j > 0 && norm.ccc(marks[j - 1]) > cc {
                    marks[j] = marks[j - 1]
                    j -= 1
                }
                marks[j] = c
            }
            for c in marks { unit.append(c) }
        }
        marks.removeAll(keepingCapacity: true)
    }
}
