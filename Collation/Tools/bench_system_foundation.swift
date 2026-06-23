#!/usr/bin/env swift
// Benchmark: System Foundation string comparison APIs (NSString → ICU).
//
// This standalone script uses the system Foundation framework, NOT the
// SwiftPM FoundationEssentials. Run it directly with `swift` (not via
// `swift run`) so it links the system Foundation.
//
// Usage: swift bench_system_foundation.swift <corpus.txt> [reps]

import Foundation
import Dispatch

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift bench_system_foundation.swift <corpus.txt> [reps]\n".utf8))
    exit(2)
}
let lines = try String(contentsOfFile: arguments[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true)
    .map(String.init)
let reps = arguments.count > 2 ? (Int(arguments[2]) ?? 200) : 200

let locale = Locale(identifier: "en")

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

measure("compare(locale:)  ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].compare(lines[i], locale: locale).rawValue
        }
    }
}

measure("localizedCompare  ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].localizedCompare(lines[i]).rawValue
        }
    }
}

measure("localizedStdCmp   ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].localizedStandardCompare(lines[i]).rawValue
        }
    }
}

let needle = lines.count > 1 ? String(lines[1].prefix(4)) : "test"
measure("localizedStdContns", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            sink += line.localizedStandardContains(needle) ? 1 : 0
        }
    }
}

if sink == Int.min { print("") }
