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

@Suite("Japanese RecurrenceRule Parity Probe")
private struct JapaneseRecurrenceRuleParityProbe {

    private static func makePair() -> (icu: Calendar, ours: Calendar) {
        let icuInner = _CalendarICU(
            identifier: .japanese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let oursInner = _CalendarJapanese(
            identifier: .japanese, timeZone: .gmt, locale: nil,
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
        ("Heisei 2015-03-01", g(2015, 3, 1)),
        ("Heisei→Reiwa 2018-11-15", g(2018, 11, 15)),  // straddles era boundary on iteration
        ("Reiwa 2020-01-01", g(2020, 1, 1)),
        ("Reiwa 2024-06-15", g(2024, 6, 15)),
        ("Reiwa 2025-09-23", g(2025, 9, 23)),
        ("Reiwa 2026-06-11", g(2026, 6, 11)),
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

    @Test func yearly_constitutionDay() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .yearly, end: .afterOccurrences(5))
        ruleIcu.months = [5]
        ruleIcu.daysOfTheMonth = [3]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .yearly, end: .afterOccurrences(5))
        ruleOurs.months = [5]
        ruleOurs.daysOfTheMonth = [3]
        for (label, anchor) in Self.anchors {
            let i = Self.collect(rule: ruleIcu, from: anchor, count: 5)
            let o = Self.collect(rule: ruleOurs, from: anchor, count: 5)
            Self.compare("yearly_constitutionDay", label, i, o, failures: &failures)
        }
        print("[yearly_constitutionDay] anchors=\(Self.anchors.count) compared=\(Self.anchors.count * 5) failures=\(failures.count)")
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

    // MARK: - Era-transition recurrences (Japanese-specific)

    /// Monthly first-of-month starting in Heisei (Mar 2018), running 24 months
    /// to cross into Reiwa (May 2019). Both impls must agree across the boundary.
    @Test func monthly_acrossHeiseiReiwaBoundary() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .monthly, end: .afterOccurrences(24))
        ruleIcu.daysOfTheMonth = [1]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .monthly, end: .afterOccurrences(24))
        ruleOurs.daysOfTheMonth = [1]
        let anchor = Self.g(2018, 3, 1)
        let i = Self.collect(rule: ruleIcu, from: anchor, count: 24)
        let o = Self.collect(rule: ruleOurs, from: anchor, count: 24)
        Self.compare("monthly_acrossHeiseiReiwaBoundary", "2018-03-01", i, o, failures: &failures)
        print("[monthly_acrossHeiseiReiwaBoundary] compared=\(min(i.count, o.count)) failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }

    /// Yearly May 1 starting in Heisei, running 5 occurrences past Reiwa start.
    /// May 1 1989 was Heisei 1; May 1 2019 began Reiwa 1.
    @Test func yearly_mayFirst_acrossEraBoundaries() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        var ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .yearly, end: .afterOccurrences(5))
        ruleIcu.months = [5]
        ruleIcu.daysOfTheMonth = [1]
        var ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .yearly, end: .afterOccurrences(5))
        ruleOurs.months = [5]
        ruleOurs.daysOfTheMonth = [1]
        for anchor in [Self.g(2017, 1, 1), Self.g(2018, 6, 15), Self.g(2019, 4, 1)] {
            let i = Self.collect(rule: ruleIcu, from: anchor, count: 5)
            let o = Self.collect(rule: ruleOurs, from: anchor, count: 5)
            Self.compare("yearly_mayFirst", "\(anchor)", i, o, failures: &failures)
        }
        print("[yearly_mayFirst_acrossEraBoundaries] failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }

    /// Daily for 60 days starting just before Reiwa, ensuring no off-by-one
    /// or duplicate at the era boundary.
    @Test func daily_acrossHeiseiReiwaBoundary() {
        let (icu, ours) = Self.makePair()
        var failures: [String] = []
        let ruleIcu = Calendar.RecurrenceRule(calendar: icu, frequency: .daily, end: .afterOccurrences(60))
        let ruleOurs = Calendar.RecurrenceRule(calendar: ours, frequency: .daily, end: .afterOccurrences(60))
        let anchor = Self.g(2019, 4, 15)  // 16 days before Reiwa
        let i = Self.collect(rule: ruleIcu, from: anchor, count: 60)
        let o = Self.collect(rule: ruleOurs, from: anchor, count: 60)
        Self.compare("daily_acrossHeiseiReiwaBoundary", "2019-04-15", i, o, failures: &failures)
        print("[daily_acrossHeiseiReiwaBoundary] compared=\(min(i.count, o.count)) failures=\(failures.count)")
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }
}
