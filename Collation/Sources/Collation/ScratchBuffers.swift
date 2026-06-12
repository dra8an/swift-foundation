// Reusable per-call buffers. Building the CE and NFD iterators afresh costs
// several heap allocations per compare()/sortKey() call; a RootCollator
// instead keeps a small pool of buffer sets and resets them, so repeated
// calls run allocation-free once the buffers have grown to the working size.
// (ICU4C reaches the same goal with stack buffers, which Swift arrays cannot
// express.) The public API stays thread-safe: a set is checked out for the
// duration of one call, and concurrent calls beyond the pool's capacity
// simply allocate a fresh set.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Minimal mutual exclusion for the pool: os_unfair_lock on Darwin (a few ns
/// uncontended, vs NSLock's objc dispatch), NSLock elsewhere. The unfair lock
/// must live at a stable address, hence the allocation.
private struct PoolLock {
    #if canImport(Darwin)
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }
    func deallocate() { lock.deallocate() }
    @inline(__always) func acquire() { os_unfair_lock_lock(lock) }
    @inline(__always) func release() { os_unfair_lock_unlock(lock) }
    #else
    private let lock = NSLock()
    func deallocate() {}
    @inline(__always) func acquire() { lock.lock() }
    @inline(__always) func release() { lock.unlock() }
    #endif
}

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
    private let lock = PoolLock()
    private var free: [ScratchBuffers] = []

    func take() -> ScratchBuffers? {
        lock.acquire()
        defer { lock.release() }
        return free.popLast()
    }

    func give(_ buffers: ScratchBuffers) {
        lock.acquire()
        defer { lock.release() }
        if free.count < 4 { free.append(buffers) }
    }

    deinit {
        lock.deallocate()
    }
}
