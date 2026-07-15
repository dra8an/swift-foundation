// §32 thai probe ladder — attribution only, engine copy is unmodified apart
// from visibility loosening (sed in assemble script). Mirrors §29's method:
// each probe adds/removes one layer; differences attribute the cost.
//
// P0 full public compare            (calibration: must match EngineBench)
// P1 compareBody direct             (P0−P1 = compareFastPath byte-scan attempt + entry)
// P2 scalar skip-walk + unsafeStart (prefix machinery inside the body)
// P3 takeScratch/giveScratch pair   (the TLS round-trip, isolated)
// P4 pipeline core, scratch hoisted (skip-walk + reset + compareUpToQuaternary)
// P5 NFD drain, both sides          (normalization front end alone, full strings)
// P6 collectAll, both sides         (NFD + CE production, full strings; sortKey shape)

import Dispatch
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: ThaiLadder <corpus> [reps]") }
let lines = try String(contentsOfFile: args[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
let reps = args.count > 2 ? (Int(args[2]) ?? 10) : 10
let collator = try! RootCollator()
let opts = collator.defaultOptions

func measure(_ name: String, ops: Int, _ body: () -> Void) {
    body()
    var best = UInt64.max
    for _ in 0..<9 {
        let s = DispatchTime.now().uptimeNanoseconds
        body()
        best = min(best, DispatchTime.now().uptimeNanoseconds - s)
    }
    print("\(name): \(best / UInt64(ops)) ns/op (\(ops) ops)")
}

var sink = 0
let pairOps = (lines.count - 1) * reps

measure("P0.compareFull ", ops: pairOps) {
    let c = collator
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += (try! c.compare(lines[i - 1], lines[i], options: opts)).rawValue
        }
    }
}

measure("P1.compareBody ", ops: pairOps) {
    let c = collator
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += (try! c.compareBody(
                lines[i - 1], lines[i], options: opts, triedFastLatin: true)).rawValue
        }
    }
}

measure("P2.skipWalk    ", ops: pairOps) {
    let c = collator
    for _ in 0..<reps {
        for i in 1..<lines.count {
            var lIter = lines[i - 1].unicodeScalars.makeIterator()
            var rIter = lines[i].unicodeScalars.makeIterator()
            var shared = 0
            var lNext = lIter.next()
            var rNext = rIter.next()
            while let a = lNext, let b = rNext, a == b {
                shared += 1
                lNext = lIter.next()
                rNext = rIter.next()
            }
            if shared > 0,
               (lNext.map { c.unsafeStart($0.value, numeric: false) } ?? false)
                || (rNext.map { c.unsafeStart($0.value, numeric: false) } ?? false) {
                shared = 0
            }
            sink += shared &+ (lNext.map { Int($0.value) } ?? 0)
        }
    }
}

measure("P3.scratchPair ", ops: pairOps) {
    let c = collator
    for _ in 0..<reps {
        for _ in 1..<lines.count {
            let s = c.takeScratch()
            sink += s.key.count
            c.giveScratch(s)
        }
    }
}

// Hoisted scratch for P4–P6: taken once, reused, returned at the end.
let hoisted = collator.takeScratch()

measure("P4.pipelineCore", ops: pairOps) {
    let c = collator
    let s = hoisted
    let vtop = c.variableTopValue(opts)
    let reorder = c.reordering
    for _ in 0..<reps {
        for i in 1..<lines.count {
            let left = lines[i - 1]
            let right = lines[i]
            var lIter = left.unicodeScalars.makeIterator()
            var rIter = right.unicodeScalars.makeIterator()
            var shared = 0
            var lNext = lIter.next()
            var rNext = rIter.next()
            while let a = lNext, let b = rNext, a == b {
                shared += 1
                lNext = lIter.next()
                rNext = rIter.next()
            }
            var fellBack = false
            if shared > 0,
               (lNext.map { c.unsafeStart($0.value, numeric: false) } ?? false)
                || (rNext.map { c.unsafeStart($0.value, numeric: false) } ?? false) {
                shared = 0
                fellBack = true
            }
            if fellBack {
                s.left.reset(numeric: false, scalars: left.unicodeScalars)
                s.right.reset(numeric: false, scalars: right.unicodeScalars)
            } else {
                s.left.reset(numeric: false, source: lIter, first: lNext?.value)
                s.right.reset(numeric: false, source: rIter, first: rNext?.value)
            }
            sink += try! CollationCompare.compareUpToQuaternary(
                &s.left, &s.right, options: opts.icuOptions,
                variableTopValue: vtop, reordering: reorder)
        }
    }
}

measure("P5.nfdDrain    ", ops: pairOps) {
    let s = hoisted
    for _ in 0..<reps {
        for i in 1..<lines.count {
            s.left.scalars.reset(scalars: lines[i - 1].unicodeScalars)
            while let c = s.left.scalars.next() { sink &+= Int(c) }
            s.left.scalars.reset(scalars: lines[i].unicodeScalars)
            while let c = s.left.scalars.next() { sink &+= Int(c) }
        }
    }
}

measure("P6.collectAll  ", ops: pairOps) {
    let s = hoisted
    for _ in 0..<reps {
        for i in 1..<lines.count {
            s.left.reset(numeric: false, scalars: lines[i - 1].unicodeScalars)
            sink += (try! s.left.collectAll()).count
            s.left.reset(numeric: false, scalars: lines[i].unicodeScalars)
            sink += (try! s.left.collectAll()).count
        }
    }
}

// P7: one pass of statistics — how often does the skip-walk's work get
// thrown away (unsafeStart fallback), and how much prefix is there to skip?
do {
    let c = collator
    var pairs = 0, fellBackCount = 0, sharedTotal = 0, sharedPositive = 0
    var scalarTotal = 0
    var unsafeFirstDiff = 0
    for i in 1..<lines.count {
        pairs += 1
        scalarTotal += lines[i].unicodeScalars.count
        var lIter = lines[i - 1].unicodeScalars.makeIterator()
        var rIter = lines[i].unicodeScalars.makeIterator()
        var shared = 0
        var lNext = lIter.next()
        var rNext = rIter.next()
        while let a = lNext, let b = rNext, a == b {
            shared += 1
            lNext = lIter.next()
            rNext = rIter.next()
        }
        let lUnsafe = lNext.map { c.unsafeStart($0.value, numeric: false) } ?? false
        let rUnsafe = rNext.map { c.unsafeStart($0.value, numeric: false) } ?? false
        if lUnsafe || rUnsafe { unsafeFirstDiff += 1 }
        if shared > 0 {
            sharedPositive += 1
            sharedTotal += shared
            if lUnsafe || rUnsafe { fellBackCount += 1 }
        }
    }
    // Deepest safe restart inside the shared prefix: would ICU-style partial
    // backup keep any of the skip? Also: which scalar classes are unsafe?
    var anySafeInPrefix = 0, safeDepthTotal = 0
    for i in 1..<lines.count {
        let l = Array(lines[i - 1].unicodeScalars), r = Array(lines[i].unicodeScalars)
        var shared = 0
        while shared < l.count, shared < r.count, l[shared] == r[shared] { shared += 1 }
        guard shared > 0 else { continue }
        var deepestSafe = 0  // restart index; 0 = full restart
        for j in (0..<shared).reversed() where !c.unsafeStart(l[j].value, numeric: false) {
            deepestSafe = j; break
        }
        if deepestSafe > 0 { anySafeInPrefix += 1; safeDepthTotal += deepestSafe }
    }
    print("P7.safeRestart: prefix pairs with safe j>0: \(anySafeInPrefix), avgDepth(when>0)=\(Double(safeDepthTotal)/Double(max(anySafeInPrefix,1)))")
    for probe in [0x0E01, 0x0E19, 0x0E32, 0x0E40, 0x0E48, 0x0E4C] {
        print("P7.unsafe(U+\(String(probe, radix: 16))): \(c.unsafeStart(UInt32(probe), numeric: false))")
    }
    print("P7.stats: pairs=\(pairs) avgScalars=\(Double(scalarTotal)/Double(pairs))")
    print("P7.stats: shared>0 in \(sharedPositive) (\(100*sharedPositive/pairs)%), avgShared(when>0)=\(Double(sharedTotal)/Double(max(sharedPositive,1)))")
    print("P7.stats: unsafe first-diff in \(unsafeFirstDiff) (\(100*unsafeFirstDiff/pairs)%), fellBack (shared>0 AND unsafe) in \(fellBackCount) (\(100*fellBackCount/pairs)%)")
}

collator.giveScratch(hoisted)
if sink == Int.min { print("") }
