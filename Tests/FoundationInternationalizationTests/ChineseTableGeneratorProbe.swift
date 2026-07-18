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

// Local-only research probe: sweeps _CalendarICU(.chinese) daily and emits
// the packed baked table for Chinese years 1901-2100. Not part of any suite
// that ships. Regeneration = rerun this test.

import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

@Suite("Chinese Table Generator Probe")
private struct ChineseTableGeneratorProbe {

    // RD of 1970-01-01 = 719163; midday GMT instants address civil days.
    private static func rd(_ y: Int, _ m: Int, _ d: Int) -> Int {
        func fd(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
        let ym1 = y - 1
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        var r = 365 * ym1 + fd(ym1, 4) - fd(ym1, 100) + fd(ym1, 400)
        r += fd(367 * m - 362, 12) + (m <= 2 ? 0 : (leap ? -1 : -2)) + d
        return r
    }

    private static func gregYear(ofRD day: Int) -> Int {
        var y = Int(Double(day) / 365.2425) + 1
        while rd(y, 1, 1) > day { y -= 1 }
        while rd(y + 1, 1, 1) <= day { y += 1 }
        return y
    }

    private static func date(ofRD day: Int) -> Date {
        Date(timeIntervalSince1970: Double(day - 719_163) * 86400.0 + 43_200.0)
    }

    private static func gregStr(_ day: Int) -> String {
        let y = gregYear(ofRD: day)
        var m = 1
        while m < 12 && rd(y, m + 1, 1) <= day { m += 1 }
        func p2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(y)-\(p2(m))-\(p2(day - rd(y, m, 1) + 1))"
    }

    @Test func chineseTableGeneratorSweep() throws {
        let icu = _CalendarICU(
            identifier: .chinese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let fields: Calendar.ComponentSet = [.month, .day, .isLeapMonth]

        let from = Self.rd(1899, 12, 1)
        let to = Self.rd(2101, 3, 10)

        // Collect per-day labels; detect month starts by (month, leap) change.
        var events: [(num: Int, leap: Bool, start: Int)] = []
        var domAnomalies: [String] = []
        var prev: (num: Int, leap: Bool, dom: Int)? = nil
        for day in from...to {
            let c = icu.dateComponents(fields, from: Self.date(ofRD: day), in: .gmt)
            let cur = (num: c.month!, leap: c.isLeapMonth ?? false, dom: c.day!)
            if let p = prev {
                if cur.num != p.num || cur.leap != p.leap {
                    events.append((cur.num, cur.leap, day))
                    if cur.dom != 1 {
                        domAnomalies.append("\(Self.gregStr(day)): month \(cur.num)\(cur.leap ? "L" : "") starts with dom=\(cur.dom)")
                    }
                } else if cur.dom != p.dom + 1 {
                    domAnomalies.append("\(Self.gregStr(day)): dom \(p.dom) -> \(cur.dom) inside m\(cur.num)\(cur.leap ? "L" : "")")
                }
            } else {
                events.append((cur.num, cur.leap, day))
            }
            prev = cur
        }

        // Group into Chinese years at (month 1, not leap).
        var years: [(iso: Int, months: [(num: Int, leap: Bool, start: Int)], end: Int)] = []
        var group: [(num: Int, leap: Bool, start: Int)] = []
        for ev in events {
            if ev.num == 1 && !ev.leap {
                if group.count >= 12 {
                    years.append((Self.gregYear(ofRD: group[0].start), group, ev.start))
                }
                group = [ev]
            } else if !group.isEmpty {
                group.append(ev)
            }
        }

        // Pack years 1901-2100. Layout (mirrors icu4swift PackedChineseYearData):
        //   bits 0-12: month lengths, bit i = 1 if ordinal month i+1 has 30 days
        //   bits 13-16: leap month display number (0 = none; leap follows that number)
        //   bits 17-22: new-year offset from Jan 19 of the related ISO year
        var structuralErrors: [String] = []
        var packed: [(iso: Int, value: UInt32)] = []
        var offMin = Int.max, offMax = Int.min
        for y in years {
            guard y.iso >= 1901 && y.iso <= 2100 else {
                if y.iso == 1900 {
                    let desc = y.months.map { "m\($0.num)\($0.leap ? "L" : "")@\(Self.gregStr($0.start))" }.joined(separator: " ")
                    print("INFO Chinese year 1900 (not in table): \(desc)")
                }
                continue
            }
            let n = y.months.count
            if n != 12 && n != 13 { structuralErrors.append("\(y.iso): \(n) months"); continue }
            let leaps = y.months.filter { $0.leap }
            if (n == 13 && leaps.count != 1) || (n == 12 && !leaps.isEmpty) {
                structuralErrors.append("\(y.iso): \(n) months, \(leaps.count) leaps")
                continue
            }
            var value: UInt32 = 0
            for i in 0..<n {
                let next = (i + 1 < n) ? y.months[i + 1].start : y.end
                let len = next - y.months[i].start
                guard len == 29 || len == 30 else {
                    structuralErrors.append("\(y.iso): month \(i + 1) length \(len)")
                    continue
                }
                if len == 30 { value |= UInt32(1) << i }
            }
            if let lm = leaps.first { value |= UInt32(lm.num) << 13 }
            let offset = y.months[0].start - Self.rd(y.iso, 1, 19)
            guard offset > 0 && offset < 64 else {
                structuralErrors.append("\(y.iso): NY offset \(offset) out of 6-bit range")
                continue
            }
            offMin = min(offMin, offset); offMax = max(offMax, offset)
            value |= UInt32(offset) << 17
            packed.append((y.iso, value))
        }

        // Emit table source.
        var out = "// Generated by ChineseTableGeneratorProbe from _CalendarICU(.chinese) daily sweep.\n"
        out += "// Chinese years 1901-2100 keyed by related ISO year. Packing:\n"
        out += "// bits 0-12 month lengths (1=30d), 13-16 leap display number (0=none),\n"
        out += "// 17-22 new-year offset from Jan 19 of the related ISO year.\n"
        out += "static let chineseYearStart = 1901\n"
        out += "static let chineseYearData: [UInt32] = [\n"
        for chunk in stride(from: 0, to: packed.count, by: 4) {
            let slice = packed[chunk..<min(chunk + 4, packed.count)]
            let hexes = slice.map { v -> String in
                let h = String(v.value, radix: 16, uppercase: true)
                return "0x" + String(repeating: "0", count: 8 - h.count) + h + ","
            }.joined(separator: " ")
            out += "    \(hexes) // \(slice.first!.iso)-\(slice.last!.iso)\n"
        }
        out += "]\n"
        let outPath = "/Users/draganbesevic/Projects/claude/swift-foundation/backup/chinese-generated-table.swift.txt"
        try Data(out.utf8).write(to: URL(filePath: outPath))

        print("GENERATOR: \(packed.count) years packed (\(packed.first?.iso ?? 0)-\(packed.last?.iso ?? 0)), NY offset range \(offMin)-\(offMax)")
        print("GENERATOR: wrote \(outPath)")
        if !domAnomalies.isEmpty {
            print("DOM ANOMALIES (\(domAnomalies.count)):")
            for a in domAnomalies.prefix(20) { print("  \(a)") }
        }
        for e in structuralErrors.prefix(20) { print("STRUCTURAL: \(e)") }

        #expect(packed.count == 200)
        #expect(structuralErrors.isEmpty)
    }
}

@Suite("Chinese Convention Discovery Probe")
private struct ChineseConventionDiscoveryProbe {
    @Test func chineseConventionDiscovery() throws {
        let icu = _CalendarICU(
            identifier: .chinese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let fields: Calendar.ComponentSet = [.era, .year, .month, .day, .isLeapMonth, .dayOfYear, .quarter, .weekOfYear, .yearForWeekOfYear]
        // (gregorian y, m, d, label)
        let samples: [(Int, Int, Int, String)] = [
            (1901, 2, 19, "CNY 1901"), (1901, 2, 18, "day before CNY 1901"),
            (1906, 5, 23, "1906 m4L d1"), (1906, 6, 21, "1906 m4L last"),
            (2000, 2, 5, "CNY 2000"), (2024, 2, 10, "CNY 2024"),
            (2025, 7, 17, "today-ish"), (2033, 12, 22, "2033 m11L era?"),
            (2100, 12, 31, "last HKO day (m12 d1 of 2100)"),
            (1900, 1, 31, "CNY 1900 (fallback zone)"), (1900, 9, 24, "1900 m8L d1"),
            (1899, 6, 1, "pre-1900"), (2101, 6, 1, "post-2100"),
            (1800, 6, 1, "deep fallback 1800"), (2200, 6, 1, "deep fallback 2200"),
            (1, 1, 1, "gregorian year 1"), (2637 - 4637, 3, 1, "near epoch -2000"),
        ]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        for (y, m, d, label) in samples {
            var dc = DateComponents(); dc.year = y; dc.month = m; dc.day = d; dc.hour = 12
            guard let date = cal.date(from: dc) else { print("DISCOVERY \(label): date construction failed"); continue }
            let c = icu.dateComponents(fields, from: date, in: .gmt)
            print("DISCOVERY \(label) [g\(y)-\(m)-\(d)]: era=\(c.era ?? -1) year=\(c.year ?? -1) month=\(c.month ?? -1)\((c.isLeapMonth ?? false) ? "L" : "") day=\(c.day ?? -1) doy=\(c.dayOfYear ?? -1) q=\(c.quarter ?? -1) woy=\(c.weekOfYear ?? -1) yfwoy=\(c.yearForWeekOfYear ?? -1)")
        }
        #expect(Bool(true))
    }
}

@Suite("Chinese Engine Parity Probe")
private struct ChineseEngineParityProbe {
    private static func rd(_ y: Int, _ m: Int, _ d: Int) -> Int {
        _ChineseAstro.gregorianRD(y, m, d)
    }

    @Test func chineseEngineDailySweep() throws {
        let icu = _CalendarICU(
            identifier: .chinese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let fields: Calendar.ComponentSet = [.month, .day, .isLeapMonth]
        let from = Self.rd(1899, 1, 1)
        let to = Self.rd(2102, 12, 31)
        let tableFrom = Self.rd(1901, 2, 19)   // CNY 1901: table span start
        let tableTo = Self.rd(2101, 1, 28)     // day before CNY 2101 (end of table year 2100)

        // ICU internal inconsistency (Apple table/astronomy clash): these two
        // months report dom starting at 0. Bounded known divergence.
        let artifactWindows = [
            (Self.rd(2057, 9, 26)...Self.rd(2057, 10, 29)),
            (Self.rd(2097, 8, 5)...Self.rd(2097, 9, 7)),
        ]
        var inTableDiffs: [String] = []
        var inTableOutsideArtifact: [String] = []
        var outTableDiffs = 0
        var outRuns: [(start: Int, end: Int, sample: String)] = []
        var inRun = false
        for day in from...to {
            let date = Date(timeIntervalSince1970: Double(day - 719_163) * 86400.0 + 43_200.0)
            let c = icu.dateComponents(fields, from: date, in: .gmt)
            let y = _ChineseCalendarEngine.year(containingRD: day)
            guard let (ord, dom) = y.ordinalAndDay(rd: day) else {
                inTableDiffs.append("day \(day): engine gap!")
                continue
            }
            let label = y.label(ordinal: ord)
            let match = c.month == label.month && (c.isLeapMonth ?? false) == label.isLeap && c.day == dom
            if !match {
                let desc = "rd \(day): icu m\(c.month!)\((c.isLeapMonth ?? false) ? "L" : "") d\(c.day!) vs ours m\(label.month)\(label.isLeap ? "L" : "") d\(dom)"
                if day >= tableFrom && day <= tableTo {
                    if inTableDiffs.count < 70 { inTableDiffs.append(desc) }
                    if !artifactWindows.contains(where: { $0.contains(day) }) {
                        inTableOutsideArtifact.append(desc)
                    }
                } else {
                    outTableDiffs += 1
                    if inRun { outRuns[outRuns.count - 1].end = day }
                    else { outRuns.append((day, day, desc)); inRun = true }
                }
            } else {
                inRun = false
            }
        }
        print("ENGINE in-table diffs: \(inTableDiffs.count) (outside artifact windows: \(inTableOutsideArtifact.count))")
        for d in inTableOutsideArtifact.prefix(8) { print("  NON-ARTIFACT: \(d)") }
        print("ENGINE out-of-table diff days: \(outTableDiffs), runs: \(outRuns.count)")
        for r in outRuns { print("  run len \(r.end - r.start + 1): \(r.sample)") }
        // In-table parity gate: divergence ONLY within the two artifact windows.
        #expect(inTableOutsideArtifact.isEmpty)
    }
}

@Suite("Chinese M1 RoundTrip Probe")
private struct ChineseM1RoundTripProbe {
    @Test func chineseM1RoundTripAndFields() throws {
        let icu = _CalendarICU(
            identifier: .chinese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let ours = _CalendarChinese(
            identifier: .chinese, timeZone: .gmt, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        let fields: Calendar.ComponentSet = [.era, .year, .month, .day, .isLeapMonth,
                                             .dayOfYear, .weekday, .weekOfYear,
                                             .yearForWeekOfYear, .weekOfMonth,
                                             .weekdayOrdinal, .quarter, .hour]
        let artifact: [ClosedRange<Int>] = [
            _ChineseAstro.gregorianRD(2057, 9, 26)..._ChineseAstro.gregorianRD(2057, 10, 29),
            _ChineseAstro.gregorianRD(2097, 8, 5)..._ChineseAstro.gregorianRD(2097, 9, 7),
        ]
        var fieldDiffs: [String] = []
        var roundTripFails: [String] = []
        var checked = 0

        // Every 13th day over 1899-2102 (in-table + both fallback seams), noon GMT.
        var rd = _ChineseAstro.gregorianRD(1899, 1, 1)
        let endRD = _ChineseAstro.gregorianRD(2102, 12, 31)
        let known2101 = 767186...767215   // documented fallback divergence (m6 2101)
        while rd <= endRD {
            defer { rd += 13 }
            if artifact.contains(where: { $0.contains(rd) }) { continue }
            if known2101.contains(rd) { continue }
            let date = Date(timeIntervalSinceReferenceDate: Double(rd - 730_486) * 86400.0 + 43_200.0)
            checked += 1

            let ic = icu.dateComponents(fields, from: date, in: .gmt)
            let oc = ours.dateComponents(fields, from: date, in: .gmt)
            for (name, a, b) in [
                ("era", ic.era, oc.era), ("year", ic.year, oc.year),
                ("month", ic.month, oc.month), ("day", ic.day, oc.day),
                ("doy", ic.dayOfYear, oc.dayOfYear), ("wd", ic.weekday, oc.weekday),
                ("woy", ic.weekOfYear, oc.weekOfYear),
                ("yfwoy", ic.yearForWeekOfYear, oc.yearForWeekOfYear),
                ("wom", ic.weekOfMonth, oc.weekOfMonth),
                ("wdo", ic.weekdayOrdinal, oc.weekdayOrdinal),
                ("q", ic.quarter, oc.quarter), ("hour", ic.hour, oc.hour),
            ] where a != b {
                if fieldDiffs.count < 15 { fieldDiffs.append("rd \(rd) \(name): icu \(a ?? -99) ours \(b ?? -99)") }
            }
            if (ic.isLeapMonth ?? false) != (oc.isLeapMonth ?? false) {
                if fieldDiffs.count < 15 { fieldDiffs.append("rd \(rd) isLeapMonth: \(ic.isLeapMonth ?? false) vs \(oc.isLeapMonth ?? false)") }
            }

            // Round-trip: our components -> date(from:) -> same instant.
            var dc = DateComponents()
            dc.era = oc.era; dc.year = oc.year; dc.month = oc.month; dc.day = oc.day
            dc.isLeapMonth = oc.isLeapMonth; dc.hour = 12
            if let rt = ours.date(from: dc) {
                if rt != date, roundTripFails.count < 10 {
                    roundTripFails.append("rd \(rd): \(date) -> \(rt)")
                }
            } else if roundTripFails.count < 10 {
                roundTripFails.append("rd \(rd): date(from:) nil for \(dc)")
            }
        }
        print("M1: checked \(checked) sampled days; field diffs \(fieldDiffs.count); round-trip fails \(roundTripFails.count)")
        for d in fieldDiffs { print("  FIELD: \(d)") }
        for r in roundTripFails { print("  RT: \(r)") }
        #expect(fieldDiffs.isEmpty)
        #expect(roundTripFails.isEmpty)
    }
}
