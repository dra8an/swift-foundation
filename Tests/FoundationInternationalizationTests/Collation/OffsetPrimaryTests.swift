import Testing
@testable import FoundationInternationalization

/// `CollationConstants.incThreeBytePrimaryByOffset` uses unsigned arithmetic since technique log §51 (bb). These tests check it against the signed original of ICU's Collation::incThreeBytePrimaryByOffset over the inputs that the data can produce: every third byte, the edges of the second byte, both compressibility settings, and offsets from 0.
@Suite struct OffsetPrimaryTests {
    /// The signed original, as ported before §51 (bb).
    private static func reference(_ basePrimary: UInt32, _ isCompressible: Bool, _ offset: Int32) -> UInt32 {
        var offset = offset + (Int32(bitPattern: basePrimary >> 8) & 0xff) - 2
        var primary = UInt32(bitPattern: (offset % 254) + 2) << 8
        offset /= 254
        if isCompressible {
            offset += (Int32(bitPattern: basePrimary >> 16) & 0xff) - 4
            primary |= UInt32(bitPattern: (offset % 251) + 4) << 16
            offset /= 251
        } else {
            offset += (Int32(bitPattern: basePrimary >> 16) & 0xff) - 2
            primary |= UInt32(bitPattern: (offset % 254) + 2) << 16
            offset /= 254
        }
        return primary | ((basePrimary & 0xff00_0000) &+ UInt32(bitPattern: offset << 24))
    }

    @Test func smallOffsetsOverEveryThirdByte() {
        var mismatches: [(UInt32, Bool, Int32)] = []
        for lead: UInt32 in [0x7a, 0xe2, 0xfb] {
            for second: UInt32 in [2, 3, 4, 5, 0x80, 250, 251, 253, 254] {
                for third: UInt32 in 2...255 {
                    let base = (lead << 24) | (second << 16) | (third << 8)
                    for compressible in [false, true] where !(compressible && second < 4) {
                        for offset: Int32 in 0..<1024 where CollationConstants.incThreeBytePrimaryByOffset(base, compressible, offset) != Self.reference(base, compressible, offset) {
                            mismatches.append((base, compressible, offset))
                        }
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "first mismatches: \(mismatches.prefix(5))")
    }

    @Test func largeOffsets() {
        var mismatches: [(UInt32, Bool, Int32)] = []
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200_000 {
            let second = UInt32.random(in: 4...254, using: &generator)
            let third = UInt32.random(in: 2...255, using: &generator)
            let base = (UInt32(0xe2) << 24) | (second << 16) | (third << 8)
            let compressible = Bool.random(using: &generator)
            // OFFSET ranges cover at most a few tens of thousands of code points, with steps up to 0x7f.
            let offset = Int32.random(in: 0...(0x30000 * 0x7f), using: &generator)
            if CollationConstants.incThreeBytePrimaryByOffset(base, compressible, offset) != Self.reference(base, compressible, offset) {
                mismatches.append((base, compressible, offset))
            }
        }
        #expect(mismatches.isEmpty, "first mismatches: \(mismatches.prefix(5))")
    }
}
