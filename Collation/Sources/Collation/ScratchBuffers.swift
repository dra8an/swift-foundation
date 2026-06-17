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

// MARK: - Thread-Local Scratch Cache

/// A process-wide, never-deleted pthread key for caching one ScratchBuffers
/// per thread. The key's destructor runs on thread exit, releasing the slot.
///
/// Design:
/// - ONE key for the entire process (never exhausts the 512-key limit).
/// - Each thread's slot holds a buffer set tagged with the collator ID that
///   owns it. On take(), the ID is checked; a mismatch means the buffer was
///   left by a different (possibly dead) collator — it's discarded.
/// - Collator IDs are monotonically increasing (never reused), so address
///   reuse after free cannot cause a stale buffer to match a new collator.
/// - The slot is a raw struct pointer (no class, no ARC on the read path).
private let _scratchTLSKey: pthread_key_t = {
    var key = pthread_key_t()
    let rc = pthread_key_create(&key) { raw in
        let slot = raw.assumingMemoryBound(to: TLSSlot.self)
        slot.deinitialize(count: 1)
        slot.deallocate()
    }
    precondition(rc == 0, "pthread_key_create failed: \(rc)")
    return key
}()

/// Monotonically increasing collator ID. Each RootCollator gets a unique ID
/// that's never reused (even if the collator's memory address is recycled).
private let _nextCollatorID = LockedCounter()

private final class LockedCounter: @unchecked Sendable {
    private var value: UInt64 = 0
    private let lock = PoolLock()

    func next() -> UInt64 {
        lock.acquire()
        value += 1
        let v = value
        lock.release()
        return v
    }
}

/// The raw struct stored in thread-local storage. No class — no ARC.
private struct TLSSlot {
    var collatorID: UInt64
    var buffers: ScratchBuffers?
}

/// Thread-local scratch buffer interface. One instance per RootCollator;
/// each holds a unique monotonic ID. The actual TLS slot is process-wide.
struct ThreadLocalScratch: @unchecked Sendable {
    let collatorID: UInt64

    init() {
        collatorID = _nextCollatorID.next()
    }

    /// Takes the cached buffer set for this thread if it belongs to this
    /// collator. Returns nil on first call, ID mismatch, or re-entrant call.
    @inline(__always)
    func take() -> ScratchBuffers? {
        guard let raw = pthread_getspecific(_scratchTLSKey) else { return nil }
        let slot = raw.assumingMemoryBound(to: TLSSlot.self)
        guard slot.pointee.collatorID == collatorID else {
            // Stale buffer from a different collator — discard it.
            slot.pointee.buffers = nil
            return nil
        }
        let buffers = slot.pointee.buffers
        slot.pointee.buffers = nil
        return buffers
    }

    /// Stashes a buffer set back into the thread-local slot.
    @inline(__always)
    func give(_ buffers: ScratchBuffers) {
        if let raw = pthread_getspecific(_scratchTLSKey) {
            let slot = raw.assumingMemoryBound(to: TLSSlot.self)
            slot.pointee.collatorID = collatorID
            slot.pointee.buffers = buffers
        } else {
            let slot = UnsafeMutablePointer<TLSSlot>.allocate(capacity: 1)
            slot.initialize(to: TLSSlot(collatorID: collatorID, buffers: buffers))
            pthread_setspecific(_scratchTLSKey, UnsafeRawPointer(slot))
        }
    }
}

// MARK: - Fast-Latin Setup Cache

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
