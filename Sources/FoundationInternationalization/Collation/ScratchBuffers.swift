// Reusable per-call buffers. Building the CE and NFD iterators afresh costs
// several heap allocations per compare()/sortKey() call; a RootCollator
// instead keeps a thread-local buffer set and resets it, so repeated calls
// run allocation-free once the buffers have grown to the working size.
// (ICU4C reaches the same goal with stack buffers, which Swift arrays cannot
// express.) The public API stays thread-safe: each thread owns its own
// buffer set, with no locking or reference counting on the checkout path.

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Minimal mutual exclusion: os_unfair_lock on Darwin (a few ns uncontended,
/// vs NSLock's objc dispatch), NSLock elsewhere. The unfair lock must live at
/// a stable address, hence the allocation.
struct PoolLock {
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

    init(data: CollationData, base: CollationData?, norm: NormalizationData,
         simpleCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         thaiCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0)) {
        let empty = "".unicodeScalars
        self.left = CEIterator(data: data, base: base, norm: norm, numeric: false, scalars: empty, simpleCEs: simpleCEs, thaiCEs: thaiCEs)
        self.right = CEIterator(data: data, base: base, norm: norm, numeric: false, scalars: empty, simpleCEs: simpleCEs, thaiCEs: thaiCEs)
    }
}

/// Thread-local scratch buffer stash. Each thread caches one ScratchBuffers
/// instance, avoiding all locking, exclusivity checks, and ARC traffic on
/// the take/give path. If a thread re-enters (e.g. compare inside compare,
/// which doesn't happen in practice but is sound), `take()` returns nil and
/// the caller allocates a fresh set.
///
/// Implementation: a single pthread_key_t holds an UnsafeMutablePointer to
/// a `ThreadLocalSlot` (which wraps the optional ScratchBuffers). The key's
/// destructor frees the slot on thread exit.
final class ThreadLocalScratch: @unchecked Sendable {
    /// The slot stored in thread-local storage. Wrapping in a struct stored
    /// via UnsafeMutablePointer avoids ARC on the TLS read path entirely.
    struct Slot {
        var buffers: ScratchBuffers?
    }

    private var key: pthread_key_t

    init() {
        var k = pthread_key_t()
        pthread_key_create(&k) { raw in
            // Destructor: called on thread exit. Release the slot.
            let slot = raw.assumingMemoryBound(to: Slot.self)
            slot.deinitialize(count: 1)
            slot.deallocate()
        }
        key = k
    }

    deinit {
        // Note: any thread-local slots still alive at this point will be
        // cleaned up by their thread's exit destructor. We just destroy the
        // key itself.
        pthread_key_delete(key)
    }

    /// Takes the cached buffer set for this thread, or nil if none is
    /// stashed (first call on this thread, or re-entrant call).
    @inline(__always)
    func take() -> ScratchBuffers? {
        guard let raw = pthread_getspecific(key) else { return nil }
        let slot = raw.assumingMemoryBound(to: Slot.self)
        let buffers = slot.pointee.buffers
        slot.pointee.buffers = nil
        return buffers
    }

    /// Stashes a buffer set back into the thread-local slot. If the slot
    /// doesn't exist yet (first give on this thread), creates it.
    @inline(__always)
    func give(_ buffers: ScratchBuffers) {
        if let raw = pthread_getspecific(key) {
            let slot = raw.assumingMemoryBound(to: Slot.self)
            slot.pointee.buffers = buffers
        } else {
            let slot = UnsafeMutablePointer<Slot>.allocate(capacity: 1)
            slot.initialize(to: Slot(buffers: buffers))
            pthread_setspecific(key, UnsafeRawPointer(slot))
        }
    }
}

/// One immutable fast-Latin setup: the precomputed primaries and packed
/// options for one options word (packedOptions < 0 = unsupported).
final class FastLatinSetup: Sendable {
    let word: Int32
    let packedOptions: Int32
    let primaries: [UInt16]

    init(word: Int32, packedOptions: Int32, primaries: [UInt16]) {
        self.word = word
        self.packedOptions = packedOptions
        self.primaries = primaries
    }
}

/// Holds the most recently used fast-Latin setup, so bail-free compares need
/// no scratch buffers at all. Snapshots are immutable: a reader keeps using
/// its snapshot even if another thread replaces the current one.
final class FastLatinCache: @unchecked Sendable {
    private let lock = PoolLock()
    private var current: FastLatinSetup?

    func setup(for word: Int32) -> FastLatinSetup? {
        lock.acquire()
        defer { lock.release() }
        guard let current, current.word == word else { return nil }
        return current
    }

    func store(_ setup: FastLatinSetup) {
        lock.acquire()
        defer { lock.release() }
        current = setup
    }

    deinit {
        lock.deallocate()
    }
}

/// Legacy pool kept as fallback: if thread-local take returns nil (first call
/// or re-entrant), we try the pool before allocating fresh. In practice the
/// thread-local handles >99% of calls; this exists only for correctness in
/// edge cases (and for ScratchBuffers created before the thread-local was
/// warmed up on that thread).
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
