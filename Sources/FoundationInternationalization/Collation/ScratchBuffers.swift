// Reusable per-call buffers. Building the CE and NFD iterators afresh costs several heap allocations per compare()/sortKey() call; a RootCollator instead keeps a thread-local buffer set and resets it, so repeated calls run allocation-free once the buffers have grown to the working size. (ICU4C reaches the same goal with stack buffers, which Swift arrays cannot express.) The public API stays thread-safe: each thread owns its own buffer set, with no locking or reference counting on the checkout path.

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Minimal mutual exclusion: os_unfair_lock on Darwin (a few ns uncontended, vs NSLock's objc dispatch), NSLock elsewhere. The unfair lock must live at a stable address, hence the allocation.
struct PoolLock {
    #if canImport(Darwin)
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }
    func deallocate() { lock.deinitialize(count: 1); lock.deallocate() }
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

    /// The search family's buffers, bundled into ONE stored property.
    ///
    /// Each of these was a separate stored property, and each mutating access to a stored property of a class opens a dynamically-enforced access scope — so an entry that touched three of them paid three `swift_beginAccess`/`endAccess` pairs on top of the one for `left` (search 5, searchBackwards 5, contains 4, measured in the object). Fusing the calls cannot merge those, because they are DIFFERENT properties; bundling can. One `inout` of this struct costs one scope, and reaching its fields from inside is statically enforced, hence free.
    ///
    /// This is more §37-aligned, not less: that rule's cost was three separate `inout` parameters at an entry whose byte-scan fast path never touched them. The bundle is one parameter, still passed only after the byte scan bails.
    struct SearchBuffers {
        /// Masked pattern CEs (rebuilt per call, allocation-free).
        var patternCEs: [Int64] = []
        /// The annotated text-CE window (forward) / full text CEs (backward). The per-call allocation of this array was once the largest single cost of CJK searches.
        var annotatedCEs: [AnnotatedCE] = []
        /// contains: masked text CEs.
        var maskedTextCEs: [Int64] = []
        /// NFD-position → source-scalar-index map, built lazily by confirmMatch only for a full CE match on decomposing text. Its per-call allocation (plus per-scalar temporaries) was ~half the cost of every matching search on accented text.
        var nfdSourceMap: [Int] = []
    }

    var search = SearchBuffers()

    init(data: CollationData, base: CollationData?, norm: NormalizationData,
         simpleCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         thaiCEs: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         simpleCEsWithDigits: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0),
         thaiCEsWithDigits: UnsafeBufferPointer<Int64> = .init(start: nil, count: 0)) {
        let empty = "".unicodeScalars
        self.left = CEIterator(data: data, base: base, norm: norm, numeric: false, scalars: empty, simpleCEs: simpleCEs, thaiCEs: thaiCEs, simpleCEsWithDigits: simpleCEsWithDigits, thaiCEsWithDigits: thaiCEsWithDigits)
        self.right = CEIterator(data: data, base: base, norm: norm, numeric: false, scalars: empty, simpleCEs: simpleCEs, thaiCEs: thaiCEs, simpleCEsWithDigits: simpleCEsWithDigits, thaiCEsWithDigits: thaiCEsWithDigits)
    }

    /// Resets `left` onto `scalars` and produces all its CEs under ONE dynamic access scope.
    ///
    /// `left` is a stored property of a class, so each mutating access to it opens a dynamically-enforced access scope — a real `swift_beginAccess`/`swift_endAccess` pair. Written as two statements (`left.reset(…)` then `left.collectAll()`) that is two pairs, because the optimizer's access merging gives up across a throwing call: `collectAll` throws, so the pairs stay split (visible in the shipping object as two scopes on `+0x10`, one around the out-of-line `reset` and one around the whole inlined `collectAll` loop).
    ///
    /// Routing both through a single `inout` argument opens the scope once at that argument and closes it on return. Merely moving the two statements into a method here does NOT help — the throwing call still splits them, measured.
    ///
    /// This is not the §37 anti-pattern: that rule is about `inout` parameters on an entry whose common case bails before touching them, so the caller pays the scope ahead of the bail. `sortKey` has no fast path — it always produces CEs — so the scope is opened exactly where the work happens.
    @inline(__always)
    func resetAndCollectLeft(numeric: Bool, scalars: String.UnicodeScalarView) throws {
        try ScratchBuffers.resetAndCollect(&left, numeric: numeric, scalars: scalars)
    }

    @inline(__always)
    private static func resetAndCollect(
        _ iter: inout CEIterator, numeric: Bool, scalars: String.UnicodeScalarView
    ) throws {
        iter.reset(numeric: numeric, scalars: scalars)
        _ = try iter.collectAll()
    }

    /// Resets both iterators and runs the comparison under TWO access scopes instead of four.
    ///
    /// The pipeline path used to touch `left`/`right` three times each in source order — reset, reset, then the two `inout` arguments of `compareUpToQuaternary` — which is four dynamic scopes per compare (confirmed in the object: two around the out-of-line resets, then two NESTED around the single call). Routing everything through one static helper opens one scope per iterator, at the arguments, covering the resets AND the comparison.
    ///
    /// Two overloads rather than one with a mode flag or closure: the skip-walk path hands over already-positioned iterators, and a closure at this call site is the §33 shape that costs paths sortKey +8%. Both are called only from inside the pipeline branch, i.e. after the fast-Latin bail, so §37's rule about paying scopes ahead of a bail does not apply.
    @inline(__always)
    func resetBothAndCompare(
        numeric: Bool,
        leftScalars: String.UnicodeScalarView, rightScalars: String.UnicodeScalarView,
        options: Int32, variableTopValue: UInt32, reordering: Reordering?
    ) throws -> Int {
        try ScratchBuffers.resetBothAndCompare(
            &left, &right, options: options, variableTopValue: variableTopValue,
            reordering: reordering
        ) { l, r in
            l.reset(numeric: numeric, scalars: leftScalars)
            r.reset(numeric: numeric, scalars: rightScalars)
        }
    }

    @inline(__always)
    func resetBothAndCompare(
        numeric: Bool,
        leftSource: String.UnicodeScalarView.Iterator, leftFirst: UInt32?,
        rightSource: String.UnicodeScalarView.Iterator, rightFirst: UInt32?,
        options: Int32, variableTopValue: UInt32, reordering: Reordering?
    ) throws -> Int {
        try ScratchBuffers.resetBothAndCompare(
            &left, &right, options: options, variableTopValue: variableTopValue,
            reordering: reordering
        ) { l, r in
            l.reset(numeric: numeric, source: leftSource, first: leftFirst)
            r.reset(numeric: numeric, source: rightSource, first: rightFirst)
        }
    }

    /// The scopes are opened at `l`/`r` here and cover both the reset and the comparison. `reset` is a non-escaping closure that is always inlined into the caller, so no closure survives at the call site.
    @inline(__always)
    private static func resetBothAndCompare(
        _ l: inout CEIterator, _ r: inout CEIterator,
        options: Int32, variableTopValue: UInt32, reordering: Reordering?,
        reset: (inout CEIterator, inout CEIterator) -> Void
    ) throws -> Int {
        reset(&l, &r)
        return try CollationCompare.compareUpToQuaternary(
            &l, &r, options: options, variableTopValue: variableTopValue,
            reordering: reordering)
    }

    /// Runs the whole identical level under two access scopes instead of two PER SCALAR.
    ///
    /// The drain loop calls `next()` on each side's NFD iterator, and each of those was a mutating access to a stored property of this class — so the loop paid a `swift_beginAccess`/`endAccess` pair per side per scalar, the densest exclusivity concentration in the engine. Hoisting the loop behind one `inout` per iterator opens the scopes once for the entire drain.
    @inline(__always)
    func compareIdenticalLevel(
        left: String.UnicodeScalarView, right: String.UnicodeScalarView, skippingFirst shared: Int
    ) -> RootCollator.Order {
        ScratchBuffers.compareIdenticalLevel(
            &self.left, &self.right, left: left, right: right, skippingFirst: shared)
    }

    @inline(__always)
    private static func compareIdenticalLevel(
        _ l: inout CEIterator, _ r: inout CEIterator,
        left: String.UnicodeScalarView, right: String.UnicodeScalarView, skippingFirst shared: Int
    ) -> RootCollator.Order {
        // ICU also runs the identical level from the skip position.
        l.scalars.reset(scalars: left, skippingFirst: shared)
        r.scalars.reset(scalars: right, skippingFirst: shared)
        while true {
            let lc = l.scalars.next()
            let rc = r.scalars.next()
            if lc != rc {
                return identicalRank(lc) < identicalRank(rc) ? .ascending : .descending
            }
            if lc == nil { return .same }
        }
    }

    /// End-of-string sorts below U+FFFE (the merge separator), which sorts below all code points. (compareNFDIter: end = -2, U+FFFE = -1.)
    @inline(__always)
    private static func identicalRank(_ c: UInt32?) -> Int64 {
        guard let c else { return -2 }
        return c == 0xfffe ? -1 : Int64(c)
    }

    /// Drains the NFD scalars for the sort key's identical level into `nfdScalars` under two access scopes instead of two per scalar (`left` for `next()`, `nfdScalars` for `append`).
    @inline(__always)
    func collectNFDScalars(scalars view: String.UnicodeScalarView) {
        ScratchBuffers.collectNFDScalars(&left, into: &nfdScalars, scalars: view)
    }

    @inline(__always)
    private static func collectNFDScalars(
        _ iter: inout CEIterator, into out: inout [UInt32], scalars view: String.UnicodeScalarView
    ) {
        iter.scalars.reset(scalars: view)
        // isEmpty guard: removeAll on a never-used array hits the shared empty-singleton storage and takes the copy-on-write slow path.
        if !out.isEmpty { out.removeAll(keepingCapacity: true) }
        while let c = iter.scalars.next() { out.append(c) }
    }
}

/// Thread-local scratch buffer stash. Each thread caches one ScratchBuffers instance, avoiding all locking, exclusivity checks, and ARC traffic on the take/give path. If a thread re-enters (e.g. compare inside compare, which doesn't happen in practice but is sound), `take()` returns nil and the caller allocates a fresh set.
///
/// Implementation: a single pthread_key_t holds an UnsafeMutablePointer to a `ThreadLocalSlot` (which wraps the optional ScratchBuffers). The key's destructor frees the slot on thread exit.
final class ThreadLocalScratch: @unchecked Sendable {
    /// The slot stored in thread-local storage. Wrapping in a struct stored via UnsafeMutablePointer avoids ARC on the TLS read path entirely.
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
        // Note: any thread-local slots still alive at this point will be cleaned up by their thread's exit destructor. We just destroy the key itself.
        pthread_key_delete(key)
    }

    /// Takes the cached buffer set for this thread, or nil if none is stashed (first call on this thread, or re-entrant call).
    @inline(__always)
    func take() -> ScratchBuffers? {
        guard let raw = pthread_getspecific(key) else { return nil }
        let slot = raw.assumingMemoryBound(to: Slot.self)
        let buffers = slot.pointee.buffers
        slot.pointee.buffers = nil
        return buffers
    }

    /// Stashes a buffer set back into the thread-local slot. If the slot doesn't exist yet (first give on this thread), creates it.
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

/// One immutable fast-Latin setup: the precomputed primaries and packed options for one options word (packedOptions < 0 = unsupported).
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

/// Holds the most recently used fast-Latin setup, so bail-free compares need no scratch buffers at all. Snapshots are immutable: a reader keeps using its snapshot even if another thread replaces the current one.
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
