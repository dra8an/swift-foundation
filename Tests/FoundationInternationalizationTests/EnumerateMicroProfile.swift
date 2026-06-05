//===----------------------------------------------------------------------===//
// Micro-benchmark: isolate protocol-call cost vs enumerate-framework cost.
// Temporary — delete after analysis.
//===----------------------------------------------------------------------===//

import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

private let referenceDate = Date(timeIntervalSinceReferenceDate: 496359355.795410)
private let timedRuns = 10

private func repeatedTimed(_ body: () -> Void) -> (minElapsed: Double, maxElapsed: Double) {
    var minT = Double.infinity
    var maxT = 0.0
    for _ in 0..<timedRuns {
        let t0 = ProcessInfo.processInfo.systemUptime
        body()
        let elapsed = ProcessInfo.processInfo.systemUptime - t0
        minT = min(minT, elapsed)
        maxT = max(maxT, elapsed)
    }
    return (minT, maxT)
}

@Suite("Enumerate Micro-Profile")
private struct EnumerateMicroProfile {

    // Raw protocol call speed: 1000 iterations of dateComponents + date(from:)
    // This is the core work enumerate does per-step, without the framework overhead.
    @Test func protocolCallsOnly() {
        let icuInner = _CalendarICU(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let hebrewInner = _CalendarHebrew(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)

        let iterations = 10_000
        for (label, cal) in [("ICU", icuInner as any _CalendarProtocol), ("Hebrew", hebrewInner as any _CalendarProtocol)] {
            var checksum: Int64 = 0
            // warmup
            for i in 0..<100 {
                let d = referenceDate.addingTimeInterval(Double(i) * 86400 * 30)
                let comps = cal.dateComponents([.month, .day], from: d, in: .gmt)
                if let di = cal.dateInterval(of: .month, for: d) {
                    checksum &+= Int64(di.duration)
                }
                _ = comps
            }

            let (minT, maxT) = repeatedTimed {
                for i in 0..<iterations {
                    let d = referenceDate.addingTimeInterval(Double(i) * 86400 * 30)
                    // Simulate what enumerate does per month-step:
                    _ = cal.dateComponents([.month, .day], from: d, in: .gmt)
                    if let di = cal.dateInterval(of: .month, for: d) {
                        checksum &+= Int64(di.duration)
                    }
                }
            }
            _ = checksum
            let minPer = Int(minT * 1e9 / Double(iterations))
            let maxPer = Int(maxT * 1e9 / Double(iterations))
            print("protocolCalls [\(label)]: min \(minPer) ns/call-pair (max \(maxPer)) — best of \(timedRuns)")
        }
    }

    // Direct Hebrew year computation: how fast can we find next 25 Kislev
    // WITHOUT the enumerate framework?
    @Test func directNextHanukkah() {
        let hebrewInner = _CalendarHebrew(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)

        var checksum: Int64 = 0
        let iterations = 1000

        // warmup
        for i in 0..<10 {
            let d = referenceDate.addingTimeInterval(Double(i) * 86400 * 365)
            let comps = hebrewInner.dateComponents([.year, .month, .day], from: d, in: .gmt)
            guard let y = comps.year, let m = comps.month, let day = comps.day else { continue }
            // Direct: if we're before Kislev 25 this year, it's this year; otherwise next year
            var targetYear = Int32(y)
            if m > 3 || (m == 3 && day > 25) { targetYear += 1 }
            if let bib = HebrewArithmetic.civilToBiblical(year: targetYear, civilMonth: 3) {
                let rd = HebrewArithmetic.fixedFromHebrew(year: targetYear, month: bib, day: 25)
                checksum &+= Int64(rd)
            }
        }

        let (minT, maxT) = repeatedTimed {
            for i in 0..<iterations {
                let d = referenceDate.addingTimeInterval(Double(i) * 86400 * 365)
                let comps = hebrewInner.dateComponents([.year, .month, .day], from: d, in: .gmt)
                guard let y = comps.year, let m = comps.month, let day = comps.day else { continue }
                var targetYear = Int32(y)
                if m > 3 || (m == 3 && day > 25) { targetYear += 1 }
                if let bib = HebrewArithmetic.civilToBiblical(year: targetYear, civilMonth: 3) {
                    let rd = HebrewArithmetic.fixedFromHebrew(year: targetYear, month: bib, day: 25)
                    checksum &+= Int64(rd)
                }
            }
        }
        _ = checksum
        let minPer = Int(minT * 1e6 / Double(iterations))
        let maxPer = Int(maxT * 1e6 / Double(iterations))
        print("directNextHanukkah [Hebrew]: min \(minPer) µs/match (max \(maxPer)) — best of \(timedRuns)")

        // Compare: same 1000 matches via enumerateDates
        let cal = Calendar(inner: hebrewInner)
        let dc = DateComponents(month: 3, day: 25)
        let (minE, maxE) = repeatedTimed {
            var count = iterations
            cal.enumerateDates(startingAfter: referenceDate, matching: dc, matchingPolicy: .nextTime) { r, _, stop in
                checksum &+= Int64(r?.timeIntervalSinceReferenceDate ?? 0)
                count -= 1; if count == 0 { stop = true }
            }
        }
        _ = checksum
        let minEPer = Int(minE * 1e6 / Double(iterations))
        let maxEPer = Int(maxE * 1e6 / Double(iterations))
        print("enumerateHanukkah  [Hebrew]: min \(minEPer) µs/match (max \(maxEPer)) — best of \(timedRuns)")
        print("enumerate/direct ratio: \(Double(minEPer) / Double(max(minPer, 1)))×")

        // Fast-path: _CalendarHebrew.nextDate(after:matching:)
        let dc2 = DateComponents(month: 3, day: 25)

        // Correctness: verify fast-path matches enumerateDates
        var enumDates: [Date] = []
        let calForCheck = Calendar(inner: hebrewInner)
        var count = 20
        calForCheck.enumerateDates(startingAfter: referenceDate, matching: dc2, matchingPolicy: .nextTime) { r, _, stop in
            if let r { enumDates.append(r) }
            count -= 1; if count == 0 { stop = true }
        }
        var fastDates: [Date] = []
        var cur = referenceDate
        for _ in 0..<20 {
            guard let next = hebrewInner.nextDate(after: cur, matching: dc2, direction: .forward) else { break }
            fastDates.append(next)
            cur = next
        }
        var mismatches = 0
        for i in 0..<min(enumDates.count, fastDates.count) {
            if enumDates[i] != fastDates[i] {
                mismatches += 1
                if mismatches <= 3 {
                    print("MISMATCH [\(i)]: enum=\(enumDates[i]) fast=\(fastDates[i])")
                }
            }
        }
        print("correctness: \(enumDates.count) enum vs \(fastDates.count) fast, \(mismatches) mismatches")
        #expect(mismatches == 0, "fast-path diverges from enumerateDates")

        let (minFast, _) = repeatedTimed {
            var current = referenceDate
            for _ in 0..<iterations {
                guard let next = hebrewInner.nextDate(after: current, matching: dc2, direction: .forward) else { break }
                checksum &+= Int64(next.timeIntervalSinceReferenceDate)
                current = next
            }
        }
        _ = checksum
        let minFNs = Int(minFast * 1e9 / Double(iterations))
        print("fastPath nextDate  [Hebrew]: min \(minFNs) ns/match — best of \(timedRuns)")
        print("enumerate/fastPath ratio: \(Double(minEPer) / (Double(minFNs) / 1000.0))×")
    }

    /// Correctness: the extended fast-path patterns ({m,d,h,m,s}, {day:1}, {month:1},
    /// {weekday:7}) must produce IDENTICAL output to ICU's enumerateDates result.
    /// ICU has no fast path, so it's an independent ground truth.
    @Test func extendedFastPath_correctnessVsICU() {
        let icuInner = _CalendarICU(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let hebrewInner = _CalendarHebrew(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let icu = Calendar(inner: icuInner)
        // Use direct method to bypass our wired Calendar.enumerateDates fast-path.
        // ICU's wrapper is fine — _calendarClass(.hebrew) returns _CalendarICU here too,
        // but Calendar(inner: icuInner) routes through icuInner specifically.

        struct Probe {
            let name: String
            let dc: DateComponents
            let count: Int
        }
        let probes: [Probe] = [
            Probe(name: "{m:3, d:25} (Hanukkah, baseline)",                 dc: DateComponents(month: 3, day: 25), count: 50),
            Probe(name: "{m:3, d:25, h:18, mi:30} (Hanukkah at 18:30)",     dc: DateComponents(month: 3, day: 25, hour: 18, minute: 30), count: 50),
            Probe(name: "{m:8, d:15, h:19} (Passover at 19:00)",            dc: DateComponents(month: 8, day: 15, hour: 19), count: 50),
            Probe(name: "{m:1} (Tishri 1 each year)",                       dc: DateComponents(month: 1), count: 50),
            Probe(name: "{m:1, h:6} (Tishri 1 at 06:00)",                   dc: DateComponents(month: 1, hour: 6), count: 50),
            Probe(name: "{d:1} (Rosh Chodesh)",                             dc: DateComponents(day: 1), count: 100),
            Probe(name: "{d:15, h:12} (mid-month at noon)",                 dc: DateComponents(day: 15, hour: 12), count: 100),
            Probe(name: "{wd:7} (every Saturday)",                          dc: DateComponents(weekday: 7), count: 100),
            Probe(name: "{wd:2, h:9, mi:0} (every Monday at 09:00)",        dc: { var c = DateComponents(); c.weekday = 2; c.hour = 9; c.minute = 0; return c }(), count: 100),
            Probe(name: "{m:1, wd:7, wdOrd:1} (1st Saturday of Tishri)",    dc: { var c = DateComponents(); c.month = 1; c.weekday = 7; c.weekdayOrdinal = 1; return c }(), count: 50),
            Probe(name: "{m:2, wd:5, wdOrd:4} (4th Thursday of Cheshvan)",  dc: { var c = DateComponents(); c.month = 2; c.weekday = 5; c.weekdayOrdinal = 4; return c }(), count: 50),
            Probe(name: "{m:7, wd:6, wdOrd:-1} (last Friday of Adar)",      dc: { var c = DateComponents(); c.month = 7; c.weekday = 6; c.weekdayOrdinal = -1; return c }(), count: 50),
            Probe(name: "{m:1, wd:2, wdOrd:1, h:9} (1st Mon of Tishri 09:00)", dc: { var c = DateComponents(); c.month = 1; c.weekday = 2; c.weekdayOrdinal = 1; c.hour = 9; return c }(), count: 50),
            Probe(name: "{m:6, wd:1, wdOrd:1} (1st Sun of Adar I — leap-only)", dc: { var c = DateComponents(); c.month = 6; c.weekday = 1; c.weekdayOrdinal = 1; return c }(), count: 20),
            Probe(name: "{m:8, wd:3, wdOrd:-2} (2nd-to-last Tue of Nisan)", dc: { var c = DateComponents(); c.month = 8; c.weekday = 3; c.weekdayOrdinal = -2; return c }(), count: 50),
            Probe(name: "{m:11, wd:5, wOM:4} (Thu in week 4 of Tammuz)",   dc: { var c = DateComponents(); c.month = 11; c.weekday = 5; c.weekOfMonth = 4; return c }(), count: 50),
            Probe(name: "{m:1, wd:7, wOM:1} (Sat in week 1 of Tishri)",    dc: { var c = DateComponents(); c.month = 1; c.weekday = 7; c.weekOfMonth = 1; return c }(), count: 50),
            Probe(name: "{m:7, wd:6, wOM:5} (Fri in week 5 of Adar)",      dc: { var c = DateComponents(); c.month = 7; c.weekday = 6; c.weekOfMonth = 5; return c }(), count: 30),
            Probe(name: "{m:6, wd:2, wOM:2} (Mon in week 2 Adar I leap)",  dc: { var c = DateComponents(); c.month = 6; c.weekday = 2; c.weekOfMonth = 2; return c }(), count: 20),
            Probe(name: "{m:11, wd:5, wOM:4, h:14} (with hour 14)",        dc: { var c = DateComponents(); c.month = 11; c.weekday = 5; c.weekOfMonth = 4; c.hour = 14; return c }(), count: 30),
            Probe(name: "{wd:5, wdOrd:4} (no month — 4th Thu of any month)", dc: { var c = DateComponents(); c.weekday = 5; c.weekdayOrdinal = 4; return c }(), count: 100),
            Probe(name: "{wd:2, wdOrd:1} (1st Mon of any month)",           dc: { var c = DateComponents(); c.weekday = 2; c.weekdayOrdinal = 1; return c }(), count: 100),
            Probe(name: "{wd:6, wdOrd:5, h:9} (5th Fri at 09:00)",          dc: { var c = DateComponents(); c.weekday = 6; c.weekdayOrdinal = 5; c.hour = 9; return c }(), count: 50),
        ]

        var totalMismatches = 0

        for p in probes {
            // ICU ground truth via enumerateDates.
            var icuDates: [Date] = []
            var n = p.count
            icu.enumerateDates(startingAfter: referenceDate, matching: p.dc, matchingPolicy: .nextTime) { r, _, stop in
                if let r { icuDates.append(r) }
                n -= 1; if n == 0 { stop = true }
            }

            // Our fast path: chain direct calls.
            var fastDates: [Date] = []
            var cur = referenceDate
            for _ in 0..<p.count {
                guard let next = hebrewInner.nextDate(after: cur, matching: p.dc, direction: .forward) else { break }
                fastDates.append(next)
                cur = next
            }

            var mismatches = 0
            for i in 0..<min(icuDates.count, fastDates.count) {
                if icuDates[i] != fastDates[i] {
                    mismatches += 1
                    if mismatches <= 3 {
                        print("MISMATCH [\(p.name)] [\(i)]: ICU=\(icuDates[i]) fast=\(fastDates[i])")
                    }
                }
            }
            if icuDates.count != fastDates.count {
                print("COUNT [\(p.name)]: icu=\(icuDates.count) fast=\(fastDates.count)")
            }
            if mismatches == 0 && icuDates.count == fastDates.count {
                print("✓ \(p.name): \(icuDates.count) matches, no divergence")
            } else {
                print("✘ \(p.name): \(mismatches) mismatches (\(icuDates.count) vs \(fastDates.count))")
                totalMismatches += mismatches + abs(icuDates.count - fastDates.count)
            }
        }

        #expect(totalMismatches == 0, "fast-path diverges from ICU on \(totalMismatches) date(s)")
    }
}
