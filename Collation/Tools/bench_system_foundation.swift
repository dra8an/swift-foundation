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

// Warm-up, not measured (technique log §51 (aw)). Swift initializes each `static let` once
// (swift_once; dispatch_once on Apple platforms). For the next ~16-28 ms, until the kernel's
// quiescent count of the CPUs moves on, each read of such a global takes the out-of-line
// dispatch_once_f call. A Foundation call reads two of them, so the first rows of a run read up
// to ~6 ns slow, on a level that changed from run to run. Each API runs once here, then the short
// calls run for 100 ms: busy, not asleep, so that the CPU clock stays up. The system bench
// (Tools/bench_system_foundation.swift) has the same block.
struct WarmItem { let name: String }
do {
    let warmEnd = DispatchTime.now().uptimeNanoseconds + 100_000_000
    let a = lines[0], b = lines.count > 1 ? lines[1] : lines[0]
    let w = String(b.prefix(4))
    sink += a.compare(b, locale: locale).rawValue + a.localizedCompare(b).rawValue
    sink += a.localizedStandardCompare(b).rawValue + a.localizedCaseInsensitiveCompare(b).rawValue
    sink += a.compare(b, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: locale).rawValue
    sink += (a.localizedStandardContains(w) ? 1 : 0) + (a.localizedCaseInsensitiveContains(w) ? 1 : 0)
    sink += a.localizedStandardRange(of: w) == nil ? 0 : 1
    sink += a.range(of: w, options: [], locale: locale) == nil ? 0 : 1
    sink += a.range(of: w, options: [.backwards], locale: locale) == nil ? 0 : 1
    let few = Array(lines.prefix(16))
    let fewItems = few.map { WarmItem(name: $0) }
    sink += few.sorted(using: String.StandardComparator.localizedStandard).count
    sink += few.sorted(using: String.Comparator(options: [], locale: locale)).count
    sink += fewItems.sorted(using: KeyPathComparator(\WarmItem.name, comparator: String.StandardComparator.localizedStandard)).count
    sink += fewItems.sorted(using: SortDescriptor(\WarmItem.name, comparator: String.StandardComparator.localizedStandard)).count
    while DispatchTime.now().uptimeNanoseconds < warmEnd {
        for i in 1..<max(2, min(lines.count, 2000)) {
            let x = lines[i - 1], y = lines[min(i, lines.count - 1)]
            sink += x.compare(y, locale: locale).rawValue + x.localizedCompare(y).rawValue
            sink += x.localizedStandardCompare(y).rawValue + x.localizedCaseInsensitiveCompare(y).rawValue
        }
    }
}

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
