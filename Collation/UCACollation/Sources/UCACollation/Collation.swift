// Constants and bit-layout helpers for collation elements,
// ported from ICU4C i18n/collation.h and collation.cpp (ICU 79, data format "UCol" v5).
//
// A CE32 is a 32-bit encoding of one (or more) collation elements.
// Simple CE32 (low byte < 0xc0): ppppsstt = 16-bit primary, 8-bit secondary, 8-bit tertiary.
// Special CE32 (low byte >= 0xc0): bits 3..0 hold a tag; layout of the rest depends on the tag.

enum Collation {
    // MARK: Special CE32 tags (collation.h)

    static let specialCE32LowByte: UInt32 = 0xc0
    static let fallbackCE32: UInt32 = 0xc0  // specialCE32LowByte | fallbackTag

    enum Tag: UInt32 {
        case fallback = 0
        case longPrimary = 1
        case longSecondary = 2
        case reserved3 = 3
        case latinExpansion = 4
        case expansion32 = 5
        case expansion = 6
        case builderData = 7
        case prefix = 8
        case contraction = 9
        case digit = 10
        case u0000 = 11
        case hangul = 12
        case leadSurrogate = 13
        case offset = 14
        case implicit = 15
    }

    @inline(__always)
    static func isSpecialCE32(_ ce32: UInt32) -> Bool {
        (ce32 & 0xff) >= specialCE32LowByte
    }

    @inline(__always)
    static func tagFromCE32(_ ce32: UInt32) -> Tag {
        Tag(rawValue: ce32 & 0xf)!
    }

    /// 19-bit index from a special CE32 with index and length fields (bits 31..13).
    @inline(__always)
    static func indexFromCE32(_ ce32: UInt32) -> Int {
        Int(ce32 >> 13)
    }

    /// 5-bit length from a special CE32 (bits 12..8).
    @inline(__always)
    static func lengthFromCE32(_ ce32: UInt32) -> Int {
        Int((ce32 >> 8) & 0x1f)
    }

    // MARK: Primary weight extraction

    /// Primary weight (left-justified in 32 bits) of a simple CE32 `ppppsstt`.
    @inline(__always)
    static func primaryFromSimpleCE32(_ ce32: UInt32) -> UInt32 {
        ce32 & 0xffff_0000
    }

    /// Primary weight of a LONG_PRIMARY special CE32 `ppppppC1`.
    @inline(__always)
    static func primaryFromLongPrimaryCE32(_ ce32: UInt32) -> UInt32 {
        ce32 & 0xffff_ff00
    }

    /// Primary weight of the first CE of a LATIN_EXPANSION CE32 (bits 31..24 = pp).
    /// The second CE of a Latin expansion is always primary-ignorable.
    @inline(__always)
    static func latinExpansionFirstPrimary(_ ce32: UInt32) -> UInt32 {
        ce32 & 0xff00_0000
    }

    /// Primary weight of a 64-bit CE (upper 32 bits).
    @inline(__always)
    static func primaryFromCE(_ ce: Int64) -> UInt32 {
        UInt32(truncatingIfNeeded: ce >> 32)
    }

    // MARK: Computed primaries (collation.cpp)

    static let unassignedImplicitByte: UInt32 = 0xfe

    /// Primary weight for an unassigned code point (IMPLICIT tag).
    /// Ported from Collation::unassignedPrimaryFromCodePoint().
    static func unassignedPrimaryFromCodePoint(_ c: UInt32) -> UInt32 {
        // Create a gap before U+0000. (ICU also uses c = -1 for [first unassigned].)
        var c = Int32(bitPattern: c) + 1
        // Fourth byte: 18 values, every 14th byte value (gap of 13).
        var primary = UInt32(2 + (c % 18) * 14)
        c /= 18
        // Third byte: 254 values.
        primary |= UInt32(2 + (c % 254)) << 8
        c /= 254
        // Second byte: 251 values 04..FE excluding the primary compression bytes.
        primary |= UInt32(4 + (c % 251)) << 16
        // One lead byte covers all code points (c < 0x1182B4 = 1*251*254*18).
        return primary | (unassignedImplicitByte << 24)
    }

    /// Primary weight for an OFFSET-tag code point.
    /// `dataCE` upper 32 bits: three-byte primary pppppp00.
    /// Lower 32 bits: base code point (bits 31..8), isCompressible (bit 7), step (bits 6..0).
    /// Ported from Collation::getThreeBytePrimaryForOffsetData().
    static func threeBytePrimaryForOffsetData(_ c: UInt32, _ dataCE: Int64) -> UInt32 {
        let p = UInt32(truncatingIfNeeded: dataCE >> 32)
        let lower32 = Int32(truncatingIfNeeded: dataCE)
        let offset = (Int32(bitPattern: c) - (lower32 >> 8)) * (lower32 & 0x7f)
        let isCompressible = (lower32 & 0x80) != 0
        return incThreeBytePrimaryByOffset(p, isCompressible, offset)
    }

    /// Ported from Collation::incThreeBytePrimaryByOffset().
    static func incThreeBytePrimaryByOffset(
        _ basePrimary: UInt32, _ isCompressible: Bool, _ offset: Int32
    ) -> UInt32 {
        // Extract the third byte, minus the minimum byte value,
        // plus the offset, modulo the number of usable byte values, plus the minimum.
        var offset = offset + (Int32(bitPattern: basePrimary >> 8) & 0xff) - 2
        var primary = UInt32(bitPattern: (offset % 254) + 2) << 8
        offset /= 254
        // Same with the second byte,
        // but reserve the PRIMARY_COMPRESSION_LOW_BYTE and high byte if necessary.
        if isCompressible {
            offset += (Int32(bitPattern: basePrimary >> 16) & 0xff) - 4
            primary |= UInt32(bitPattern: (offset % 251) + 4) << 16
            offset /= 251
        } else {
            offset += (Int32(bitPattern: basePrimary >> 16) & 0xff) - 2
            primary |= UInt32(bitPattern: (offset % 254) + 2) << 16
            offset /= 254
        }
        // First byte, assume no further overflow.
        return primary | ((basePrimary & 0xff00_0000) &+ UInt32(bitPattern: offset << 24))
    }
}
