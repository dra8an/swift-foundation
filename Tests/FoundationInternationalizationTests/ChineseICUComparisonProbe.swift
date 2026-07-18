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

/// Suite A: protocol-level field parity, _CalendarChinese vs _CalendarICU(.chinese).
@Suite("Chinese ICU Comparison Probe")
private struct ChineseICUComparisonProbe {

    // MARK: - Helpers

    private static func makePair() -> (icu: _CalendarICU, ours: _CalendarChinese) {
        let icu = _CalendarICU(
            identifier: .chinese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let ours = _CalendarChinese(
            identifier: .chinese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        return (icu, ours)
    }

    private static func g(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        let rd = _ChineseAstro.gregorianRD(y, m, d)
        return Date(timeIntervalSinceReferenceDate:
            Double(rd - 730_486) * 86400.0 + Double(hour * 3600 + minute * 60 + second))
    }

    /// ICU-internal-inconsistency months (dom=0 artifacts) + the documented
    /// out-of-table 2101-m6 divergence: excluded everywhere.
    private static func isExcluded(_ date: Date) -> Bool {
        let rd = Int((date.timeIntervalSinceReferenceDate / 86400.0).rounded(.down)) + 730_486
        // Whole Chinese years 2057 and 2097: the dom=0 artifact corrupts ICU's
        // own year-level queries (e.g. range(.day,.year) = 325).
        let artifact = [
            _ChineseAstro.gregorianRD(2057, 2, 1)..._ChineseAstro.gregorianRD(2058, 2, 20),
            _ChineseAstro.gregorianRD(2097, 2, 1)..._ChineseAstro.gregorianRD(2098, 2, 20),
            _ChineseAstro.gregorianRD(2101, 6, 24)..._ChineseAstro.gregorianRD(2101, 7, 26),
        ]
        return artifact.contains { $0.contains(rd) }
    }

    private static func compareAt(
        label: String, date: Date,
        icu: _CalendarICU, ours: _CalendarChinese,
        divergences: inout [String]
    ) {
        if isExcluded(date) { return }
        func cmp(_ field: String, _ a: Any?, _ b: Any?) {
            let aa = "\(a ?? "nil")"
            let bb = "\(b ?? "nil")"
            if aa != bb {
                divergences.append("[\(label)] \(field): ICU=\(aa) ours=\(bb)")
            }
        }

        let fields: Calendar.ComponentSet = [
            .era, .year, .month, .day, .isLeapMonth, .hour, .minute, .second,
            .weekday, .weekdayOrdinal, .quarter,
            .weekOfMonth, .weekOfYear, .yearForWeekOfYear,
            .dayOfYear
        ]
        let ic = icu.dateComponents(fields, from: date, in: .gmt)
        let oc = ours.dateComponents(fields, from: date, in: .gmt)
        cmp("dc.era",               ic.era,               oc.era)
        cmp("dc.year",              ic.year,              oc.year)
        cmp("dc.month",             ic.month,             oc.month)
        cmp("dc.isLeapMonth",       ic.isLeapMonth,       oc.isLeapMonth)
        cmp("dc.day",               ic.day,               oc.day)
        cmp("dc.hour",              ic.hour,              oc.hour)
        cmp("dc.minute",            ic.minute,            oc.minute)
        cmp("dc.second",            ic.second,            oc.second)
        cmp("dc.weekday",           ic.weekday,           oc.weekday)
        cmp("dc.weekdayOrdinal",    ic.weekdayOrdinal,    oc.weekdayOrdinal)
        cmp("dc.quarter",           ic.quarter,           oc.quarter)
        cmp("dc.weekOfMonth",       ic.weekOfMonth,       oc.weekOfMonth)
        cmp("dc.weekOfYear",        ic.weekOfYear,        oc.weekOfYear)
        cmp("dc.yearForWeekOfYear", ic.yearForWeekOfYear, oc.yearForWeekOfYear)
        cmp("dc.dayOfYear",         ic.dayOfYear,         oc.dayOfYear)

        for c in [Calendar.Component.era, .year, .month, .day, .hour,
                  .weekOfYear, .weekOfMonth, .yearForWeekOfYear] {
            let iv = icu.dateInterval(of: c, for: date)
            let ov = ours.dateInterval(of: c, for: date)
            cmp("dateInterval(\(c)).start",
                iv.map { $0.start.timeIntervalSinceReferenceDate },
                ov.map { $0.start.timeIntervalSinceReferenceDate })
            cmp("dateInterval(\(c)).duration",
                iv.map { Int($0.duration) },
                ov.map { Int($0.duration) })
        }

        let ordPairs: [(Calendar.Component, Calendar.Component)] = [
            (.day, .year), (.day, .month), (.month, .year), (.hour, .day),
            (.weekOfYear, .year), (.weekOfMonth, .month),
            (.weekday, .year), (.weekday, .month), (.weekday, .weekOfYear),
            (.weekdayOrdinal, .month)
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
                  .month, .year, .yearForWeekOfYear, .hour] {
            var dc = DateComponents()
            dc.setValue(1, for: c)
            let ir = icu.date(byAdding: dc, to: date, wrappingComponents: false)
            let or = ours.date(byAdding: dc, to: date, wrappingComponents: false)
            if let ir, Self.isExcluded(ir) { continue }
            cmp("date(byAdding:.\(c))", ir.map { "\($0)" }, or.map { "\($0)" })
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

    // MARK: - Topic 1: representative dates (in-table)

    @Test func chineseCompareFieldsSideBySide() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        let dates: [(String, Date)] = [
            ("CNY 1901", Self.g(1901, 2, 19)),
            ("CNY-eve 1902", Self.g(1902, 2, 7)),
            ("1906 leap-4 first", Self.g(1906, 5, 23)),
            ("1906 leap-4 last", Self.g(1906, 6, 21)),
            ("mid 1944", Self.g(1944, 8, 15)),
            ("CNY 2000", Self.g(2000, 2, 5)),
            ("2020 leap-4", Self.g(2020, 5, 23)),
            ("2023 leap-2", Self.g(2023, 3, 22)),
            ("2033 leap-11 first", Self.g(2033, 12, 22)),
            ("2034 mid", Self.g(2034, 6, 15)),
            ("2096 mid", Self.g(2096, 6, 15)),
            ("last table day", Self.g(2101, 1, 28)),
        ]
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("chineseCompareFieldsSideBySide", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 2: dense weekly sweep 2020s

    @Test func chineseSweepDecade2020s() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var d = Self.g(2020, 1, 1)
        for i in 0..<520 {
            Self.compareAt(label: "2020s+\(i)w", date: d, icu: icu, ours: ours, divergences: &divergences)
            d = d.addingTimeInterval(86400 * 7)
        }
        Self.reportAndAssert("chineseSweepDecade2020s", divergences, dateCount: 520)
    }

    // MARK: - Topic 3: CNY boundaries across the table

    @Test func chineseNewYearBoundaries() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var count = 0
        for iso in stride(from: 1901, through: 2100, by: 7) {
            let ny = _ChineseCalendarEngine.year(relatedIso: iso).newYearRD
            for delta in [-1, 0, 1] {
                let rd = ny + delta
                let date = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
                Self.compareAt(label: "CNY \(iso)\(delta >= 0 ? "+" : "")\(delta)", date: date, icu: icu, ours: ours, divergences: &divergences)
                count += 1
            }
        }
        Self.reportAndAssert("chineseNewYearBoundaries", divergences, dateCount: count)
    }

    // MARK: - Topic 4: leap-month edges across the table

    @Test func chineseLeapMonthEdges() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var count = 0
        for iso in stride(from: 1903, through: 2099, by: 3) {
            let y = _ChineseCalendarEngine.year(relatedIso: iso)
            guard let lo = y.leapOrdinal else { continue }
            let start = y.monthStartRD(ordinal: lo)
            let len = y.monthLength(ordinal: lo)
            for rd in [start - 1, start, start + len - 1, start + len] {
                let date = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
                Self.compareAt(label: "leap \(iso) rd\(rd)", date: date, icu: icu, ours: ours, divergences: &divergences)
                count += 1
            }
        }
        Self.reportAndAssert("chineseLeapMonthEdges", divergences, dateCount: count)
    }

    // MARK: - Topic 5: time-of-day edges

    @Test func chineseTimeOfDayEdges() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        let base = Self.g(2025, 6, 15, hour: 0)
        var count = 0
        for (h, m, s, label) in [
            (0, 0, 0, "midnight"), (0, 0, 1, "00:00:01"),
            (11, 59, 59, "11:59:59"), (12, 0, 0, "noon"),
            (23, 59, 59, "23:59:59"),
        ] {
            let date = base.addingTimeInterval(TimeInterval(h * 3600 + m * 60 + s))
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
            count += 1
        }
        Self.reportAndAssert("chineseTimeOfDayEdges", divergences, dateCount: count)
    }

    // MARK: - Topic 6: table seams

    @Test func chineseTableSeams() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var count = 0
        // Daily bands across both seams: CNY 1901 ± 40d, CNY 2101 ± 40d.
        for (iso, seam) in [(1901, _ChineseCalendarEngine.year(relatedIso: 1901).newYearRD),
                            (2101, _ChineseCalendarEngine.year(relatedIso: 2101).newYearRD)] {
            for delta in -40...40 {
                let rd = seam + delta
                let date = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
                Self.compareAt(label: "seam \(iso) \(delta)", date: date, icu: icu, ours: ours, divergences: &divergences)
                count += 1
            }
        }
        Self.reportAndAssert("chineseTableSeams", divergences, dateCount: count)
    }

    // MARK: - Topic 7: date(byAdding:) larger units incl. leap clamping

    @Test func chineseDateByAddingLargerUnits() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        let dates: [(String, Date)] = [
            ("2020 leap-4 d30", Self.g(2020, 6, 20)),   // near leap month end
            ("2023 leap-2 d1", Self.g(2023, 3, 22)),
            ("CNY 2024", Self.g(2024, 2, 10)),
            ("2025 mid-year", Self.g(2025, 7, 4)),
            ("1935 m12 d30", Self.g(1936, 1, 23)),
        ]
        for (label, date) in dates {
            for unit in [Calendar.Component.year, .month, .weekOfYear, .weekOfMonth, .day] {
                for delta in [-25, -3, -1, 1, 3, 25, 60] {
                    var dc = DateComponents()
                    dc.setValue(delta, for: unit)
                    let icuResult = icu.date(byAdding: dc, to: date, wrappingComponents: false)
                    let ourResult = ours.date(byAdding: dc, to: date, wrappingComponents: false)
                    if let icuResult, Self.isExcluded(icuResult) { continue }
                    if icuResult != ourResult {
                        failures.append("\(label) +\(delta) \(unit): ICU=\(String(describing: icuResult)) ours=\(String(describing: ourResult))")
                    }
                }
            }
        }
        Self.reportAndAssert("chineseDateByAddingLargerUnits", failures, dateCount: dates.count)
    }

    // MARK: - Topic 8: dateComponents(from:to:)

    @Test func chineseDateComponentsFromTo() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        let starts: [(String, Date)] = [
            ("2020-01-15", Self.g(2020, 1, 15)),
            ("1999-06-30", Self.g(1999, 6, 30)),
            ("2023-03-22 leap", Self.g(2023, 3, 22)),
        ]
        let endOffsets: [TimeInterval] = [
            86400.0, 86400.0 * 30, 86400.0 * 365, 86400.0 * 365 * 5, -86400.0 * 365,
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
        Self.reportAndAssert("chineseDateComponentsFromTo", failures, dateCount: starts.count * endOffsets.count)
    }

    // MARK: - Topic 9: date(from:) construction incl. leap months

    @Test func chineseDateFromComponents() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var cases: [(String, DateComponents)] = []
        func dc(_ era: Int?, _ y: Int, _ m: Int, _ leap: Bool?, _ d: Int) -> DateComponents {
            var c = DateComponents()
            c.era = era; c.year = y; c.month = m; c.day = d
            if let leap { c.isLeapMonth = leap }
            c.hour = 12
            return c
        }
        // era 78 year 37 = ext 4657 = related ISO 2020 (leap-4 year).
        cases.append(("2020 m4", dc(78, 37, 4, false, 15)))
        cases.append(("2020 m4L", dc(78, 37, 4, true, 15)))
        cases.append(("2020 m4L d1", dc(78, 37, 4, true, 1)))
        cases.append(("2020 m5", dc(78, 37, 5, false, 1)))
        cases.append(("no-era year 41", dc(nil, 41, 1, nil, 1)))
        cases.append(("era 77 y1 m1", dc(77, 1, 1, nil, 1)))
        cases.append(("leap flag on non-leap month", dc(78, 37, 7, true, 5)))
        cases.append(("era 76 y37 m8L", dc(76, 37, 8, true, 10)))   // 1900 fallback year (leap-8)
        for (label, c) in cases {
            let ir = icu.date(from: c)
            let or = ours.date(from: c)
            if ir != or {
                failures.append("\(label): ICU=\(String(describing: ir)) ours=\(String(describing: or))")
            }
        }
        Self.reportAndAssert("chineseDateFromComponents", failures, dateCount: cases.count)
    }
}
