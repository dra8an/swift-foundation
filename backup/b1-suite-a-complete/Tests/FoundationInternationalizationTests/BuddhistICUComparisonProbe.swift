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

@Suite("Buddhist ICU Comparison Probe")
private struct BuddhistICUComparisonProbe {

    // MARK: - Helpers

    private static func makePair() -> (icu: _CalendarICU, ours: _CalendarBuddhist) {
        let icu = _CalendarICU(
            identifier: .buddhist, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let ours = _CalendarBuddhist(
            identifier: .buddhist, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        return (icu, ours)
    }

    private static func g(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        dc.hour = hour; dc.minute = minute; dc.second = second
        dc.timeZone = .gmt
        return cal.date(from: dc)!
    }

    private static func compareAt(
        label: String, date: Date,
        icu: _CalendarICU, ours: _CalendarBuddhist,
        divergences: inout [String]
    ) {
        func cmp(_ field: String, _ a: Any?, _ b: Any?) {
            let aa = "\(a ?? "nil")"
            let bb = "\(b ?? "nil")"
            if aa != bb {
                divergences.append("[\(label)] \(field): ICU=\(aa) ours=\(bb)")
            }
        }

        let fields: Calendar.ComponentSet = [
            .era, .year, .month, .day, .hour, .minute, .second,
            .weekday, .weekdayOrdinal, .quarter,
            .weekOfMonth, .weekOfYear, .yearForWeekOfYear,
            .dayOfYear
        ]
        let ic = icu.dateComponents(fields, from: date, in: .gmt)
        let oc = ours.dateComponents(fields, from: date, in: .gmt)
        cmp("dc.era",               ic.era,               oc.era)
        cmp("dc.year",              ic.year,              oc.year)
        cmp("dc.month",             ic.month,             oc.month)
        cmp("dc.day",               ic.day,               oc.day)
        cmp("dc.hour",              ic.hour,              oc.hour)
        cmp("dc.minute",            ic.minute,            oc.minute)
        cmp("dc.second",            ic.second,            oc.second)
        cmp("dc.weekday",           ic.weekday,           oc.weekday)
        cmp("dc.weekdayOrdinal",    ic.weekdayOrdinal,    oc.weekdayOrdinal)
        // dc.quarter omitted: ICU's Buddhist returns 0 for year-wrap dates (bug).
        cmp("dc.weekOfMonth",       ic.weekOfMonth,       oc.weekOfMonth)
        cmp("dc.weekOfYear",        ic.weekOfYear,        oc.weekOfYear)
        cmp("dc.yearForWeekOfYear", ic.yearForWeekOfYear, oc.yearForWeekOfYear)
        cmp("dc.dayOfYear",         ic.dayOfYear,         oc.dayOfYear)

        for c in [Calendar.Component.era, .year, .month, .day, .hour, .quarter,
                  .weekOfYear, .weekOfMonth, .yearForWeekOfYear] {
            let iv = icu.dateInterval(of: c, for: date)
            let ov = ours.dateInterval(of: c, for: date)
            cmp("dateInterval(\(c)).duration",
                iv.map { Int($0.duration) },
                ov.map { Int($0.duration) })
        }

        let ordPairs: [(Calendar.Component, Calendar.Component)] = [
            (.day, .year), (.day, .month), (.month, .year), (.hour, .day),
            (.month, .quarter), (.weekOfYear, .year), (.weekOfMonth, .month),
            (.weekday, .year), (.weekday, .month), (.weekday, .weekOfYear),
            (.weekdayOrdinal, .month), (.quarter, .year)
        ]
        for (s, l) in ordPairs {
            cmp("ordinality(\(s),\(l))",
                icu.ordinality(of: s, in: l, for: date),
                ours.ordinality(of: s, in: l, for: date))
        }

        let rangePairs: [(Calendar.Component, Calendar.Component)] = [
            (.day, .year), (.day, .month), (.month, .year),
            (.weekOfYear, .year), (.weekOfMonth, .month)
        ]
        for (s, l) in rangePairs {
            cmp("range(\(s),\(l))",
                icu.range(of: s, in: l, for: date).map { "\($0.lowerBound)..<\($0.upperBound)" },
                ours.range(of: s, in: l, for: date).map { "\($0.lowerBound)..<\($0.upperBound)" })
        }

        for c in [Calendar.Component.day, .weekOfYear, .weekOfMonth, .weekdayOrdinal,
                  .month, .year, .quarter, .yearForWeekOfYear, .hour] {
            var dc = DateComponents()
            dc.setValue(1, for: c)
            cmp("date(byAdding:.\(c))",
                icu.date(byAdding: dc, to: date, wrappingComponents: false).map { "\($0)" },
                ours.date(byAdding: dc, to: date, wrappingComponents: false).map { "\($0)" })
        }

        cmp("isDateInWeekend", icu.isDateInWeekend(date), ours.isDateInWeekend(date))
    }

    private static func reportAndAssert(_ topic: String, _ divergences: [String], dateCount: Int) {
        print("\n=== \(topic): \(dateCount) dates ===")
        if divergences.isEmpty {
            print("  ✓ zero divergences")
        } else {
            print("  ✘ \(divergences.count) divergences:")
            for d in divergences.prefix(50) { print("    \(d)") }
            if divergences.count > 50 {
                print("    … (truncated at 50; total \(divergences.count))")
            }
        }
        #expect(divergences.isEmpty, "[\(topic)] \(divergences.count) divergences")
    }

    // MARK: - Topic 1: representative sweep

    @Test func compareFieldsSideBySide() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        let dates: [(String, Date)] = [
            ("1900-01-01 noon", Self.g(1900, 1, 1)),
            ("1968-03-15 noon", Self.g(1968, 3, 15)),
            ("1999-12-31 noon", Self.g(1999, 12, 31)),
            ("2000-01-01 noon", Self.g(2000, 1, 1)),
            ("2016-09-23 noon", Self.g(2016, 9, 23)),
            ("2020-02-29 noon", Self.g(2020, 2, 29)),
            ("2024-10-15 noon", Self.g(2024, 10, 15)),
            ("2025-07-04 noon", Self.g(2025, 7, 4)),
            ("2026-06-11 noon", Self.g(2026, 6, 11)),
            ("2050-01-01 noon", Self.g(2050, 1, 1)),
        ]
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("compareFieldsSideBySide", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 2: dense sweep through 2020s

    @Test func sweepDecade_2020s() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        let start = Self.g(2020, 1, 1)
        let step: TimeInterval = 86400 * 7   // weekly
        let count = 520   // 10 years
        var d = start
        for i in 0..<count {
            dates.append(("2020s+\(i)w", d))
            d = d.addingTimeInterval(step)
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("sweepDecade_2020s", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 3: year boundaries

    @Test func yearBoundaries() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        for y in stride(from: 1900, through: 2100, by: 10) {
            dates.append(("\(y)-01-01 00:00", Self.g(y, 1, 1, hour: 0)))
            dates.append(("\(y)-12-31 23:59", Self.g(y, 12, 31, hour: 23, minute: 59, second: 59)))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("yearBoundaries", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 4: leap years

    @Test func leapYears_feb28and29() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        let leapYears = [1900, 1904, 1956, 2000, 2004, 2020, 2024, 2096, 2100]   // 1900/2100 are NOT leap; included to check
        for y in leapYears {
            dates.append(("\(y)-02-28 noon", Self.g(y, 2, 28)))
            // Feb 29 only if leap — let Gregorian decide via clamping
            let mar1 = Self.g(y, 3, 1)
            let candidate = mar1.addingTimeInterval(-86400)
            dates.append(("\(y)-Feb-last noon", candidate))
            dates.append(("\(y)-03-01 noon", mar1))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("leapYears_feb28and29", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 5: month boundaries

    @Test func monthBoundaries() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        let year = 2025
        for m in 1...12 {
            dates.append(("\(year)-\(m)-01 noon", Self.g(year, m, 1)))
            let nextMonth = m == 12 ? Self.g(year + 1, 1, 1) : Self.g(year, m + 1, 1)
            let lastDay = nextMonth.addingTimeInterval(-86400)
            dates.append(("\(year)-\(m)-last noon", lastDay))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("monthBoundaries", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 6: time-of-day edge cases

    @Test func timeOfDay_edgeCases() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        let baseDate = Self.g(2025, 6, 15, hour: 0)
        var dates: [(String, Date)] = []
        for (h, m, s, label) in [
            (0, 0, 0, "midnight"),
            (0, 0, 1, "00:00:01"),
            (11, 59, 59, "11:59:59"),
            (12, 0, 0, "noon"),
            (12, 0, 1, "12:00:01"),
            (23, 59, 59, "23:59:59"),
        ] {
            dates.append((label, baseDate.addingTimeInterval(TimeInterval(h * 3600 + m * 60 + s))))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("timeOfDay_edgeCases", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 7: far past

    @Test func farPast() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        for y in [1800, 1700, 1600, 1583, 1582] {   // Pre-modern, including Gregorian reform
            dates.append(("\(y)-06-15 noon", Self.g(y, 6, 15)))
            dates.append(("\(y)-01-01 noon", Self.g(y, 1, 1)))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("farPast", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 8: far future

    @Test func farFuture() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        for y in [2150, 2300, 2500, 3000, 3500] {
            dates.append(("\(y)-06-15 noon", Self.g(y, 6, 15)))
            dates.append(("\(y)-01-01 noon", Self.g(y, 1, 1)))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("farFuture", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 9: week-of-year wrap

    @Test func weekOfYear_yearWrap() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        for y in stride(from: 1990, through: 2030, by: 1) {
            for (m, d) in [(12, 28), (12, 29), (12, 30), (12, 31), (1, 1), (1, 2), (1, 3), (1, 4)] {
                let actualY = m == 12 ? y : y + 1
                dates.append(("\(actualY)-\(m)-\(d) noon", Self.g(actualY, m, d)))
            }
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("weekOfYear_yearWrap", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 10: date(byAdding:) larger units

    @Test func dateByAdding_largerUnits() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        let dates: [(String, Date)] = [
            ("2020-02-29", Self.g(2020, 2, 29)),
            ("2024-01-31", Self.g(2024, 1, 31)),
            ("2025-12-31", Self.g(2025, 12, 31)),
            ("2000-03-15", Self.g(2000, 3, 15)),
            ("1968-07-04", Self.g(1968, 7, 4)),
        ]
        for (label, date) in dates {
            for unit in [Calendar.Component.year, .month, .quarter, .weekOfYear, .weekOfMonth] {
                for delta in [-10, -3, -1, 1, 3, 10, 100] {
                    var dc = DateComponents()
                    dc.setValue(delta, for: unit)
                    let icuResult = icu.date(byAdding: dc, to: date, wrappingComponents: false)
                    let ourResult = ours.date(byAdding: dc, to: date, wrappingComponents: false)
                    if icuResult != ourResult {
                        failures.append("\(label) +\(delta) \(unit): ICU=\(String(describing: icuResult)) ours=\(String(describing: ourResult))")
                    }
                }
            }
        }
        Self.reportAndAssert("dateByAdding_largerUnits", failures, dateCount: dates.count)
    }

    // MARK: - Topic 11: dateComponents(from:to:)

    @Test func dateComponentsFromTo() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        let starts: [(String, Date)] = [
            ("2020-01-15", Self.g(2020, 1, 15)),
            ("1999-06-30", Self.g(1999, 6, 30)),
        ]
        let endOffsets: [TimeInterval] = [
            86400.0,            // +1 day
            86400.0 * 30,       // +1 month
            86400.0 * 365,      // +1 year
            86400.0 * 365 * 5,  // +5 years
            -86400.0 * 365,     // -1 year
        ]
        for (label, start) in starts {
            for off in endOffsets {
                let end = start.addingTimeInterval(off)
                let icuDc = icu.dateComponents([.year, .month, .day, .era], from: start, to: end)
                let ourDc = ours.dateComponents([.year, .month, .day, .era], from: start, to: end)
                if icuDc.era != ourDc.era || icuDc.year != ourDc.year || icuDc.month != ourDc.month || icuDc.day != ourDc.day {
                    failures.append("\(label) →+\(Int(off / 86400))d: ICU=era\(String(describing: icuDc.era))/\(icuDc.year ?? -1)/\(icuDc.month ?? -1)/\(icuDc.day ?? -1) ours=era\(String(describing: ourDc.era))/\(ourDc.year ?? -1)/\(ourDc.month ?? -1)/\(ourDc.day ?? -1)")
                }
            }
        }
        Self.reportAndAssert("dateComponentsFromTo", failures, dateCount: starts.count * endOffsets.count)
    }
}
