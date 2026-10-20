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

measure("localizedCaseICmp ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].localizedCaseInsensitiveCompare(lines[i]).rawValue
        }
    }
}

let needle = lines.count > 1 ? String(lines[1].prefix(4)) : "test"

measure("localizedCaseICnt ", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            sink += line.localizedCaseInsensitiveContains(needle) ? 1 : 0
        }
    }
}

measure("localizedStdContns", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            sink += line.localizedStandardContains(needle) ? 1 : 0
        }
    }
}

measure("localizedStdRange ", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            if let r = line.localizedStandardRange(of: needle) {
                sink += line.distance(from: r.lowerBound, to: r.upperBound)
            }
        }
    }
}

measure("range(of:locale:) ", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            if let r = line.range(of: needle, options: [], locale: locale) {
                sink += line.distance(from: r.lowerBound, to: r.upperBound)
            }
        }
    }
}

measure("range(backwards)  ", ops: lines.count * reps) {
    for _ in 0..<reps {
        for line in lines {
            if let r = line.range(of: needle, options: [.backwards], locale: locale) {
                sink += line.distance(from: r.lowerBound, to: r.upperBound)
            }
        }
    }
}

// 8. compare(_:options:range:locale:) with non-default options — the options-translation path
measure("compare(opts:loc:) ", ops: (lines.count - 1) * reps) {
    for _ in 0..<reps {
        for i in 1..<lines.count {
            sink += lines[i - 1].compare(lines[i], options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: locale).rawValue
        }
    }
}

// 9. The sorting APIs: one op is one ELEMENT of a sort (a sort of n lines makes about n·log2(n) comparisons). Each pass sorts max(1, reps / 50) times, so thai (~33k lines, 10 reps) sorts once.
struct Item { let name: String }
let items = lines.map { Item(name: $0) }
let sorts = max(1, reps / 50)

measure("sortStdComparator ", ops: lines.count * sorts) {
    for _ in 0..<sorts {
        sink += lines.sorted(using: String.StandardComparator.localizedStandard).count
    }
}

measure("sortCmp(locale)   ", ops: lines.count * sorts) {
    let comparator = String.Comparator(options: [], locale: locale)
    for _ in 0..<sorts {
        sink += lines.sorted(using: comparator).count
    }
}

measure("sortKeyPathCmp    ", ops: lines.count * sorts) {
    let comparator = KeyPathComparator(\Item.name, comparator: String.StandardComparator.localizedStandard)
    for _ in 0..<sorts {
        sink += items.sorted(using: comparator).count
    }
}

measure("sortSortDescriptor", ops: lines.count * sorts) {
    let descriptor = SortDescriptor(\Item.name, comparator: String.StandardComparator.localizedStandard)
    for _ in 0..<sorts {
        sink += items.sorted(using: descriptor).count
    }
}

if sink == Int.min { print("") }
