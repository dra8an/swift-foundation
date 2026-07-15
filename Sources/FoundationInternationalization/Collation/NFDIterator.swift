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
    /// A combining mark stashed by the Latin fast path — returned on the next
    /// call to next() before resuming normal source reading.
    var pendingMark: UInt32? = nil
    /// Decomposed scalars of the next input scalar, carried over when it
    /// started a new reorderable unit and ended the previous refill.
    var carried: [UInt32] = []
    /// Current normalized output unit.
    var unit: [UInt32] = []
    var unitNext = 0
    /// Combining marks (ccc > 0) of the unit being built, sorted on flush.
    var marks: [UInt32] = []
    /// True once any input scalar has been decomposed (the output stream is no
    /// longer 1:1 with the source). While false, NFD scalar offsets equal
    /// source scalar offsets — mark reordering permutes scalars within a unit
    /// but never changes counts. CollationSearch uses this to skip building
    /// the NFD→source position map.
    private(set) var sawDecomposition = false

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
        pendingMark = nil
        sawDecomposition = false
        clearBuffers()
    }

    /// Rewinds onto an already-positioned scalar iterator plus one scalar the
    /// caller has already pulled from it (`first`). Equivalent to resetting onto
    /// the suffix `first` followed by the rest of `iter`, but without building a
    /// new String iterator or re-walking the skipped prefix.
    mutating func reset(source iter: String.UnicodeScalarView.Iterator, first: UInt32?) {
        source = iter
        pendingFirst = first
        pendingMark = nil
        sawDecomposition = false
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
        if let mark = pendingMark {
            pendingMark = nil
            return mark
        }
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
            // Fast path for Latin precomposed characters (U+00C0..U+02FF):
            // decompose to [starter, mark] and emit directly if the following
            // character is a starter (no canonical reordering possible).
            // Bypasses refill() entirely — no arrays, no loops, no carry.
            if c < 0x0300, let quick = norm.quickDecomp(c) {
                sawDecomposition = true
                let following = nextSourceScalar()
                if following == nil || (following! < 0x300 || norm.leadCCC(following!) == 0) {
                    pendingFirst = following
                    pendingMark = quick.mark
                    return quick.base
                }
                // Rare: combining mark follows — fall through to refill.
                pendingFirst = following
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
        // Fast path for a lone combining mark between starters (Thai
        // tone/vowel marks): a non-decomposing mark whose follower starts
        // with ccc 0 (or ends the input) is a complete single-mark
        // reorderable unit by itself — nothing can sort across either
        // boundary, so it becomes the unit with none of the absorb/
        // flushMarks machinery, and the peeked follower goes to
        // `pendingFirst` (skipping the carried-scalar refill round trip).
        // Output stays 1:1 with the source (mirrors ICU's FCD pass-through,
        // which never buffers ordered marks). Two adjacent marks or a
        // decomposing mark take the full path below. This check lives HERE,
        // not in next(), so next()'s inlined copies stay byte-identical and
        // no other corpus can be affected (optimization-targets.md §34).
        if let c = first, carried.isEmpty {
            let v = norm.value(c)
            if (v >> 16) & 7 == 0, UInt8(truncatingIfNeeded: v) != 0 {
                let following = nextSourceScalar()
                if following == nil || (following! < 0x300 || norm.leadCCC(following!) == 0) {
                    pendingFirst = following
                    unit.append(c)
                    return
                }
                // Adjacent mark: hand the peeked scalar back and buffer.
                pendingFirst = following
            }
        }
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
            if let quick = norm.quickDecomp(first) {
                // Fast path for simple [starter, mark]: build unit directly
                // without absorb/flushMarks calls. We know base is CCC=0 and
                // mark is CCC>0 from quickDecomp's guard.
                sawDecomposition = true
                unit.append(quick.base)
                marks.append(quick.mark)
            } else if norm.hasDecomposition(first) {
                sawDecomposition = true
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
            if let quick = norm.quickDecomp(v) {
                // Common Latin case: [starter, mark]. The starter begins a new
                // reorderable unit if we already have content.
                sawDecomposition = true
                if (!unit.isEmpty || !marks.isEmpty) {
                    carried.append(quick.base)
                    carried.append(quick.mark)
                    flushMarks()
                    return
                }
                absorb(quick.base)
                absorb(quick.mark)
                continue
            }
            sawDecomposition = true
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
