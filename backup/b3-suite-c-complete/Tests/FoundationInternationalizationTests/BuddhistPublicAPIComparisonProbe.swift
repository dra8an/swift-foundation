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

@Suite("Buddhist Calendar Public API Probe")
private struct BuddhistPublicAPIComparisonProbe {

    private static func makePair(timeZone: TimeZone = .gmt,
                                 firstWeekday: Int? = nil,
                                 minimumDaysInFirstWeek: Int? = nil) -> (icu: Calendar, ours: Calendar) {
        let icuInner = _CalendarICU(
            identifier: .buddhist, timeZone: timeZone, locale: nil,
            firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek, gregorianStartDate: nil
        )
        let oursInner = _CalendarBuddhist(
            identifier: .buddhist, timeZone: timeZone, locale: nil,
            firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek, gregorianStartDate: nil
        )
        return (Calendar(inner: icuInner), Calendar(inner: oursInner))
    }

    private static func g(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, second: Int = 0, in tz: TimeZone = .gmt) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        dc.hour = hour; dc.minute = minute; dc.second = second
        dc.timeZone = tz
        return cal.date(from: dc)!
    }

    private final class Divergences {
        var list: [String] = []
        func compare(_ label: String, _ field: String, _ icu: Any?, _ ours: Any?) {
            let a = "\(icu ?? "nil")"
            let b = "\(ours ?? "nil")"
            if a != b {
                list.append("[\(label)] \(field): ICU=\(a) ours=\(b)")
            }
        }
        func compareSet(_ label: String, _ field: String, _ icu: DateComponents, _ ours: DateComponents) {
            let comps: [(String, Int?, Int?)] = [
                ("era", icu.era, ours.era),
                ("year", icu.year, ours.year),
                ("month", icu.month, ours.month),
                ("day", icu.day, ours.day),
                ("hour", icu.hour, ours.hour),
                ("minute", icu.minute, ours.minute),
                ("second", icu.second, ours.second),
                ("nanosecond", icu.nanosecond, ours.nanosecond),
                ("weekday", icu.weekday, ours.weekday),
                ("weekdayOrdinal", icu.weekdayOrdinal, ours.weekdayOrdinal),
                ("weekOfMonth", icu.weekOfMonth, ours.weekOfMonth),
                ("weekOfYear", icu.weekOfYear, ours.weekOfYear),
                ("yearForWeekOfYear", icu.yearForWeekOfYear, ours.yearForWeekOfYear),
                ("dayOfYear", icu.dayOfYear, ours.dayOfYear),
                // quarter omitted: ICU Buddhist returns 0 for year-wrap dates (bug)
            ]
            for (name, a, b) in comps where a != b {
                list.append("[\(label)] \(field).\(name): ICU=\(a.map(String.init) ?? "nil") ours=\(b.map(String.init) ?? "nil")")
            }
        }
    }

    private static func compareSurfaces(label: String, date d: Date,
                                        icu: Calendar, ours: Calendar,
                                        div: Divergences) {
        // .quarter omitted (ICU bug at year wraps)
        let allComps: [Calendar.Component] = [
            .era, .year, .month, .day, .hour, .minute, .second, .nanosecond,
            .weekday, .weekdayOrdinal, .weekOfMonth, .weekOfYear,
            .yearForWeekOfYear, .dayOfYear
        ]
        for c in allComps {
            div.compare(label, "component(\(c))", icu.component(c, from: d), ours.component(c, from: d))
        }

        let allSet: Set<Calendar.Component> = Set(allComps + [.calendar, .timeZone])
        div.compareSet(label, "dateComponents([.all], from:)",
                       icu.dateComponents(allSet, from: d),
                       ours.dateComponents(allSet, from: d))

        div.compareSet(label, "dateComponents(in: cal.tz, from:)",
                       icu.dateComponents(in: icu.timeZone, from: d),
                       ours.dateComponents(in: ours.timeZone, from: d))

        div.compare(label, "startOfDay(for:)",
                    "\(icu.startOfDay(for: d))",
                    "\(ours.startOfDay(for: d))")

        for c in allComps where c != .nanosecond {
            let a = icu.dateInterval(of: c, for: d)
            let b = ours.dateInterval(of: c, for: d)
            div.compare(label, "dateInterval(\(c)).start",
                        a.map { "\($0.start)" },
                        b.map { "\($0.start)" })
            div.compare(label, "dateInterval(\(c)).duration",
                        a.map { Int($0.duration) },
                        b.map { Int($0.duration) })
        }

        let rangePairs: [(Calendar.Component, Calendar.Component)] = [
            (.day, .year), (.day, .month), (.month, .year),
            (.weekOfYear, .year), (.weekOfMonth, .month),
            (.hour, .day), (.minute, .hour), (.second, .minute),
            (.weekdayOrdinal, .month), (.weekday, .month), (.weekday, .year)
        ]
        for (s, l) in rangePairs {
            div.compare(label, "range(\(s),\(l))",
                        icu.range(of: s, in: l, for: d).map { "\($0.lowerBound)..<\($0.upperBound)" },
                        ours.range(of: s, in: l, for: d).map { "\($0.lowerBound)..<\($0.upperBound)" })
        }

        let ordPairs: [(Calendar.Component, Calendar.Component)] = [
            (.day, .year), (.day, .month), (.month, .year), (.hour, .day),
            (.weekOfYear, .year), (.weekOfMonth, .month),
            (.weekday, .year), (.weekday, .month), (.weekday, .weekOfYear),
            (.weekdayOrdinal, .month),
            (.minute, .hour), (.second, .minute)
        ]
        for (s, l) in ordPairs {
            div.compare(label, "ordinality(\(s),\(l))",
                        icu.ordinality(of: s, in: l, for: d),
                        ours.ordinality(of: s, in: l, for: d))
        }

        let ymdH = icu.dateComponents([.era, .year, .month, .day, .hour], from: d)
        div.compare(label, "date(from: dc).roundTrip",
                    "\(icu.date(from: ymdH) ?? Date.distantPast)",
                    "\(ours.date(from: ymdH) ?? Date.distantPast)")

        let adds: [(Calendar.Component, Int)] = [
            (.day, 1), (.day, -1), (.day, 30), (.day, 365),
            (.month, 1), (.month, -1), (.month, 6), (.month, 12),
            (.year, 1), (.year, -1), (.year, 5),
            (.hour, 1), (.hour, 24), (.minute, 1), (.second, 1),
            (.weekOfYear, 1), (.weekOfMonth, 1), (.weekdayOrdinal, 1),
            (.yearForWeekOfYear, 1),
        ]
        for (c, v) in adds {
            div.compare(label, "date(byAdding:\(c), value:\(v))",
                        icu.date(byAdding: c, value: v, to: d).map { "\($0)" },
                        ours.date(byAdding: c, value: v, to: d).map { "\($0)" })
        }

        var multi = DateComponents()
        multi.year = 1; multi.month = 2; multi.day = 3; multi.hour = 4
        div.compare(label, "date(byAdding: multi)",
                    icu.date(byAdding: multi, to: d).map { "\($0)" },
                    ours.date(byAdding: multi, to: d).map { "\($0)" })

        div.compare(label, "date(byAdding:.day, value:1, wrapping:true)",
                    icu.date(byAdding: .day, value: 1, to: d, wrappingComponents: true).map { "\($0)" },
                    ours.date(byAdding: .day, value: 1, to: d, wrappingComponents: true).map { "\($0)" })

        for (c, v) in [(Calendar.Component.hour, 18),
                       (.minute, 30),
                       (.day, 15)] {
            div.compare(label, "date(bySetting:\(c), value:\(v))",
                        icu.date(bySetting: c, value: v, of: d).map { "\($0)" },
                        ours.date(bySetting: c, value: v, of: d).map { "\($0)" })
        }

        div.compare(label, "date(bySettingHour:6, minute:15, second:30)",
                    icu.date(bySettingHour: 6, minute: 15, second: 30, of: d).map { "\($0)" },
                    ours.date(bySettingHour: 6, minute: 15, second: 30, of: d).map { "\($0)" })

        let d2 = d.addingTimeInterval(86400 * 3)
        for c in allComps where c != .nanosecond {
            div.compare(label, "compare(d, d+3d, .\(c))",
                        "\(icu.compare(d, to: d2, toGranularity: c).rawValue)",
                        "\(ours.compare(d, to: d2, toGranularity: c).rawValue)")
        }
        let d3 = d.addingTimeInterval(86400 * 60)
        for c in [Calendar.Component.day, .month, .year, .weekOfYear, .weekOfMonth] {
            div.compare(label, "compare(d, d+60d, .\(c))",
                        "\(icu.compare(d, to: d3, toGranularity: c).rawValue)",
                        "\(ours.compare(d, to: d3, toGranularity: c).rawValue)")
        }

        for c in allComps where c != .nanosecond {
            div.compare(label, "isDate(equalTo: d+3d, .\(c))",
                        icu.isDate(d, equalTo: d2, toGranularity: c),
                        ours.isDate(d, equalTo: d2, toGranularity: c))
        }

        div.compare(label, "isDate(d, inSameDayAs: d)",
                    icu.isDate(d, inSameDayAs: d),
                    ours.isDate(d, inSameDayAs: d))
        div.compare(label, "isDate(d, inSameDayAs: d+3d)",
                    icu.isDate(d, inSameDayAs: d2),
                    ours.isDate(d, inSameDayAs: d2))

        let matchingDC = icu.dateComponents([.year, .month, .day], from: d)
        div.compare(label, "date(d, matchesComponents: y/m/d)",
                    icu.date(d, matchesComponents: matchingDC),
                    ours.date(d, matchesComponents: matchingDC))
        var wrong = matchingDC
        wrong.day = (wrong.day ?? 1) + 1
        div.compare(label, "date(d, matchesComponents: y/m/d+1)",
                    icu.date(d, matchesComponents: wrong),
                    ours.date(d, matchesComponents: wrong))

        div.compare(label, "isDateInWeekend(d)",
                    icu.isDateInWeekend(d),
                    ours.isDateInWeekend(d))
        let d_sat = d.addingTimeInterval(86400.0 * Double((7 - icu.component(.weekday, from: d)) % 7))
        div.compare(label, "isDateInWeekend(nextSaturday)",
                    icu.isDateInWeekend(d_sat),
                    ours.isDateInWeekend(d_sat))

        let icuWknd = icu.dateIntervalOfWeekend(containing: d)
        let ourWknd = ours.dateIntervalOfWeekend(containing: d)
        div.compare(label, "dateIntervalOfWeekend(d).start",
                    icuWknd.map { "\($0.start)" },
                    ourWknd.map { "\($0.start)" })
        div.compare(label, "dateIntervalOfWeekend(d).duration",
                    icuWknd.map { Int($0.duration) },
                    ourWknd.map { Int($0.duration) })

        for direction in [Calendar.SearchDirection.forward, .backward] {
            let icuNext = icu.nextWeekend(startingAfter: d, direction: direction)
            let ourNext = ours.nextWeekend(startingAfter: d, direction: direction)
            div.compare(label, "nextWeekend(d, \(direction)).start",
                        icuNext.map { "\($0.start)" },
                        ourNext.map { "\($0.start)" })
            div.compare(label, "nextWeekend(d, \(direction)).duration",
                        icuNext.map { Int($0.duration) },
                        ourNext.map { Int($0.duration) })
        }

        func collect(_ cal: Calendar, start: Date, dc: DateComponents, count: Int) -> [Date] {
            var result: [Date] = []
            cal.enumerateDates(startingAfter: start, matching: dc, matchingPolicy: .nextTime) { date, _, stop in
                if let date = date { result.append(date) }
                if result.count >= count { stop = true }
            }
            return result
        }
        let christmasDC = DateComponents(month: 12, day: 25)
        let icuXmas = collect(icu, start: d, dc: christmasDC, count: 3)
        let ourXmas = collect(ours, start: d, dc: christmasDC, count: 3)
        div.compare(label, "enumerateDates(Christmas).count",
                    icuXmas.count, ourXmas.count)
        for i in 0..<min(icuXmas.count, ourXmas.count) {
            div.compare(label, "enumerateDates(Christmas)[\(i)]",
                        "\(icuXmas[i])", "\(ourXmas[i])")
        }

        let songkranDC = DateComponents(month: 4, day: 13)
        let icuSong = collect(icu, start: d, dc: songkranDC, count: 3)
        let ourSong = collect(ours, start: d, dc: songkranDC, count: 3)
        div.compare(label, "enumerateDates(Songkran).count",
                    icuSong.count, ourSong.count)
        for i in 0..<min(icuSong.count, ourSong.count) {
            div.compare(label, "enumerateDates(Songkran)[\(i)]",
                        "\(icuSong[i])", "\(ourSong[i])")
        }

        div.compare(label, "nextDate(after: d, matching: Christmas)",
                    icu.nextDate(after: d, matching: christmasDC, matchingPolicy: .nextTime).map { "\($0)" },
                    ours.nextDate(after: d, matching: christmasDC, matchingPolicy: .nextTime).map { "\($0)" })

        let diffIcu = icu.dateComponents([.year, .month, .day], from: d, to: d3)
        let diffOur = ours.dateComponents([.year, .month, .day], from: d, to: d3)
        div.compareSet(label, "dateComponents([y,m,d], from:d, to:d+60)", diffIcu, diffOur)
    }

    private static func reportAndAssert(_ topic: String, _ div: Divergences, dateCount: Int) {
        print("\n=== \(topic): \(dateCount) dates ===")
        if div.list.isEmpty {
            print("  ✓ zero divergences across the public Calendar API")
        } else {
            print("  ✘ \(div.list.count) divergences:")
            for msg in div.list.prefix(80) { print("    \(msg)") }
            if div.list.count > 80 {
                print("    … (truncated at 80; total \(div.list.count))")
            }
        }
        #expect(div.list.isEmpty, "[\(topic)] \(div.list.count) divergences")
    }

    // MARK: - Topic 1: public-API sweep

    @Test func publicAPI_sweepAllMethods() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
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
            Self.compareSurfaces(label: label, date: date, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("publicAPI_sweepAllMethods", div, dateCount: dates.count)
    }

    // MARK: - Topic 2: DST time zones

    @Test func dstTimezones_americaLosAngeles() {
        guard let la = TimeZone(identifier: "America/Los_Angeles") else { return }
        let (icu, ours) = Self.makePair(timeZone: la)
        let div = Divergences()
        let dates: [(String, Date)] = [
            ("2024-03-10 spring forward", Self.g(2024, 3, 10, hour: 2, in: la)),
            ("2024-03-10 1:59 before",    Self.g(2024, 3, 10, hour: 1, minute: 59, in: la)),
            ("2024-03-10 3:00 after",     Self.g(2024, 3, 10, hour: 3, in: la)),
            ("2024-11-03 fall back",      Self.g(2024, 11, 3, hour: 1, minute: 30, in: la)),
            ("2024-11-03 1:59 amb",       Self.g(2024, 11, 3, hour: 1, minute: 59, in: la)),
            ("2024-11-03 2:00 after",     Self.g(2024, 11, 3, hour: 2, in: la)),
            ("2025-06-21 summer solstice", Self.g(2025, 6, 21, in: la)),
            ("2025-12-21 winter solstice", Self.g(2025, 12, 21, in: la)),
        ]
        for (label, date) in dates {
            Self.compareSurfaces(label: label, date: date, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("dstTimezones_americaLosAngeles", div, dateCount: dates.count)
    }

    // MARK: - Topic 3: locale variations (firstWeekday + minDays)

    @Test func localeVariations_firstWeekdayAndMinDays() {
        let configs: [(label: String, fw: Int, md: Int)] = [
            ("US (fw=1, md=1)", 1, 1),
            ("ISO (fw=2, md=4)", 2, 4),
            ("Sat-start (fw=7, md=1)", 7, 1),
            ("fw=5 md=3", 5, 3),
        ]
        let dates: [(String, Date)] = [
            ("2025-01-01", Self.g(2025, 1, 1)),
            ("2025-06-15", Self.g(2025, 6, 15)),
            ("2025-12-31", Self.g(2025, 12, 31)),
            ("2020-01-04", Self.g(2020, 1, 4)),
            ("2030-12-29", Self.g(2030, 12, 29)),
        ]
        let div = Divergences()
        for cfg in configs {
            let (icu, ours) = Self.makePair(firstWeekday: cfg.fw, minimumDaysInFirstWeek: cfg.md)
            for (label, date) in dates {
                Self.compareSurfaces(label: "\(cfg.label) | \(label)", date: date,
                                     icu: icu, ours: ours, div: div)
            }
        }
        Self.reportAndAssert("localeVariations_firstWeekdayAndMinDays", div,
                             dateCount: configs.count * dates.count)
    }

    // MARK: - Topic 4: year boundaries (leap + common Gregorian years)

    @Test func yearBoundaries_commonAndLeap() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        var dates: [(String, Date)] = []
        for y in [1900, 2000, 2020, 2024, 2100, 2400] {
            dates.append(("\(y)-01-01 00:00", Self.g(y, 1, 1, hour: 0)))
            dates.append(("\(y)-12-31 23:59", Self.g(y, 12, 31, hour: 23, minute: 59, second: 59)))
            dates.append(("\(y)-02-28 noon",  Self.g(y, 2, 28)))
        }
        for (label, date) in dates {
            Self.compareSurfaces(label: label, date: date, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("yearBoundaries_commonAndLeap", div, dateCount: dates.count)
    }

    // MARK: - Topic 5: month boundaries

    @Test func monthBoundaries_allMonths() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        var dates: [(String, Date)] = []
        let year = 2025
        for m in 1...12 {
            dates.append(("\(year)-\(m)-01 noon", Self.g(year, m, 1)))
            let nextMonth = m == 12 ? Self.g(year + 1, 1, 1) : Self.g(year, m + 1, 1)
            dates.append(("\(year)-\(m)-last noon", nextMonth.addingTimeInterval(-86400)))
        }
        for (label, date) in dates {
            Self.compareSurfaces(label: label, date: date, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("monthBoundaries_allMonths", div, dateCount: dates.count)
    }

    // MARK: - Topic 6: time-of-day edges

    @Test func timeOfDay_edgeCases() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        let baseDay = Self.g(2025, 6, 15, hour: 0)
        var dates: [(String, Date)] = []
        for (h, m, s, label) in [
            (0, 0, 0, "midnight"),
            (0, 0, 1, "00:00:01"),
            (11, 59, 59, "11:59:59"),
            (12, 0, 0, "noon"),
            (23, 59, 59, "23:59:59"),
        ] {
            dates.append((label, baseDay.addingTimeInterval(TimeInterval(h * 3600 + m * 60 + s))))
        }
        for (label, date) in dates {
            Self.compareSurfaces(label: label, date: date, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("timeOfDay_edgeCases", div, dateCount: dates.count)
    }

    // MARK: - Topic 7: far past + future

    @Test func farPastAndFarFuture() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        var dates: [(String, Date)] = []
        for y in [1582, 1700, 1800, 2150, 2500, 3000] {
            dates.append(("\(y)-06-15 noon", Self.g(y, 6, 15)))
        }
        for (label, date) in dates {
            Self.compareSurfaces(label: label, date: date, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("farPastAndFarFuture", div, dateCount: dates.count)
    }

    // MARK: - Topic 8: week-of-year wrap

    @Test func weekOfYear_yearWrap() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        var dates: [(String, Date)] = []
        for y in stride(from: 2000, through: 2030, by: 5) {
            for (m, d) in [(12, 29), (12, 30), (12, 31), (1, 1), (1, 2), (1, 3)] {
                let actualY = m == 12 ? y : y + 1
                dates.append(("\(actualY)-\(m)-\(d) noon", Self.g(actualY, m, d)))
            }
        }
        for (label, date) in dates {
            Self.compareSurfaces(label: label, date: date, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("weekOfYear_yearWrap", div, dateCount: dates.count)
    }
}
