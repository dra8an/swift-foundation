//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Owner of the immutable memory behind CollationData / NormalizationData.
//
// The data structs hold UnsafeBufferPointer views into this storage plus one reference to it, which makes copying them trivial (a single retain instead of one per internal array — the CE iterator copies its data struct on every lookup, so this is hot), and buffer reads are unchecked in release builds. Safety model: the views never outlive the owning struct, all offsets are validated at parse time, and the bundled data files are version-pinned and exercised by the conformance suites — the same trust ICU4C places in its own memory-mapped arrays. `Span` cannot replace the views: it is non-escapable, so a stored property of these structs cannot hold it, and the structs live as long as their collator.

// @unchecked Sendable: the memory is allocated and written only while the data is parsed, before the value is shared, and never changed afterwards; it is freed in deinit, when no view can exist any more. This class is the one owner of the raw memory; manually allocated memory has no Sendable alternative, so no migration is planned.
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
            guard let base = source.baseAddress else { return }  // empty input: nothing to copy
            typed.update(from: base, count: source.count)
        }
        return UnsafeBufferPointer(start: typed, count: values.count)
    }

    /// Copies `count` little-endian values of `T` from `raw`, starting at `byteOffset`, into freshly allocated storage owned by this object and returns a view of it: one bulk copy of a part of a data file (a per-value loop on a big-endian host). The caller checks that the bytes are inside `raw`.
    func storeLittleEndian<T: FixedWidthInteger>(
        _ raw: UnsafeRawBufferPointer, at byteOffset: Int, count: Int, as type: T.Type
    ) -> UnsafeBufferPointer<T> {
        guard count > 0, let source = raw.baseAddress else { return UnsafeBufferPointer(start: nil, count: 0) }
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: count * MemoryLayout<T>.stride,
            alignment: MemoryLayout<T>.alignment)
        allocations.append(memory)
        #if _endian(little)
        memory.copyMemory(from: source + byteOffset, byteCount: count * MemoryLayout<T>.size)
        let typed = memory.bindMemory(to: T.self, capacity: count)
        #else
        let typed = memory.bindMemory(to: T.self, capacity: count)
        for i in 0..<count {
            typed[i] = T(littleEndian: raw.loadUnaligned(fromByteOffset: byteOffset + i * MemoryLayout<T>.size, as: T.self))
        }
        #endif
        return UnsafeBufferPointer(start: typed, count: count)
    }

    deinit {
        for allocation in allocations { allocation.deallocate() }
    }
}
