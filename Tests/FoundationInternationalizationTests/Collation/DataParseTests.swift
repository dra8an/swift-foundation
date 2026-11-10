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
import Foundation
@testable import FoundationInternationalization

/// The data parsers copy each part of a file once, in bulk, and check every part they read against the file size (technique log §51, START HERE item 7). The copies must equal a byte-by-byte little-endian decode, and a cut file must throw, never read past its end.
@Suite struct DataParseTests {
    /// The compiled-in bytes of a bundled resource ("ucadata", "nfd", "tailorings/<name>").
    static func file(_ name: String) throws -> [UInt8] {
        [UInt8](try #require(collationResourceBytes(name), "\(name) is compiled in"))
    }

    /// The byte-by-byte decode of the old parser: the part `ix` of a "UCol" file as little-endian values of `width` bytes.
    static func decodedPart(_ bytes: [UInt8], _ ix: Int, width: Int) -> [UInt64] {
        let headerSize = Int(bytes[0]) | (Int(bytes[1]) << 8)
        func i32(_ at: Int) -> Int {
            let b = headerSize + at
            return Int(Int32(bitPattern: UInt32(bytes[b]) | (UInt32(bytes[b + 1]) << 8) | (UInt32(bytes[b + 2]) << 16) | (UInt32(bytes[b + 3]) << 24)))
        }
        let start = headerSize + i32(ix * 4)
        let count = (i32((ix + 1) * 4) - i32(ix * 4)) / width
        return (0..<count).map { i in
            var v: UInt64 = 0
            for j in 0..<width { v |= UInt64(bytes[start + i * width + j]) << (8 * j) }
            return v
        }
    }

    @Test func rootPartsEqualTheByteDecode() throws {
        let bytes = try Self.file("ucadata")
        let data = try CollationData(bytes: bytes)
        #expect(data.ces.map { UInt64(bitPattern: $0) } == Self.decodedPart(bytes, 9, width: 8))
        #expect(data.ce32s.map { UInt64($0) } == Self.decodedPart(bytes, 11, width: 4))
        #expect(data.contexts.map { UInt64($0) } == Self.decodedPart(bytes, 13, width: 2))
        #expect(data.fastLatinTable.map { UInt64($0) } == Self.decodedPart(bytes, 15, width: 2))
        // The trie part: a 16-byte header, then u16 index[indexLength], then u32 data.
        let trie = Self.decodedPart(bytes, 7, width: 2)
        let indexLength = Int(trie[3])
        #expect(data.trie.index.map { UInt64($0) } == Array(trie[8..<(8 + indexLength)]))
        let dataWords = (8 + indexLength)..<(8 + indexLength + 2 * data.trie.data.count)
        let decodedData = stride(from: dataWords.lowerBound, to: dataWords.upperBound, by: 2).map { trie[$0] | (trie[$0 + 1] << 16) }
        #expect(data.trie.data.map { UInt64($0) } == decodedData)
    }

    @Test func cutFilesThrow() throws {
        let uca = try Self.file("ucadata")
        // The data ends at indexes[19] (IX_TOTAL_SIZE); the file has padding after it, which the parser does not read.
        let headerSize = Int(uca[0]) | (Int(uca[1]) << 8)
        let dataEnd = headerSize + (Int(uca[headerSize + 76]) | (Int(uca[headerSize + 77]) << 8) | (Int(uca[headerSize + 78]) << 16))
        #expect(dataEnd <= uca.count)
        for length in [0, 23, 100, uca.count / 2, dataEnd - 300, dataEnd - 1] {
            #expect(throws: (any Error).self, "ucadata cut to \(length) bytes") { try CollationData(bytes: Array(uca[..<length])) }
        }
        let nfd = try Self.file("nfd")
        for length in [0, 7, 100, nfd.count / 2, nfd.count - 1] {
            #expect(throws: (any Error).self, "nfd.bin cut to \(length) bytes") {
                try Array(nfd[..<length]).withUnsafeBytes { try NormalizationData(raw: $0) }
            }
        }
        let ja = try Self.file("tailorings/ja")
        for length in [0, 23, 100, ja.count / 2, ja.count - 1] {
            #expect(throws: (any Error).self, "ja.bin cut to \(length) bytes") { try CollationData.tailoring(bytes: Array(ja[..<length])) }
        }
    }
}
