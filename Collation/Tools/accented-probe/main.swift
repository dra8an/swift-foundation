// nfdMap attribution: engine-level search on decomposing (accented) text
// WITH a real match candidate — the only workload where confirmMatch builds
// the NFD→source map. Variants:
//   A end:    needle = line.suffix(8)  — full CE scan, match, map build
//   B start:  needle = line.prefix(8)  — instant match, map still built (whole line)
//   C absent: needle = "qqqqqqqq"      — full CE scan, no match, NO map (control)
// "hold A|B|C" = long-run one variant for sampling.
import Dispatch
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: AccentedProbe <corpus> [reps] [hold A|B|C]") }
let lines = try String(contentsOfFile: args[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
let reps = args.count > 2 ? (Int(args[2]) ?? 300) : 300
let holdVariant: String? = args.firstIndex(of: "hold").flatMap {
    $0 + 1 < args.count ? args[$0 + 1] : nil
}
let collator = try! RootCollator()

let endNeedles = lines.map { String($0.suffix(8)) }
let startNeedles = lines.map { String($0.prefix(8)) }
let absentNeedle = "qqqqqqqq"

// Hook verification by OUTPUT ROWS (§40 rule): prove the match/no-match
// premise of each variant before timing anything.
var hitsA = 0, hitsB = 0, hitsC = 0
for (i, line) in lines.enumerated() {
    if collator.search(for: endNeedles[i], in: line) != nil { hitsA += 1 }
    if collator.search(for: startNeedles[i], in: line) != nil { hitsB += 1 }
    if collator.search(for: absentNeedle, in: line) != nil { hitsC += 1 }
}
print("corpus: \(lines.count) lines | hits A(end)=\(hitsA) B(start)=\(hitsB) C(absent)=\(hitsC)")
guard hitsA == lines.count, hitsB == lines.count, hitsC == 0 else {
    fatalError("variant premise broken — fix the workload before timing")
}

var sink = 0
@MainActor func measure(_ name: String, _ body: () -> Void) {
    body()
    var best = UInt64.max
    for _ in 0..<9 {
        let s = DispatchTime.now().uptimeNanoseconds
        body()
        best = min(best, DispatchTime.now().uptimeNanoseconds - s)
    }
    print("\(name): \(best / UInt64(lines.count * reps)) ns/op (\(lines.count * reps) ops)")
}

@MainActor func runA() {
    let c = collator
    for _ in 0..<reps {
        for (i, line) in lines.enumerated() {
            if let r = c.search(for: endNeedles[i], in: line) {
                sink += line.distance(from: r.lowerBound, to: r.upperBound)
            }
        }
    }
}
@MainActor func runB() {
    let c = collator
    for _ in 0..<reps {
        for (i, line) in lines.enumerated() {
            if let r = c.search(for: startNeedles[i], in: line) {
                sink += line.distance(from: r.lowerBound, to: r.upperBound)
            }
        }
    }
}
@MainActor func runC() {
    let c = collator
    for _ in 0..<reps {
        for line in lines {
            if c.search(for: absentNeedle, in: line) != nil { sink += 1 }
        }
    }
}

if let v = holdVariant {
    print("holding variant \(v) for sampling…")
    for _ in 0..<10000 {
        switch v {
        case "A": runA()
        case "B": runB()
        default: runC()
        }
    }
} else {
    measure("A end-match   ", runA)
    measure("B start-match ", runB)
    measure("C absent      ", runC)
}
if sink == Int.min { print("") }
