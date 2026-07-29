//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

// Gates for the mean-element zone beyond the validated astronomical range (CHINESE_PLAN § 11.28): seam tiling at both edges, structural invariants across the full supported domain, the reported extreme years pinned, round trips, leap-rate sanity, and a speed bound.
@Suite("Chinese Mean Zone Probe")
private struct ChineseMeanZoneProbe {

    private static func checkStructure(_ y: _ChineseYear, _ bad: inout [String]) {
        let n = Int(y.monthCount)
        if n != 12 && n != 13 { bad.append("\(y.relatedISOYear): monthCount \(n)") }
        var sum = 0
        for o in 1...max(n, 1) {
            let len = y.monthLength(ordinal: o)
            if len != 29 && len != 30 { bad.append("\(y.relatedISOYear): month \(o) length \(len)") }
            sum += len
        }
        if sum != y.endRataDie - y.newYearRataDie {
            bad.append("\(y.relatedISOYear): bits sum \(sum) vs span \(y.endRataDie - y.newYearRataDie)")
        }
        if (n == 13) != (y.leapMonthNumber != 0) { bad.append("\(y.relatedISOYear): leap flag") }
    }

    @Test func seamsTileExactly() {
        var bad: [String] = []
        for range in [15_990...16_012, (-12_012)...(-11_988)] {
            var prev = _ChineseCalendarEngine.year(relatedISOYear: range.lowerBound - 1)
            for y in range {
                let yr = _ChineseCalendarEngine.year(relatedISOYear: y)
                if prev.endRataDie != yr.newYearRataDie {
                    bad.append("\(y): gap \(yr.newYearRataDie - prev.endRataDie)")
                }
                Self.checkStructure(yr, &bad)
                prev = yr
            }
        }
        print("=== chineseMeanSeams: \(bad.count) anomalies ===")
        for b in bad.prefix(10) { print("  \(b)") }
        #expect(bad.isEmpty)
    }

    @Test func structureAcrossFullDomain() {
        var bad: [String] = []
        // Prime stride so no calendrical cycle aliases the sampling; the reported years near 90,000 are pinned explicitly.
        var years: [Int] = Array(stride(from: -4_990_000, through: 4_990_000, by: 99_991))
        years += Array(90_000...90_005)
        years += [-4_999_999, 4_999_999]
        for y in years {
            var localBad: [String] = []
            Self.checkStructure(_ChineseCalendarEngine.year(relatedISOYear: y), &localBad)
            let next = _ChineseCalendarEngine.year(relatedISOYear: y + 1)
            if _ChineseCalendarEngine.year(relatedISOYear: y).endRataDie != next.newYearRataDie {
                localBad.append("\(y): no tiling with successor")
            }
            bad += localBad
        }
        print("=== chineseMeanStructure: \(years.count) years, \(bad.count) anomalies ===")
        for b in bad.prefix(10) { print("  \(b)") }
        #expect(bad.isEmpty)
    }

    @Test func roundTripsAtExtremes() {
        let c = _CalendarChinese(identifier: .chinese, timeZone: .gmt, locale: nil,
                                 firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures = 0
        for gy in [90_000, 100_000, 1_000_000, 4_900_000, -100_000, -1_000_000, -4_900_000] {
            var rataDie = _CalendarAstronomy.gregorianRataDie(gy, 1, 1)
            let end = _CalendarAstronomy.gregorianRataDie(gy + 2, 1, 1)
            while rataDie <= end {
                let d = Date(timeIntervalSinceReferenceDate: Double(rataDie - _CalendarUtility.rataDieAtDateReference) * 86400.0 + 43_200.0)
                let dc = c.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: d, in: .gmt)
                var back = DateComponents()
                back.era = dc.era; back.year = dc.year; back.month = dc.month
                back.day = dc.day; back.isLeapMonth = dc.isLeapMonth; back.hour = 12
                if c.date(from: back) != d { failures += 1 }
                rataDie += 13
            }
        }
        #expect(failures == 0)
    }

    @Test func leapRateIsMetonic() {
        // The mean zone must produce leap years at close to the Metonic 7 in 19 rate, with leap months spread across display numbers.
        var leapCount = 0
        var displays = Set<UInt8>()
        for y in 200_000...200_189 {
            let yr = _ChineseCalendarEngine.year(relatedISOYear: y)
            if yr.leapMonthNumber != 0 {
                leapCount += 1
                displays.insert(yr.leapMonthNumber)
            }
        }
        print("=== chineseMeanLeapRate: \(leapCount)/190 leap years, \(displays.count) distinct display numbers ===")
        #expect(leapCount >= 63 && leapCount <= 77)
        #expect(displays.count >= 4)
    }

    @Test func extremeQueriesAreFast() {
        let c = _CalendarChinese(identifier: .chinese, timeZone: .gmt, locale: nil,
                                 firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let d = Date(timeIntervalSinceReferenceDate: Double(_CalendarAstronomy.gregorianRataDie(4_900_000, 6, 1) - _CalendarUtility.rataDieAtDateReference) * 86400.0)
        // Warm the anchors and caches once, then require the steady state to be fast.
        _ = c.dateComponents([.year, .month, .day], from: d, in: .gmt)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<100 {
                _ = c.dateComponents([.year, .month, .day], from: d, in: .gmt)
            }
        }
        print("=== chineseMeanSpeed: \(elapsed / 100) per query at year 4.9M ===")
        #expect(elapsed < .milliseconds(500))
    }
}
