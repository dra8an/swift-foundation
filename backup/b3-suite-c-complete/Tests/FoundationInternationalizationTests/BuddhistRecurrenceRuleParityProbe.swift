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

@Suite("Buddhist RecurrenceRule Parity Probe")
private struct BuddhistRecurrenceRuleParityProbe {

    private static func makePair() -> (icu: Calendar, ours: Calendar) {
        let icuInner = _CalendarICU(
            identifier: .buddhist, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let oursInner = _CalendarBuddhist(
            identifier: .buddhist, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        return (Calendar(inner: icuInner), Calendar(inner: oursInner))
    }

    private static func g(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d; dc.hour = 12
        dc.timeZone = .gmt
        return cal.date(from: dc)!
    }

    private static func compare(_ rule: String, _ start: String, _ icu: [Date], _ ours: [Date], failures: inout [String]) {
        if icu.count != ours.count {
            failures.append("[\(rule) from \(start)] count mismatch: ICU=\(icu.count) ours=\(ours.count)")
            return
        }
        for i in 0..<icu.count where icu[i] != ours[i] {
            failures.append("[\(rule) from \(start)][\(i)] ICU=\(icu[i]) ours=\(ours[i])")
        }
    }

    private static func collect(rule: Calendar.RecurrenceRule, from start: Date, count: Int) -> [Date] {
        var result: [Date] = []
        for date in rule.recurrences(of: start) {
            result.append(date)
            if result.count >= count { break }
        }
        return result
    }

    private static let anchors: [(label: String, date: Date)] = [
        ("2020-01-01", g(2020, 1, 1)),
        ("2024-06-15", g(2024, 6, 15)),
        ("2025-09-23", g(2025, 9, 23)),
        ("2026-06-11", g(2026, 6, 11)),
    ]

    @Test func yearly_christmas() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .yearly, end: .afterOccurrences(5))
        ruleIcu.months = [12]
        ruleIcu.daysOfTheMonth = [25]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .yearly, end: .afterOccurrences(5))
        ruleOurs.months = [12]
        ruleOurs.daysOfTheMonth = [25]
        for (label, anchor) in Self.anchors {
            let i = Self.collect(rule: ruleIcu, from: anchor, count: 5)
            let o = Self.collect(rule: ruleOurs, from: anchor, count: 5)
            Self.compare("yearly_christmas", label, i, o, failures: &failures)
        }
        print("[yearly_christmas] anchors=\(Self.anchors.count) compared=\(Self.anchors.count * 5) failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }

    @Test func yearly_songkran() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .yearly, end: .afterOccurrences(5))
        ruleIcu.months = [4]
        ruleIcu.daysOfTheMonth = [13]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .yearly, end: .afterOccurrences(5))
        ruleOurs.months = [4]
        ruleOurs.daysOfTheMonth = [13]
        for (label, anchor) in Self.anchors {
            let i = Self.collect(rule: ruleIcu, from: anchor, count: 5)
            let o = Self.collect(rule: ruleOurs, from: anchor, count: 5)
            Self.compare("yearly_songkran", label, i, o, failures: &failures)
        }
        print("[yearly_songkran] anchors=\(Self.anchors.count) compared=\(Self.anchors.count * 5) failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }

    @Test func monthly_firstOfMonth() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .monthly, end: .afterOccurrences(12))
        ruleIcu.daysOfTheMonth = [1]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .monthly, end: .afterOccurrences(12))
        ruleOurs.daysOfTheMonth = [1]
        for (label, anchor) in Self.anchors {
            let i = Self.collect(rule: ruleIcu, from: anchor, count: 12)
            let o = Self.collect(rule: ruleOurs, from: anchor, count: 12)
            Self.compare("monthly_firstOfMonth", label, i, o, failures: &failures)
        }
        print("[monthly_firstOfMonth] anchors=\(Self.anchors.count) compared=\(Self.anchors.count * 12) failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }

    @Test func weekly_mondays() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .weekly, end: .afterOccurrences(8))
        ruleIcu.weekdays = [.every(.monday)]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .weekly, end: .afterOccurrences(8))
        ruleOurs.weekdays = [.every(.monday)]
        for (label, anchor) in Self.anchors {
            let i = Self.collect(rule: ruleIcu, from: anchor, count: 8)
            let o = Self.collect(rule: ruleOurs, from: anchor, count: 8)
            Self.compare("weekly_mondays", label, i, o, failures: &failures)
        }
        print("[weekly_mondays] anchors=\(Self.anchors.count) compared=\(Self.anchors.count * 8) failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }

    @Test func yearly_thanksgivingShape() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .yearly, end: .afterOccurrences(5))
        ruleIcu.months = [11]
        ruleIcu.weekdays = [.nth(4, .thursday)]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .yearly, end: .afterOccurrences(5))
        ruleOurs.months = [11]
        ruleOurs.weekdays = [.nth(4, .thursday)]
        for (label, anchor) in Self.anchors {
            let i = Self.collect(rule: ruleIcu, from: anchor, count: 5)
            let o = Self.collect(rule: ruleOurs, from: anchor, count: 5)
            Self.compare("yearly_thanksgivingShape", label, i, o, failures: &failures)
        }
        print("[yearly_thanksgivingShape] anchors=\(Self.anchors.count) compared=\(Self.anchors.count * 5) failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }
}
