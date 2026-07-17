// chncmp — compare Chinese calendar year structures across engines:
//   * Reingold (Meeus polynomials, icu4swift ReingoldEngine)
//   * Moshier (VSOP87/DE404, icu4swift MoshierEngine)
//   * ICU4C Duffett-Smith (via macOS Foundation Calendar(identifier: .chinese))
//   * HKO authoritative CSV (1901-2100) as ground truth in range
//
// The year-structure algorithm is a faithful copy of icu4swift's
// ChineseYearData.compute (ChineseCalendar.swift:380-507), parameterized by
// engine + UTC-offset function so we can isolate ephemeris vs meridian effects.

import Foundation
import CalendarCore
import CalendarSimple
import AstronomicalEngine

// MARK: - Offsets

let lmtCutoff = GregorianArithmetic.fixedFromGregorian(year: 1929, month: 1, day: 1).dayNumber

func offsetChina(_ rd: Int64) -> Double {
    // icu4swift shipping convention: Beijing LMT before 1929, UTC+8 after.
    rd < lmtCutoff ? 1397.0 / 180.0 / 24.0 : 8.0 / 24.0
}

func offsetUTC8(_ rd: Int64) -> Double { 8.0 / 24.0 }

// MARK: - Year structure

struct YearStruct {
    let relatedIso: Int32
    let newYear: Int64
    let monthLengths: [Bool]   // true = 30 days
    let leapMonth: UInt8?      // display number the leap duplicates (icu4swift convention)

    // Rows: (displayNum, isLeap, startRD, length)
    var rows: [(num: Int, leap: Bool, start: Int64, len: Int)] {
        var out: [(Int, Bool, Int64, Int)] = []
        var start = newYear
        for ordinal in 1...monthLengths.count {
            let len = monthLengths[ordinal - 1] ? 30 : 29
            let (num, leap): (Int, Bool)
            if let lm = leapMonth {
                let leapOrdinal = Int(lm) + 1
                if ordinal == leapOrdinal { (num, leap) = (Int(lm), true) }
                else if ordinal > leapOrdinal { (num, leap) = (ordinal - 1, false) }
                else { (num, leap) = (ordinal, false) }
            } else {
                (num, leap) = (ordinal, false)
            }
            out.append((num, leap, start, len))
            start += Int64(len)
        }
        return out
    }
}

// MARK: - compute() copy (parameterized)

func computeYear(
    engine: any AstronomicalEngineProtocol,
    relatedIso: Int32,
    offset: (Int64) -> Double
) -> YearStruct {
    let jan1 = GregorianArithmetic.fixedFromGregorian(year: relatedIso, month: 1, day: 1)

    func midnight(_ rd: RataDie) -> Moment {
        Moment(Double(rd.dayNumber)) - offset(rd.dayNumber)
    }

    func newMoonOnOrAfter(_ rd: RataDie) -> RataDie {
        let nmMoment = engine.newMoonAtOrAfter(midnight(rd))
        let off = offset(nmMoment.rataDie.dayNumber)
        let local = (nmMoment + off).inner
        let frac = local - local.rounded(.down)
        if frac < 1e-4 {
            return RataDie(Int64(local.rounded(.down)) - 1)
        }
        return RataDie(Int64(local.rounded(.down)))
    }

    func newMoonOnOrBefore(_ rd: RataDie) -> RataDie {
        var nm = newMoonOnOrAfter(RataDie(rd.dayNumber - 35))
        while true {
            let next = newMoonOnOrAfter(RataDie(nm.dayNumber + 1))
            if next.dayNumber > rd.dayNumber { return nm }
            nm = next
        }
    }

    func solarLongitudeAt(_ rd: RataDie) -> Double {
        engine.solarLongitude(at: midnight(rd))
    }

    func majorSolarTerm(_ rd: RataDie) -> UInt32 {
        let lon = solarLongitudeAt(rd)
        return UInt32(((2.0 + (lon / 30.0).rounded(.down) - 1.0)
            .truncatingRemainder(dividingBy: 12.0) + 12.0)
            .truncatingRemainder(dividingBy: 12.0)) + 1
    }

    func findNewYear(forJan1 j1: RataDie) -> RataDie {
        let search = midnight(RataDie(j1.dayNumber + 30))
        let estimate = Astronomical.estimatePriorSolarLongitude(angle: 270.0, moment: search)
        var sd = Moment(estimate.inner.rounded(.down))
        while 270.0 >= engine.solarLongitude(at: midnight(RataDie(Int64(sd.inner + 1.0)))) {
            sd = sd + 1.0
        }
        let solsticeRd = sd.rataDie
        let m11 = newMoonOnOrBefore(solsticeRd)
        let m12 = newMoonOnOrAfter(RataDie(m11.dayNumber + 1))
        let m13 = newMoonOnOrAfter(RataDie(m12.dayNumber + 1))
        if majorSolarTerm(m11) == majorSolarTerm(m12) || majorSolarTerm(m12) == majorSolarTerm(m13) {
            return newMoonOnOrAfter(RataDie(m13.dayNumber + 1))
        }
        return m13
    }

    let newYear = findNewYear(forJan1: jan1)
    let nextJan1 = GregorianArithmetic.fixedFromGregorian(year: relatedIso + 1, month: 1, day: 1)
    let nextNewYear = findNewYear(forJan1: nextJan1)

    var monthLengths: [Bool] = []
    var detectedLeap: UInt8? = nil
    var current = newYear
    var currentTerm = majorSolarTerm(current)

    for i in 0..<12 {
        let next = newMoonOnOrAfter(RataDie(current.dayNumber + 1))
        let nextTerm = majorSolarTerm(next)
        if currentTerm == nextTerm {
            detectedLeap = UInt8(i)
        }
        monthLengths.append((next.dayNumber - current.dayNumber) == 30)
        current = next
        currentTerm = nextTerm
    }

    var leapMonthNum: UInt8? = nil
    if current != nextNewYear {
        monthLengths.append((nextNewYear.dayNumber - current.dayNumber) == 30)
        leapMonthNum = detectedLeap ?? 12
    }

    return YearStruct(relatedIso: relatedIso, newYear: newYear.dayNumber,
                      monthLengths: monthLengths, leapMonth: leapMonthNum)
}

// MARK: - Gregorian helpers

func gregYear(of rd: Int64) -> Int32 {
    var y = Int32(Double(rd) / 365.2425) + 1
    while GregorianArithmetic.fixedFromGregorian(year: y, month: 1, day: 1).dayNumber > rd { y -= 1 }
    while GregorianArithmetic.fixedFromGregorian(year: y + 1, month: 1, day: 1).dayNumber <= rd { y += 1 }
    return y
}

// MARK: - Foundation (ICU Duffett-Smith) extraction

// Rows per related ISO year, derived from a daily scan.
func foundationYears(gregFrom: Int32, gregTo: Int32) -> [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]] {
    var cal = Calendar(identifier: .chinese)
    let tz = TimeZone(secondsFromGMT: 8 * 3600)!
    cal.timeZone = tz

    let rdEpoch: Int64 = 719163  // RD of 1970-01-01
    let startRD = GregorianArithmetic.fixedFromGregorian(year: gregFrom, month: 1, day: 1).dayNumber
    let endRD = GregorianArithmetic.fixedFromGregorian(year: gregTo, month: 3, day: 10).dayNumber

    // Collect month-start events (day == 1)
    var events: [(num: Int, leap: Bool, rd: Int64)] = []
    var rd = startRD
    while rd <= endRD {
        let date = Date(timeIntervalSince1970: Double(rd - rdEpoch) * 86400.0 + 4 * 3600.0)
        let c = cal.dateComponents([.month, .day, .isLeapMonth], from: date)
        if c.day == 1 {
            events.append((c.month!, c.isLeapMonth ?? false, rd))
            rd += 25  // skip ahead: next month start is >= 29 days away
        } else if c.day! < 25 {
            rd += Int64(29 - c.day!)  // jump near the next month start
        } else {
            rd += 1
        }
    }

    // Group into Chinese years at each (month 1, not leap) event
    var out: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]] = [:]
    var group: [(num: Int, leap: Bool, rd: Int64)] = []
    for ev in events {
        if ev.num == 1 && !ev.leap {
            if group.count >= 12 {
                let year = gregYear(of: group[0].rd)
                var rows: [(Int, Bool, Int64, Int)] = []
                for (i, m) in group.enumerated() {
                    let next = (i + 1 < group.count) ? group[i + 1].rd : ev.rd
                    rows.append((m.num, m.leap, m.rd, Int(next - m.rd)))
                }
                out[year] = rows
            }
            group = [ev]
        } else if !group.isEmpty {
            group.append(ev)
        }
    }
    return out
}

// MARK: - HKO CSV

func loadHKO(_ path: String) -> [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]] {
    let text = try! String(contentsOfFile: path, encoding: .utf8)
    var out: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]] = [:]
    for line in text.split(separator: "\n").dropFirst() {
        let f = line.split(separator: ",").map { String($0) }
        guard f.count >= 7 else { continue }
        let year = Int32(f[0])!
        let start = GregorianArithmetic.fixedFromGregorian(
            year: Int32(f[4])!, month: UInt8(f[5])!, day: UInt8(f[6])!).dayNumber
        out[year, default: []].append((Int(f[1])!, f[2] == "1", start, Int(f[3])!))
    }
    return out
}

// MARK: - Comparison

struct CompareResult {
    var yearsCompared = 0
    var yearsClean = 0
    var startDiffs = 0            // same label sequence, different start RD
    var startDiffTotalMonths = 0  // months compared where labels aligned
    var deltaHisto: [Int: Int] = [:]
    var labelMismatchYears: [Int32] = []   // leap placement / numbering differs
    var monthCountMismatchYears: [Int32] = []
    var newYearDiffYears: [(Int32, Int64)] = []
    var exampleDiffs: [String] = []
}

func compare(
    _ a: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]],
    _ b: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]],
    years: ClosedRange<Int32>,
    aName: String, bName: String
) -> CompareResult {
    var r = CompareResult()
    for y in years {
        guard let ra = a[y], let rb = b[y] else { continue }
        r.yearsCompared += 1
        var clean = true
        if ra.count != rb.count {
            r.monthCountMismatchYears.append(y)
            if ra[0].start != rb[0].start { r.newYearDiffYears.append((y, ra[0].start - rb[0].start)) }
            continue
        }
        let labelsA = ra.map { "\($0.num)\($0.leap ? "L" : "")" }
        let labelsB = rb.map { "\($0.num)\($0.leap ? "L" : "")" }
        if labelsA != labelsB {
            r.labelMismatchYears.append(y)
            clean = false
        }
        for i in 0..<ra.count {
            r.startDiffTotalMonths += 1
            let d = Int(ra[i].start - rb[i].start)
            if d != 0 {
                r.startDiffs += 1
                r.deltaHisto[d, default: 0] += 1
                clean = false
                if r.exampleDiffs.count < 8 {
                    r.exampleDiffs.append("y\(y) m\(labelsA[i]): \(aName)=\(ra[i].start) \(bName)=\(rb[i].start) (Δ\(d))")
                }
            }
        }
        if ra[0].start != rb[0].start { r.newYearDiffYears.append((y, ra[0].start - rb[0].start)) }
        if clean { r.yearsClean += 1 }
    }
    return r
}

func report(_ name: String, _ r: CompareResult) {
    print("== \(name) ==")
    print("  years compared: \(r.yearsCompared), fully clean: \(r.yearsClean)")
    print("  month starts differing: \(r.startDiffs) / \(r.startDiffTotalMonths)  histo: \(r.deltaHisto.sorted { $0.key < $1.key })")
    print("  label (leap-placement/numbering) mismatch years: \(r.labelMismatchYears.count) \(r.labelMismatchYears.prefix(12))")
    print("  month-count mismatch years: \(r.monthCountMismatchYears.count) \(r.monthCountMismatchYears.prefix(12))")
    print("  new-year start differs in \(r.newYearDiffYears.count) years \(r.newYearDiffYears.prefix(6))")
    for e in r.exampleDiffs { print("    ex: \(e)") }
}

// MARK: - Runs

func computeRange(_ engine: any AstronomicalEngineProtocol, _ years: ClosedRange<Int32>,
                  _ offset: (Int64) -> Double) -> [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]] {
    var out: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]] = [:]
    for y in years { out[y] = computeYear(engine: engine, relatedIso: y, offset: offset).rows }
    return out
}

let reingold = ReingoldEngine()
let moshier = MoshierEngine()
let t0 = ProcessInfo.processInfo.systemUptime

// ---- A) In-range skill vs HKO (1901-2099) ----
print("### A) Engine skill vs HKO authority, 1901-2099")
let hko = loadHKO("/Users/draganbesevic/Projects/claude/CalendarAPI/icu4swift/Tests/CalendarAstronomicalTests/chinese_months_1901_2100_hko.csv")
let inYears: ClosedRange<Int32> = 1901...2099

let moshChinaIn = computeRange(moshier, inYears, offsetChina(_:))
report("Moshier+ChinaLMT vs HKO (harness validation, expect the known 1906 cluster)",
       compare(moshChinaIn, hko, years: inYears, aName: "moshier", bName: "hko"))

let reinChinaIn = computeRange(reingold, inYears, offsetChina(_:))
report("Reingold+ChinaLMT vs HKO", compare(reinChinaIn, hko, years: inYears, aName: "reingold", bName: "hko"))

let icuIn = foundationYears(gregFrom: 1900, gregTo: 2100)
report("ICU(Duffett-Smith, system Foundation) vs HKO",
       compare(icuIn, hko, years: inYears, aName: "icu", bName: "hko"))
print("  [t=\(Int(ProcessInfo.processInfo.systemUptime - t0))s]\n")

// ---- B) Out-of-range PAST 1500-1699 ----
print("### B) Past 1500-1699 (our shipping fallback = Reingold)")
let pastYears: ClosedRange<Int32> = 1500...1699
let icuPast = foundationYears(gregFrom: 1499, gregTo: 1701)
let reinChinaPast = computeRange(reingold, pastYears, offsetChina(_:))
let reinU8Past = computeRange(reingold, pastYears, offsetUTC8(_:))
let moshU8Past = computeRange(moshier, pastYears, offsetUTC8(_:))

report("Reingold+ChinaLMT (shipping) vs ICU", compare(reinChinaPast, icuPast, years: pastYears, aName: "reingold", bName: "icu"))
report("Reingold+UTC8 vs ICU (ephemeris-only diff)", compare(reinU8Past, icuPast, years: pastYears, aName: "reingold", bName: "icu"))
report("Moshier+UTC8 vs ICU (referee proxy)", compare(moshU8Past, icuPast, years: pastYears, aName: "moshier", bName: "icu"))
report("Reingold+UTC8 vs Moshier+UTC8", compare(reinU8Past, moshU8Past, years: pastYears, aName: "reingold", bName: "moshier"))
print("  [t=\(Int(ProcessInfo.processInfo.systemUptime - t0))s]\n")

// ---- C) Out-of-range FUTURE 2151-2350 ----
print("### C) Future 2151-2350 (offset = UTC+8 for everyone)")
let futYears: ClosedRange<Int32> = 2151...2350
let icuFut = foundationYears(gregFrom: 2150, gregTo: 2352)
let reinFut = computeRange(reingold, futYears, offsetUTC8(_:))
let moshFut = computeRange(moshier, futYears, offsetUTC8(_:))

report("Reingold vs ICU", compare(reinFut, icuFut, years: futYears, aName: "reingold", bName: "icu"))
report("Moshier vs ICU (referee proxy)", compare(moshFut, icuFut, years: futYears, aName: "moshier", bName: "icu"))
report("Reingold vs Moshier", compare(reinFut, moshFut, years: futYears, aName: "reingold", bName: "moshier"))
print("  [t=\(Int(ProcessInfo.processInfo.systemUptime - t0))s]\n")

// ---- D) Referee tally: when Reingold and ICU disagree, whom does Moshier back? ----
print("### D) Referee tally on disagreements (same-label months only)")
func referee(_ rein: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]],
             _ icu: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]],
             _ mosh: [Int32: [(num: Int, leap: Bool, start: Int64, len: Int)]],
             years: ClosedRange<Int32>, label: String) {
    var withRein = 0, withICU = 0, neither = 0
    for y in years {
        guard let rr = rein[y], let ri = icu[y], let rm = mosh[y],
              rr.count == ri.count, rr.count == rm.count else { continue }
        for i in 0..<rr.count where rr[i].start != ri[i].start {
            if rm[i].start == rr[i].start { withRein += 1 }
            else if rm[i].start == ri[i].start { withICU += 1 }
            else { neither += 1 }
        }
    }
    print("  \(label): Moshier sides with Reingold \(withRein), with ICU \(withICU), neither \(neither)")
}
referee(reinU8Past, icuPast, moshU8Past, years: pastYears, label: "past 1500-1699 (UTC8)")
referee(reinFut, icuFut, moshFut, years: futYears, label: "future 2151-2350")

// ---- E) Shoulders: where icu4swift's HybridEngine actually runs Moshier ----
print("\n### E) Shoulders 1700-1900 & 2100-2150: Reingold vs Moshier (shipping offsets)")
for years in [1700...1900, 2100...2150] as [ClosedRange<Int32>] {
    let rein = computeRange(reingold, years, offsetChina(_:))
    let mosh = computeRange(moshier, years, offsetChina(_:))
    report("Reingold vs Moshier \(years.lowerBound)-\(years.upperBound)",
           compare(rein, mosh, years: years, aName: "reingold", bName: "moshier"))
}
// ---- F) Packing bounds over proposed baked range 1600-2600 ----
print("\n### F) New-year offset from Jan 19, years 1600-2600 (packing bounds)")
var minOff = Int64.max, maxOff = Int64.min
var y13 = 0
for y in 1600...2600 {
    let ys = computeYear(engine: reingold, relatedIso: Int32(y), offset: offsetChina(_:))
    let jan19 = GregorianArithmetic.fixedFromGregorian(year: Int32(y), month: 1, day: 19).dayNumber
    let off = ys.newYear - jan19
    minOff = min(minOff, off); maxOff = max(maxOff, off)
    if ys.monthLengths.count == 13 { y13 += 1 }
    if off > 50 || off < 3 {
        print("  extreme: year \(y) offset \(off) months \(ys.monthLengths.count) leap \(ys.leapMonth.map(String.init) ?? "-")")
    }
}
print("  offset min \(minOff), max \(maxOff) (6-bit field holds 0-63); 13-month years: \(y13)/1001")
// ---- G) Live fallback zone under the 1900-2100 table: Reingold vs ICU ----
print("\n### G) Live fallback zones (1900-2100 table): Reingold vs ICU")
let icuZone1 = foundationYears(gregFrom: 1699, gregTo: 1901)
let icuZone2 = foundationYears(gregFrom: 2100, gregTo: 2152)
let z1: ClosedRange<Int32> = 1700...1899
let z2: ClosedRange<Int32> = 2101...2150
report("Reingold+ChinaLMT vs ICU 1700-1899",
       compare(computeRange(reingold, z1, offsetChina(_:)), icuZone1, years: z1, aName: "reingold", bName: "icu"))
report("Reingold+UTC8 vs ICU 2101-2150",
       compare(computeRange(reingold, z2, offsetUTC8(_:)), icuZone2, years: z2, aName: "reingold", bName: "icu"))
// ---- H) Full dump of contested years + all disputed month starts ----
func gregStr(_ rd: Int64) -> String {
    let y = gregYear(of: rd)
    var m: UInt8 = 1
    while m < 12 && GregorianArithmetic.fixedFromGregorian(year: y, month: m + 1, day: 1).dayNumber <= rd { m += 1 }
    let d = rd - GregorianArithmetic.fixedFromGregorian(year: y, month: m, day: 1).dayNumber + 1
    return "\(y)-\(String(format: "%02d", m))-\(String(format: "%02d", d))"
}

func dumpRows(_ name: String, _ rows: [(num: Int, leap: Bool, start: Int64, len: Int)]?) {
    guard let rows else { print("    \(name): (missing)"); return }
    let s = rows.map { "m\($0.num)\($0.leap ? "L" : "")@\(gregStr($0.start))" }.joined(separator: " ")
    print("    \(name): \(s)")
}

print("\n### H) Contested years — full month-start tables")
let focusPast: [Int32] = [1775, 1776, 1794, 1795, 1813, 1814, 1870, 1871, 1889, 1890]
let focusFut: [Int32] = [2147, 2148]
let moshLMTZone = computeRange(moshier, 1775...1890, offsetChina(_:))
for y in focusPast {
    print("  year \(y):")
    dumpRows("rein+LMT", computeRange(reingold, y...y, offsetChina(_:))[y])
    dumpRows("mosh+LMT", moshLMTZone[y])
    dumpRows("rein+UTC8", computeRange(reingold, y...y, offsetUTC8(_:))[y])
    dumpRows("icu      ", icuZone1[y])
}
for y in focusFut {
    print("  year \(y):")
    dumpRows("rein+UTC8", computeRange(reingold, y...y, offsetUTC8(_:))[y])
    dumpRows("mosh+UTC8", computeRange(moshier, y...y, offsetUTC8(_:))[y])
    dumpRows("icu      ", icuZone2[y])
}

print("\n### H2) All ±1-day disputed month starts (same-structure years), 1700-1899 & 2101-2150")
let reinZ1 = computeRange(reingold, z1, offsetChina(_:))
let moshZ1 = computeRange(moshier, z1, offsetChina(_:))
for y in z1 {
    guard let rr = reinZ1[y], let ri = icuZone1[y], rr.count == ri.count else { continue }
    for i in 0..<rr.count where rr[i].start != ri[i].start {
        let mo = moshZ1[y].map { $0.count == rr.count ? gregStr($0[i].start) : "struct-diff" } ?? "?"
        print("  \(y) m\(rr[i].num)\(rr[i].leap ? "L" : ""): rein \(gregStr(rr[i].start))  mosh \(mo)  icu \(gregStr(ri[i].start))")
    }
}
let reinZ2 = computeRange(reingold, z2, offsetUTC8(_:))
let moshZ2 = computeRange(moshier, z2, offsetUTC8(_:))
for y in z2 {
    guard let rr = reinZ2[y], let ri = icuZone2[y], rr.count == ri.count else { continue }
    for i in 0..<rr.count where rr[i].start != ri[i].start {
        let mo = moshZ2[y].map { $0.count == rr.count ? gregStr($0[i].start) : "struct-diff" } ?? "?"
        print("  \(y) m\(rr[i].num)\(rr[i].leap ? "L" : ""): rein \(gregStr(rr[i].start))  mosh \(mo)  icu \(gregStr(ri[i].start))")
    }
}
print("\nTotal runtime: \(Int(ProcessInfo.processInfo.systemUptime - t0))s")
