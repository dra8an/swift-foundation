// §47 discontiguous-contraction probe: which corpus lines reach the UTS #10
// S2.1.3 "remove C" branch, and are the POSITIONS the search APIs report for
// them correct?
//
// Why a probe and not just a test: the branch is invisible from the outside.
// It fires on 84 of the 206268 UCA conformance lines, produces perfect CEs and
// perfect sort keys every time, and no ordering or key-byte gate can see it —
// which is how §46(b) survived 1500 tests. The build script splices a hit
// counter into `removeAhead` so this probe can identify the firing lines,
// then checks each one three ways.
//
// A discontiguous match consumes a NON-CONTIGUOUS set of scalars (it reaches
// across the marks it skipped), so the two things that broke were: the scalar
// COUNT, which ignored the out-of-order consumption and drifted for the rest
// of the string (§46(b)), and the reported END of a match that finishes at
// such a contraction, which excluded the far-side scalar (§47). Both are
// position-only defects.
//
//   Collation/Tools/build_disc_probe.sh
//   $(...) <corpus> [--hex] [--limit N]
//
// --hex reads the conformance format (space-separated hex scalars, # comments)
// instead of plain UTF-8 lines. Exits non-zero if any check fails.
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    fatalError("usage: DiscProbe <corpus> [--hex] [--limit N]")
}
let hexFormat = args.contains("--hex")
let limit: Int = {
    guard let i = args.firstIndex(of: "--limit"), i + 1 < args.count else { return 200 }
    return Int(args[i + 1]) ?? 200
}()

let content = try String(contentsOfFile: args[1], encoding: .utf8)
var lines: [String] = []
var unrepresentable = 0
for raw in content.split(separator: "\n", omittingEmptySubsequences: true) {
    if hexFormat {
        if raw.hasPrefix("#") { continue }
        var s = ""
        var ok = true
        for hex in raw.split(separator: " ") {
            guard let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) else {
                ok = false  // unpaired surrogate: not representable as a Swift String
                break
            }
            s.unicodeScalars.append(scalar)
        }
        if ok { lines.append(s) } else { unrepresentable += 1 }
    } else {
        lines.append(String(raw))
    }
}

let collator = try! RootCollator()

func hex(_ s: String) -> String {
    s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
}

// Which lines reach the branch? The counter only moves when S2.1.3 fires.
var firing: [String] = []
for line in lines {
    let before = DiscProbeCounter.hits
    _ = try! collator.sortKey(for: line)
    if DiscProbeCounter.hits > before { firing.append(line) }
}
print("corpus: \(lines.count) lines\(unrepresentable > 0 ? " (\(unrepresentable) skipped: unpaired surrogates)" : "")")
print("  reach S2.1.3 'remove C': \(firing.count) lines, \(DiscProbeCounter.hits) hits")
guard !firing.isEmpty else {
    print("  no discontiguous contractions in this corpus — nothing to check.")
    print("  (Golden/fuzz-corpus.txt is in that category; see the gen_fuzz_corpus.py")
    print("   coverage gap on the audit list.)")
    exit(0)
}

// Per-CE NFD spans for the first few, the diagnostic view: a discontiguous
// contraction's span is the convex hull of its non-contiguous consumed set,
// so it OVERLAPS the span of the skipped mark that follows it.
print("  spans (first \(min(5, firing.count)) firing lines):")
for line in firing.prefix(5) {
    var iter = CEIterator(data: collator.data, base: collator.base, norm: collator.norm,
                          numeric: false, scalars: line.unicodeScalars)
    var spans: [String] = []
    while try! iter.appendMore() { spans.append("[\(iter.spanStart),\(iter.spanEnd))") }
    var nfd = NFDIterator(norm: collator.norm, scalars: line.unicodeScalars)
    var nfdCount = 0
    while nfd.next() != nil { nfdCount += 1 }
    let counted = iter.scalarsConsumed == nfdCount ? "ok" : "DRIFT \(iter.scalarsConsumed) vs \(nfdCount)"
    print("    \(hex(line))  spans=\(spans.joined(separator: " ")) count=\(counted)")
}

// Three position checks per firing line.
let sentinel = "\u{2603}zq"   // snowman + ASCII: cannot collide with mark/Cyrillic/Arabic corpora
var checked = 0
var failScalarCount = 0, failAfter = 0, failSelf = 0, failRoundTrip = 0

for line in firing.prefix(limit) {
    checked += 1

    // 1. The scalar count must equal the NFD scalar count — the §46(b) invariant,
    //    and the one PositionInvariantTests runs over whole corpora.
    var iter = CEIterator(data: collator.data, base: collator.base, norm: collator.norm,
                          numeric: false, scalars: line.unicodeScalars)
    _ = try! iter.collectAll()
    var nfd = NFDIterator(norm: collator.norm, scalars: line.unicodeScalars)
    var nfdCount = 0
    while nfd.next() != nil { nfdCount += 1 }
    if iter.scalarsConsumed != nfdCount {
        failScalarCount += 1
        if failScalarCount <= 5 {
            print("  COUNT   \(hex(line)): consumed \(iter.scalarsConsumed), NFD has \(nfdCount)")
        }
    }

    // 2. A match placed AFTER the contraction must be reported at its true
    //    offset (§46(b): the count drifted, so it was short by one and the
    //    range was rejected outright — 27 of 40 came back nil).
    let after = line + sentinel
    let expectedAfter = after.unicodeScalars.index(
        after.unicodeScalars.startIndex,
        offsetBy: after.unicodeScalars.count - sentinel.unicodeScalars.count)..<after.endIndex
    let gotAfter = collator.search(for: sentinel, in: after)
    if gotAfter != expectedAfter {
        failAfter += 1
        if failAfter <= 5 {
            print("  AFTER   \(hex(line)): expected \(expectedAfter), got \(gotAfter.map(String.init(describing:)) ?? "nil")")
        }
    }

    // 3. A match ENDING at the contraction — self-search must cover the whole
    //    string (§47: the last CE's end excluded the far-side scalar, landed
    //    mid-combining-sequence, and boundary validation rejected it).
    let gotSelf = collator.search(for: line, in: line)
    if gotSelf != line.startIndex..<line.endIndex {
        failSelf += 1
        if failSelf <= 5 {
            print("  SELF    \(hex(line)): got \(gotSelf.map(String.init(describing:)) ?? "nil")")
        }
    }

    // 4. Content round-trip: whatever range comes back must collate equal to
    //    the pattern. Catches misalignment regardless of cause.
    if let r = gotSelf, (try! collator.compare(String(line[r]), line)) != .same {
        failRoundTrip += 1
    }
}

let failures = failScalarCount + failAfter + failSelf + failRoundTrip
print("  checked \(checked) firing lines: scalar-count \(failScalarCount), match-after \(failAfter), self-search \(failSelf), round-trip \(failRoundTrip)")
if failures == 0 {
    print("  all position checks pass.")
} else {
    print("  \(failures) POSITION FAILURES")
    exit(1)
}
