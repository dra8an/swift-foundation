//===----------------------------------------------------------------------===//
// Allocations breakdown: separate construction cost from arithmetic cost.
// Temporary — delete after analysis.
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
private let iterations = 10_000

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

@Suite("Allocations Breakdown")
private struct AllocationsBreakdown {

    @Test func fullBreakdown() {
        var checksum: Int64 = 0

        print("\n=== Allocations Breakdown ===\n")

        for (tzLabel, tz) in [("GMT", TimeZone.gmt)] + (TimeZone(identifier: "America/Los_Angeles").map { [("LA", $0)] } ?? []) {

            print("--- TimeZone: \(tzLabel) ---")

            // Layer 1: Construction only (create calendar, don't use it)
            for (label, mkInner) in [
                ("ICU", { _CalendarICU(identifier: .hebrew, timeZone: tz, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil) as any _CalendarProtocol }),
                ("Hebrew", { _CalendarHebrew(identifier: .hebrew, timeZone: tz, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil) as any _CalendarProtocol })
            ] {
                // warmup
                for _ in 0..<100 { let inner = mkInner(); checksum &+= Int64(inner.firstWeekday) }

                let (minT, _) = repeatedTimed {
                    for _ in 0..<iterations {
                        let inner = mkInner()
                        checksum &+= Int64(inner.firstWeekday)
                    }
                }
                let per = Int(minT * 1e9 / Double(iterations))
                print("Layer 1 — construction only        [\(label)]: \(per) ns/iter")
            }

            // Layer 2: date(byAdding: .day) only (calendar pre-created, reused)
            for (label, inner) in [
                ("ICU", _CalendarICU(identifier: .hebrew, timeZone: tz, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil) as any _CalendarProtocol),
                ("Hebrew", _CalendarHebrew(identifier: .hebrew, timeZone: tz, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil) as any _CalendarProtocol)
            ] {
                let cal = Calendar(inner: inner)
                // warmup
                for _ in 0..<100 {
                    if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
                }

                let (minT, _) = repeatedTimed {
                    for _ in 0..<iterations {
                        if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
                    }
                }
                let per = Int(minT * 1e9 / Double(iterations))
                print("Layer 2 — date(byAdding:.day) only  [\(label)]: \(per) ns/iter")
            }

            // Layer 3: Both combined (matches the original benchmark)
            for (label, mkCal) in [
                ("ICU", { Calendar(inner: _CalendarICU(identifier: .hebrew, timeZone: tz, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)) }),
                ("Hebrew", { Calendar(inner: _CalendarHebrew(identifier: .hebrew, timeZone: tz, locale: nil, firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)) })
            ] {
                // warmup
                for _ in 0..<100 {
                    let cal = mkCal()
                    if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
                }

                let (minT, _) = repeatedTimed {
                    for _ in 0..<iterations {
                        let cal = mkCal()
                        if let d = cal.date(byAdding: .day, value: 1, to: referenceDate) { checksum &+= Int64(d.timeIntervalSinceReferenceDate) }
                    }
                }
                let per = Int(minT * 1e9 / Double(iterations))
                print("Layer 3 — construct + byAdding      [\(label)]: \(per) ns/iter")
            }

            print("")
        }

        _ = checksum
    }
}
