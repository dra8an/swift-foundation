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

@Suite("Japanese Calendar Public API Probe")
private struct ChinesePublicAPIComparisonProbe {

    private static func makePair(timeZone: TimeZone = .gmt,
                                 firstWeekday: Int? = nil,
                                 minimumDaysInFirstWeek: Int? = nil) -> (icu: Calendar, ours: Calendar) {
        let icuInner = _CalendarICU(
            identifier: .chinese, timeZone: timeZone, locale: nil,
            firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek, gregorianStartDate: nil
        )
        let oursInner = _CalendarChinese(
            identifier: .chinese, timeZone: timeZone, locale: nil,
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
                ("isLeapMonth", (icu.isLeapMonth ?? false) ? 1 : 0, (ours.isLeapMonth ?? false) ? 1 : 0),
                // quarter omitted: ICU returns 0 for year-wrap dates (same bug as Buddhist)
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

        // .era omitted: ICU quirk, for Japanese eras with a successor, ICU sets
        // the era interval's end to `start.gregorianYear + (next.gregorianYear -
        // start.gregorianYear)` at the start's month/day, ignoring the next era's
        // actual month/day. e.g. Heisei ends 2019-01-08 per ICU vs the actual
        // Reiwa start 2019-05-01. Our impl returns the semantically correct
        // [era.start, next-era.start) range, so durations diverge.
        // .yearForWeekOfYear also omitted: deliberate ICU divergence (§ 11.21).
        for c in allComps where c != .nanosecond && c != .era && c != .yearForWeekOfYear {
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
            // (.yearForWeekOfYear, 1) omitted: deliberate ICU divergence (§ 11.21)
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
        let christmasDC = DateComponents(month: 1, day: 1)   // Chinese New Year
        let icuXmas = collect(icu, start: d, dc: christmasDC, count: 3)
        let ourXmas = collect(ours, start: d, dc: christmasDC, count: 3)
        div.compare(label, "enumerateDates(Christmas).count",
                    icuXmas.count, ourXmas.count)
        for i in 0..<min(icuXmas.count, ourXmas.count) {
            div.compare(label, "enumerateDates(Christmas)[\(i)]",
                        "\(icuXmas[i])", "\(ourXmas[i])")
        }

        let constitutionDC = DateComponents(month: 8, day: 15)   // Mid-Autumn
        let icuConst = collect(icu, start: d, dc: constitutionDC, count: 3)
        let ourConst = collect(ours, start: d, dc: constitutionDC, count: 3)
        div.compare(label, "enumerateDates(May3).count",
                    icuConst.count, ourConst.count)
        for i in 0..<min(icuConst.count, ourConst.count) {
            div.compare(label, "enumerateDates(May3)[\(i)]",
                        "\(icuConst[i])", "\(ourConst[i])")
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

    // MARK: - Topic 1: public-API sweep across the baked range

    @Test func chinesePublicAPI_sweepAllMethods() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        let dates: [(String, Date)] = [
            ("1902-06-15", Self.g(1902, 6, 15)),
            ("1925-01-24 CNY", Self.g(1925, 1, 24)),
            ("1944-08-15", Self.g(1944, 8, 15)),
            ("1968-02-14", Self.g(1968, 2, 14)),
            ("1988-10-01", Self.g(1988, 10, 1)),
            ("2006-08-15 leap-7", Self.g(2006, 8, 15)),
            ("2020-05-23 leap-4 d1", Self.g(2020, 5, 23)),
            ("2033-12-25 leap-11", Self.g(2033, 12, 25)),
            ("2077-07-07", Self.g(2077, 7, 7)),
            ("2099-11-30", Self.g(2099, 11, 30)),
        ]
        for (label, d) in dates {
            Self.compareSurfaces(label: label, date: d, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("chinesePublicAPI_sweepAllMethods", div, dateCount: dates.count)
    }

    // MARK: - Topic 2: DST time zones

    @Test func chineseDstTimezones_americaLosAngeles() {
        guard let la = TimeZone(identifier: "America/Los_Angeles") else { return }
        let (icu, ours) = Self.makePair(timeZone: la)
        let div = Divergences()
        let dates: [(String, Date)] = [
            ("springForward-eve", Self.g(2024, 3, 9, hour: 20, in: la)),
            ("springForward-day", Self.g(2024, 3, 10, hour: 12, in: la)),
            ("fallBack-day", Self.g(2024, 11, 3, hour: 12, in: la)),
            ("CNY-2024-LA", Self.g(2024, 2, 10, in: la)),
        ]
        for (label, d) in dates {
            Self.compareSurfaces(label: label, date: d, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("chineseDstTimezones_americaLosAngeles", div, dateCount: dates.count)
    }

    // MARK: - Topic 3: locale variations (firstWeekday + minDays)

    @Test func chineseLocaleVariations_firstWeekdayAndMinDays() {
        let div = Divergences()
        var count = 0
        for (fw, md) in [(2, 4), (1, 1), (7, 7)] {
            let (icu, ours) = Self.makePair(firstWeekday: fw, minimumDaysInFirstWeek: md)
            for (label, d) in [
                ("CNY-2025 fw\(fw)md\(md)", Self.g(2025, 1, 29)),
                ("mid-2025 fw\(fw)md\(md)", Self.g(2025, 7, 4)),
            ] {
                Self.compareSurfaces(label: label, date: d, icu: icu, ours: ours, div: div)
                count += 1
            }
        }
        Self.reportAndAssert("chineseLocaleVariations_firstWeekdayAndMinDays", div, dateCount: count)
    }

    // MARK: - Topic 4: Chinese New Year boundaries

    @Test func chineseYearBoundaries_publicAPI() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        var count = 0
        for iso in [1913, 1953, 1998, 2024, 2081] {
            let ny = _CalendarChinese.year(relatedISOYear: iso).newYearRataDie
            for delta in [-1, 0] {
                let rd = ny + delta
                let d = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
                Self.compareSurfaces(label: "CNY \(iso)\(delta >= 0 ? "+" : "")\(delta)", date: d, icu: icu, ours: ours, div: div)
                count += 1
            }
        }
        Self.reportAndAssert("chineseYearBoundaries_publicAPI", div, dateCount: count)
    }

    // MARK: - Topic 5: month boundaries through a leap year

    @Test func chineseMonthBoundaries_leapYear2020() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        var count = 0
        let y = _CalendarChinese.year(relatedISOYear: 2020)
        for ordinal in 1...Int(y.monthCount) {
            let start = y.monthStartRataDie(ordinal: ordinal)
            let last = start + y.monthLength(ordinal: ordinal) - 1
            for rd in [start, last] {
                let d = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
                Self.compareSurfaces(label: "2020 ord\(ordinal) rd\(rd)", date: d, icu: icu, ours: ours, div: div)
                count += 1
            }
        }
        Self.reportAndAssert("chineseMonthBoundaries_leapYear2020", div, dateCount: count)
    }

    // MARK: - Topic 6: time-of-day edges

    @Test func chineseTimeOfDay_edgeCases() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        let base = Self.g(2025, 6, 15, hour: 0)
        var count = 0
        for (h, m, sec, label) in [
            (0, 0, 0, "midnight"), (11, 59, 59, "11:59:59"),
            (12, 0, 0, "noon"), (23, 59, 59, "23:59:59"),
        ] {
            let d = base.addingTimeInterval(TimeInterval(h * 3600 + m * 60 + sec))
            Self.compareSurfaces(label: label, date: d, icu: icu, ours: ours, div: div)
            count += 1
        }
        Self.reportAndAssert("chineseTimeOfDay_edgeCases", div, dateCount: count)
    }

    // MARK: - Topic 7: leap-month public-API behaviour (Chinese-specific)

    @Test func chineseLeapMonth_publicAPI() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        let dates: [(String, Date)] = [
            ("m4L-2020 d1", Self.g(2020, 5, 23)),
            ("m4L-2020 mid", Self.g(2020, 6, 5)),
            ("m4L-2020 last", Self.g(2020, 6, 20)),
            ("m2L-2023 d1", Self.g(2023, 3, 22)),
            ("m11L-2033 d1", Self.g(2033, 12, 22)),
            ("m6L-2025 d1", Self.g(2025, 7, 25)),
        ]
        for (label, d) in dates {
            Self.compareSurfaces(label: label, date: d, icu: icu, ours: ours, div: div)
        }
        Self.reportAndAssert("chineseLeapMonth_publicAPI", div, dateCount: dates.count)
    }

    // MARK: - Topic 8: week-of-year wrap

    @Test func chineseWeekOfYear_yearWrap() {
        let (icu, ours) = Self.makePair()
        let div = Divergences()
        var count = 0
        for iso in stride(from: 1990, through: 2030, by: 5) {
            let ny = _CalendarChinese.year(relatedISOYear: iso).newYearRataDie
            for delta in [-3, -1, 0, 1, 3] {
                let rd = ny + delta
                let d = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
                Self.compareSurfaces(label: "wrap \(iso) \(delta)", date: d, icu: icu, ours: ours, div: div)
                count += 1
            }
        }
        Self.reportAndAssert("chineseWeekOfYear_yearWrap", div, dateCount: count)
    }
}
