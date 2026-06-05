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

/// Side-by-side probe: `_CalendarICU(.hebrew)` (the pre-port behavior) vs
/// `_CalendarHebrew` (our port). One-shot diagnostic, not a pass/fail test.
@Suite("Hebrew ICU Comparison Probe")
private struct HebrewICUComparisonProbe {

    // Simple fixed-width padding (no String(format:) since that's Darwin Foundation only).
    private static func pad(_ s: String, _ width: Int) -> String {
        s + String(repeating: " ", count: max(0, width - s.count))
    }

    @Test func compareFieldsSideBySide() {
        let icu = _CalendarICU(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let ours = _CalendarHebrew(
            identifier: .hebrew, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )

        let d = Date(timeIntervalSinceReferenceDate: 496359355.795410)
        print("\n=== Hebrew calendar: _CalendarICU vs _CalendarHebrew ===")
        print("Probe date: \(d)\n")

        // --- dateComponents query ---
        let fields: Calendar.ComponentSet = [
            .era, .year, .month, .day, .hour, .minute, .second,
            .weekday, .weekdayOrdinal, .quarter,
            .weekOfMonth, .weekOfYear, .yearForWeekOfYear,
            .dayOfYear, .isLeapMonth
        ]
        let icuComps = icu.dateComponents(fields, from: d, in: .gmt)
        let ourComps = ours.dateComponents(fields, from: d, in: .gmt)

        print("dateComponents(…, from: d):")
        print("  " + Self.pad("field", 22) + Self.pad("ICU", 14) + "ours")
        func row(_ name: String, _ a: Int?, _ b: Int?) {
            print("  " + Self.pad(name, 22) + Self.pad(a.map(String.init) ?? "nil", 14) + (b.map(String.init) ?? "nil"))
        }
        func rowBool(_ name: String, _ a: Bool?, _ b: Bool?) {
            print("  " + Self.pad(name, 22) + Self.pad(a.map { $0 ? "true" : "false" } ?? "nil", 14) + (b.map { $0 ? "true" : "false" } ?? "nil"))
        }
        row(".era",               icuComps.era,               ourComps.era)
        row(".year",              icuComps.year,              ourComps.year)
        row(".month",             icuComps.month,             ourComps.month)
        row(".day",               icuComps.day,               ourComps.day)
        row(".hour",              icuComps.hour,              ourComps.hour)
        row(".minute",            icuComps.minute,            ourComps.minute)
        row(".second",            icuComps.second,            ourComps.second)
        row(".weekday",           icuComps.weekday,           ourComps.weekday)
        row(".weekdayOrdinal",    icuComps.weekdayOrdinal,    ourComps.weekdayOrdinal)
        row(".quarter",           icuComps.quarter,           ourComps.quarter)
        row(".weekOfMonth",       icuComps.weekOfMonth,       ourComps.weekOfMonth)
        row(".weekOfYear",        icuComps.weekOfYear,        ourComps.weekOfYear)
        row(".yearForWeekOfYear", icuComps.yearForWeekOfYear, ourComps.yearForWeekOfYear)
        row(".dayOfYear",         icuComps.dayOfYear,         ourComps.dayOfYear)
        rowBool(".isLeapMonth",   icuComps.isLeapMonth,       ourComps.isLeapMonth)

        // --- dateInterval ---
        print("\ndateInterval(of: X, for: d):")
        print("  " + Self.pad("component", 22) + Self.pad("ICU duration (s)", 24) + "ours duration (s)")
        func intervalRow(_ name: String, _ a: DateInterval?, _ b: DateInterval?) {
            let af = a.map { "\(Int($0.duration))" } ?? "nil"
            let bf = b.map { "\(Int($0.duration))" } ?? "nil"
            print("  " + Self.pad(name, 22) + Self.pad(af, 24) + bf)
        }
        intervalRow(".era",               icu.dateInterval(of: .era,               for: d), ours.dateInterval(of: .era,               for: d))
        intervalRow(".year",              icu.dateInterval(of: .year,              for: d), ours.dateInterval(of: .year,              for: d))
        intervalRow(".month",             icu.dateInterval(of: .month,             for: d), ours.dateInterval(of: .month,             for: d))
        intervalRow(".day",               icu.dateInterval(of: .day,               for: d), ours.dateInterval(of: .day,               for: d))
        intervalRow(".hour",              icu.dateInterval(of: .hour,              for: d), ours.dateInterval(of: .hour,              for: d))
        intervalRow(".quarter",           icu.dateInterval(of: .quarter,           for: d), ours.dateInterval(of: .quarter,           for: d))
        intervalRow(".weekOfYear",        icu.dateInterval(of: .weekOfYear,        for: d), ours.dateInterval(of: .weekOfYear,        for: d))
        intervalRow(".weekOfMonth",       icu.dateInterval(of: .weekOfMonth,       for: d), ours.dateInterval(of: .weekOfMonth,       for: d))
        intervalRow(".yearForWeekOfYear", icu.dateInterval(of: .yearForWeekOfYear, for: d), ours.dateInterval(of: .yearForWeekOfYear, for: d))

        // --- ordinality ---
        print("\nordinality(of: smaller, in: larger, for: d):")
        print("  " + Self.pad("(smaller, larger)", 28) + Self.pad("ICU", 10) + "ours")
        func ordRow(_ small: Calendar.Component, _ large: Calendar.Component) {
            let a = icu.ordinality(of: small, in: large, for: d)
            let b = ours.ordinality(of: small, in: large, for: d)
            print("  " + Self.pad("(.\(small), .\(large))", 28) + Self.pad(a.map(String.init) ?? "nil", 10) + (b.map(String.init) ?? "nil"))
        }
        ordRow(.day, .year)
        ordRow(.day, .month)
        ordRow(.month, .year)
        ordRow(.month, .quarter)
        ordRow(.weekOfYear, .year)
        ordRow(.weekOfMonth, .month)
        ordRow(.weekday, .year)
        ordRow(.weekday, .month)
        ordRow(.weekday, .weekOfYear)
        ordRow(.weekdayOrdinal, .month)
        ordRow(.quarter, .year)
        ordRow(.hour, .day)

        // --- range(of:in:for:) ---
        print("\nrange(of: smaller, in: larger, for: d):")
        print("  " + Self.pad("(smaller, larger)", 28) + Self.pad("ICU", 14) + "ours")
        func rangeRow(_ small: Calendar.Component, _ large: Calendar.Component) {
            let a = icu.range(of: small, in: large, for: d)
            let b = ours.range(of: small, in: large, for: d)
            print("  " + Self.pad("(.\(small), .\(large))", 28) +
                  Self.pad(a.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil", 14) +
                  (b.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil"))
        }
        rangeRow(.day, .year)
        rangeRow(.day, .month)
        rangeRow(.month, .year)
        rangeRow(.weekOfYear, .year)
        rangeRow(.weekOfMonth, .month)

        // --- date(byAdding:) — show date +1 of each component ---
        print("\ndate(byAdding: <c>, value: 1, to: d):")
        print("  " + Self.pad("component", 22) + Self.pad("ICU", 36) + "ours")
        func addRow(_ comp: Calendar.Component) {
            var dc = DateComponents()
            dc.setValue(1, for: comp)
            let a = icu.date(byAdding: dc, to: d, wrappingComponents: false)
            let b = ours.date(byAdding: dc, to: d, wrappingComponents: false)
            print("  " + Self.pad(".\(comp)", 22) +
                  Self.pad(a.map { "\($0)" } ?? "nil", 36) +
                  (b.map { "\($0)" } ?? "nil"))
        }
        addRow(.day)
        addRow(.weekOfYear)
        addRow(.weekOfMonth)
        addRow(.weekdayOrdinal)
        addRow(.month)
        addRow(.year)
        addRow(.quarter)
        addRow(.yearForWeekOfYear)
        addRow(.hour)

        // --- minimumRange / maximumRange ---
        print("\nminimumRange / maximumRange:")
        print("  " + Self.pad("component", 22) + Self.pad("ICU min", 14) + Self.pad("ours min", 14) + Self.pad("ICU max", 14) + "ours max")
        func rangeComp(_ c: Calendar.Component) {
            let s = { (r: Range<Int>?) in r.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil" }
            print("  " + Self.pad(".\(c)", 22) +
                  Self.pad(s(icu.minimumRange(of: c)), 14) +
                  Self.pad(s(ours.minimumRange(of: c)), 14) +
                  Self.pad(s(icu.maximumRange(of: c)), 14) +
                  s(ours.maximumRange(of: c)))
        }
        rangeComp(.era)
        rangeComp(.year)
        rangeComp(.month)
        rangeComp(.day)
        rangeComp(.hour)
        rangeComp(.weekday)
        rangeComp(.weekdayOrdinal)
        rangeComp(.quarter)
        rangeComp(.weekOfMonth)
        rangeComp(.weekOfYear)
        rangeComp(.yearForWeekOfYear)
        rangeComp(.dayOfYear)
        rangeComp(.isLeapMonth)

        print("\n=== end probe ===\n")
    }
}
