// cjk range-cell attribution: engine-level search on the cjk corpus,
// same needle rule as BenchFoundation. "hold" arg = long-run for sampling.
import Dispatch
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: CJKProbe <corpus> [reps] [hold]") }
let lines = try String(contentsOfFile: args[1], encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
let reps = args.count > 2 ? (Int(args[2]) ?? 300) : 300
let hold = args.contains("hold")
let collator = try! RootCollator()
let needle = lines.count > 1 ? String(lines[1].prefix(4)) : "test"

func measure(_ name: String, ops: Int, _ body: () -> Void) {
    body()
    var best = UInt64.max
    for _ in 0..<(hold ? 10000 : 9) {
        let s = DispatchTime.now().uptimeNanoseconds
        body()
        best = min(best, DispatchTime.now().uptimeNanoseconds - s)
    }
    print("\(name): \(best / UInt64(ops)) ns/op (\(ops) ops)")
}

var sink = 0
var hits = 0
for line in lines { if collator.search(for: needle, in: line) != nil { hits += 1 } }
print("corpus: \(lines.count) lines, needle \"\(needle)\", hits \(hits)")

measure("engine.search    ", ops: lines.count * reps) {
    let c = collator
    for _ in 0..<reps {
        for line in lines {
            if let r = c.search(for: needle, in: line) {
                sink += line.distance(from: r.lowerBound, to: r.upperBound)
            }
        }
    }
}
if sink == Int.min { print("") }
