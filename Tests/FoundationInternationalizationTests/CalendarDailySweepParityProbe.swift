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

/// Exhaustive day-by-day parity vs ICU. The sampled suites (A/B/C) cover the
/// API surface; these sweeps close the gap between samples: every single day
/// is compared on the core field set, so an era/year/week divergence anywhere
/// in the range cannot hide between anchors. Also covers pre-Taika dates
/// (before the first Japanese era, 645-06-19), which no other suite touches.
@Suite("Buddhist+Japanese Daily Sweep Parity Probe")
private struct CalendarDailySweepParityProbe {

    private static let fields: Calendar.ComponentSet = [
        .era, .year, .month, .day, .dayOfYear, .weekday, .weekOfYear, .yearForWeekOfYear
    ]

    private static func g(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d; dc.hour = 12
        dc.timeZone = .gmt
        return cal.date(from: dc)!
    }

    private static func compareDay(_ icu: any _CalendarProtocol, _ ours: any _CalendarProtocol,
                                   date: Date, label: String, failures: inout [String]) {
        let ic = icu.dateComponents(Self.fields, from: date, in: .gmt)
        let oc = ours.dateComponents(Self.fields, from: date, in: .gmt)
        if ic.era != oc.era || ic.year != oc.year || ic.month != oc.month || ic.day != oc.day
            || ic.dayOfYear != oc.dayOfYear || ic.weekday != oc.weekday
            || ic.weekOfYear != oc.weekOfYear || ic.yearForWeekOfYear != oc.yearForWeekOfYear {
            failures.append("[\(label)] ICU=e\(ic.era ?? -1)/y\(ic.year ?? -1)/m\(ic.month ?? -1)/d\(ic.day ?? -1)/doy\(ic.dayOfYear ?? -1)/wd\(ic.weekday ?? -1)/woy\(ic.weekOfYear ?? -1)/yfw\(ic.yearForWeekOfYear ?? -1) ours=e\(oc.era ?? -1)/y\(oc.year ?? -1)/m\(oc.month ?? -1)/d\(oc.day ?? -1)/doy\(oc.dayOfYear ?? -1)/wd\(oc.weekday ?? -1)/woy\(oc.weekOfYear ?? -1)/yfw\(oc.yearForWeekOfYear ?? -1)")
        }
    }

    private static func sweep(_ icu: any _CalendarProtocol, _ ours: any _CalendarProtocol,
                              from start: Date, to end: Date, stepDays: Int = 1,
                              labelPrefix: String, skip: ((Date) -> Bool)? = nil,
                              failures: inout [String]) -> Int {
        var date = start
        var count = 0
        let step = 86400.0 * Double(stepDays)
        while date <= end {
            if skip?(date) != true {
                Self.compareDay(icu, ours, date: date, label: "\(labelPrefix) \(date)", failures: &failures)
            }
            count += 1
            if failures.count > 200 { break }  // enough to diagnose; don't flood
            date = date.addingTimeInterval(step)
        }
        return count
    }

    private static func reportAndAssert(_ topic: String, days: Int, _ failures: [String]) {
        print("[\(topic)] days=\(days) failures=\(failures.count)")
        for f in failures.prefix(30) { print("    \(f)") }
        #expect(failures.isEmpty, "[\(topic)] \(failures.count) failures in \(days) days: \(failures.prefix(5))")
    }

    // MARK: - Daily sweeps

    /// Every day from Meiji 1 (1868) through 2100 — covers all five modern era
    /// transitions and every week/year wrap in the range.
    @Test func japanese_dailySweep_1868_2100() {
        let icu = _CalendarICU(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let ours = _CalendarJapanese(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures: [String] = []
        let days = Self.sweep(icu, ours, from: Self.g(1868, 1, 1), to: Self.g(2100, 12, 31),
                              labelPrefix: "ja", failures: &failures)
        Self.reportAndAssert("japanese_dailySweep_1868_2100", days: days, failures)
    }

    /// Every day 1900–2100 for the Buddhist calendar.
    @Test func buddhist_dailySweep_1900_2100() {
        let icu = _CalendarICU(identifier: .buddhist, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let ours = _CalendarBuddhist(identifier: .buddhist, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures: [String] = []
        let days = Self.sweep(icu, ours, from: Self.g(1900, 1, 1), to: Self.g(2100, 12, 31),
                              labelPrefix: "bud", failures: &failures)
        Self.reportAndAssert("buddhist_dailySweep_1900_2100", days: days, failures)
    }

    // MARK: - Pre-Taika (before the first Japanese era, 645-06-19)

    /// Sampled sweep well before the first era: every 30 days, years 200–643.
    @Test func japanese_preTaika_sampled() {
        let icu = _CalendarICU(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let ours = _CalendarJapanese(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures: [String] = []
        let days = Self.sweep(icu, ours, from: Self.g(200, 1, 1), to: Self.g(643, 12, 31), stepDays: 30,
                              labelPrefix: "preTaika", failures: &failures)
        Self.reportAndAssert("japanese_preTaika_sampled", days: days, failures)
    }

    /// Daily band across the Taika boundary itself (645-06-19).
    @Test func japanese_preTaika_boundaryBand() {
        let icu = _CalendarICU(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let ours = _CalendarJapanese(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures: [String] = []
        let days = Self.sweep(icu, ours, from: Self.g(644, 1, 1), to: Self.g(646, 12, 31),
                              labelPrefix: "taikaBand", failures: &failures)
        Self.reportAndAssert("japanese_preTaika_boundaryBand", days: days, failures)
    }

    /// Round-trip `dateComponents → date(from:)` parity for pre-Taika dates.
    @Test func japanese_preTaika_roundTrips() {
        let icu = _CalendarICU(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let ours = _CalendarJapanese(identifier: .japanese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var failures: [String] = []
        let dates = [Self.g(300, 6, 15), Self.g(500, 1, 1), Self.g(600, 12, 31), Self.g(645, 6, 18), Self.g(645, 6, 19)]
        for date in dates {
            // Decompose with ICU (ground truth), reconstruct with both, compare.
            let comps = icu.dateComponents([.era, .year, .month, .day, .hour], from: date, in: .gmt)
            let i = icu.date(from: comps)
            let o = ours.date(from: comps)
            if i != o {
                failures.append("[rt \(date)] comps=e\(comps.era ?? -1)/y\(comps.year ?? -1)/m\(comps.month ?? -1)/d\(comps.day ?? -1) ICU=\(String(describing: i)) ours=\(String(describing: o))")
            }
        }
        Self.reportAndAssert("japanese_preTaika_roundTrips", days: dates.count, failures)
    }

    // MARK: - Chinese

    /// Every day 1899–2102 (baked range + both fallback seams), excluding the
    /// documented registry windows (CHINESE_PLAN.md § 11.3): the two Apple-ICU
    /// dom=0 artifact years and the 2101-m6 fallback divergence.
    @Test func chinese_dailySweep_1899_2102() {
        let icu = _CalendarICU(identifier: .chinese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let ours = _CalendarChinese(identifier: .chinese, timeZone: .gmt, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let excluded: [ClosedRange<Date>] = [
            Self.g(2057, 2, 1)...Self.g(2058, 2, 20),
            Self.g(2097, 2, 1)...Self.g(2098, 2, 20),
            Self.g(2101, 6, 24)...Self.g(2101, 7, 27),
        ]
        var failures: [String] = []
        let days = Self.sweep(icu, ours, from: Self.g(1899, 1, 1), to: Self.g(2102, 12, 31),
                              labelPrefix: "chn",
                              skip: { d in excluded.contains { $0.contains(d) } },
                              failures: &failures)
        Self.reportAndAssert("chinese_dailySweep_1899_2102", days: days, failures)
    }
}
