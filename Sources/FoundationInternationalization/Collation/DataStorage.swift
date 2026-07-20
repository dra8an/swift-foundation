// Owner of the immutable memory behind CollationData / NormalizationData.
//
// The data structs hold UnsafeBufferPointer views into this storage plus one reference to it, which makes copying them trivial (a single retain instead of one per internal array — the CE iterator copies its data struct on every lookup, so this is hot), and buffer reads are unchecked in release builds. Safety model: the views never outlive the owning struct, all offsets are validated at parse time, and the bundled data files are version-pinned and exercised by the conformance suites — the same trust ICU4C places in its own memory-mapped arrays.

final class DataStorage: @unchecked Sendable {
    private var allocations: [UnsafeMutableRawPointer] = []

    /// Copies `values` into freshly allocated storage owned by this object and returns a view of it (empty input: a valid empty view, no allocation).
    func store<T>(_ values: [T]) -> UnsafeBufferPointer<T> {
        guard !values.isEmpty else { return UnsafeBufferPointer(start: nil, count: 0) }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: values.count * MemoryLayout<T>.stride,
            alignment: MemoryLayout<T>.alignment)
        allocations.append(raw)
        let typed = raw.bindMemory(to: T.self, capacity: values.count)
        values.withUnsafeBufferPointer { source in
            typed.update(from: source.baseAddress!, count: source.count)
        }
        return UnsafeBufferPointer(start: typed, count: values.count)
    }

    deinit {
        for allocation in allocations { allocation.deallocate() }
    }
}
