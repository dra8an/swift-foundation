// §43 sortKey entry ladder (§29 pattern): peel the sortKey(for:into:) entry
// one layer per stage and attribute the gap to ICU's ucol_getSortKey.
//   S0  public sortKey(for:into:)            — the Table-1 sk row
//   S1  body with caller-held scratch        — S0−S1 = TLS take/give
//   S2  S1 as a non-throwing clone           — S1−S2 = throws structure
//   S3  reset + collectAll only              — the CE pipeline share
//   S4  writer only, on pre-collected CEs    — the write share
//   S5  reset only                           — the per-call reset cost
// Verification: S1/S2 keys must be byte-identical to S0 over the corpus.
//
// REFRESHED 2026-08-19: S1/S2 had gone stale. They still called the BUFFERED
// writer and the pre-§48 two-scope `reset` + `collectAll` pair, so from §46
// onward they measured a body the module no longer ships — S1 read ~40 ns
// high on ascii and the "TLS" and "throws" attributions drawn from it were
// both wrong. The byte-identity check could never catch this: all three
// writers emit identical keys by construction, which is the point of them.
// S1/S2 now mirror the shipping body exactly (resetAndCollectLeft, the
// storage-resolved compressibleBytes, writeSortKeyUpToQuaternarySingle);
// the buffered and direct writers stay reachable as S4/S4b for the
// writer-vs-writer comparison only.
import Dispatch
import Foundation

extension RootCollator {
    // S1: exact copy of the public sortKey(for:into:) body minus TLS.
    func skNoTLS(
        _ s: String, into key: inout [UInt8], scratch: ScratchBuffers,
        options: CollationOptions = CollationOptions()
    ) throws {
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        try scratch.resetCollectAndWriteKey(
            numeric: options.numeric, scalars: s.unicodeScalars,
            compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, terminate: options.strength != .identical, into: &key)
        if options.strength == .identical {
            key.append(1)
            scratch.collectNFDScalars(scalars: s.unicodeScalars)
            CollationKeys.writeIdenticalLevelRun(scalars: scratch.nfdScalars, into: &key)
            key.append(0)
        }
    }

    // S2: byte-for-byte the S1 body, but non-throwing (try! inside).
    func skNoThrow(
        _ s: String, into key: inout [UInt8], scratch: ScratchBuffers,
        options: CollationOptions = CollationOptions()
    ) {
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        try! scratch.resetCollectAndWriteKey(
            numeric: options.numeric, scalars: s.unicodeScalars,
            compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, terminate: options.strength != .identical, into: &key)
        if options.strength == .identical {
            key.append(1)
            scratch.collectNFDScalars(scalars: s.unicodeScalars)
            CollationKeys.writeIdenticalLevelRun(scalars: scratch.nfdScalars, into: &key)
            key.append(0)
        }
    }

    // S3: pipeline only — reset + collectAll, no writer. Uses the same fused
    // single-scope helper the shipping body calls.
    func skPipelineOnly(_ s: String, scratch: ScratchBuffers) -> Int {
        try! scratch.resetAndCollectLeft(numeric: false, scalars: s.unicodeScalars)
        return scratch.left.pointee.ces.count
    }

    // S4: writer only, on CEs collected once outside the timing loop. The
    // buffered reference writer; its level buffers are owned by the ladder
    // (ScratchBuffers no longer carries them — the writer does not ship).
    func skWriterOnly(
        ces: [Int64], into key: inout [UInt8], levels: inout SortKeyLevelBuffers,
        options: CollationOptions = CollationOptions()
    ) {
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        key.removeAll(keepingCapacity: true)
        CollationKeys.writeSortKeyUpToQuaternary(
            ces: ces, compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, into: &key, reusing: &levels)
        key.append(0)
    }

    // S5: reset only.
    func skResetOnly(_ s: String, scratch: ScratchBuffers) -> Int {
        scratch.left.pointee.reset(numeric: false, scalars: s.unicodeScalars)
        return scratch.left.pointee.ces.count
    }

    // S4b: the §43 direct multi-pass writer, on the same pre-collected CEs.
    func skWriterDirect(
        ces: [Int64], into key: inout [UInt8],
        options: CollationOptions = CollationOptions()
    ) {
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        key.removeAll(keepingCapacity: true)
        CollationKeys.writeSortKeyUpToQuaternaryDirect(
            ces: ces, compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, into: &key)
        key.append(0)
    }

    // Buffered-writer twin of skWriterDirect for the option-matrix identity
    // check (no terminator differences: both append 0).
    func skWriterBuffered(
        ces: [Int64], into key: inout [UInt8], levels: inout SortKeyLevelBuffers,
        options: CollationOptions
    ) {
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        key.removeAll(keepingCapacity: true)
        CollationKeys.writeSortKeyUpToQuaternary(
            ces: ces, compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, into: &key, reusing: &levels)
        key.append(0)
    }

    // S4c: the single-pass writer with in-region level buffers — THE SHIPPING
    // WRITER (the third point in the writer design space, ICU's shape).
    // S4/S4b keep the buffered and direct writers reachable for the
    // writer-vs-writer comparison; only this one reflects the module.
    func skWriterSingle(
        ces: borrowing CEBuffer, into key: inout [UInt8],
        options: CollationOptions = CollationOptions()
    ) {
        let compressibleBytes = data.compressibleBytes.isEmpty
            ? base!.compressibleBytes : data.compressibleBytes
        // The writer replaces the key's contents and adds the terminator itself.
        CollationKeys.writeSortKeyUpToQuaternarySingle(
            ces: ces, compressibleBytes: compressibleBytes,
            options: options.icuOptions, variableTopValue: variableTopValue(options),
            reordering: reordering, terminate: true, into: &key)
    }

    // A DEDICATED probe scratch — the thread-local slot must stay free so
    // S0's internal takeScratch behaves exactly as in production (holding
    // the TLS scratch would force S0 to allocate fresh buffers per call).
    func ladderScratch() -> ScratchBuffers {
        ScratchBuffers(data: data, base: base, norm: norm,
                       simpleCEs: simpleCEs, thaiCEs: thaiCEs,
                       simpleCEsWithDigits: simpleCEsWithDigits,
                       thaiCEsWithDigits: thaiCEsWithDigits)
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: SKLadder <corpus> [reps]") }
let lines = try String(contentsOfFile: args[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
let reps = args.count > 2 ? (Int(args[2]) ?? 300) : 300
let collator = try! RootCollator()
let scratch = collator.ladderScratch()
// Level buffers for the buffered reference writer (S4 and the identity check).
var ladderLevels = SortKeyLevelBuffers()

// The option matrix. CE production is options-independent at numeric=off, so
// one CE array per line serves every set here.
//
// `.identical` matters and was missing until 2026-08-19: it is the ONLY set
// that reaches the identical-level drain (collectNFDScalars +
// writeIdenticalLevelRun), so without it the stage clones' drain code was
// timed but never checked. §48 rewrote that drain and the refresh rewrote the
// clones' copy of it; both went unverified here.
var optionMatrix: [(String, CollationOptions)] = []
do {
    var o = CollationOptions(); optionMatrix.append(("default", o))
    o = CollationOptions(); o.strength = .primary; optionMatrix.append(("primary", o))
    o = CollationOptions(); o.strength = .secondary; optionMatrix.append(("secondary", o))
    o = CollationOptions(); o.strength = .quaternary; optionMatrix.append(("quaternary", o))
    o = CollationOptions(); o.strength = .quaternary; o.alternate = .shifted
    optionMatrix.append(("shifted", o))
    o = CollationOptions(); o.caseLevel = true; optionMatrix.append(("caseLevel", o))
    o = CollationOptions(); o.caseFirst = .upperFirst; optionMatrix.append(("upperFirst", o))
    o = CollationOptions(); o.backwardSecondary = true; optionMatrix.append(("french", o))
    o = CollationOptions(); o.strength = .identical; optionMatrix.append(("identical", o))
    o = CollationOptions(); o.strength = .identical; o.alternate = .shifted
    optionMatrix.append(("identical+shifted", o))
}

// Pre-collect CEs per line for S4, and verify S1/S2 keys == S0 keys ACROSS THE
// WHOLE MATRIX — the stage clones must track the public entry at every option
// set, not just the default one.
var lineCEs: [[Int64]] = []
/// The same CEs as a CEBuffer per line, for the shipping writer (it takes a CEBuffer; a noncopyable value cannot be an array element, hence the box — the module reads `scratch.left.pointee.ces` through a class too).
final class CEBox {
    var ces = CEBuffer()
    init(_ source: borrowing CEBuffer) {
        for i in 0..<source.count { ces.append(source[i]) }
    }
}
var lineBoxes: [CEBox] = []
var s0key: [UInt8] = [], s1key: [UInt8] = [], s2key: [UInt8] = []
var stageMismatches: [String: Int] = [:]
for line in lines {
    scratch.left.pointee.reset(numeric: false, scalars: line.unicodeScalars)
    _ = try! scratch.left.pointee.collectAll()
    // Verbatim buffer state (sentinel included) — S4 must see exactly what
    // the real body hands the writer.
    lineCEs.append(scratch.left.pointee.ces.toArray())
    lineBoxes.append(CEBox(scratch.left.pointee.ces))
}
for (name, opts) in optionMatrix {
    var bad = 0
    for line in lines {
        try! collator.sortKey(for: line, into: &s0key, options: opts)
        try! collator.skNoTLS(line, into: &s1key, scratch: scratch, options: opts)
        collator.skNoThrow(line, into: &s2key, scratch: scratch, options: opts)
        if s1key != s0key || s2key != s0key { bad += 1 }
    }
    stageMismatches[name] = bad
}
let stageSummary = optionMatrix.map { "\($0.0)=\(stageMismatches[$0.0]!)" }.joined(separator: " ")
print("corpus: \(lines.count) lines | S1/S2 vs S0 mismatched lines: \(stageSummary)")
guard stageMismatches.values.allSatisfy({ $0 == 0 }) else {
    fatalError("stage clones diverge from the public entry")
}
var directMismatches: [String: Int] = [:]
var singleMismatches: [String: Int] = [:]
var bufKey: [UInt8] = [], dirKey: [UInt8] = [], sglKey: [UInt8] = []
for (name, opts) in optionMatrix {
    var bad = 0
    var badSingle = 0
    for (k, ces) in lineCEs.enumerated() {
        collator.skWriterBuffered(ces: ces, into: &bufKey, levels: &ladderLevels, options: opts)
        collator.skWriterDirect(ces: ces, into: &dirKey, options: opts)
        collator.skWriterSingle(ces: lineBoxes[k].ces, into: &sglKey, options: opts)
        if bufKey != dirKey { bad += 1 }
        if bufKey != sglKey { badSingle += 1 }
    }
    directMismatches[name] = bad
    singleMismatches[name] = badSingle
}
let identitySummary = optionMatrix.map { "\($0.0)=\(directMismatches[$0.0]!)" }.joined(separator: " ")
print("direct-writer identity (mismatched lines): \(identitySummary)")
let singleSummary = optionMatrix.map { "\($0.0)=\(singleMismatches[$0.0]!)" }.joined(separator: " ")
print("single-pass-writer identity (mismatched lines): \(singleSummary)")
guard directMismatches.values.allSatisfy({ $0 == 0 }) else {
    fatalError("direct writer diverges from buffered writer")
}
guard singleMismatches.values.allSatisfy({ $0 == 0 }) else {
    fatalError("single-pass writer diverges from buffered writer")
}

var sink = 0
var key: [UInt8] = []
@MainActor func measure(_ name: String, _ body: () -> Void) {
    body()
    var best = UInt64.max
    for _ in 0..<9 {
        let s = DispatchTime.now().uptimeNanoseconds
        body()
        best = min(best, DispatchTime.now().uptimeNanoseconds - s)
    }
    print("\(name): \(best / UInt64(lines.count * reps)) ns/op")
}

measure("S0 public       ") {
    let c = collator
    for _ in 0..<reps { for line in lines { try! c.sortKey(for: line, into: &key); sink += key.count } }
}
measure("S1 no-TLS       ") {
    let c = collator
    for _ in 0..<reps { for line in lines { try! c.skNoTLS(line, into: &key, scratch: scratch); sink += key.count } }
}
measure("S2 no-throws    ") {
    let c = collator
    for _ in 0..<reps { for line in lines { c.skNoThrow(line, into: &key, scratch: scratch); sink += key.count } }
}
measure("S3 pipeline-only") {
    let c = collator
    for _ in 0..<reps { for line in lines { sink += c.skPipelineOnly(line, scratch: scratch) } }
}
measure("S4 writer-only  ") {
    let c = collator
    for _ in 0..<reps { for (i, _) in lines.enumerated() { c.skWriterOnly(ces: lineCEs[i], into: &key, levels: &ladderLevels); sink += key.count } }
}
measure("S4b writer-direct") {
    let c = collator
    for _ in 0..<reps { for (i, _) in lines.enumerated() { c.skWriterDirect(ces: lineCEs[i], into: &key); sink += key.count } }
}
measure("S4c writer-single") {
    let c = collator
    for _ in 0..<reps { for (i, _) in lines.enumerated() { c.skWriterSingle(ces: lineBoxes[i].ces, into: &key); sink += key.count } }
}
measure("S5 reset-only   ") {
    let c = collator
    for _ in 0..<reps { for line in lines { sink += c.skResetOnly(line, scratch: scratch) } }
}
if sink == Int.min { print("") }

// Hold-loop hooks for `sample PID 10`. `holdS4` held the BUFFERED writer,
// which stopped shipping at §46 — profiling it attributes work to code no
// user reaches. It now holds S4c, the shipping single-pass writer; `holdS4buf`
// keeps the old target for writer-vs-writer profile diffs.
if args.contains("holdS4") {
    print("holding S4c writer-single (THE SHIPPING WRITER) for sampling…")
    let c = collator
    for _ in 0..<200000 {
        for (i, _) in lines.enumerated() {
            c.skWriterSingle(ces: lineBoxes[i].ces, into: &key)
            sink += key.count
        }
    }
}

if args.contains("holdS4buf") {
    print("holding S4 writer-only (buffered, NOT shipping) for sampling…")
    let c = collator
    for _ in 0..<200000 {
        for (i, _) in lines.enumerated() {
            c.skWriterOnly(ces: lineCEs[i], into: &key, levels: &ladderLevels)
            sink += key.count
        }
    }
}

if args.contains("holdS0") {
    print("holding S0 public entry for sampling…")
    let c = collator
    for _ in 0..<200000 {
        for line in lines {
            try! c.sortKey(for: line, into: &key)
            sink += key.count
        }
    }
}
