// Offline generator: parses ICU's norm2/nfc.txt (canonical decompositions and
// canonical combining classes, the gennorm2 source format) and emits nfd.bin,
// the normalization resource consumed by NormalizationData.swift.
//
// Decompositions are recursively expanded to full canonical (NFD) form.
// Hangul syllables are not in nfc.txt and are decomposed arithmetically at
// runtime; this tool asserts that assumption.
//
// nfd.bin layout (little-endian):
//   u32 magic "SNFD" (0x44464e53)
//   u32 version (1)
//   u32 cccCount
//   u32[cccCount]    (scalar << 8) | ccc, sorted by scalar
//   u32 decompCount
//   u64[decompCount] (scalar << 32) | (bufferOffset << 8) | length, sorted by scalar
//   u32 bufferCount
//   u32[bufferCount] decomposition scalars
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

// Serialize.
var out = Data()
func append32(_ v: UInt32) {
    withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
}
func append64(_ v: UInt64) {
    withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
}

append32(0x4446_4e53)  // "SNFD"
append32(1)

let cccEntries = cccMap.map { ($0.key << 8) | UInt32($0.value) }.sorted()
append32(UInt32(cccEntries.count))
cccEntries.forEach(append32)

var buffer: [UInt32] = []
var decompEntries: [UInt64] = []
for (c, d) in fullDecomp.sorted(by: { $0.key < $1.key }) {
    precondition(d.count < 256 && buffer.count < (1 << 24))
    decompEntries.append((UInt64(c) << 32) | UInt64(buffer.count << 8) | UInt64(d.count))
    buffer.append(contentsOf: d)
}
append32(UInt32(decompEntries.count))
decompEntries.forEach(append64)
append32(UInt32(buffer.count))
buffer.forEach(append32)

try out.write(to: URL(fileURLWithPath: arguments[2]))
print("Unicode \(unicodeVersion): \(cccEntries.count) ccc entries, \(decompEntries.count) decompositions, \(buffer.count) buffer scalars, \(out.count) bytes")
}

try run()
