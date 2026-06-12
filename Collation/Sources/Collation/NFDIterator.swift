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
    /// across compares runs allocation-free.
    mutating func reset(scalars: String.UnicodeScalarView) {
        source = scalars.makeIterator()
        carried.removeAll(keepingCapacity: true)
        unit.removeAll(keepingCapacity: true)
        unitNext = 0
        marks.removeAll(keepingCapacity: true)
    }

    /// Scratch buffer for one scalar's decomposition, reused across refills.
    private var decomposed: [UInt32] = []

    /// Next scalar of the NFD form of the input, or nil at the end.
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
            guard let scalar = source.next() else { return nil }
            let c = scalar.value
            if c < 0xc0 || (norm.ccc(c) == 0 && !norm.hasDecomposition(c)) {
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
            for c in carried { absorb(c) }
            carried.removeAll(keepingCapacity: true)
        }
        if let first {
            decomposed.removeAll(keepingCapacity: true)
            if !norm.appendDecomposition(of: first, to: &decomposed) {
                decomposed.append(first)
            }
            for c in decomposed { absorb(c) }
        }
        while let scalar = source.next() {
            decomposed.removeAll(keepingCapacity: true)
            if !norm.appendDecomposition(of: scalar.value, to: &decomposed) {
                decomposed.append(scalar.value)
            }
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
            // Insertion sort: stable, and mark runs are short in practice.
            var sorted: [(ccc: UInt8, scalar: UInt32)] = []
            for c in marks {
                let cc = norm.ccc(c)
                var i = sorted.count
                while i > 0 && sorted[i - 1].ccc > cc { i -= 1 }
                sorted.insert((cc, c), at: i)
            }
            unit.append(contentsOf: sorted.map(\.scalar))
        }
        marks.removeAll(keepingCapacity: true)
    }
}
