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
    print("\(name): \(best / UInt64(ops)) ns/op (\(ops) ops)")
}

var sink = 0

measure("RootCollator.cmp  ", ops: (lines.count - 1) * reps) {
    let c = collator
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += (try! c.compare(lines[i - 1], lines[i], options: opts)).rawValue
        }
    }
}

measure("RootCollator.sk   ", ops: lines.count * reps) {
    let c = collator
    var key: [UInt8] = []
    for _ in 0..<reps {
        for line in lines {
            try! c.sortKey(for: line, into: &key, options: opts)
            sink += key.count
        }
    }
}

measure("RootCollator.skRet", ops: lines.count * reps) {
    let c = collator
    for _ in 0..<reps {
        for line in lines {
            sink += (try! c.sortKey(for: line, options: opts)).count
        }
    }
}

if sink == Int.min { print("") }
