// Read-only UTrie2 (32-bit values), parsed from its serialized form.
// Ported from ICU4C common/utrie2.h, utrie2_impl.h, utrie2.cpp.
//
// Serialized layout (little-endian on this platform):
//   UTrie2Header (16 bytes):
//     u32 signature        "Tri2" = 0x54726932
//     u16 options          bits 3..0 = valueBits (1 = 32-bit data)
//     u16 indexLength
//     u16 shiftedDataLength    dataLength >> 2
//     u16 index2NullOffset
//     u16 dataNullOffset
//     u16 shiftedHighStart     highStart >> 11
//   u16 index[indexLength]
//   u32 data[shiftedDataLength << 2]

struct UTrie2 {
    // Lookup constants (utrie2.h). SHIFT_1 = 11, SHIFT_2 = 5, INDEX_SHIFT = 2.
    private static let dataMask: UInt32 = 0x1f          // (1 << SHIFT_2) - 1
    private static let index2Mask: UInt32 = 0x3f        // (1 << (SHIFT_1 - SHIFT_2)) - 1
    // LSCP_INDEX_2_OFFSET (0x800) - (0xd800 >> SHIFT_2): index-2 block for
    // lead-surrogate code points D800..DBFF, stored after the regular BMP index.
    private static let lscpAdjustedOffset: UInt32 = 0x800 - (0xd800 >> 5)  // 0x140
    // INDEX_1_OFFSET (0x840) - OMITTED_BMP_INDEX_1_LENGTH (0x20)
    private static let index1AdjustedOffset: UInt32 = 0x820
    private static let badUTF8DataOffset = 0x80

    let index: [UInt16]
    let data: [UInt32]
    let highStart: UInt32
    let highValueIndex: Int

    enum ParseError: Error {
        case tooShort
        case badSignature(UInt32)
        case unexpectedValueWidth
    }

    /// Parses a serialized 32-bit UTrie2 from `bytes` starting at `offset`,
    /// spanning at most `length` bytes.
    init(bytes: [UInt8], offset: Int, length: Int) throws {
        guard length >= 16 else { throw ParseError.tooShort }
        func u16(_ at: Int) -> UInt16 {
            UInt16(bytes[offset + at]) | (UInt16(bytes[offset + at + 1]) << 8)
        }
        let signature = UInt32(u16(0)) | (UInt32(u16(2)) << 16)
        guard signature == 0x54726932 else { throw ParseError.badSignature(signature) }
        guard (u16(4) & 0xf) == 1 else { throw ParseError.unexpectedValueWidth }  // 32-bit values
        let indexLength = Int(u16(6))
        let dataLength = Int(u16(8)) << 2
        highStart = UInt32(u16(14)) << 11
        highValueIndex = dataLength - 4  // UTRIE2_DATA_GRANULARITY

        let indexStart = offset + 16
        let dataStart = indexStart + indexLength * 2
        guard length >= 16 + indexLength * 2 + dataLength * 4 else { throw ParseError.tooShort }

        var index = [UInt16](repeating: 0, count: indexLength)
        for i in 0..<indexLength {
            index[i] = UInt16(bytes[indexStart + i * 2]) | (UInt16(bytes[indexStart + i * 2 + 1]) << 8)
        }
        self.index = index

        var data = [UInt32](repeating: 0, count: dataLength)
        for i in 0..<dataLength {
            let b = dataStart + i * 4
            data[i] = UInt32(bytes[b]) | (UInt32(bytes[b + 1]) << 8)
                | (UInt32(bytes[b + 2]) << 16) | (UInt32(bytes[b + 3]) << 24)
        }
        self.data = data
    }

    /// Value for code point `c` (0..0x10FFFF). Ported from UTRIE2_GET32 / _UTRIE2_INDEX_FROM_CP.
    @inline(__always)
    func get(_ c: UInt32) -> UInt32 {
        if c < 0xd800 {
            return data[(Int(index[Int(c >> 5)]) << 2) + Int(c & Self.dataMask)]
        } else if c <= 0xffff {
            // Lead-surrogate code points use a separate index-2 block.
            let i2 = c <= 0xdbff ? Self.lscpAdjustedOffset + (c >> 5) : c >> 5
            return data[(Int(index[Int(i2)]) << 2) + Int(c & Self.dataMask)]
        } else if c <= 0x10ffff {
            if c >= highStart {
                return data[highValueIndex]
            }
            let i1 = Int(Self.index1AdjustedOffset + (c >> 11))
            let i2 = Int(index[i1]) + Int((c >> 5) & Self.index2Mask)
            return data[(Int(index[i2]) << 2) + Int(c & Self.dataMask)]
        }
        return data[Self.badUTF8DataOffset]  // error value; unreachable for valid scalars
    }
}
