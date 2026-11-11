// A stand-in for FoundationEssentials' LockedState (package API) for the bench tools, which build
// the engine sources in a package of their own, without FoundationEssentials. Darwin only, like the tools;
// the same API as far as the engine uses it: init(initialState:), withLock, withLockUnchecked.
import os

struct LockedState<State> {
    private final class Storage {
        var state: State
        let lock: UnsafeMutablePointer<os_unfair_lock>
        init(_ state: State) {
            self.state = state
            lock = .allocate(capacity: 1)
            lock.initialize(to: os_unfair_lock())
        }
        deinit {
            lock.deinitialize(count: 1)
            lock.deallocate()
        }
    }

    private let storage: Storage

    init(initialState: State) {
        storage = Storage(initialState)
    }

    func withLock<T>(_ body: @Sendable (inout State) throws -> T) rethrows -> T {
        try withLockUnchecked(body)
    }

    func withLockUnchecked<T>(_ body: (inout State) throws -> T) rethrows -> T {
        os_unfair_lock_lock(storage.lock)
        defer { os_unfair_lock_unlock(storage.lock) }
        return try body(&storage.state)
    }
}

extension LockedState: @unchecked Sendable where State: Sendable {}
