// Day-level parity sweep: the Duffett-Smith port vs macOS system ICU
// (Calendar(identifier: .chinese)). Expected: 0 divergent days everywhere.

import Foundation
import AstronomicalEngine

func gregYear(ofEpochDay day: Int) -> Int {
    var y = Int(Double(day) / 365.2425) + 1970
    while ChineseAstro.gregorianEpochDay(y, 1, 1) > day { y -= 1 }
    while ChineseAstro.gregorianEpochDay(y + 1, 1, 1) <= day { y += 1 }
    return y
}

var icuCal = Calendar(identifier: .chinese)
icuCal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

let astro = ChineseAstro()
let ranges = [(1500, 1700), (1900, 2100), (2150, 2350)]
var totalDays = 0
var totalDiffs = 0

for (y1, y2) in ranges {
    let from = ChineseAstro.gregorianEpochDay(y1, 1, 1)
    let to = ChineseAstro.gregorianEpochDay(y2, 12, 31)
    var diffs = 0
    var examples: [String] = []
    let t0 = ProcessInfo.processInfo.systemUptime

    var inRun = false
    for day in from...to {
        let gyear = gregYear(ofEpochDay: day)
        let info = astro.computeMonthInfo(gyear: gyear, days: day)
        let ourMonth = info.month
        let ourDom = day - info.thisMoon + 1
        let ourLeap = info.isLeapMonth

        let date = Date(timeIntervalSince1970: Double(day) * 86400.0 + 4 * 3600.0)
        let c = icuCal.dateComponents([.month, .day, .isLeapMonth], from: date)

        if c.month != ourMonth || c.day != ourDom || (c.isLeapMonth ?? false) != ourLeap {
            diffs += 1
            if !inRun {
                inRun = true
                examples.append("run from day \(day) (greg \(gyear)): ours m\(ourMonth)\(ourLeap ? "L" : "") d\(ourDom), icu m\(c.month!)\((c.isLeapMonth ?? false) ? "L" : "") d\(c.day!)")
            }
        } else {
            inRun = false
        }
    }

    let elapsed = ProcessInfo.processInfo.systemUptime - t0
    let n = to - from + 1
    totalDays += n
    totalDiffs += diffs
    print("\(y1)-\(y2): \(diffs) divergent days / \(n)  (\(String(format: "%.1f", elapsed))s)")
    for e in examples { print("   \(e)") }
}

print("\nTOTAL vs system ICU: \(totalDiffs) divergent days / \(totalDays)")

// Port vs HKO authority (month starts, 1901-2099)
let hkoPath = "/Users/draganbesevic/Projects/claude/CalendarAPI/icu4swift/Tests/CalendarAstronomicalTests/chinese_months_1901_2100_hko.csv"
let text = try! String(contentsOfFile: hkoPath, encoding: .utf8)
var hkoChecked = 0
var hkoBad = 0
for line in text.split(separator: "\n").dropFirst() {
    let f = line.split(separator: ",").map { String($0) }
    guard f.count >= 7, let iso = Int(f[0]), iso <= 2099 else { continue }
    let startDay = ChineseAstro.gregorianEpochDay(Int(f[4])!, Int(f[5])!, Int(f[6])!)
    let info = astro.computeMonthInfo(gyear: gregYear(ofEpochDay: startDay), days: startDay)
    hkoChecked += 1
    let dom = startDay - info.thisMoon + 1
    if info.month != Int(f[1])! || (f[2] == "1") != info.isLeapMonth || dom != 1 {
        hkoBad += 1
        if hkoBad <= 12 {
            print("HKO mismatch: \(f[0])-m\(f[1])\(f[2] == "1" ? "L" : "") starts \(f[4])-\(f[5])-\(f[6]): port says m\(info.month)\(info.isLeapMonth ? "L" : "") d\(dom)")
        }
    }
}
print("Port vs HKO month starts: \(hkoBad) mismatches / \(hkoChecked)")

// ---- EXPERIMENT: chnsecal RULES + Reingold instants vs system ICU ----
// If this matches ICU's labels at the contested leap-placement years, the
// CNY-month pathologies are icu4swift's findNewYear heuristic, not Reingold.
print("\n### chnsecal-rules + Reingold instants vs system ICU")

func gregStr(_ day: Int) -> String {
    let y = gregYear(ofEpochDay: day)
    var m = 1
    while m < 12 && ChineseAstro.gregorianEpochDay(y, m + 1, 1) <= day { m += 1 }
    let d = day - ChineseAstro.gregorianEpochDay(y, m, 1) + 1
    return "\(y)-\(String(format: "%02d", m))-\(String(format: "%02d", d))"
}

func icuYears(_ cal: Calendar, gregFrom: Int, gregTo: Int) -> [Int: [(num: Int, leap: Bool, start: Int)]] {
    var events: [(num: Int, leap: Bool, day: Int)] = []
    var day = ChineseAstro.gregorianEpochDay(gregFrom, 1, 1)
    let end = ChineseAstro.gregorianEpochDay(gregTo, 3, 10)
    while day <= end {
        let date = Date(timeIntervalSince1970: Double(day) * 86400.0 + 4 * 3600.0)
        let c = cal.dateComponents([.month, .day, .isLeapMonth], from: date)
        if c.day == 1 {
            events.append((c.month!, c.isLeapMonth ?? false, day))
            day += 25
        } else if c.day! < 25 {
            day += 29 - c.day!
        } else {
            day += 1
        }
    }
    var out: [Int: [(num: Int, leap: Bool, start: Int)]] = [:]
    var group: [(num: Int, leap: Bool, day: Int)] = []
    for ev in events {
        if ev.num == 1 && !ev.leap {
            if group.count >= 12 {
                out[gregYear(ofEpochDay: group[0].day)] = group.map { ($0.num, $0.leap, $0.day) }
            }
            group = [ev]
        } else if !group.isEmpty {
            group.append(ev)
        }
    }
    return out
}

let ra = ReingoldChineseAstro()
func rulesYears(_ ra: ReingoldChineseAstro, gregFrom: Int, gregTo: Int) -> [Int: [(num: Int, leap: Bool, start: Int)]] {
    var out: [Int: [(num: Int, leap: Bool, start: Int)]] = [:]
    for gy in gregFrom...gregTo {
        let ny = ra.newYear(gy)
        let nyNext = ra.newYear(gy + 1)
        var starts = [ny]
        var cur = ny
        while true {
            let nxt = ra.newMoonNear(Double(cur + 25), true)
            if nxt >= nyNext { break }
            starts.append(nxt)
            cur = nxt
        }
        out[gy] = starts.map { s in
            let info = ra.computeMonthInfo(gyear: gregYear(ofEpochDay: s), days: s)
            return (info.month, info.isLeapMonth, s)
        }
    }
    return out
}

func labels(_ rows: [(num: Int, leap: Bool, start: Int)]) -> String {
    rows.map { "m\($0.num)\($0.leap ? "L" : "")" }.joined(separator: " ")
}

for (lo, hi) in [(1700, 1899), (2101, 2150)] {
    let icuY = icuYears(icuCal, gregFrom: lo - 1, gregTo: hi + 2)
    let rulY = rulesYears(ra, gregFrom: lo, gregTo: hi)
    var cleanYears = 0, labelDiff = 0, startDiffs = 0, comparedYears = 0, comparedStarts = 0
    for y in lo...hi {
        guard let ri = icuY[y], let rr = rulY[y] else { continue }
        comparedYears += 1
        var clean = true
        if labels(ri) != labels(rr) || ri.count != rr.count {
            labelDiff += 1
            clean = false
            print("  LABEL DIFF \(y): rules [\(labels(rr))] icu [\(labels(ri))]")
        } else {
            for i in 0..<ri.count {
                comparedStarts += 1
                if ri[i].start != rr[i].start {
                    startDiffs += 1
                    clean = false
                }
            }
        }
        if clean { cleanYears += 1 }
    }
    print("  \(lo)-\(hi): years \(comparedYears), fully clean \(cleanYears), label-diff years \(labelDiff), ±day start diffs \(startDiffs)/\(comparedStarts)")
}

print("\n### Focus years, chnsecal-rules + Reingold")
for y in [1775, 1776, 1794, 1795, 1813, 1814, 1870, 1871, 1889, 1890, 2147, 2148] {
    let rul = rulesYears(ra, gregFrom: y, gregTo: y)[y]!
    print("  \(y): \(rul.map { "m\($0.num)\($0.leap ? "L" : "")@\(gregStr($0.start))" }.joined(separator: " "))")
}

print("\n### Decider zhongqi instants (UTC+8), Reingold vs Moshier")
let reinE = ReingoldEngine()
let moshE = MoshierEngine()
let deciderCases: [(Int, Int, Int, Double, String)] = [
    (1727, 4, 18, 30.0, "Guyu λ=30 decides m2L-vs-m3L; boundary Apr 21 00:00"),
    (1800, 6, 19, 90.0, "Xiazhi λ=90 decides m4L-vs-m5L; boundary Jun 22 00:00"),
    (1805, 8, 21, 150.0, "Chushu λ=150 decides m6L-vs-m7L; boundary Aug 24 00:00"),
    (1827, 7, 21, 120.0, "Dashu λ=120 decides m5L-vs-m6L; boundary Jul 24 00:00"),
]
for (y, m, d, target, desc) in deciderCases {
    for (name, eng) in [("rein", reinE as any AstronomicalEngineProtocol), ("mosh", moshE)] {
        var lo = Moment(Double(ChineseAstro.gregorianEpochDay(y, m, d) + 719_163)) - 8.0 / 24.0
        var hi = lo + 6.0
        for _ in 0..<48 {
            let mid = Moment((lo.inner + hi.inner) / 2)
            if eng.solarLongitude(at: mid) < target { lo = mid } else { hi = mid }
        }
        let localInner = lo.inner + 8.0 / 24.0
        let day = Int(localInner.rounded(.down)) - 719_163
        let frac = localInner - localInner.rounded(.down)
        let hh = Int(frac * 24.0)
        let mm = Int((frac * 1440.0).truncatingRemainder(dividingBy: 60.0))
        print("  \(y) \(name): \(gregStr(day)) \(String(format: "%02d:%02d", hh, mm)) — \(desc)")
    }
}

print("\n### Adjudication targets 1727/1800/1805/1827: rules vs ICU with dates")
let adjIcu = icuYears(icuCal, gregFrom: 1726, gregTo: 1829)
for y in [1727, 1800, 1805, 1827] {
    let rul = rulesYears(ra, gregFrom: y, gregTo: y)[y]!
    print("  \(y) rules: \(rul.map { "m\($0.num)\($0.leap ? "L" : "")@\(gregStr($0.start))" }.joined(separator: " "))")
    if let ic = adjIcu[y] {
        print("  \(y) icu  : \(ic.map { "m\($0.num)\($0.leap ? "L" : "")@\(gregStr($0.start))" }.joined(separator: " "))")
    }
}
