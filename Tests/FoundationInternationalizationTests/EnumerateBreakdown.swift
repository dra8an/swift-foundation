//===----------------------------------------------------------------------===//
// Micro-benchmark: break down enumerate cost layer by layer.
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

@Suite("Enumerate Breakdown")
private struct EnumerateBreakdown {

    @Test func fullBreakdown() {
        let icuInner = _CalendarICU(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let hebrewInner = _CalendarHebrew(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)

        let icuCal = Calendar(inner: icuInner)
        let hebrewCal = Calendar(inner: hebrewInner)
        let iterations = 1000
        var checksum: Int64 = 0
        let dc = DateComponents(month: 3, day: 25)

        print("\n=== Enumerate Breakdown: nextThousandHanukkahs ===\n")

        // Layer 1: Direct computation (O(1) per match — decompose + construct target)
        for (label, cal) in [("ICU", icuInner as any _CalendarProtocol), ("Hebrew", hebrewInner as any _CalendarProtocol)] {
            let (minDirect, _) = repeatedTimed {
                var current = referenceDate
                for _ in 0..<iterations {
                    let comps = cal.dateComponents([.year, .month, .day], from: current, in: .gmt)
                    guard let y = comps.year, let m = comps.month, let day = comps.day else { continue }
                    var targetYear = y
                    if m > 3 || (m == 3 && day > 25) { targetYear += 1 }
                    var target = DateComponents()
                    target.era = 0; target.year = targetYear; target.month = 3; target.day = 25
                    target.hour = 0; target.timeZone = .gmt
                    if let result = cal.date(from: target) {
                        checksum &+= Int64(result.timeIntervalSinceReferenceDate)
                        current = result
                    }
                }
            }
            let directPer = Int(minDirect * 1e6 / Double(iterations))
            print("Layer 1 — direct (decompose+construct) [\(label)]: \(directPer) µs/match")
        }

        // Also: Hebrew-only pure arithmetic (no protocol dispatch, no DateComponents alloc)
        let (minPureArith, _) = repeatedTimed {
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
        let pureArithPer = Int(minPureArith * 1e6 / Double(iterations))
        print("Layer 1b — pure arithmetic (no protocol) [Hebrew]: \(pureArithPer) µs/match")

        // Layer 2: Simulate enumerate's month-stepping loop (protocol calls only, no framework)
        // For each match: decompose → loop ~12 months (component + dateInterval each) → find target → construct date
        for (label, cal) in [("ICU", icuInner as any _CalendarProtocol), ("Hebrew", hebrewInner as any _CalendarProtocol)] {
            let (minSim, _) = repeatedTimed {
                var current = referenceDate
                for _ in 0..<iterations {
                    // Step through months until we find month == 3
                    var found = false
                    var searchDate = current
                    while !found {
                        let m = cal.dateComponents([.month], from: searchDate, in: .gmt).month ?? 0
                        if m == 3 {
                            // Now find day 25 within this month
                            let comps = cal.dateComponents([.year, .month, .day], from: searchDate, in: .gmt)
                            if let day = comps.day, day <= 25 {
                                // Advance to day 25
                                var target = DateComponents()
                                target.era = 0
                                target.year = comps.year
                                target.month = 3
                                target.day = 25
                                target.hour = 0
                                target.timeZone = .gmt
                                if let result = cal.date(from: target) {
                                    if result > current {
                                        checksum &+= Int64(result.timeIntervalSinceReferenceDate)
                                        current = result
                                        found = true
                                    }
                                }
                            }
                        }
                        if !found {
                            // Advance by one month
                            if let interval = cal.dateInterval(of: .month, for: searchDate) {
                                searchDate = interval.start + interval.duration
                            } else {
                                break
                            }
                        }
                    }
                }
            }
            let simPer = Int(minSim * 1e6 / Double(iterations))
            print("Layer 2 — manual month-loop [\(label)]: \(simPer) µs/match")
        }

        // Layer 3: Full enumerate framework
        for (label, cal) in [("ICU", icuCal), ("Hebrew", hebrewCal)] {
            let (minEnum, _) = repeatedTimed {
                var count = iterations
                cal.enumerateDates(startingAfter: referenceDate, matching: dc, matchingPolicy: .nextTime) { r, _, stop in
                    checksum &+= Int64(r?.timeIntervalSinceReferenceDate ?? 0)
                    count -= 1; if count == 0 { stop = true }
                }
            }
            let enumPer = Int(minEnum * 1e6 / Double(iterations))
            print("Layer 3 — enumerateDates   [\(label)]: \(enumPer) µs/match")
        }

        print("\n=== Summary ===")
        print("Layer 1:  direct computation (decompose + construct target date)")
        print("Layer 1b: pure Hebrew arithmetic (no protocol dispatch, no DateComponents)")
        print("Layer 2:  manual month-loop (~12 protocol calls per match)")
        print("Layer 3:  full enumerateDates framework")

        _ = checksum
    }
}
