// Reusable per-call buffers. Building the CE and NFD iterators afresh costs
// several heap allocations per compare()/sortKey() call; a RootCollator
// instead keeps a small pool of buffer sets and resets them, so repeated
// calls run allocation-free once the buffers have grown to the working size.
// (ICU4C reaches the same goal with stack buffers, which Swift arrays cannot
// express.) The public API stays thread-safe: a set is checked out for the
// duration of one call, and concurrent calls beyond the pool's capacity
// simply allocate a fresh set.

import Foundation

/// One set of buffers: everything a single compare() or sortKey() call needs.
final class ScratchBuffers {
    var left: CEIterator
    var right: CEIterator
    /// sortKey: the key bytes under construction.
    var key: [UInt8] = []
    /// sortKey: the per-level byte buffers.
    var levels = SortKeyLevelBuffers()
    /// sortKey: NFD scalars for the identical level.
    var nfdScalars: [UInt32] = []

    init(data: CollationData, base: CollationData?, norm: NormalizationData) {
        let empty = "".unicodeScalars
        self.left = CEIterator(data: data, base: base, norm: norm, numeric: false, scalars: empty)
        self.right = CEIterator(data: data, base: base, norm: norm, numeric: false, scalars: empty)
    }
}

/// A small thread-safe pool of buffer sets, shared by all copies of one
/// RootCollator (the iterators inside are bound to its collation data).
final class ScratchPool: @unchecked Sendable {
    private let lock = NSLock()
    private var free: [ScratchBuffers] = []

    func take() -> ScratchBuffers? {
        lock.lock()
        defer { lock.unlock() }
        return free.popLast()
    }

    func give(_ buffers: ScratchBuffers) {
        lock.lock()
        defer { lock.unlock() }
        if free.count < 4 { free.append(buffers) }
    }
}
