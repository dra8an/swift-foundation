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

/// The data parsers copy each part of a file once, in bulk, and check every part they read against the file size. The copies must equal a byte-by-byte little-endian decode, and a cut file must throw, never read past its end.
@Suite struct DataParseTests {
    /// The compiled-in bytes of a bundled resource ("ucadata", "nfd", "tailorings/<name>").
    static func file(_ name: String) throws -> [UInt8] {
        [UInt8](try #require(collationResourceBytes(name), "\(name) is compiled in"))
    }

    /// A byte-by-byte decode, the reference for the bulk copies: the part `ix` of a "UCol" file as little-endian values of `width` bytes.
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

    @Test(arguments: ["ucadata", "nfd", "tailorings/ja"])
    func cutFilesThrow(name: String) throws {
        let file = try Self.file(name)
        let lengths: [Int]
        switch name {
        case "ucadata":
            // The data ends at indexes[19] (IX_TOTAL_SIZE); the file has padding after it, which the parser does not read.
            let headerSize = Int(file[0]) | (Int(file[1]) << 8)
            let dataEnd = headerSize + (Int(file[headerSize + 76]) | (Int(file[headerSize + 77]) << 8) | (Int(file[headerSize + 78]) << 16))
            #expect(dataEnd <= file.count)
            lengths = [0, 23, 100, file.count / 2, dataEnd - 300, dataEnd - 1]
        case "nfd":
            lengths = [0, 7, 100, file.count / 2, file.count - 1]
        default:
            lengths = [0, 23, 100, file.count / 2, file.count - 1]
        }
        for length in lengths {
            #expect(throws: (any Error).self, "\(name) cut to \(length) bytes") { try Self.parse(name, Array(file[..<length])) }
        }
    }

    /// The parser of each file of `cutFilesThrow`.
    static func parse(_ name: String, _ bytes: [UInt8]) throws {
        switch name {
        case "ucadata": _ = try CollationData(bytes: bytes)
        case "nfd": _ = try bytes.withUnsafeBytes { try NormalizationData(raw: $0) }
        default: _ = try CollationData.tailoring(bytes: bytes)
        }
    }
}
