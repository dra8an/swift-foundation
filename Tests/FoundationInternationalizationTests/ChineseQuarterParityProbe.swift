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

// S3 gate (CHINESE_PLAN § 11.23, user decision: match ICU): quarter surfaces
// must be ICU-identical on the implemented set — dateInterval(.quarter),
// ordinality (.quarter,.year)/(.month,.quarter)/(.day,.quarter), range
// (.quarter,.year)/(.month,.quarter)/(.day,.quarter) — plus byAdding/from:to
// .quarter no-op parity. The week/hour ordinality towers in .quarter stay
// unimplemented on both Swift calendars (merged Hebrew scope) and are not
// compared here.
@Suite("Chinese Quarter Parity Probe")
private struct ChineseQuarterParityProbe {

    private static func makePair(tz: TimeZone = .gmt) -> (icu: Calendar, ours: Calendar) {
        let icuInner = _CalendarICU(
            identifier: .chinese, timeZone: tz, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let oursInner = _CalendarChinese(
            identifier: .chinese, timeZone: tz, locale: nil,
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
        guard let date = cal.date(from: dc) else {
            preconditionFailure("invalid Gregorian probe date \(y)-\(m)-\(d)")
        }
        return date
    }

    @Test func quarterSurfaces() {
        let (icu, ours) = Self.makePair()

        var samples: [(String, Date)] = []
        // Broad sweep across the baked range, all four quarters per sampled year.
        // Chinese years 2057/2097 excluded (ICU d0 artifact corrupts them, § 11.3).
        for gy in stride(from: 1900, through: 2099, by: 3) {
            if [2056, 2057, 2096, 2097].contains(gy) { continue }
            for (m, d) in [(2, 20), (4, 10), (6, 25), (9, 5), (11, 15), (12, 30)] {
                samples.append(("\(gy)-\(m)-\(d)", Self.g(gy, m, d)))
            }
        }
        // Leap-month and quarter-boundary targets.
        let targeted: [(String, Date)] = [
            ("CNY 2025", Self.g(2025, 1, 29)),
            ("m4 d1 2025", Self.g(2025, 4, 28)),
            ("m3 last 2025", Self.g(2025, 4, 27)),
            ("leap-6 2025", Self.g(2025, 8, 1)),
            ("m7 2025", Self.g(2025, 9, 1)),
            ("leap-2 2023", Self.g(2023, 4, 1)),
            ("leap-4 1906", Self.g(1906, 6, 10)),
            ("leap-9 2014", Self.g(2014, 11, 1)),
            ("leap-10 1984", Self.g(1984, 12, 15)),
            ("leap-6 2017", Self.g(2017, 7, 15)),
            ("m12 end 2026", Self.g(2026, 2, 16)),
        ]
        samples.append(contentsOf: targeted)

        var failures: [String] = []
        func cmp<T: Equatable>(_ label: String, _ name: String, _ a: T?, _ b: T?) {
            if a != b {
                failures.append("[\(label)] \(name): icu=\(a.map { "\($0)" } ?? "nil") ours=\(b.map { "\($0)" } ?? "nil")")
            }
        }

        for (label, d) in samples {
            let iInterval = icu.dateInterval(of: .quarter, for: d)
            let oInterval = ours.dateInterval(of: .quarter, for: d)
            cmp(label, "dateInterval(.quarter).start", iInterval?.start, oInterval?.start)
            cmp(label, "dateInterval(.quarter).duration", iInterval?.duration, oInterval?.duration)

            cmp(label, "ordinality(.quarter,.year)",
                icu.ordinality(of: .quarter, in: .year, for: d),
                ours.ordinality(of: .quarter, in: .year, for: d))
            cmp(label, "ordinality(.month,.quarter)",
                icu.ordinality(of: .month, in: .quarter, for: d),
                ours.ordinality(of: .month, in: .quarter, for: d))
            cmp(label, "ordinality(.day,.quarter)",
                icu.ordinality(of: .day, in: .quarter, for: d),
                ours.ordinality(of: .day, in: .quarter, for: d))

            cmp(label, "range(.quarter,.year)",
                icu.range(of: .quarter, in: .year, for: d),
                ours.range(of: .quarter, in: .year, for: d))
            cmp(label, "range(.month,.quarter)",
                icu.range(of: .month, in: .quarter, for: d),
                ours.range(of: .month, in: .quarter, for: d))
            cmp(label, "range(.day,.quarter)",
                icu.range(of: .day, in: .quarter, for: d),
                ours.range(of: .day, in: .quarter, for: d))
        }

        // byAdding/from:to .quarter are no-ops on both backends; guard that stays true.
        for (label, d) in targeted {
            cmp(label, "byAdding(.quarter,+1)",
                icu.date(byAdding: .quarter, value: 1, to: d),
                ours.date(byAdding: .quarter, value: 1, to: d))
            cmp(label, "byAdding(.quarter,-1)",
                icu.date(byAdding: .quarter, value: -1, to: d),
                ours.date(byAdding: .quarter, value: -1, to: d))
            cmp(label, "from:to(.quarter)",
                icu.dateComponents([.quarter], from: d, to: Self.g(2026, 6, 15)).quarter,
                ours.dateComponents([.quarter], from: d, to: Self.g(2026, 6, 15)).quarter)
        }

        print("=== chineseQuarterParity: \(samples.count) dates, \(failures.count) diffs ===")
        for f in failures.prefix(25) { print("  \(f)") }
        #expect(failures.isEmpty)
    }

    // R5 (§ 11.25): DST coverage for the floor-seconds (.day,.quarter) formula, plus nextDate quarter matching (generic dateAfterMatchingQuarter path, both backends).
    @Test func quarterSurfacesDSTAndMatching() {
        guard let la = TimeZone(identifier: "America/Los_Angeles") else {
            preconditionFailure("missing tz database entry")
        }
        let (icu, ours) = Self.makePair(tz: la)
        var failures: [String] = []
        func cmp<T: Equatable>(_ label: String, _ name: String, _ a: T?, _ b: T?) {
            if a != b {
                failures.append("[\(label)] \(name): icu=\(a.map { "\($0)" } ?? "nil") ours=\(b.map { "\($0)" } ?? "nil")")
            }
        }
        // Quarters straddling the 2025 US transitions (Mar 9 forward, Nov 2 back), sampled on and after the shift, plus the leap-6 quirk date.
        let dstSamples: [(String, Date)] = [
            ("spring-forward day", Self.g(2025, 3, 9)),
            ("post-spring-forward", Self.g(2025, 3, 20)),
            ("leap-6 LA", Self.g(2025, 8, 1)),
            ("fall-back day", Self.g(2025, 11, 2)),
            ("post-fall-back", Self.g(2025, 11, 10)),
            ("Q4 LA", Self.g(2025, 12, 5)),
        ]
        for (label, d) in dstSamples {
            let iv1 = icu.dateInterval(of: .quarter, for: d)
            let iv2 = ours.dateInterval(of: .quarter, for: d)
            cmp(label, "interval.start", iv1?.start, iv2?.start)
            cmp(label, "interval.duration", iv1?.duration, iv2?.duration)
            cmp(label, "ord(.quarter,.year)",
                icu.ordinality(of: .quarter, in: .year, for: d),
                ours.ordinality(of: .quarter, in: .year, for: d))
            cmp(label, "ord(.month,.quarter)",
                icu.ordinality(of: .month, in: .quarter, for: d),
                ours.ordinality(of: .month, in: .quarter, for: d))
            cmp(label, "ord(.day,.quarter)",
                icu.ordinality(of: .day, in: .quarter, for: d),
                ours.ordinality(of: .day, in: .quarter, for: d))
            cmp(label, "range(.month,.quarter)",
                icu.range(of: .month, in: .quarter, for: d),
                ours.range(of: .month, in: .quarter, for: d))
            cmp(label, "range(.day,.quarter)",
                icu.range(of: .day, in: .quarter, for: d),
                ours.range(of: .day, in: .quarter, for: d))
        }
        let (icuG, oursG) = Self.makePair()
        for (pairLabel, ic, oc) in [("LA", icu, ours), ("GMT", icuG, oursG)] {
            for q in 1...4 {
                var dc = DateComponents()
                dc.quarter = q
                for (aLabel, anchor) in [("2025", Self.g(2025, 2, 10)), ("leap-2 2023", Self.g(2023, 3, 25))] {
                    cmp("\(pairLabel) q\(q) \(aLabel)", "nextDate",
                        ic.nextDate(after: anchor, matching: dc, matchingPolicy: .nextTime),
                        oc.nextDate(after: anchor, matching: dc, matchingPolicy: .nextTime))
                }
            }
        }
        print("=== chineseQuarterDSTAndMatching: \(failures.count) diffs ===")
        for f in failures.prefix(10) { print("  \(f)") }
        #expect(failures.isEmpty)
    }
}
