// Engine-only benchmark: RootCollator compare/sortKey with no Foundation
// APIs and no Locale — so it builds and runs FULL-WMO even on machine 1,
// where the whole-module BenchFoundation executable SIGILLs in the Locale
// dynamic-replacement path (Docs/25 build note). Assembled into a scratch
// package by Tools/build_engine_bench.sh; Table 1 of bench_matrix.py runs
// this binary, Table 2 keeps BenchFoundation (no-WMO on machine 1).

import Dispatch
import CollEngine
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: EngineBench <corpus> [reps]") }
let lines = try String(contentsOfFile: args[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
let reps = args.count > 2 ? (Int(args[2]) ?? 200) : 200
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
    // One decimal: whole nanoseconds made one rounding step 6% of the 16 ns ascii compare row.
    print("\(name): \(String(format: "%.1f", Double(best) / Double(ops))) ns/op (\(ops) ops)")
}

var sink = 0

// Each timed loop reads local copies and adds into a local sum. `lines`, `opts` and `sink` are top-level variables of
// this file, that is, globals: through a global, the compiler loads the array again, packs the options again and
// stores the sum on every pass. With the globals, the compare loop had 42 instructions around one call (13 in the C
// loop of bench_icu) and cost 1.2 to 1.5 ns of a 9 ns compare (technique log §52 (k)). A caller with local values
// does not pay that. Check the loop after a change of this file or of the compiler: Tools/insn-count/loop_check.sh.

measure("RootCollator.cmp  ", ops: (lines.count - 1) * reps) {
    let c = collator, ls = lines, o = opts
    var sum = 0
    for _ in 0..<reps {
        for i in 1..<ls.count {
            // The tag byte of the result, not `.rawValue`: `Order` is a package type of another module, so its
            // `rawValue` getter is a call from this file (and only from here; Foundation's callers are in the
            // engine's module). A `switch` would add a branch on the result, which the processor mispredicts.
            sum &+= Int(unsafeBitCast(try! c.compare(ls[i - 1], ls[i], options: o), to: UInt8.self))
        }
    }
    sink &+= sum
}

measure("RootCollator.sk   ", ops: lines.count * reps) {
    let c = collator, ls = lines, o = opts
    var key: [UInt8] = []
    var sum = 0
    for _ in 0..<reps {
        for line in ls {
            try! c.sortKey(for: line, into: &key, options: o)
            sum &+= key.count
        }
    }
    sink &+= sum
}

measure("RootCollator.skRet", ops: lines.count * reps) {
    let c = collator, ls = lines, o = opts
    var sum = 0
    for _ in 0..<reps {
        for line in ls {
            sum &+= (try! c.sortKey(for: line, options: o)).count
        }
    }
    sink &+= sum
}

if sink == Int.min { print("") }
