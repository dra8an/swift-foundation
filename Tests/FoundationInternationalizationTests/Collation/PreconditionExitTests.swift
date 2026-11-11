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

import Testing

#if canImport(FoundationEssentials)
@testable import FoundationEssentials
@testable import FoundationInternationalization
#elseif FOUNDATION_FRAMEWORK
@testable import Foundation
#endif

/// The engine's preconditions that a caller can reach: each must stop the process, with its own message. The others cannot be reached through the API: the default of a switch over all 16 values of a 4-bit tag, a trie node value that is 0 or 1 by its encoding, a private function whose callers keep its bound, an invalid scalar from the NFD iterator, and a key path that is always a stored property.
#if FOUNDATION_EXIT_TESTS
@Suite struct PreconditionExitTests {
    /// The standard error of the child process contains `message`.
    private static func reported(_ result: ExitTest.Result?, _ message: String) -> Bool {
        guard let result else { return false }
        return String(decoding: result.standardErrorContent, as: UTF8.self).contains(message)
    }

    @Test func ceBufferReadOutOfRange() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            var ces = CEBuffer()
            ces.append(1)
            _ = ces[1]
        }
        #expect(Self.reported(result, "CE index out of range"))
    }

    @Test func ceBufferWriteOutOfRange() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            var ces = CEBuffer()
            ces[0] = 1
        }
        #expect(Self.reported(result, "CE index out of range"))
    }

    /// A trie of one final value node: `first` finds no unit after it and stops the trie, so there is no value to read.
    @Test func trieValueWithoutAValueResult() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let units: [UInt16] = [0x8000]
            units.withUnsafeBufferPointer { buffer in
                var trie = UCharsTrie(units: buffer, offset: 0)
                _ = trie.first(0x61)
                _ = trie.getValue()
            }
        }
        #expect(Self.reported(result, "getValue() requires a preceding result with hasValue"))
    }

    /// A tailoring has no compressible-byte table of its own and takes the root's; used as root data, without a base, it has none.
    @Test func tailoringDataWithoutItsBase() async throws {
        let data = try #require(try CollationData.bundledTailoring(named: "sv").data)
        try #require(data.compressibleBytes.isEmpty)
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            guard let data = try? CollationData.bundledTailoring(named: "sv").data, let norm = try? NormalizationData.standard() else { return }
            _ = RootCollator(data: data, norm: norm)
        }
        #expect(Self.reported(result, "collation data has neither its own compressible-byte table nor a base to inherit one from"))
    }
}
#endif
