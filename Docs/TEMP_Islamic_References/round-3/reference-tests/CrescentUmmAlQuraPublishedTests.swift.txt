// Umm al-Qura's published calendar, AH 1440–1450: every month start computed from the rule (conjunction before sunset
// and moonset after sunset at the Kaaba), compared with the published first days in crescent_official_dates.csv
// (rows rule=ummalqura, from the official 1420–1450 table).
//
// Asserted: with the one named correction the computation reproduces all 131 published decisions; without it the
// rule alone reproduces exactly 130, and the miss is exactly `ummAlQuraCorrections`.

import Testing
import Foundation
import CalendarCore
@testable import AstronomicalEngine
@testable import CalendarAstronomical

private func rd(_ y: Int, _ m: Int, _ d: Int) -> Int64 {
    let y1 = Int64(y - 1)
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    var days = 365 * y1 + y1 / 4 - y1 / 100 + y1 / 400 + Int64((367 * m - 362) / 12)
    if m > 2 { days += leap ? -1 : -2 }
    return days + Int64(d)
}

/// Published Umm al-Qura first days keyed by Hijri year * 12 + month - 1.
private func publishedUmmAlQuraStarts() -> [Int: Int64] {
    let csv = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("crescent_official_dates.csv").path
    guard let data = try? String(contentsOfFile: csv, encoding: .utf8) else { return [:] }
    var starts: [Int: Int64] = [:]
    for line in data.split(whereSeparator: \.isNewline).dropFirst() {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 5, f[0] == "ummalqura", f[1] == "ummalqura", let y = Int(f[2]), let m = Int(f[3]) else { continue }
        let g = f[4].split(separator: "-").compactMap { Int($0) }
        guard g.count == 3 else { continue }
        starts[y * 12 + m - 1] = starts[y * 12 + m - 1] ?? rd(g[0], g[1], g[2])
    }
    return starts
}

@Suite struct CrescentUmmAlQuraPublishedTests {
    @Test func everyPublishedMonthStart() {
        let starts = publishedUmmAlQuraStarts()
        var total = 0, ruleHits = 0, correctedHits = 0
        var ruleMisses: [String] = [], correctedMisses: [String] = []
        for idx in starts.keys.sorted() {
            guard let p = starts[idx - 1], let s = starts[idx] else { continue }
            total += 1
            let next = (year: idx / 12, month: idx % 12 + 1)
            let published = Int(s - p)
            let rule = CrescentRules.ummAlQuraMonthLength(start: RataDie(p), next: next, corrections: false)
            let corrected = CrescentRules.ummAlQuraMonthLength(start: RataDie(p), next: next, corrections: true)
            let tag = "AH \(next.year)-\(next.month)"
            if rule == published { ruleHits += 1 } else { ruleMisses.append(tag) }
            if corrected == published { correctedHits += 1 } else { correctedMisses.append(tag) }
        }
        print("UMMALQURA|published decisions \(total)|rule \(ruleHits)|with corrections \(correctedHits)|rule misses: \(ruleMisses.joined(separator: " "))")
        #expect(total == 131)
        #expect(correctedHits == total, "months not reproduced: \(correctedMisses)")
        #expect(ruleMisses == ["AH 1446-6"])
    }
}
