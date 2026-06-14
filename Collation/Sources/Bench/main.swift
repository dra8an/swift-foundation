// Benchmark harness: measures compare() and sortKey() throughput over a
// corpus file (one string per line). Counterpart: Tools/bench_icu.c.
//
// Usage: swift run -c release Bench <corpus.txt> [reps]

import Dispatch
import Foundation
import Collation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: Bench <corpus.txt> [reps] [tailoring]\n".utf8))
    exit(2)
}
let lines = try String(contentsOfFile: arguments[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true)
    .map(String.init)
let reps = arguments.count > 2 ? Int(arguments[2])! : 200

// Optional 3rd arg selects a bundled tailoring (e.g. "th"); default is root.
let collator = arguments.count > 3
    ? try RootCollator(tailoringNamed: arguments[3]) : try RootCollator()
let options = collator.defaultOptions

func measure(_ name: String, ops: Int, _ body: () throws -> Void) rethrows {
    // Warmup.
    try body()
    let start = DispatchTime.now().uptimeNanoseconds
    try body()
    let ns = DispatchTime.now().uptimeNanoseconds - start
    print("\(name): \(ns / UInt64(ops)) ns/op (\(ops) ops)")
}

var sink = 0

try measure("compare ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += try collator.compare(lines[i - 1], lines[i], options: options).rawValue
        }
    }
}

try measure("sortKey ", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            sink += try collator.sortKey(for: line, options: options).count
        }
    }
}

if sink == Int.min { print("") }  // keep the work observable
