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
    packed: Int32, numeric: Bool, safety: UnsafePointer<RestartSafety>
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
    packed: Int32, numeric: Bool, safety: UnsafePointer<RestartSafety>
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
    // REMOVAL CLONES of compareFastPath (2026-10-16): R0 is an exact copy of the
    // shipping body (the control — it must read like L1); R1–R4 each remove ONE
    // item. Copy the body again if compareFastPath changes.

    @inline(never) func r0Exact(_ left: String, _ right: String, options: CollationOptions, restart: inout Int) -> Order? {
        let setup = defaultFLSetupPtr
        let st = storage
        let safety = UnsafePointer(st.restartSafetyPtr)
        let cjkSetup = st.quickCJKSetupPtr
        guard setup.pointee.eligible, RootCollator.bits(of: options) == setup.pointee.optionBits else { return nil }
        let table = setup.pointee.table
        let primaries = setup.pointee.primaries
        let packed = setup.pointee.packedOptions
        var restartScalars = -1
        let fast: Int32 = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                let f = RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: table, primaries: primaries, options: packed,
                    numeric: options.numeric, safety: safety, mismatch: &mismatch)
                if f != CollationFastLatin.bailOutResult { return f }
                let q = RootCollator.quickCJKDispatch(
                    lBytes, rBytes, at: mismatch, setup: cjkSetup,
                    numeric: options.numeric, safety: safety)
                if q != CollationFastLatin.bailOutResult { return q }
                restartScalars = RootCollator.restartScalarCount(
                    lBytes, rBytes, at: mismatch, safety: safety, numeric: options.numeric)
                return CollationFastLatin.bailOutResult
            } ?? CollationFastLatin.bailOutResult
        } ?? CollationFastLatin.bailOutResult
        if fast != CollationFastLatin.bailOutResult {
            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
        }
        restart = restartScalars
        return nil
    }

    // R1: no bail-out calls (no CJK dispatch, no restart check, no restart count).
    @inline(never) func r1NoBailCalls(_ left: String, _ right: String, options: CollationOptions, restart: inout Int) -> Order? {
        let setup = defaultFLSetupPtr
        let st = storage
        let safety = UnsafePointer(st.restartSafetyPtr)
        guard setup.pointee.eligible, RootCollator.bits(of: options) == setup.pointee.optionBits else { return nil }
        let table = setup.pointee.table
        let primaries = setup.pointee.primaries
        let packed = setup.pointee.packedOptions
        let fast: Int32 = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                return RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: table, primaries: primaries, options: packed,
                    numeric: options.numeric, safety: safety, mismatch: &mismatch)
            } ?? CollationFastLatin.bailOutResult
        } ?? CollationFastLatin.bailOutResult
        if fast != CollationFastLatin.bailOutResult {
            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
        }
        return nil
    }

    // R2: no options checks in the guard (only the init-time eligibility flag).
    @inline(never) func r2NoOptionsCheck(_ left: String, _ right: String, options: CollationOptions, restart: inout Int) -> Order? {
        let setup = defaultFLSetupPtr
        let st = storage
        let safety = UnsafePointer(st.restartSafetyPtr)
        let cjkSetup = st.quickCJKSetupPtr
        guard setup.pointee.eligible else { return nil }
        let table = setup.pointee.table
        let primaries = setup.pointee.primaries
        let packed = setup.pointee.packedOptions
        var restartScalars = -1
        let fast: Int32 = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                let f = RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: table, primaries: primaries, options: packed,
                    numeric: options.numeric, safety: safety, mismatch: &mismatch)
                if f != CollationFastLatin.bailOutResult { return f }
                let q = RootCollator.quickCJKDispatch(
                    lBytes, rBytes, at: mismatch, setup: cjkSetup,
                    numeric: options.numeric, safety: safety)
                if q != CollationFastLatin.bailOutResult { return q }
                restartScalars = RootCollator.restartScalarCount(
                    lBytes, rBytes, at: mismatch, safety: safety, numeric: options.numeric)
                return CollationFastLatin.bailOutResult
            } ?? CollationFastLatin.bailOutResult
        } ?? CollationFastLatin.bailOutResult
        if fast != CollationFastLatin.bailOutResult {
            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
        }
        restart = restartScalars
        return nil
    }

    // R3: returns Int32 — no conversion to Order? (bail-out reported as the bail value).
    @inline(never) func r3NoConversion(_ left: String, _ right: String, options: CollationOptions, restart: inout Int) -> Int32 {
        let setup = defaultFLSetupPtr
        let st = storage
        let safety = UnsafePointer(st.restartSafetyPtr)
        let cjkSetup = st.quickCJKSetupPtr
        guard setup.pointee.eligible, RootCollator.bits(of: options) == setup.pointee.optionBits else { return CollationFastLatin.bailOutResult }
        let table = setup.pointee.table
        let primaries = setup.pointee.primaries
        let packed = setup.pointee.packedOptions
        var restartScalars = -1
        let fast: Int32 = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                let f = RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: table, primaries: primaries, options: packed,
                    numeric: options.numeric, safety: safety, mismatch: &mismatch)
                if f != CollationFastLatin.bailOutResult { return f }
                let q = RootCollator.quickCJKDispatch(
                    lBytes, rBytes, at: mismatch, setup: cjkSetup,
                    numeric: options.numeric, safety: safety)
                if q != CollationFastLatin.bailOutResult { return q }
                restartScalars = RootCollator.restartScalarCount(
                    lBytes, rBytes, at: mismatch, safety: safety, numeric: options.numeric)
                return CollationFastLatin.bailOutResult
            } ?? CollationFastLatin.bailOutResult
        } ?? CollationFastLatin.bailOutResult
        restart = restartScalars
        return fast
    }

    // R4: `numeric` as a plain Bool parameter; the closures do not capture `options`.
    @inline(never) func r4NoOptionsCapture(_ left: String, _ right: String, options: CollationOptions, restart: inout Int) -> Order? {
        let setup = defaultFLSetupPtr
        let st = storage
        let safety = UnsafePointer(st.restartSafetyPtr)
        let cjkSetup = st.quickCJKSetupPtr
        guard setup.pointee.eligible, RootCollator.bits(of: options) == setup.pointee.optionBits else { return nil }
        let table = setup.pointee.table
        let primaries = setup.pointee.primaries
        let packed = setup.pointee.packedOptions
        let numeric = options.numeric
        var restartScalars = -1
        let fast: Int32 = left.utf8.withContiguousStorageIfAvailable { lBytes in
            right.utf8.withContiguousStorageIfAvailable { rBytes in
                var mismatch = -1
                let f = RootCollator.fastLatinUTF8(
                    lBytes, rBytes, table: table, primaries: primaries, options: packed,
                    numeric: numeric, safety: safety, mismatch: &mismatch)
                if f != CollationFastLatin.bailOutResult { return f }
                let q = RootCollator.quickCJKDispatch(
                    lBytes, rBytes, at: mismatch, setup: cjkSetup,
                    numeric: numeric, safety: safety)
                if q != CollationFastLatin.bailOutResult { return q }
                restartScalars = RootCollator.restartScalarCount(
                    lBytes, rBytes, at: mismatch, safety: safety, numeric: numeric)
                return CollationFastLatin.bailOutResult
            } ?? CollationFastLatin.bailOutResult
        } ?? CollationFastLatin.bailOutResult
        if fast != CollationFastLatin.bailOutResult {
            return fast < 0 ? .ascending : fast == 0 ? .same : .descending
        }
        restart = restartScalars
        return nil
    }

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
            safety: UnsafePointer(self.storage.restartSafetyPtr), mismatch: &mismatch)
        if f == CollationFastLatin.bailOutResult { return nil }
        return f < 0 ? .ascending : f == 0 ? .same : .descending
    }
}

func order(_ v: Int32) -> RootCollator.Order { v < 0 ? .ascending : v == 0 ? .same : .descending }

// Instruction-count target: lldb stops here and single-steps until it returns
// (see the count mode below). One public compare, exactly as EngineBench calls it.
@inline(never) func countPublic(_ c: RootCollator, _ l: String, _ r: String, _ o: CollationOptions) -> Int {
    (try! c.compare(l, r, options: o)).rawValue
}

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
let safety = UnsafePointer(collator.storage.restartSafetyPtr)
let numeric = opts.numeric

// Verification.
var bailL1 = 0, bailL2 = 0, wrong = 0
for i in 1..<lines.count {
    let r0 = try! collator.compare(lines[i - 1], lines[i], options: opts)
    var skip = -1
    if let r1 = collator.compareFastPath(lines[i - 1], lines[i], options: opts, restart: &skip) {
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
    var sk = -1
    for r in [collator.r0Exact(lines[i - 1], lines[i], options: opts, restart: &sk),
              collator.r1NoBailCalls(lines[i - 1], lines[i], options: opts, restart: &sk),
              collator.r2NoOptionsCheck(lines[i - 1], lines[i], options: opts, restart: &sk),
              collator.r4NoOptionsCapture(lines[i - 1], lines[i], options: opts, restart: &sk)] {
        if let r, r != r0 { wrong += 1 }
    }
    let r3 = collator.r3NoConversion(lines[i - 1], lines[i], options: opts, restart: &sk)
    if r3 != CollationFastLatin.bailOutResult, order(r3) != r0 { wrong += 1 }
}
print("corpus: \(lines.count) lines, \(lines.count - 1) pairs | L1 bail-outs \(bailL1), L2 bail-outs \(bailL2), wrong results \(wrong)")
guard wrong == 0 else { fatalError("a ladder stage disagrees with the public entry") }

// Count mode: `CmpLadder <corpus> <reps> count <first pair> <pairs>`. For an
// instruction count under lldb (break on countPublic, single-step to its return).
// Warms every pair up first, so no lazy initialization lands in the count.
if args.count >= 6, args[3] == "count", let first = Int(args[4]), let n = Int(args[5]) {
    let pairs = (first..<(first + n)).filter { $0 >= 1 && $0 < lines.count }
    var warm = 0
    for _ in 0..<1000 { for i in pairs { warm &+= (try! collator.compare(lines[i - 1], lines[i], options: opts)).rawValue } }
    var total = 0
    for i in pairs { total &+= countPublic(collator, lines[i - 1], lines[i], opts) }
    print("count mode: \(pairs.count) pairs from \(first) (\(warm &+ total))")
    exit(0)
}

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
        var skip = -1
        sink &+= c.compareFastPath(lines[i - 1], lines[i], options: opts, restart: &skip)?.rawValue ?? 9
    } }
}
measure("R0  clone, exact (control)  ") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count { var s = -1; sink &+= c.r0Exact(lines[i - 1], lines[i], options: opts, restart: &s)?.rawValue ?? 9 } }
}
measure("R1  clone, no bail calls    ") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count { var s = -1; sink &+= c.r1NoBailCalls(lines[i - 1], lines[i], options: opts, restart: &s)?.rawValue ?? 9 } }
}
measure("R2  clone, no options check ") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count { var s = -1; sink &+= c.r2NoOptionsCheck(lines[i - 1], lines[i], options: opts, restart: &s)?.rawValue ?? 9 } }
}
measure("R3  clone, no Order? convert") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count { var s = -1; sink &+= Int(c.r3NoConversion(lines[i - 1], lines[i], options: opts, restart: &s)) } }
}
measure("R4  clone, no options capture") {
    let c = collator
    for _ in 0..<reps { for i in 1..<lines.count { var s = -1; sink &+= c.r4NoOptionsCapture(lines[i - 1], lines[i], options: opts, restart: &s)?.rawValue ?? 9 } }
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
