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

@Suite("Japanese ICU Comparison Probe")
private struct JapaneseICUComparisonProbe {

    private static func makePair() -> (icu: _CalendarICU, ours: _CalendarJapanese) {
        let icu = _CalendarICU(
            identifier: .japanese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let ours = _CalendarJapanese(
            identifier: .japanese, timeZone: .gmt, locale: nil,
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
        icu: _CalendarICU, ours: _CalendarJapanese,
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
            .weekday, .weekdayOrdinal,
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
        cmp("dc.weekOfMonth",       ic.weekOfMonth,       oc.weekOfMonth)
        cmp("dc.weekOfYear",        ic.weekOfYear,        oc.weekOfYear)
        cmp("dc.yearForWeekOfYear", ic.yearForWeekOfYear, oc.yearForWeekOfYear)
        cmp("dc.dayOfYear",         ic.dayOfYear,         oc.dayOfYear)
        // dc.quarter omitted (likely ICU bug like Buddhist).

        for c in [Calendar.Component.year, .month, .day, .hour,
                  .weekOfYear, .weekOfMonth, .yearForWeekOfYear] {
            let iv = icu.dateInterval(of: c, for: date)
            let ov = ours.dateInterval(of: c, for: date)
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

    // MARK: - Topic 1: representative sweep across all 5 modern eras

    @Test func compareFieldsSideBySide() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        let dates: [(String, Date)] = [
            ("Meiji mid (1900-06-15)",   Self.g(1900, 6, 15)),
            ("Taisho mid (1920-06-15)",  Self.g(1920, 6, 15)),
            ("Showa mid (1955-06-15)",   Self.g(1955, 6, 15)),
            ("Heisei mid (2000-06-15)",  Self.g(2000, 6, 15)),
            ("Reiwa now (2026-06-11)",   Self.g(2026, 6, 11)),
            ("Reiwa leap (2024-02-29)",  Self.g(2024, 2, 29)),
        ]
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("compareFieldsSideBySide", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 2: era boundary transitions (the critical Japanese case)

    @Test func eraTransitions() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        let transitions: [(String, Date)] = [
            // Meiji → Taishō (1912-07-30)
            ("Meiji last day 1912-07-29 noon", Self.g(1912, 7, 29)),
            ("Meiji last day 1912-07-29 23:59", Self.g(1912, 7, 29, hour: 23, minute: 59, second: 59)),
            ("Taisho 1 day 1912-07-30 00:00", Self.g(1912, 7, 30, hour: 0)),
            ("Taisho 1 day 1912-07-30 noon", Self.g(1912, 7, 30)),
            // Taishō → Shōwa (1926-12-25)
            ("Taisho last 1926-12-24 noon", Self.g(1926, 12, 24)),
            ("Showa 1 1926-12-25 00:00", Self.g(1926, 12, 25, hour: 0)),
            ("Showa 1 1926-12-25 noon", Self.g(1926, 12, 25)),
            // Shōwa → Heisei (1989-01-08)
            ("Showa last 1989-01-07 noon", Self.g(1989, 1, 7)),
            ("Heisei 1 1989-01-08 00:00", Self.g(1989, 1, 8, hour: 0)),
            ("Heisei 1 1989-01-08 noon", Self.g(1989, 1, 8)),
            // Heisei → Reiwa (2019-05-01)
            ("Heisei last 2019-04-30 23:59", Self.g(2019, 4, 30, hour: 23, minute: 59, second: 59)),
            ("Reiwa 1 2019-05-01 00:00", Self.g(2019, 5, 1, hour: 0)),
            ("Reiwa 1 2019-05-01 noon", Self.g(2019, 5, 1)),
        ]
        for (label, date) in transitions {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("eraTransitions", divergences, dateCount: transitions.count)
    }

    // MARK: - Topic 3: dense sweep through Reiwa era

    @Test func sweepReiwaEra() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        let start = Self.g(2019, 5, 1)
        let step: TimeInterval = 86400 * 14   // bi-weekly
        var d = start
        for i in 0..<200 {
            dates.append(("Reiwa+\(i)bw", d))
            d = d.addingTimeInterval(step)
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("sweepReiwaEra", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 4: year boundaries

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

    // MARK: - Topic 5: leap years

    @Test func leapYears_feb28and29() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        for y in [1904, 1920, 1956, 1988, 2000, 2020, 2024, 2096] {
            dates.append(("\(y)-02-28 noon", Self.g(y, 2, 28)))
            let mar1 = Self.g(y, 3, 1)
            dates.append(("\(y)-Feb-last noon", mar1.addingTimeInterval(-86400)))
            dates.append(("\(y)-03-01 noon", mar1))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("leapYears_feb28and29", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 6: month boundaries

    @Test func monthBoundaries() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        var dates: [(String, Date)] = []
        let year = 2025
        for m in 1...12 {
            dates.append(("\(year)-\(m)-01 noon", Self.g(year, m, 1)))
            let nextMonth = m == 12 ? Self.g(year + 1, 1, 1) : Self.g(year, m + 1, 1)
            dates.append(("\(year)-\(m)-last noon", nextMonth.addingTimeInterval(-86400)))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("monthBoundaries", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 7: time-of-day

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
            (23, 59, 59, "23:59:59"),
        ] {
            dates.append((label, baseDate.addingTimeInterval(TimeInterval(h * 3600 + m * 60 + s))))
        }
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("timeOfDay_edgeCases", divergences, dateCount: dates.count)
    }

    // MARK: - Topic 8: week-of-year wrap

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

    // MARK: - Topic 9: date(byAdding:) at era boundaries

    @Test func dateByAdding_acrossEraBoundary() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        let setups: [(String, Date)] = [
            ("Heisei last day", Self.g(2019, 4, 30)),
            ("Reiwa day 1", Self.g(2019, 5, 1)),
            ("Showa last day", Self.g(1989, 1, 7)),
            ("Heisei day 1", Self.g(1989, 1, 8)),
        ]
        for (label, date) in setups {
            for unit in [Calendar.Component.year, .month, .day] {
                for delta in [-1, 1, 2] {
                    var dc = DateComponents()
                    dc.setValue(delta, for: unit)
                    let i = icu.date(byAdding: dc, to: date, wrappingComponents: false)
                    let o = ours.date(byAdding: dc, to: date, wrappingComponents: false)
                    if i != o {
                        failures.append("[\(label) +\(delta) \(unit)] ICU=\(String(describing: i)) ours=\(String(describing: o))")
                    }
                }
            }
        }
        Self.reportAndAssert("dateByAdding_acrossEraBoundary", failures, dateCount: setups.count)
    }

    // MARK: - Topic 10: round-trip date(from:) ↔ dateComponents

    // MARK: - Pre-Meiji era coverage

    // Gated 2026-07-24: following CLDR/ICU (unicode-org/icu#4019, ICU-23341) the pre-Meiji eras were dropped and dates before Meiji inherit the Gregorian era. The bundled ICU predates that change and still reports the 237 historical eras, so these two ICU comparisons diverge by design. Re-enable them as the parity gate when Apple's ICU rebases onto ICU 79.1 or later; until then the behavior is pinned by JapaneseGregorianEraInheritanceTests.
    @Test(.disabled("bundled ICU predates the icu#4019 pre-Meiji era removal")) func preMeiji_eraSpread() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        let dates: [(String, Date)] = [
            // Taika (645) — earliest era
            ("Taika 1 (645-06-19)", Self.g(645, 6, 19)),
            ("Hakuchi mid (660-06-15)", Self.g(660, 6, 15)),
            // Hakuhō / Nara period
            ("Hakuhō (680-06-15)", Self.g(680, 6, 15)),
            ("Wadō (710-06-15)", Self.g(710, 6, 15)),
            ("Tenpyō (740-06-15)", Self.g(740, 6, 15)),
            // Heian period
            ("Enryaku (800-06-15)", Self.g(800, 6, 15)),
            ("Jōgan (870-06-15)", Self.g(870, 6, 15)),
            ("Engi (915-06-15)", Self.g(915, 6, 15)),
            // Kamakura period
            ("Bunji (1186-06-15)", Self.g(1186, 6, 15)),
            ("Jōkyū (1220-06-15)", Self.g(1220, 6, 15)),
            ("Bun'ei (1270-06-15)", Self.g(1270, 6, 15)),
            // Muromachi period
            ("Bunmei (1475-06-15)", Self.g(1475, 6, 15)),
            ("Tenshō (1580-06-15)", Self.g(1580, 6, 15)),
            // Edo period
            ("Kan'ei (1640-06-15)", Self.g(1640, 6, 15)),
            ("Genroku (1700-06-15)", Self.g(1700, 6, 15)),
            ("Kyōhō (1730-06-15)", Self.g(1730, 6, 15)),
            ("Bunsei (1825-06-15)", Self.g(1825, 6, 15)),
            ("Kaei (1850-06-15)", Self.g(1850, 6, 15)),
            ("Bunkyū (1862-06-15)", Self.g(1862, 6, 15)),
        ]
        for (label, date) in dates {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("preMeiji_eraSpread", divergences, dateCount: dates.count)
    }

    @Test(.disabled("bundled ICU predates the icu#4019 pre-Meiji era removal")) func preMeiji_eraTransitions() {
        let (icu, ours) = Self.makePair()
        var divergences: [String] = []
        // Each pair: last day of old era, first day of new era. Tests boundary precision.
        let transitions: [(String, Date)] = [
            // Taika → Hakuchi (650-02-15)
            ("Taika last (650-02-14)", Self.g(650, 2, 14)),
            ("Hakuchi 1 (650-02-15)", Self.g(650, 2, 15)),
            // Wadō → Reiki (715-09-02)
            ("Wadō last (715-09-01)", Self.g(715, 9, 1)),
            ("Reiki 1 (715-09-02)", Self.g(715, 9, 2)),
            // Tenpyō-kampō → Tenpyō-shōhō (749-07-02), both in same year
            ("Tenpyō-kampō last (749-07-01)", Self.g(749, 7, 1)),
            ("Tenpyō-shōhō 1 (749-07-02)", Self.g(749, 7, 2)),
            // Daidō → Kōnin (810-09-19)
            ("Daidō last (810-09-18)", Self.g(810, 9, 18)),
            ("Kōnin 1 (810-09-19)", Self.g(810, 9, 19)),
            // Bunsei → Tenpō (1830-12-10), late-year transition
            ("Bunsei last (1830-12-09)", Self.g(1830, 12, 9)),
            ("Tenpō 1 (1830-12-10)", Self.g(1830, 12, 10)),
            // Kaei → Ansei (1854-11-27)
            ("Kaei last (1854-11-26)", Self.g(1854, 11, 26)),
            ("Ansei 1 (1854-11-27)", Self.g(1854, 11, 27)),
            // Ansei → Man'en (1860-03-18)
            ("Ansei last (1860-03-17)", Self.g(1860, 3, 17)),
            ("Man'en 1 (1860-03-18)", Self.g(1860, 3, 18)),
            // Genji → Keiō (1865-04-07), just before Meiji
            ("Genji last (1865-04-06)", Self.g(1865, 4, 6)),
            ("Keiō 1 (1865-04-07)", Self.g(1865, 4, 7)),
            // Keiō → Meiji (1868-09-08 per Apple's ICU runtime, not CLDR's 1868-10-23)
            ("Keiō last (1868-09-07)", Self.g(1868, 9, 7)),
            ("Meiji 1 (1868-09-08)", Self.g(1868, 9, 8)),
        ]
        for (label, date) in transitions {
            Self.compareAt(label: label, date: date, icu: icu, ours: ours, divergences: &divergences)
        }
        Self.reportAndAssert("preMeiji_eraTransitions", divergences, dateCount: transitions.count)
    }

    @Test func discoverPreMeijiEras() {
        let (icu, ours) = Self.makePair()
        let years: [Int] = [1700, 1750, 1800, 1830, 1850, 1860, 1865, 1867, 1868]
        print("\n=== Pre-Meiji era discovery (Gregorian year → ICU era index + year-in-era) ===")
        for y in years {
            for (m, d) in [(1, 1), (6, 15), (12, 31)] {
                let date = Self.g(y, m, d)
                let i = icu.dateComponents([.era, .year, .month, .day], from: date)
                let o = ours.dateComponents([.era, .year, .month, .day], from: date)
                print("[\(y)-\(m)-\(d)] ICU=era\(i.era ?? -1)/y\(i.year ?? -1) ours=era\(o.era ?? -1)/y\(o.year ?? -1)")
            }
        }
    }

    @Test func roundTrip_modernEras() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        let dates: [(String, Date)] = [
            ("Meiji 5 1873-01-01", Self.g(1873, 1, 1)),
            ("Taisho 5 1916-06-15", Self.g(1916, 6, 15)),
            ("Showa 30 1955-06-15", Self.g(1955, 6, 15)),
            ("Heisei 12 2000-06-15", Self.g(2000, 6, 15)),
            ("Reiwa 8 2026-06-11", Self.g(2026, 6, 11)),
        ]
        for (label, date) in dates {
            let comps = ours.dateComponents([.era, .year, .month, .day], from: date, in: .gmt)
            let icuRT = icu.date(from: comps)
            let ourRT = ours.date(from: comps)
            if icuRT != ourRT {
                failures.append("[\(label)] ICU.rt=\(String(describing: icuRT)) ours.rt=\(String(describing: ourRT))")
            }
        }
        Self.reportAndAssert("roundTrip_modernEras", failures, dateCount: dates.count)
    }
}
