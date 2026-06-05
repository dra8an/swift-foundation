//===----------------------------------------------------------------------===//
// Temporary benchmark: ICU baseline vs _CalendarHebrew, 10 runs each.
// Delete after capturing numbers.
//===----------------------------------------------------------------------===//

import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

private let referenceDate = Date(timeIntervalSinceReferenceDate: 496359355.795410)
private let timedRuns = 10

private func repeatedTimed(_ body: () -> Void) -> (minElapsed: Double, maxElapsed: Double) {
    var minT = Double.infinity
    var maxT = 0.0
    for _ in 0..<timedRuns {
        let t0 = ProcessInfo.processInfo.systemUptime
        body()
        let elapsed = ProcessInfo.processInfo.systemUptime - t0
        minT = min(minT, elapsed)
        maxT = max(maxT, elapsed)
    }
    return (minT, maxT)
}

private func report(_ label: String, iterations: Int, unit: String, scale: Double, minT: Double, maxT: Double) {
    let minPer = Int(minT * scale / Double(iterations))
    let maxPer = Int(maxT * scale / Double(iterations))
    let minMs = Int(minT * 1000)
    let maxMs = Int(maxT * 1000)
    print("\(label): min \(minPer) \(unit) (max \(maxPer)) — total \(minMs)ms (max \(maxMs)ms) — best of \(timedRuns)")
}

@Suite("Hebrew vs ICU Benchmark Comparison")
private struct HebrewVsICUBenchmark {

    private static func makeICUCalendar(timeZone: TimeZone = .gmt) -> Calendar {
        let inner = _CalendarICU(
            identifier: .hebrew, timeZone: timeZone, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        return Calendar(inner: inner)
    }

    private static func makeHebrewCalendar(timeZone: TimeZone = .gmt) -> Calendar {
        let inner = _CalendarHebrew(
            identifier: .hebrew, timeZone: timeZone, locale: nil,
            firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil
        )
        return Calendar(inner: inner)
    }

    @Test func benchmark_nextThousandHanukkahs() {
        let dc = DateComponents(month: 3, day: 25)
        let tzConfigs: [(String, TimeZone)] = [("GMT", .gmt)]
        + (TimeZone(identifier: "America/Los_Angeles").map { [("LA", $0)] } ?? [])

        for (tzLabel, tz) in tzConfigs {
            for (label, cal) in [("ICU", Self.makeICUCalendar(timeZone: tz)), ("Hebrew", Self.makeHebrewCalendar(timeZone: tz))] {
            var checksum: Int64 = 0
            // warmup
            var warmCount = 10
            cal.enumerateDates(startingAfter: referenceDate, matching: dc, matchingPolicy: .nextTime) { r, _, stop in
                checksum &+= Int64(r?.timeIntervalSinceReferenceDate ?? 0)
                warmCount -= 1; if warmCount == 0 { stop = true }
            }
            let (minT, maxT) = repeatedTimed {
                var count = 1000
                cal.enumerateDates(startingAfter: referenceDate, matching: dc, matchingPolicy: .nextTime) { r, _, stop in
                    checksum &+= Int64(r?.timeIntervalSinceReferenceDate ?? 0)
                    count -= 1; if count == 0 { stop = true }
                }
            }
            _ = checksum
            report("nextThousandHanukkahs [\(label)] [\(tzLabel)]", iterations: 1000, unit: "µs/match", scale: 1e6, minT: minT, maxT: maxT)
        }
        }
    }

    // Generic helper: time `Calendar.enumerateDates` for a given pattern, both calendars × both TZs.
    private func runEnumerateBenchmark(label: String, matching dc: DateComponents, matches: Int = 1000) {
        let tzConfigs: [(String, TimeZone)] = [("GMT", .gmt)]
            + (TimeZone(identifier: "America/Los_Angeles").map { [("LA", $0)] } ?? [])
        for (tzLabel, tz) in tzConfigs {
            for (calLabel, cal) in [("ICU", Self.makeICUCalendar(timeZone: tz)),
                                    ("Hebrew", Self.makeHebrewCalendar(timeZone: tz))] {
                var checksum: Int64 = 0
                // warmup
                var warmCount = 10
                cal.enumerateDates(startingAfter: referenceDate, matching: dc, matchingPolicy: .nextTime) { r, _, stop in
                    checksum &+= Int64(r?.timeIntervalSinceReferenceDate ?? 0)
                    warmCount -= 1; if warmCount == 0 { stop = true }
                }
                let (minT, maxT) = repeatedTimed {
                    var count = matches
                    cal.enumerateDates(startingAfter: referenceDate, matching: dc, matchingPolicy: .nextTime) { r, _, stop in
                        checksum &+= Int64(r?.timeIntervalSinceReferenceDate ?? 0)
                        count -= 1; if count == 0 { stop = true }
                    }
                }
                _ = checksum
                report("\(label) [\(calLabel)] [\(tzLabel)]", iterations: matches, unit: "µs/match", scale: 1e6, minT: minT, maxT: maxT)
            }
        }
    }

    /// Baseline: {month, day} only — the existing fast-path. Acts as control.
    @Test func benchmark_nextThousandHanukkahsWithTime() {
        // {month, day, hour, minute, second} — Hanukkah candle-lighting at 18:30:00.
        let dc = DateComponents(month: 3, day: 25, hour: 18, minute: 30, second: 0)
        runEnumerateBenchmark(label: "nextThousandHanukkahsAt1830", matching: dc)
    }

    /// {day} alone — Rosh Chodesh (1st of every Hebrew month).
    @Test func benchmark_nextThousandRoshChodesh() {
        let dc = DateComponents(day: 1)
        runEnumerateBenchmark(label: "nextThousandRoshChodesh", matching: dc)
    }

    /// {month} alone — Tishri 1 (Hebrew New Year, day defaults to 1).
    @Test func benchmark_nextThousandTishriStarts() {
        let dc = DateComponents(month: 1)
        runEnumerateBenchmark(label: "nextThousandTishriStarts", matching: dc)
    }

    /// {weekday} — every Saturday (Shabbat). ICU weekday convention: Sat = 7.
    @Test func benchmark_nextThousandSaturdays() {
        let dc = DateComponents(weekday: 7)
        runEnumerateBenchmark(label: "nextThousandSaturdays", matching: dc)
    }

    @Test func benchmark_allocations() {
        let tzConfigs: [(String, TimeZone)] = [("GMT", .gmt)]
        + (TimeZone(identifier: "America/Los_Angeles").map { [("LA", $0)] } ?? [])

        for (tzLabel, tz) in tzConfigs {
        for (label, mkCal) in [("ICU", { Self.makeICUCalendar(timeZone: tz) }), ("Hebrew", { Self.makeHebrewCalendar(timeZone: tz) })] {
            var checksum: Int64 = 0
            for _ in 0..<100 {
                let cal = mkCal()
                if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
            }
            let iterations = 10_000
            let (minT, maxT) = repeatedTimed {
                for _ in 0..<iterations {
                    let cal = mkCal()
                    if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
                }
            }
            _ = checksum
            report("allocations [\(label)] [\(tzLabel)]", iterations: iterations, unit: "ns/iter", scale: 1e9, minT: minT, maxT: maxT)
        }
        }
    }

    @Test func benchmark_roundTrip() {
        let components: Set<Calendar.Component> = [.year, .month, .day]
        let tzConfigs: [(String, TimeZone)] = [("GMT", .gmt)]
        + (TimeZone(identifier: "America/Los_Angeles").map { [("LA", $0)] } ?? [])

        for (tzLabel, tz) in tzConfigs {
        for (label, cal) in [("ICU", Self.makeICUCalendar(timeZone: tz)), ("Hebrew", Self.makeHebrewCalendar(timeZone: tz))] {
            var checksum: Int64 = 0
            for i in 0..<100 {
                let d = referenceDate.addingTimeInterval(Double(i) * 86400)
                let comps = cal.dateComponents(components, from: d)
                if let rt = cal.date(from: comps) { checksum &+= Int64(rt.timeIntervalSinceReferenceDate) }
            }
            let iterations = 10_000
            let (minT, maxT) = repeatedTimed {
                for i in 0..<iterations {
                    let d = referenceDate.addingTimeInterval(Double(i) * 86400)
                    let comps = cal.dateComponents(components, from: d)
                    if let rt = cal.date(from: comps) { checksum &+= Int64(rt.timeIntervalSinceReferenceDate) }
                }
            }
            _ = checksum
            report("roundTrip [\(label)] [\(tzLabel)]", iterations: iterations, unit: "ns/round-trip", scale: 1e9, minT: minT, maxT: maxT)
        }
        }
    }

    @Test func benchmark_copyOnWrite() {
        let tzConfigs: [(String, TimeZone)] = [("GMT", .gmt)]
        + (TimeZone(identifier: "America/Los_Angeles").map { [("LA", $0)] } ?? [])

        for (tzLabel, tz) in tzConfigs {
        for (label, startCal) in [("ICU", Self.makeICUCalendar(timeZone: tz)), ("Hebrew", Self.makeHebrewCalendar(timeZone: tz))] {
            var cal = startCal
            var checksum: Int64 = 0
            for i in 0..<100 {
                cal.firstWeekday = (i % 2) + 1
                if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
            }
            let iterations = 10_000
            let (minT, maxT) = repeatedTimed {
                for i in 0..<iterations {
                    cal.firstWeekday = (i % 2) + 1
                    if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
                }
            }
            _ = checksum
            report("copyOnWrite [\(label)] [\(tzLabel)]", iterations: iterations, unit: "ns/iter", scale: 1e9, minT: minT, maxT: maxT)
        }
        }
    }
}
