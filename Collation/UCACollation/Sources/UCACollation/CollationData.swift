// Parser for the binary collation data format ("UCol" v5, ucadata.icu),
// ported from ICU4C i18n/collationdatareader.h/.cpp.
//
// File layout:
//   UDataHeader:
//     u16 headerSize
//     u8  magic1 (0xda), u8 magic2 (0x27)
//     UDataInfo: u16 size, u16 reserved, u8 isBigEndian, u8 charsetFamily,
//                u8 sizeofUChar, u8 reserved, u8 dataFormat[4] ("UCol"),
//                u8 formatVersion[4], u8 dataVersion[4]
//     ... padded to headerSize
//   int32 indexes[indexes[0]]   -- all part offsets are byte offsets relative
//                                  to the start of the indexes array; part i
//                                  spans [indexes[i], indexes[i+1]).
//   data parts (trie, ces, ce32s, contexts, ...)

import Foundation

public struct CollationData: Sendable {
    // indexes[] slots (CollationDataReader::IX_*).
    private enum IX {
        static let indexesLength = 0
        static let options = 1
        static let jamoCE32sStart = 4
        static let reorderCodesOffset = 5
        static let trieOffset = 7
        static let cesOffset = 9
        static let ce32sOffset = 11
        static let rootElementsOffset = 12
        static let contextsOffset = 13
        static let unsafeBwdOffset = 14
    }

    let trie: UTrie2
    let ce32s: [UInt32]
    let ces: [Int64]
    let contexts: [UInt16]
    /// Start of the 67 Hangul Jamo CE32s within ce32s, or < 0 if none.
    let jamoCE32sStart: Int
    /// Single-byte primary `xx000000` used for numeric collation.
    let numericPrimary: UInt32

    public enum ParseError: Error {
        case tooShort
        case badMagic
        case notUColFormat
        case unsupportedFormatVersion(UInt8)
        case bigEndianData
        case missingPart(String)
    }

    public init(contentsOf url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))
        try self.init(bytes: bytes)
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= 24 else { throw ParseError.tooShort }
        guard bytes[2] == 0xda && bytes[3] == 0x27 else { throw ParseError.badMagic }
        guard bytes[8] == 0 else { throw ParseError.bigEndianData }
        // dataFormat "UCol"
        guard bytes[12] == 0x55, bytes[13] == 0x43, bytes[14] == 0x6f, bytes[15] == 0x6c else {
            throw ParseError.notUColFormat
        }
        guard bytes[16] == 5 else { throw ParseError.unsupportedFormatVersion(bytes[16]) }

        let headerSize = Int(bytes[0]) | (Int(bytes[1]) << 8)
        guard bytes.count >= headerSize + 8 else { throw ParseError.tooShort }

        func i32(_ byteOffset: Int) -> Int32 {
            let b = headerSize + byteOffset
            return Int32(bytes[b]) | (Int32(bytes[b + 1]) << 8)
                | (Int32(bytes[b + 2]) << 16) | (Int32(bytes[b + 3]) << 24)
        }

        let indexesLength = Int(i32(0))
        guard indexesLength >= IX.contextsOffset + 2,
              bytes.count >= headerSize + indexesLength * 4
        else { throw ParseError.tooShort }

        var indexes = [Int32](repeating: 0, count: indexesLength)
        for i in 0..<indexesLength { indexes[i] = i32(i * 4) }

        func part(_ ix: Int) -> (offset: Int, length: Int) {
            (Int(indexes[ix]), Int(indexes[ix + 1] - indexes[ix]))
        }

        numericPrimary = UInt32(bitPattern: indexes[IX.options]) & 0xff00_0000
        jamoCE32sStart = Int(indexes[IX.jamoCE32sStart])

        let (trieOffset, trieLength) = part(IX.trieOffset)
        guard trieLength >= 8 else { throw ParseError.missingPart("trie") }
        trie = try UTrie2(bytes: bytes, offset: headerSize + trieOffset, length: trieLength)

        let (cesOffset, cesLength) = part(IX.cesOffset)
        var ces = [Int64](repeating: 0, count: max(0, cesLength / 8))
        for i in 0..<ces.count {
            let b = headerSize + cesOffset + i * 8
            var v: UInt64 = 0
            for j in 0..<8 { v |= UInt64(bytes[b + j]) << (8 * j) }
            ces[i] = Int64(bitPattern: v)
        }
        self.ces = ces

        let (ce32sOffset, ce32sLength) = part(IX.ce32sOffset)
        var ce32s = [UInt32](repeating: 0, count: max(0, ce32sLength / 4))
        for i in 0..<ce32s.count {
            let b = headerSize + ce32sOffset + i * 4
            ce32s[i] = UInt32(bytes[b]) | (UInt32(bytes[b + 1]) << 8)
                | (UInt32(bytes[b + 2]) << 16) | (UInt32(bytes[b + 3]) << 24)
        }
        self.ce32s = ce32s

        let (contextsOffset, contextsLength) = part(IX.contextsOffset)
        var contexts = [UInt16](repeating: 0, count: max(0, contextsLength / 2))
        for i in 0..<contexts.count {
            let b = headerSize + contextsOffset + i * 2
            contexts[i] = UInt16(bytes[b]) | (UInt16(bytes[b + 1]) << 8)
        }
        self.contexts = contexts
    }

    /// Reads a CE32 stored as two big-endian-ordered 16-bit units in contexts[].
    /// (CollationData::readCE32.)
    @inline(__always)
    func readContextCE32(at index: Int) -> UInt32 {
        (UInt32(contexts[index]) << 16) | UInt32(contexts[index + 1])
    }

    /// The bundled CLDR root collation data (ucadata.icu, ICU 79 / "UCol" v5).
    public static func root() throws -> CollationData {
        guard let url = Bundle.module.url(forResource: "ucadata", withExtension: "icu") else {
            throw ParseError.missingPart("bundled ucadata.icu")
        }
        return try CollationData(contentsOf: url)
    }
}
