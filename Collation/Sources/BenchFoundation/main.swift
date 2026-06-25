// Benchmark: Foundation string comparison APIs.
//
// Measures the same Foundation APIs (localizedCompare, String.Comparator,
// localizedStandardContains, compare(_:locale:)) that end users call.
//
// In the SwiftPM build these route through our Swift collator.
// A companion standalone script (bench_system_foundation.swift) calls the
// same APIs through the system Foundation (NSString → ICU) for comparison.
//
// Usage: swift run -c release BenchFoundation <corpus.txt> [reps]

import Dispatch
import FoundationEssentials
import FoundationInternationalization

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: BenchFoundation <corpus.txt> [reps]\n", stderr)
    exit(2)
}
let lines = try String(contentsOfFile: arguments[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true)
    .map(String.init)
let reps = arguments.count > 2 ? (Int(arguments[2]) ?? 200) : 200

let locale = Locale(identifier: "en")
let collator = try! RootCollator()
let defaultOpts = collator.defaultOptions

func measure(_ name: String, ops: Int, _ body: () -> Void) {
    body()
    var best = UInt64.max
    for _ in 0..<9 {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        best = min(best, DispatchTime.now().uptimeNanoseconds - start)
    }
    print("\(name): \(best / UInt64(ops)) ns/op (\(ops) ops)")
}

var sink = 0

// 0. Direct RootCollator.compare — cross-module baseline
measure("RootCollator.cmp  ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += (try! collator.compare(lines[i - 1], lines[i], options: defaultOpts)).rawValue
        }
    }
}

// 0b. Direct RootCollator.sortKey — pure-engine baseline vs ucol_getSortKey
measure("RootCollator.sk   ", ops: lines.count * reps) {
    var key: [UInt8] = []
    for _ in 0..<reps {
        for line in lines {
            try! collator.sortKey(for: line, into: &key, options: defaultOpts)
            sink += key.count
        }
    }
}

// 1. compare(_:locale:)
measure("compare(locale:)  ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].compare(lines[i], locale: locale).rawValue
        }
    }
}

// 2. localizedCompare
measure("localizedCompare  ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].localizedCompare(lines[i]).rawValue
        }
    }
}

// 3. localizedStandardCompare
measure("localizedStdCmp   ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].localizedStandardCompare(lines[i]).rawValue
        }
    }
}

// 4. localizedStandardContains
let needle = lines.count > 1 ? String(lines[1].prefix(4)) : "test"
measure("localizedStdContns", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            sink += line.localizedStandardContains(needle) ? 1 : 0
        }
    }
}

if sink == Int.min { print("") }
