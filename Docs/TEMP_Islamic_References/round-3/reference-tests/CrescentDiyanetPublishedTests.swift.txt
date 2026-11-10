// Diyanet's published calendar, AH 1399–1457 (December 1978 to about February 2036): every month start computed from
// the era rules, compared with the published first days in crescent_official_dates.csv (rows rule=diyanet).
//
// Two facts are asserted. With the five named corrections the computation reproduces all 707 published decisions.
// Without them the era rules alone reproduce exactly 702, and the five misses are exactly `diyanetCorrections`
// (so neither the rule nor the data can drift unnoticed). Runs in a few minutes.

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

/// Published Diyanet first days keyed by Hijri year * 12 + month - 1.
private func publishedDiyanetStarts() -> [Int: Int64] {
    let csv = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("crescent_official_dates.csv").path
    guard let data = try? String(contentsOfFile: csv, encoding: .utf8) else { return [:] }
    var starts: [Int: Int64] = [:]
    for line in data.split(whereSeparator: \.isNewline).dropFirst() {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 5, f[0] == "diyanet", f[1] == "diyanet", let y = Int(f[2]), let m = Int(f[3]) else { continue }
        let g = f[4].split(separator: "-").compactMap { Int($0) }
        guard g.count == 3 else { continue }
        starts[y * 12 + m - 1] = starts[y * 12 + m - 1] ?? rd(g[0], g[1], g[2])
    }
    return starts
}

@Suite struct CrescentDiyanetPublishedTests {
    @Test func eraBoundaries() {
        #expect(rd(2009, 1, 1) == 733408)
        #expect(rd(2014, 1, 1) == 735234)
        #expect(rd(2017, 1, 1) == 736330)
        #expect(CrescentRules.DiyanetEra(firstDay: RataDie(rd(2008, 12, 31))) == .before2009)
        #expect(CrescentRules.DiyanetEra(firstDay: RataDie(rd(2009, 1, 1))) == .years2009to2013)
        #expect(CrescentRules.DiyanetEra(firstDay: RataDie(rd(2014, 1, 1))) == .years2014to2016)
        #expect(CrescentRules.DiyanetEra(firstDay: RataDie(rd(2017, 1, 1))) == .from2017)
    }

    @Test func everyPublishedMonthStart() {
        let starts = publishedDiyanetStarts()
        var total = 0, ruleHits = 0, correctedHits = 0
        var ruleMisses: [String] = [], correctedMisses: [String] = []
        for idx in starts.keys.sorted() where idx >= 1399 * 12 {
            guard let p = starts[idx - 1], let s = starts[idx] else { continue }
            total += 1
            let next = (year: idx / 12, month: idx % 12 + 1)
            let published = Int(s - p)
            let rule = CrescentRules.diyanetMonthLength(start: RataDie(p), next: next, corrections: false)
            let isCorrection = CrescentRules.diyanetCorrections.contains { $0.year == next.year && $0.month == next.month }
            let corrected = isCorrection ? 30 : rule
            let tag = "AH \(next.year)-\(next.month)"
            if rule == published { ruleHits += 1 } else { ruleMisses.append(tag) }
            if corrected == published { correctedHits += 1 } else { correctedMisses.append(tag) }
        }
        print("DIYANET|published decisions \(total)|era rules \(ruleHits)|with corrections \(correctedHits)|rule misses: \(ruleMisses.joined(separator: " "))")
        #expect(total == 707)
        #expect(correctedHits == total, "months not reproduced: \(correctedMisses)")
        #expect(ruleMisses == ["AH 1399-9", "AH 1401-8", "AH 1411-5", "AH 1444-11", "AH 1453-12"])
    }
}
