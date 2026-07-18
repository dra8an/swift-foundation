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

/// Parity for the matching policies the other suites do not exercise:
/// `.strict` (incl. skipped leap days / short months / nonexistent DST times),
/// `repeatedTimePolicy` `.first` vs `.last` at DST fall-back, and
/// backward-direction enumeration under `.strict`.
@Suite("Buddhist+Japanese Strict Policy Parity Probe")
private struct CalendarStrictPolicyParityProbe {

    private static func makePair(_ identifier: Calendar.Identifier, timeZone: TimeZone = .gmt) -> (icu: Calendar, ours: Calendar) {
        let icuInner = _CalendarICU(
            identifier: identifier, timeZone: timeZone, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let oursInner: any _CalendarProtocol
        switch identifier {
        case .buddhist:
            oursInner = _CalendarBuddhist(identifier: identifier, timeZone: timeZone, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        case .japanese:
            oursInner = _CalendarJapanese(identifier: identifier, timeZone: timeZone, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        case .chinese:
            oursInner = _CalendarChinese(identifier: identifier, timeZone: timeZone, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        default:
            fatalError("unsupported identifier in probe")
        }
        return (Calendar(inner: icuInner), Calendar(inner: oursInner))
    }

    private static let calendars: [(String, Calendar.Identifier)] = [
        ("buddhist", .buddhist),
        ("japanese", .japanese),
        ("chinese", .chinese),
    ]

    private static func g(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, in tz: TimeZone = .gmt) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        dc.hour = hour; dc.minute = minute
        dc.timeZone = tz
        return cal.date(from: dc)!
    }

    private static func collect(_ cal: Calendar, after start: Date, matching dc: DateComponents,
                                policy: Calendar.MatchingPolicy,
                                repeated: Calendar.RepeatedTimePolicy = .first,
                                direction: Calendar.SearchDirection = .forward,
                                count: Int) -> [Date] {
        var result: [Date] = []
        cal.enumerateDates(startingAfter: start, matching: dc, matchingPolicy: policy, repeatedTimePolicy: repeated, direction: direction) { date, _, stop in
            if let date = date { result.append(date) }
            if result.count >= count { stop = true }
        }
        return result
    }

    private static func compare(_ label: String, _ icu: [Date], _ ours: [Date], failures: inout [String]) {
        if icu.count != ours.count {
            failures.append("[\(label)] count: ICU=\(icu.count) ours=\(ours.count)")
            return
        }
        for i in 0..<icu.count where icu[i] != ours[i] {
            failures.append("[\(label)][\(i)] ICU=\(icu[i]) ours=\(ours[i])")
        }
    }

    private static func reportAndAssert(_ topic: String, _ failures: [String]) {
        print("[\(topic)] failures=\(failures.count)")
        for f in failures.prefix(30) { print("    \(f)") }
        #expect(failures.isEmpty, "[\(topic)] \(failures.count) failures: \(failures.prefix(10))")
    }

    // MARK: - .strict where the pattern is periodically nonexistent

    /// Feb 29 yearly: `.strict` must skip common years; `.nextTime` approximates.
    @Test func strict_leapDayYearly() {
        var failures: [String] = []
        let dc = DateComponents(month: 2, day: 29)
        let anchors = [Self.g(2019, 6, 15), Self.g(2023, 1, 10)]
        for (calLabel, id) in Self.calendars {
            let (icu, ours) = Self.makePair(id)
            for policy in [Calendar.MatchingPolicy.strict, .nextTime] {
                for anchor in anchors {
                    let i = Self.collect(icu, after: anchor, matching: dc, policy: policy, count: 5)
                    let o = Self.collect(ours, after: anchor, matching: dc, policy: policy, count: 5)
                    Self.compare("\(calLabel) \(policy) from \(anchor)", i, o, failures: &failures)
                }
            }
        }
        Self.reportAndAssert("strict_leapDayYearly", failures)
    }

    /// Day 31 monthly: `.strict` must skip 30-day months and February.
    @Test func strict_day31Monthly() {
        var failures: [String] = []
        let dc = DateComponents(day: 31)
        let anchors = [Self.g(2025, 1, 15), Self.g(2024, 11, 2)]
        for (calLabel, id) in Self.calendars {
            let (icu, ours) = Self.makePair(id)
            for policy in [Calendar.MatchingPolicy.strict, .nextTime] {
                for anchor in anchors {
                    let i = Self.collect(icu, after: anchor, matching: dc, policy: policy, count: 8)
                    let o = Self.collect(ours, after: anchor, matching: dc, policy: policy, count: 8)
                    Self.compare("\(calLabel) \(policy) from \(anchor)", i, o, failures: &failures)
                }
            }
        }
        Self.reportAndAssert("strict_day31Monthly", failures)
    }

    /// Month+day+time pattern under `.strict`.
    @Test func strict_timePattern() {
        var failures: [String] = []
        let dc = DateComponents(month: 4, day: 13, hour: 18, minute: 30)
        let anchors = [Self.g(2020, 1, 1), Self.g(2025, 9, 23)]
        for (calLabel, id) in Self.calendars {
            let (icu, ours) = Self.makePair(id)
            for policy in [Calendar.MatchingPolicy.strict, .nextTime] {
                for anchor in anchors {
                    let i = Self.collect(icu, after: anchor, matching: dc, policy: policy, count: 4)
                    let o = Self.collect(ours, after: anchor, matching: dc, policy: policy, count: 4)
                    Self.compare("\(calLabel) \(policy) from \(anchor)", i, o, failures: &failures)
                }
            }
        }
        Self.reportAndAssert("strict_timePattern", failures)
    }

    // MARK: - DST interaction

    /// Fall-back: 1:30 AM occurs twice on 2024-11-03 in LA. `.first` vs `.last` must agree with ICU.
    @Test func dst_repeatedTime_firstVsLast() {
        guard let la = TimeZone(identifier: "America/Los_Angeles") else { return }
        var failures: [String] = []
        let dc = DateComponents(hour: 1, minute: 30)
        let anchor = Self.g(2024, 11, 2, in: la)
        for (calLabel, id) in Self.calendars {
            let (icu, ours) = Self.makePair(id, timeZone: la)
            for repeated in [Calendar.RepeatedTimePolicy.first, .last] {
                let i = Self.collect(icu, after: anchor, matching: dc, policy: .nextTime, repeated: repeated, count: 4)
                let o = Self.collect(ours, after: anchor, matching: dc, policy: .nextTime, repeated: repeated, count: 4)
                Self.compare("\(calLabel) repeated=\(repeated)", i, o, failures: &failures)
            }
        }
        Self.reportAndAssert("dst_repeatedTime_firstVsLast", failures)
    }

    /// Spring-forward: 2:30 AM does not exist on 2024-03-10 in LA. `.strict` vs `.nextTime`.
    @Test func dst_nonexistentTime() {
        guard let la = TimeZone(identifier: "America/Los_Angeles") else { return }
        var failures: [String] = []
        let dc = DateComponents(hour: 2, minute: 30)
        let anchor = Self.g(2024, 3, 9, in: la)
        for (calLabel, id) in Self.calendars {
            let (icu, ours) = Self.makePair(id, timeZone: la)
            for policy in [Calendar.MatchingPolicy.strict, .nextTime, .nextTimePreservingSmallerComponents] {
                let i = Self.collect(icu, after: anchor, matching: dc, policy: policy, count: 4)
                let o = Self.collect(ours, after: anchor, matching: dc, policy: policy, count: 4)
                Self.compare("\(calLabel) \(policy)", i, o, failures: &failures)
            }
        }
        Self.reportAndAssert("dst_nonexistentTime", failures)
    }

    // MARK: - Backward direction + nextDate under .strict

    @Test func backward_strict() {
        var failures: [String] = []
        let patterns: [(String, DateComponents)] = [
            ("feb29", DateComponents(month: 2, day: 29)),
            ("day31", DateComponents(day: 31)),
        ]
        let anchor = Self.g(2025, 6, 15)
        for (calLabel, id) in Self.calendars {
            let (icu, ours) = Self.makePair(id)
            for (pLabel, dc) in patterns {
                let i = Self.collect(icu, after: anchor, matching: dc, policy: .strict, direction: .backward, count: 4)
                let o = Self.collect(ours, after: anchor, matching: dc, policy: .strict, direction: .backward, count: 4)
                Self.compare("\(calLabel) \(pLabel) backward", i, o, failures: &failures)
            }
        }
        Self.reportAndAssert("backward_strict", failures)
    }

    @Test func nextDate_strict() {
        var failures: [String] = []
        let patterns: [(String, DateComponents)] = [
            ("feb29", DateComponents(month: 2, day: 29)),
            ("day31", DateComponents(day: 31)),
            ("m4d13h18", DateComponents(month: 4, day: 13, hour: 18)),
        ]
        let anchors = [Self.g(2023, 3, 1), Self.g(2024, 2, 28), Self.g(2025, 12, 30)]
        for (calLabel, id) in Self.calendars {
            let (icu, ours) = Self.makePair(id)
            for (pLabel, dc) in patterns {
                for anchor in anchors {
                    for direction in [Calendar.SearchDirection.forward, .backward] {
                        let i = icu.nextDate(after: anchor, matching: dc, matchingPolicy: .strict, direction: direction)
                        let o = ours.nextDate(after: anchor, matching: dc, matchingPolicy: .strict, direction: direction)
                        if i != o {
                            failures.append("[\(calLabel) \(pLabel) \(direction) from \(anchor)] ICU=\(String(describing: i)) ours=\(String(describing: o))")
                        }
                    }
                }
            }
        }
        Self.reportAndAssert("nextDate_strict", failures)
    }

    // MARK: - Chinese leap-month strict patterns (the Chinese analogue of Feb 29)

    /// {month: 4, isLeapMonth: true, day: 1} exists only in leap-4 years
    /// (2020, then 2058): `.strict` must skip all other years.
    @Test func chineseStrict_leapMonthPattern() {
        var failures: [String] = []
        var dc = DateComponents(month: 4, day: 1)
        dc.isLeapMonth = true
        let anchors = [Self.g(2019, 6, 15), Self.g(2021, 1, 10)]
        let (icu, ours) = Self.makePair(.chinese)
        for policy in [Calendar.MatchingPolicy.strict, .nextTime] {
            for anchor in anchors {
                let i = Self.collect(icu, after: anchor, matching: dc, policy: policy, count: 2)
                let o = Self.collect(ours, after: anchor, matching: dc, policy: policy, count: 2)
                Self.compare("chinese leap4 \(policy) from \(anchor)", i, o, failures: &failures)
            }
        }
        Self.reportAndAssert("chineseStrict_leapMonthPattern", failures)
    }

    /// CNY yearly {month: 1, day: 1} under `.strict` — always exists.
    @Test func chineseStrict_newYearYearly() {
        var failures: [String] = []
        let dc = DateComponents(month: 1, day: 1)
        let anchors = [Self.g(2019, 6, 15), Self.g(2024, 3, 1)]
        let (icu, ours) = Self.makePair(.chinese)
        for policy in [Calendar.MatchingPolicy.strict, .nextTime] {
            for anchor in anchors {
                let i = Self.collect(icu, after: anchor, matching: dc, policy: policy, count: 5)
                let o = Self.collect(ours, after: anchor, matching: dc, policy: policy, count: 5)
                Self.compare("chinese CNY \(policy) from \(anchor)", i, o, failures: &failures)
            }
        }
        Self.reportAndAssert("chineseStrict_newYearYearly", failures)
    }

    /// {month: 6, day: 30}: Chinese m6 has 30 days only some years — `.strict` skips short-m6 years.
    @Test func chineseStrict_day30ShortMonth() {
        var failures: [String] = []
        let dc = DateComponents(month: 6, day: 30)
        let anchors = [Self.g(2020, 1, 15), Self.g(2024, 11, 2)]
        let (icu, ours) = Self.makePair(.chinese)
        for policy in [Calendar.MatchingPolicy.strict, .nextTime] {
            for anchor in anchors {
                let i = Self.collect(icu, after: anchor, matching: dc, policy: policy, count: 4)
                let o = Self.collect(ours, after: anchor, matching: dc, policy: policy, count: 4)
                Self.compare("chinese m6d30 \(policy) from \(anchor)", i, o, failures: &failures)
            }
        }
        Self.reportAndAssert("chineseStrict_day30ShortMonth", failures)
    }
}
