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

// @unchecked: the buffer views are immutable after init and their memory is
// owned by `storage`, which the struct retains.
public struct CollationData: @unchecked Sendable {
    // indexes[] slots (CollationDataReader::IX_*).
    private enum IX {
        static let indexesLength = 0
        static let options = 1
        static let jamoCE32sStart = 4
        static let reorderCodesOffset = 5
        static let reorderTableOffset = 6
        static let trieOffset = 7
        static let cesOffset = 9
        static let ce32sOffset = 11
        static let rootElementsOffset = 12
        static let contextsOffset = 13
        static let unsafeBwdOffset = 14
        static let fastLatinTableOffset = 15
        static let scriptsOffset = 16
        static let compressibleBytesOffset = 17
    }

    /// Owns the memory behind all the buffer views below; copying the struct
    /// costs one retain (the CE iterator copies it on every lookup).
    let storage: DataStorage
    let trie: UTrie2
    let ce32s: UnsafeBufferPointer<UInt32>
    let ces: UnsafeBufferPointer<Int64>
    let contexts: UnsafeBufferPointer<UInt16>
    /// Start of the 67 Hangul Jamo CE32s within ce32s, or < 0 if none.
    let jamoCE32sStart: Int
    /// Single-byte primary `xx000000` used for numeric collation.
    let numericPrimary: UInt32
    /// Script/reorder-group data: numScripts, then scriptsIndex[numScripts+16]
    /// mapping script and special reorder codes to scriptStarts entries, then
    /// scriptStarts (primary-weight high 16 bits per range).
    let numScripts: Int
    let scriptsIndex: UnsafeBufferPointer<UInt16>
    let scriptStarts: UnsafeBufferPointer<UInt16>
    /// Per-primary-lead-byte flags: compressible lead bytes allow primary
    /// compression in sort keys. 256 entries.
    let compressibleBytes: UnsafeBufferPointer<Bool>
    /// Unsafe-backward set from the data file, as a sorted boundary list:
    /// alternating range starts and limits; `c` is in the set iff the count
    /// of boundaries <= c is odd. Characters in contraction suffixes etc. —
    /// positions where restarting collation after an identical prefix is not
    /// equivalent to full iteration. Tailoring files store only their delta
    /// over the root set; ICU adds [:^lccc=0:] and surrogates at load time
    /// (we check lead-ccc at runtime instead, and scalars exclude surrogates).
    let unsafeBackward: UnsafeBufferPointer<UInt32>
    /// Fast Latin mini-CE table (CollationFastLatin format), empty if the
    /// data has none or carries an unsupported format version. Tailorings
    /// without their own fall back to the base's at the collator level.
    let fastLatinTable: UnsafeBufferPointer<UInt16>

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

        // Tailorings may carry fewer indexes than root (e.g. ko has 13, ending
        // at the ce32s part); absent parts are length 0 via the part() guard.
        let indexesLength = Int(i32(0))
        guard indexesLength >= 2,
              bytes.count >= headerSize + indexesLength * 4
        else { throw ParseError.tooShort }

        var indexes = [Int32](repeating: 0, count: indexesLength)
        for i in 0..<indexesLength { indexes[i] = i32(i * 4) }

        // Parts whose indexes are beyond indexesLength are absent (length 0),
        // like CollationDataReader::getIndex returning -1.
        func part(_ ix: Int) -> (offset: Int, length: Int) {
            guard ix + 1 < indexesLength else { return (0, 0) }
            return (Int(indexes[ix]), Int(indexes[ix + 1] - indexes[ix]))
        }

        numericPrimary = UInt32(bitPattern: indexes[IX.options]) & 0xff00_0000
        jamoCE32sStart = Int(indexes[IX.jamoCE32sStart])

        let storage = DataStorage()
        self.storage = storage

        let (trieOffset, trieLength) = part(IX.trieOffset)
        guard trieLength >= 8 else { throw ParseError.missingPart("trie") }
        trie = try UTrie2(
            bytes: bytes, offset: headerSize + trieOffset, length: trieLength, storage: storage)

        let (cesOffset, cesLength) = part(IX.cesOffset)
        var ces = [Int64](repeating: 0, count: max(0, cesLength / 8))
        for i in 0..<ces.count {
            let b = headerSize + cesOffset + i * 8
            var v: UInt64 = 0
            for j in 0..<8 { v |= UInt64(bytes[b + j]) << (8 * j) }
            ces[i] = Int64(bitPattern: v)
        }
        self.ces = storage.store(ces)

        let (ce32sOffset, ce32sLength) = part(IX.ce32sOffset)
        var ce32s = [UInt32](repeating: 0, count: max(0, ce32sLength / 4))
        for i in 0..<ce32s.count {
            let b = headerSize + ce32sOffset + i * 4
            ce32s[i] = UInt32(bytes[b]) | (UInt32(bytes[b + 1]) << 8)
                | (UInt32(bytes[b + 2]) << 16) | (UInt32(bytes[b + 3]) << 24)
        }
        self.ce32s = storage.store(ce32s)

        let (contextsOffset, contextsLength) = part(IX.contextsOffset)
        var contexts = [UInt16](repeating: 0, count: max(0, contextsLength / 2))
        for i in 0..<contexts.count {
            let b = headerSize + contextsOffset + i * 2
            contexts[i] = UInt16(bytes[b]) | (UInt16(bytes[b + 1]) << 8)
        }
        self.contexts = storage.store(contexts)

        // Scripts part: u16 numScripts, scriptsIndex[numScripts+16], scriptStarts[].
        let (scriptsOffset, scriptsLength) = part(IX.scriptsOffset)
        if scriptsLength >= 2 {
            var scripts = [UInt16](repeating: 0, count: scriptsLength / 2)
            for i in 0..<scripts.count {
                let b = headerSize + scriptsOffset + i * 2
                scripts[i] = UInt16(bytes[b]) | (UInt16(bytes[b + 1]) << 8)
            }
            let numScripts = Int(scripts[0])
            guard scripts.count > 1 + numScripts + 16 + 2 else { throw ParseError.missingPart("scripts") }
            self.numScripts = numScripts
            self.scriptsIndex = storage.store(Array(scripts[1..<(1 + numScripts + 16)]))
            self.scriptStarts = storage.store(Array(scripts[(1 + numScripts + 16)...]))
        } else {
            numScripts = 0
            scriptsIndex = storage.store([])
            scriptStarts = storage.store([])
        }

        // Unsafe-backward set: a serialized UnicodeSet (USerializedSet wire
        // format): unit 0 is the boundary count with bit 0x8000 set when
        // supplementary boundaries follow (then unit 1 is the BMP boundary
        // count); BMP boundaries are one unit each, supplementary ones two
        // (high, low). (uset_getSerializedSet/uset_serializedContains.)
        let (ubOffset, ubLength) = part(IX.unsafeBwdOffset)
        if ubLength >= 2 {
            func u16(_ i: Int) -> Int {
                let b = headerSize + ubOffset + i * 2
                return Int(bytes[b]) | (Int(bytes[b + 1]) << 8)
            }
            let unitsAvailable = ubLength / 2
            let word0 = u16(0)
            let unitCount = word0 & 0x7fff
            let bmpCount: Int
            let arrayStart: Int
            if (word0 & 0x8000) != 0 {
                bmpCount = u16(1)
                arrayStart = 2
            } else {
                bmpCount = unitCount
                arrayStart = 1
            }
            guard arrayStart + unitCount <= unitsAvailable,
                  bmpCount <= unitCount, (unitCount - bmpCount) % 2 == 0
            else { throw ParseError.missingPart("unsafeBackwardSet") }
            var boundaries = [UInt32]()
            boundaries.reserveCapacity(bmpCount + (unitCount - bmpCount) / 2)
            for i in 0..<bmpCount {
                boundaries.append(UInt32(u16(arrayStart + i)))
            }
            var i = arrayStart + bmpCount
            while i < arrayStart + unitCount {
                boundaries.append((UInt32(u16(i)) << 16) | UInt32(u16(i + 1)))
                i += 2
            }
            unsafeBackward = storage.store(boundaries)
        } else {
            unsafeBackward = storage.store([])
        }

        // Fast Latin table: gated on the format version recorded both in the
        // options word (bits 16..23) and the table's own first unit.
        // (CollationDataReader: a mismatch means "no fast path", not an error
        // for us — the regular pipeline handles everything.)
        let (flOffset, flLength) = part(IX.fastLatinTableOffset)
        if flLength >= 4,
           ((indexes[IX.options] >> 16) & 0xff) == Int32(CollationFastLatin.version) {
            var units = [UInt16](repeating: 0, count: flLength / 2)
            for i in 0..<units.count {
                let b = headerSize + flOffset + i * 2
                units[i] = UInt16(bytes[b]) | (UInt16(bytes[b + 1]) << 8)
            }
            if (units[0] >> 8) == CollationFastLatin.version,
               Int(units[0] & 0xff) <= units.count {
                fastLatinTable = storage.store(units)
            } else {
                fastLatinTable = storage.store([])
            }
        } else {
            fastLatinTable = storage.store([])
        }

        // Optional in tailorings (fall back to the base data's).
        let (cbOffset, cbLength) = part(IX.compressibleBytesOffset)
        if cbLength >= 256 {
            compressibleBytes = storage.store(
                bytes[(headerSize + cbOffset)..<(headerSize + cbOffset + 256)].map { $0 != 0 })
        } else {
            compressibleBytes = storage.store([])
        }
    }

    /// First special reorder code (UCOL_REORDER_CODE_FIRST = space group).
    static let reorderCodeFirst: Int32 = 0x1000

    /// Index into scriptStarts for a script or special reorder code.
    /// (CollationData::getScriptIndex.)
    private func scriptIndex(of script: Int32) -> Int {
        if script < 0 {
            return 0
        } else if script < Int32(numScripts) {
            return Int(scriptsIndex[Int(script)])
        } else if script < Self.reorderCodeFirst {
            return 0
        }
        let special = script - Self.reorderCodeFirst
        guard special < 8 else { return 0 }  // MAX_NUM_SPECIAL_REORDER_CODES
        return Int(scriptsIndex[numScripts + Int(special)])
    }

    /// First primary weight of a reorder group or script.
    /// (CollationData::getFirstPrimaryForGroup.)
    func firstPrimaryForGroup(_ script: Int32) -> UInt32 {
        let index = scriptIndex(of: script)
        return index == 0 ? 0 : UInt32(scriptStarts[index]) << 16
    }

    /// Last primary weight of a reorder group (for variableTop derivation).
    /// (CollationData::getLastPrimaryForGroup.)
    func lastPrimaryForGroup(_ script: Int32) -> UInt32 {
        let index = scriptIndex(of: script)
        if index == 0 { return 0 }
        return (UInt32(scriptStarts[index + 1]) << 16) - 1
    }

    /// True if `c` is in this data's unsafe-backward boundary list (the file
    /// part only; callers combine with the base data's list, lead-ccc, and
    /// the numeric-digit rule).
    @inline(__always)
    func unsafeBackwardContains(_ c: UInt32) -> Bool {
        Self.boundariesContain(unsafeBackward, c)
    }

    /// Count of boundaries <= c; odd means inside a range.
    @inline(__always)
    static func boundariesContain(_ boundaries: UnsafeBufferPointer<UInt32>, _ c: UInt32) -> Bool {
        var lo = 0
        var hi = boundaries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if boundaries[mid] <= c { lo = mid + 1 } else { hi = mid }
        }
        return lo & 1 == 1
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

    /// The bundled NFD-only root collation data (genuca -X variant: no canonical
    /// closure, no Hangul syllable mappings; requires the NFD front end).
    public static func rootICU4X() throws -> CollationData {
        guard let url = Bundle.module.url(forResource: "ucadata-icu4x", withExtension: "icu") else {
            throw ParseError.missingPart("bundled ucadata-icu4x.icu")
        }
        return try CollationData(contentsOf: url)
    }

    // MARK: Tailorings

    /// A parsed tailoring binary (%%CollationBin): per-locale default options,
    /// optional mappings (nil for settings-only tailorings like fr-CA), and
    /// optional script reordering.
    struct Tailoring {
        let options: Int32
        let data: CollationData?
        let reordering: Reordering?
    }

    /// Parses a compiled tailoring ("UCol" v5 with data header).
    /// (CollationDataReader::read, tailoring path.)
    static func tailoring(bytes: [UInt8]) throws -> Tailoring {
        guard bytes.count >= 24, bytes[2] == 0xda, bytes[3] == 0x27 else {
            throw ParseError.badMagic
        }
        let headerSize = Int(bytes[0]) | (Int(bytes[1]) << 8)
        func i32(_ byteOffset: Int) -> Int32 {
            let b = headerSize + byteOffset
            return Int32(bytes[b]) | (Int32(bytes[b + 1]) << 8)
                | (Int32(bytes[b + 2]) << 16) | (Int32(bytes[b + 3]) << 24)
        }
        let indexesLength = Int(i32(0))
        var indexes = [Int32](repeating: 0, count: indexesLength)
        for i in 0..<indexesLength { indexes[i] = i32(i * 4) }
        func part(_ ix: Int) -> (offset: Int, length: Int) {
            guard ix + 1 < indexesLength else { return (0, 0) }
            return (headerSize + Int(indexes[ix]), Int(indexes[ix + 1] - indexes[ix]))
        }

        let options = indexes[IX.options] & 0xffff

        // Mappings: present only if there is a trie.
        let (_, trieLength) = part(IX.trieOffset)
        let data: CollationData? = trieLength >= 8 ? try CollationData(bytes: bytes) : nil

        // Script reordering: codes (with trailing ranges) and the permutation table.
        var reordering: Reordering?
        let (rcOffset, rcLength) = part(IX.reorderCodesOffset)
        if rcLength >= 4 {
            var raw = [UInt32](repeating: 0, count: rcLength / 4)
            for i in 0..<raw.count {
                let b = rcOffset + i * 4
                raw[i] = UInt32(bytes[b]) | (UInt32(bytes[b + 1]) << 8)
                    | (UInt32(bytes[b + 2]) << 16) | (UInt32(bytes[b + 3]) << 24)
            }
            // Trailing entries with non-zero upper 16 bits are reorder ranges.
            var rangesLength = 0
            while rangesLength < raw.count - 1
                && (raw[raw.count - rangesLength - 1] & 0xffff_0000) != 0 {
                rangesLength += 1
            }
            let ranges = Array(raw[(raw.count - rangesLength)...])
            let (rtOffset, rtLength) = part(IX.reorderTableOffset)
            guard rtLength >= 256 else {
                // Regenerating an omitted reorder table requires the builder's
                // makeReorderRanges; not needed for ICU-compiled data.
                throw ParseError.missingPart("reorderTable")
            }
            let table = Array(bytes[rtOffset..<(rtOffset + 256)])
            reordering = Reordering(table: table, rawRanges: ranges)
        }

        return Tailoring(options: options, data: data, reordering: reordering)
    }

    public static func tailoring(named name: String) throws -> [UInt8] {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "bin", subdirectory: "tailorings")
        else {
            throw ParseError.missingPart("bundled tailoring \(name)")
        }
        return [UInt8](try Data(contentsOf: url))
    }
}

/// Trivial (ARC-free) view of the CollationData fields the CE iterator's
/// per-scalar dispatch needs. Copying CollationData retains its storage, and
/// passing a data field alongside the iterator's inout self forces such a
/// copy on every lookup; the view is plain pointers and ints, so those
/// copies are free. The iterator's strong `data`/`base` keep the memory
/// alive for as long as any view of it exists.
struct CollationDataView {
    let trie: UTrie2
    let ce32s: UnsafeBufferPointer<UInt32>
    let ces: UnsafeBufferPointer<Int64>
    let contexts: UnsafeBufferPointer<UInt16>
    let jamoCE32sStart: Int
    let numericPrimary: UInt32

    init(_ d: CollationData) {
        trie = d.trie
        ce32s = d.ce32s
        ces = d.ces
        contexts = d.contexts
        jamoCE32sStart = d.jamoCE32sStart
        numericPrimary = d.numericPrimary
    }

    /// Reads a CE32 stored as two big-endian-ordered 16-bit units in contexts[].
    @inline(__always)
    func readContextCE32(at index: Int) -> UInt32 {
        (UInt32(contexts[index]) << 16) | UInt32(contexts[index + 1])
    }
}

/// Script reordering: a permutation of primary lead bytes, with a range table
/// for "split" lead bytes shared by two reordered scripts.
/// (CollationSettings reordering, aliasReordering/reorder/reorderEx.)
struct Reordering: Sendable {
    let table: [UInt8]      // 256 entries; 0 at non-zero index = split byte
    let ranges: [UInt32]    // (limit << 16) | offset entries from the first split byte
    let minHighNoReorder: UInt32

    init(table: [UInt8], rawRanges: [UInt32]) {
        self.table = table
        // Drop ranges before the first split byte; they are fully handled by
        // the table. (CollationSettings::aliasReordering.)
        var firstSplit = 0
        while firstSplit < rawRanges.count && (rawRanges[firstSplit] & 0xff_0000) == 0 {
            firstSplit += 1
        }
        if firstSplit == rawRanges.count {
            ranges = []
            minHighNoReorder = 0
        } else {
            ranges = Array(rawRanges[firstSplit...])
            minHighNoReorder = rawRanges[rawRanges.count - 1] & 0xffff_0000
        }
    }

    @inline(__always)
    func reorder(_ p: UInt32) -> UInt32 {
        let b = table[Int(p >> 24)]
        if b != 0 || p <= CollationConstants.noCEPrimary {
            return (UInt32(b) << 24) | (p & 0xff_ffff)
        }
        return reorderEx(p)
    }

    /// Slow path for split lead bytes. (CollationSettings::reorderEx.)
    private func reorderEx(_ p: UInt32) -> UInt32 {
        if p >= minHighNoReorder { return p }
        // Round up p so that the comparison ignores the offset bits.
        let q = p | 0xffff
        var i = 0
        while q >= ranges[i] { i += 1 }
        return p &+ (ranges[i] << 24)
    }
}
