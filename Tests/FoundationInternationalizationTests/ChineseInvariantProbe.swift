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

// M3.5 verification hardening (CHINESE_PLAN.md § 11.7): internal structural
// invariants of the engine over the DEEP fallback range, where no ICU
// comparison applies (divergence out there is intentional and documented).
// This is the guard against icu4swift-shaped bugs: its non-tiling year 1776
// lived exactly in untested fallback territory.

import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

@Suite("Chinese Invariant Probe")
private struct ChineseInvariantProbe {

    // MARK: - Invariant 1: tiling + structure, related ISO −2000...5000

    /// Every year must tile exactly with its successor, contain 12 or 13
    /// months (13 iff a leap is marked), and its encoded month-length bits
    /// must sum EXACTLY to the span to the next new year. The sum check is
    /// the silent-corruption detector: lengths are stored as 29/30 bits, so
    /// a 28- or 31-day solver artifact would otherwise vanish into a wrong
    /// bit and corrupt every date in the year.
    @Test func chineseInvariant_tilingAndStructure() {
        var failures: [String] = []
        var prev = _ChineseCalendarEngine.year(relatedIso: -2000)
        for iso in -1999...5000 {
            let y = _ChineseCalendarEngine.year(relatedIso: iso)
            if prev.endRD != y.newYearRD {
                failures.append("\(iso - 1)→\(iso): end \(prev.endRD) != next NY \(y.newYearRD)")
            }
            let n = Int(y.monthCount)
            if n != 12 && n != 13 {
                failures.append("\(iso): monthCount \(n)")
            }
            if (n == 13) != (y.leapDisplay != 0) {
                failures.append("\(iso): monthCount \(n) but leapDisplay \(y.leapDisplay)")
            }
            if y.leapDisplay > 12 {
                failures.append("\(iso): leapDisplay \(y.leapDisplay) out of range")
            }
            var sum = 0
            for o in 1...n { sum += y.monthLength(ordinal: o) }
            let span = y.endRD - y.newYearRD
            if sum != span {
                failures.append("\(iso): length-bits sum \(sum) != span \(span)")
            }
            if span < 353 || span > 385 {
                failures.append("\(iso): year length \(span) implausible")
            }
            if failures.count > 40 { break }
            prev = y
        }
        print("[chineseInvariant_tilingAndStructure] years=7001 failures=\(failures.count)")
        for f in failures.prefix(20) { print("    \(f)") }
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(5))")
    }

    // MARK: - Invariant 2: historical pins (adjudicated record, § 5c)

    /// Adjudicated against the promulgated record (Liu + Academia Sinica +
    /// sxtwl + PyEphem, § 5c): these dates are permanent expectations for the
    /// fallback design. If an engine change moves one, that change is wrong.
    /// NOTE: at 1795, 1814, 1890, and 2148 ICU disagrees, it computes leap
    /// months that never existed (fake m12L 1794/1889, m11L 1813, m1L 2148)
    /// and shifts CNY by ~a month. Do NOT "fix" these to match ICU; the
    /// divergence is intentional and documented (CHINESE_PLAN.md § 5c/11.3).
    @Test func chineseInvariant_historicalPins() {
        var failures: [String] = []
        // (relatedIso, expected CNY gregorian y-m-d)
        let cnyPins: [(Int, Int, Int, Int)] = [
            (1776, 1776, 2, 19),
            (1795, 1795, 1, 21),
            (1814, 1814, 1, 21),
            (1871, 1871, 2, 19),
            (1890, 1890, 1, 21),
            (2148, 2148, 2, 20),
        ]
        for (iso, gy, gm, gd) in cnyPins {
            let got = _ChineseCalendarEngine.year(relatedIso: iso).newYearRD
            let want = _CalendarAstronomy.gregorianRD(gy, gm, gd)
            if got != want {
                failures.append("CNY \(iso): got rd \(got), want \(want) (\(gy)-\(gm)-\(gd))")
            }
        }
        // (relatedIso, expected leap display number; 0 = no leap)
        let leapPins: [(Int, UInt8)] = [
            (1775, 10),   // 闰十月, the rare leap 10th
            (1776, 0),
            (1900, 8),    // fallback year at the table seam
            (2147, 11),   // 闰冬月
            (2148, 0),
        ]
        for (iso, want) in leapPins {
            let got = _ChineseCalendarEngine.year(relatedIso: iso).leapDisplay
            if got != want {
                failures.append("leap \(iso): got \(got), want \(want)")
            }
        }
        print("[chineseInvariant_historicalPins] pins=\(cnyPins.count + leapPins.count) failures=\(failures.count)")
        for f in failures { print("    \(f)") }
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures)")
    }

    // MARK: - Invariant 3: far-date round-trips + year-interval adjacency

    @Test func chineseInvariant_farDateRoundTrips() {
        let cal = _CalendarChinese(identifier: .chinese, timeZone: .gmt, locale: nil,
                                   firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures: [String] = []
        let fields: Calendar.ComponentSet = [.era, .year, .month, .day, .isLeapMonth]
        let sampleRDs = [
            _CalendarAstronomy.gregorianRD(-1000, 6, 15),
            _CalendarAstronomy.gregorianRD(1, 1, 1),
            _CalendarAstronomy.gregorianRD(1500, 3, 10),
            _CalendarAstronomy.gregorianRD(1681, 4, 1),    // engine-sensitive leap year (§ 5b)
            _CalendarAstronomy.gregorianRD(3000, 7, 1),
            _CalendarAstronomy.gregorianRD(4600, 12, 31),
        ]
        for rd in sampleRDs {
            let date = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
            let c = cal.dateComponents(fields, from: date, in: .gmt)
            var dc = DateComponents()
            dc.era = c.era; dc.year = c.year; dc.month = c.month; dc.day = c.day
            dc.isLeapMonth = c.isLeapMonth; dc.hour = 12
            guard let rt = cal.date(from: dc) else {
                failures.append("rd \(rd): date(from:) nil for \(dc)")
                continue
            }
            if rt != date {
                failures.append("rd \(rd): round-trip \(date) -> \(rt)")
            }
            // Year-interval adjacency: end of this year == start of next.
            guard let yi = cal.dateInterval(of: .year, for: date) else {
                failures.append("rd \(rd): dateInterval(.year) nil")
                continue
            }
            guard let nyi = cal.dateInterval(of: .year, for: yi.end + 43_200.0) else {
                failures.append("rd \(rd): next-year interval nil")
                continue
            }
            if nyi.start != yi.end {
                failures.append("rd \(rd): year intervals not adjacent: \(yi.end) vs \(nyi.start)")
            }
        }
        print("[chineseInvariant_farDateRoundTrips] samples=\(sampleRDs.count) failures=\(failures.count)")
        for f in failures { print("    \(f)") }
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures)")
    }

    // MARK: - Invariant 4: min/maximumRange vs ICU (§ 11.7 item 2)

    @Test func chineseRangeLimits_vsICU() {
        let icu = _CalendarICU(identifier: .chinese, timeZone: .gmt, locale: nil,
                               firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let ours = _CalendarChinese(identifier: .chinese, timeZone: .gmt, locale: nil,
                                    firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures: [String] = []
        let comps: [Calendar.Component] = [
            .era, .year, .month, .day, .hour, .minute, .second, .nanosecond,
            .weekday, .weekdayOrdinal, .quarter, .weekOfMonth, .weekOfYear,
            .yearForWeekOfYear, .dayOfYear, .isLeapMonth,
        ]
        for c in comps {
            let iMin = icu.minimumRange(of: c).map { "\($0)" } ?? "nil"
            let oMin = ours.minimumRange(of: c).map { "\($0)" } ?? "nil"
            if iMin != oMin { failures.append("minimumRange(\(c)): ICU=\(iMin) ours=\(oMin)") }
            let iMax = icu.maximumRange(of: c).map { "\($0)" } ?? "nil"
            let oMax = ours.maximumRange(of: c).map { "\($0)" } ?? "nil"
            if iMax != oMax { failures.append("maximumRange(\(c)): ICU=\(iMax) ours=\(oMax)") }
        }
        print("[chineseRangeLimits_vsICU] components=\(comps.count) failures=\(failures.count)")
        for f in failures { print("    \(f)") }
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures)")
    }
}
