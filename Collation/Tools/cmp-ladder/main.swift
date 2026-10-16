// Compare entry ladder (the §43 sk-ladder pattern, for compare): peel
// RootCollator.compare one layer per stage on the fast-Latin path and set
// each stage against ICU's ucol_strcollUTF8 (bench_icu).
//   L0   public compare(_:_:options:)        — the Table-1 cmp row
//   L0d  public compare(_:_:)                 — the no-options overload
//   L1   compareFastPath                      — L0 − L1 = throws + slow-path branch
//   S    pin both strings' UTF-8 only         — the string-access part of L1
//   L2   fastLatinUTF8 on bytes pinned        — the core: prefix scan +
//        before the timer, setup fields read    fast-Latin comparison
//        once                                   (L1 − L2 = guard + access)
//   F    the L2 loop with an empty stub       — this ladder's own loop floor
// Verification: L1 and L2 results must equal L0 on every adjacent pair of
// the corpus (bail-outs are counted, not timed as wrong).
import Dispatch
import Foundation

@inline(never) func pinOnly(_ l: String, _ r: String) -> Int32 {
    l.utf8.withContiguousStorageIfAvailable { lb in
        r.utf8.withContiguousStorageIfAvailable { rb in
            Int32(lb.first ?? 0) &- Int32(rb.first ?? 0)
        } ?? 0
    } ?? 0
}

@inline(never) func floorStub(_ l: UnsafeBufferPointer<UInt8>, _ r: UnsafeBufferPointer<UInt8>) -> Int32 {
    Int32(l.count) &- Int32(r.count)
}

// The three split stages. Each has exactly ONE call boundary, like L1
// (compareFastPath is too large to inline), so their differences are fair.

// L2c: the core on pinned bytes behind one call — the base for L1a and L1g.
@inline(never) func coreCall(
    _ l: UnsafeBufferPointer<UInt8>, _ r: UnsafeBufferPointer<UInt8>,
    table: UnsafeBufferPointer<UInt16>, primaries: UnsafeBufferPointer<UInt16>,
    packed: Int32, numeric: Bool, safety: RestartSafety
) -> Int32 {
    var mismatch = -1
    return RootCollator.fastLatinUTF8(l, r, table: table, primaries: primaries,
                                      options: packed, numeric: numeric, safety: safety, mismatch: &mismatch)
}

// L1a: compareFastPath's string access (the nested contiguous-storage closures),
// then the core — no guard, setup fields passed in. L1a − L2c = the access.
@inline(never) func accessThenCore(
    _ left: String, _ right: String,
    table: UnsafeBufferPointer<UInt16>, primaries: UnsafeBufferPointer<UInt16>,
    packed: Int32, numeric: Bool, safety: RestartSafety
) -> Int32 {
    left.utf8.withContiguousStorageIfAvailable { lb in
        right.utf8.withContiguousStorageIfAvailable { rb in
            var mismatch = -1
            return RootCollator.fastLatinUTF8(lb, rb, table: table, primaries: primaries,
                                              options: packed, numeric: numeric, safety: safety, mismatch: &mismatch)
        } ?? CollationFastLatin.bailOutResult
    } ?? CollationFastLatin.bailOutResult
}

extension RootCollator {
    // L1g: compareFastPath's guard and its field loads from the collator, then
    // the core and the result conversion — on pinned bytes, no string access.
    // L1g − L2c = the guard, the field loads, and the conversion.
    @inline(never) func guardThenCore(
        _ l: UnsafeBufferPointer<UInt8>, _ r: UnsafeBufferPointer<UInt8>, options: CollationOptions
    ) -> Order? {
        guard defaultFLPackedOptions >= 0, options.strength != .identical,
              options.icuOptions == defaultFLWord,
              !fastLatinTable.isEmpty else { return nil }
        var mismatch = -1
        let f = RootCollator.fastLatinUTF8(
            l, r, table: self.fastLatinTable, primaries: self.defaultFLPrimaries,
            options: self.defaultFLPackedOptions, numeric: options.numeric,
            safety: self.restartSafety, mismatch: &mismatch)
        if f == CollationFastLatin.bailOutResult { return nil }
        return f < 0 ? .ascending : f == 0 ? .same : .descending
    }
}

func order(_ v: Int32) -> RootCollator.Order { v < 0 ? .ascending : v == 0 ? .same : .descending }

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: CmpLadder <corpus> [reps]") }
let lines = try String(contentsOfFile: args[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
let reps = args.count > 2 ? (Int(args[2]) ?? 300) : 300
let collator = try! RootCollator()
let opts = collator.defaultOptions

// Pin every line's UTF-8 once, before any timing, in one allocation.
let total = lines.reduce(0) { $0 + $1.utf8.count }
let storage = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: max(total, 1))
var pinned: [UnsafeBufferPointer<UInt8>] = []
do {
    var at = 0
    for line in lines {
        let n = line.utf8.count
        _ = UnsafeMutableBufferPointer(rebasing: storage[at..<(at + n)]).initialize(from: line.utf8)
        pinned.append(UnsafeBufferPointer(rebasing: storage[at..<(at + n)]))
        at += n
    }
}
let table = collator.fastLatinTable
let primaries = collator.defaultFLPrimaries
let packed = collator.defaultFLPackedOptions
let safety = collator.restartSafety
let numeric = opts.numeric

// Verification.
var bailL1 = 0, bailL2 = 0, wrong = 0
for i in 1..<lines.count {
    let r0 = try! collator.compare(lines[i - 1], lines[i], options: opts)
    var skip = false
    if let r1 = collator.compareFastPath(lines[i - 1], lines[i], options: opts, skipWalk: &skip) {
        if r1 != r0 { wrong += 1 }
    } else { bailL1 += 1 }
    var mismatch = -1
    let r2 = RootCollator.fastLatinUTF8(pinned[i - 1], pinned[i], table: table, primaries: primaries,
                                        options: packed, numeric: numeric, safety: safety, mismatch: &mismatch)
    if r2 == CollationFastLatin.bailOutResult { bailL2 += 1 } else if order(r2) != r0 { wrong += 1 }
    let r2c = coreCall(pinned[i - 1], pinned[i], table: table, primaries: primaries,
                       packed: packed, numeric: numeric, safety: safety)
    if r2c != CollationFastLatin.bailOutResult, order(r2c) != r0 { wrong += 1 }
    let r1a = accessThenCore(lines[i - 1], lines[i], table: table, primaries: primaries,
                             packed: packed, numeric: numeric, safety: safety)
    if r1a != CollationFastLatin.bailOutResult, order(r1a) != r0 { wrong += 1 }
    if let r1g = collator.guardThenCore(pinned[i - 1], pinned[i], options: opts), r1g != r0 { wrong += 1 }
}
print("corpus: \(lines.count) lines, \(lines.count - 1) pairs | L1 bail-outs \(bailL1), L2 bail-outs \(bailL2), wrong results \(wrong)")
guard wrong == 0 else { fatalError("a ladder stage disagrees with the public entry") }

var sink = 0
let ops = (lines.count - 1) * reps
@MainActor func measure(_ name: String, _ body: () -> Void) {
    body()
    var best = UInt64.max
    for _ in 0..<9 {
        let s = DispatchTime.now().uptimeNanoseconds
        body()
        best = min(best, DispatchTime.now().uptimeNanoseconds - s)
    }
    print(String(format: "%@: %.2f ns/op", name as NSString, Double(best) / Double(ops)))
}

measure("L0  public compare(options:)") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count { sink &+= (try! c.compare(lines[i - 1], lines[i], options: opts)).rawValue } }
}
measure("L0d public compare(_:_:)    ") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count { sink &+= (try! c.compare(lines[i - 1], lines[i])).rawValue } }
}
measure("L1  compareFastPath         ") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count {
        var skip = false
        sink &+= c.compareFastPath(lines[i - 1], lines[i], options: opts, skipWalk: &skip)?.rawValue ?? 9
    } }
}
measure("S   pin both strings only   ") {
    for _ in 0..<reps { for i in 1..<lines.count { sink &+= Int(pinOnly(lines[i - 1], lines[i])) } }
}
measure("L1a string access + core    ") {
    for _ in 0..<reps { for i in 1..<lines.count {
        sink &+= Int(accessThenCore(lines[i - 1], lines[i], table: table, primaries: primaries,
                                    packed: packed, numeric: numeric, safety: safety))
    } }
}
measure("L1g guard + fields + core   ") {
    let c = collator
    pinned.withUnsafeBufferPointer { p in
        for _ in 0..<reps { for i in 1..<p.count { sink &+= c.guardThenCore(p[i - 1], p[i], options: opts)?.rawValue ?? 9 } }
    }
}
measure("L2c core behind one call    ") {
    pinned.withUnsafeBufferPointer { p in
        for _ in 0..<reps { for i in 1..<p.count {
            sink &+= Int(coreCall(p[i - 1], p[i], table: table, primaries: primaries,
                                  packed: packed, numeric: numeric, safety: safety))
        } }
    }
}
measure("L2  fastLatinUTF8, pinned   ") {
    pinned.withUnsafeBufferPointer { p in
        for _ in 0..<reps { for i in 1..<p.count {
            var mismatch = -1
            sink &+= Int(RootCollator.fastLatinUTF8(p[i - 1], p[i], table: table, primaries: primaries,
                                                    options: packed, numeric: numeric, safety: safety, mismatch: &mismatch))
        } }
    }
}
measure("F   L2 loop, empty stub     ") {
    pinned.withUnsafeBufferPointer { p in
        for _ in 0..<reps { for i in 1..<p.count { sink &+= Int(floorStub(p[i - 1], p[i])) } }
    }
}
if sink == Int.min { print("") }
