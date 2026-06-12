// Offline generator: parses ICU's norm2/nfc.txt (canonical decompositions and
// canonical combining classes, the gennorm2 source format) and emits nfd.bin,
// the normalization resource consumed by NormalizationData.swift.
//
// Decompositions are recursively expanded to full canonical (NFD) form.
// Hangul syllables are not in nfc.txt and are decomposed arithmetically at
// runtime; this tool asserts that assumption.
//
// nfd.bin layout (little-endian), version 2 — the ICU4X-style single-trie
// design: one lookup per scalar yields ccc + lead-ccc + decomposition.
//   u32 magic "SNFD" (0x44464e53)
//   u32 version (2)
//   u32 indexCount (0x110000 >> 6 = 17408)
//   u16[indexCount]  block number per 64-scalar range (deduplicated blocks)
//   u32 dataCount
//   u32[dataCount]   packed values, in blocks of 64:
//     bits  0..7   ccc of the scalar
//     bits  8..15  lead ccc (ccc of the first scalar of the full
//                  decomposition; equals ccc when there is none)
//     bits 16..18  decomposition length (0 = none; 7 = Hangul syllable,
//                  decomposed arithmetically at runtime)
//     bits 19..31  decomposition offset into the buffer
//   u32 bufferCount
//   u32[bufferCount] decomposition scalars
//
// A value of 0 therefore means "inert": ccc 0 and no decomposition.
//
// Usage: gennormdata <path/to/nfc.txt> <path/to/nfd.bin>

import Foundation

func hex<S: StringProtocol>(_ s: S) -> UInt32 {
    guard let v = UInt32(s, radix: 16) else { fatalError("bad hex: \(s)") }
    return v
}

func run() throws {
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: gennormdata <nfc.txt> <nfd.bin>\n".utf8))
    exit(2)
}

let text = try String(contentsOfFile: arguments[1], encoding: .utf8)

var cccMap: [UInt32: UInt8] = [:]
var rawDecomp: [UInt32: [UInt32]] = [:]
var unicodeVersion = "unknown"

for rawLine in text.split(separator: "\n") {
    var line = rawLine[...]
    if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    if trimmed.hasPrefix("*") {
        unicodeVersion = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        continue
    }
    if let colon = trimmed.firstIndex(of: ":") {
        // ccc assignment: "HEX..HEX:N" or "HEX:N"
        let range = trimmed[..<colon]
        guard let value = UInt8(trimmed[trimmed.index(after: colon)...]) else {
            fatalError("bad ccc line: \(trimmed)")
        }
        if let dots = range.range(of: "..") {
            for c in hex(range[..<dots.lowerBound])...hex(range[dots.upperBound...]) {
                cccMap[c] = value
            }
        } else {
            cccMap[hex(range)] = value
        }
    } else if let sep = trimmed.firstIndex(where: { $0 == "=" || $0 == ">" }) {
        // Canonical mapping: "HEX=HEX HEX..." (round trip) or "HEX>..." (one way).
        // Both are canonical decompositions for NFD purposes.
        let source = trimmed[..<sep]
        guard !source.contains(" ") else { fatalError("multi-code-point source: \(trimmed)") }
        let targets = trimmed[trimmed.index(after: sep)...].split(separator: " ").map(hex)
        guard targets.count >= 1 && targets.count <= 2 else {
            fatalError("unexpected decomposition length: \(trimmed)")
        }
        rawDecomp[hex(source)] = targets
    } else {
        fatalError("unparsed line: \(trimmed)")
    }
}

// Hangul is algorithmic; it must not appear in the data.
for c in rawDecomp.keys {
    precondition(!(0xac00...0xd7a3).contains(c), "unexpected Hangul mapping for U+\(String(c, radix: 16))")
}

// Recursively expand to full canonical decompositions.
func expand(_ c: UInt32) -> [UInt32] {
    guard let d = rawDecomp[c] else { return [c] }
    return d.flatMap(expand)
}
var fullDecomp: [UInt32: [UInt32]] = [:]
for c in rawDecomp.keys {
    fullDecomp[c] = expand(c)
}

// Pack one value per scalar: ccc, lead ccc, decomposition length + offset.
var values = [UInt32](repeating: 0, count: 0x110000)
for (c, ccc) in cccMap {
    values[Int(c)] = UInt32(ccc) | (UInt32(ccc) << 8)  // lccc = ccc until a decomposition says otherwise
}
var buffer: [UInt32] = []
for (c, d) in fullDecomp.sorted(by: { $0.key < $1.key }) {
    // Length 7 is the Hangul sentinel; real lengths must stay below it, and
    // the offset must fit its 13 bits.
    precondition(d.count <= 6, "decomposition too long for the value format")
    precondition(buffer.count < (1 << 13), "buffer offset overflows the value format")
    let lccc = cccMap[d[0]] ?? 0
    values[Int(c)] = UInt32(cccMap[c] ?? 0)
        | (UInt32(lccc) << 8)
        | (UInt32(d.count) << 16)
        | (UInt32(buffer.count) << 19)
    buffer.append(contentsOf: d)
}
// Hangul syllables decompose arithmetically at runtime: sentinel length 7.
for c in 0xac00...0xd7a3 {
    values[c] = 7 << 16
}

// Two-level trie: a flat index of deduplicated 64-value blocks.
var blockNumbers: [[UInt32]: UInt16] = [:]
var data: [UInt32] = []
var index: [UInt16] = []
for blockStart in stride(from: 0, to: 0x110000, by: 64) {
    let block = Array(values[blockStart..<(blockStart + 64)])
    if let number = blockNumbers[block] {
        index.append(number)
    } else {
        let number = UInt16(data.count >> 6)
        blockNumbers[block] = number
        data.append(contentsOf: block)
        index.append(number)
    }
}

// Serialize.
var out = Data()
func append16(_ v: UInt16) {
    withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
}
func append32(_ v: UInt32) {
    withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
}

append32(0x4446_4e53)  // "SNFD"
append32(2)
append32(UInt32(index.count))
index.forEach(append16)
append32(UInt32(data.count))
data.forEach(append32)
append32(UInt32(buffer.count))
buffer.forEach(append32)

try out.write(to: URL(fileURLWithPath: arguments[2]))
print("Unicode \(unicodeVersion): \(cccMap.count) ccc entries, \(fullDecomp.count) decompositions, \(blockNumbers.count) trie blocks, \(buffer.count) buffer scalars, \(out.count) bytes")
}

try run()
