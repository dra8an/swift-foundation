// The regional Hijri dispatcher against (a) the published calendars of the computed authorities and (b) the announced
// dates of the other authorities (moonsighting.com compilation; env ANNOUNCED_CSV, optional).

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

/// Published first days keyed by Hijri year * 12 + month - 1, for CSV rows with the given rule and scope.
private func published(rule: String, scope: String) -> [Int: Int64] {
    let csv = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("crescent_official_dates.csv").path
    guard let data = try? String(contentsOfFile: csv, encoding: .utf8) else { return [:] }
    var starts: [Int: Int64] = [:]
    for line in data.split(whereSeparator: \.isNewline).dropFirst() {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 5, f[0] == rule, f[1] == scope, let y = Int(f[2]), let m = Int(f[3]) else { continue }
        let g = f[4].split(separator: "-").compactMap { Int($0) }
        guard g.count == 3 else { continue }
        starts[y * 12 + m - 1] = starts[y * 12 + m - 1] ?? rd(g[0], g[1], g[2])
    }
    return starts
}

/// Score a method against consecutive published first days; returns (total, hits, misses as "AH y-m published/rule").
private func score(_ starts: [Int: Int64], from firstIndex: Int = 0, _ length: (RataDie, (year: Int, month: Int)) -> Int) -> (Int, Int, [String]) {
    var total = 0, hits = 0, misses: [String] = []
    for idx in starts.keys.sorted() where idx >= firstIndex {
        guard let p = starts[idx - 1], let s = starts[idx] else { continue }
        total += 1
        let next = (year: idx / 12, month: idx % 12 + 1)
        let got = length(RataDie(p), next)
        if got == Int(s - p) { hits += 1 } else { misses.append("AH \(next.year)-\(next.month) published \(s - p)d rule \(got)d") }
    }
    return (total, hits, misses)
}

@Suite struct HijriRegionalTests {
    @Test func ummAlQuraTableReproducesThePublishedTable() {
        let (total, hits, misses) = score(published(rule: "ummalqura", scope: "ummalqura")) { start, next in
            HijriRegional.monthLength(start: start, next: next, method: .ummAlQuraTable)
        }
        print("REGIONAL|Umm al-Qura table|\(hits)/\(total)|\(misses.joined(separator: "; "))")
        #expect(total == 131 && hits == total, "\(misses)")
    }

    @Test func diyanetViaDispatcher() {
        let (total, hits, misses) = score(published(rule: "diyanet", scope: "diyanet"), from: 1399 * 12) { start, next in
            HijriRegional.monthLength(start: start, next: next, method: HijriRegional.method(forRegion: "TR"))
        }
        print("REGIONAL|Diyanet (TR)|\(hits)/\(total)|\(misses.joined(separator: "; "))")
        #expect(total == 707 && hits == total, "\(misses)")
    }

    @Test func malaysiaAndIndonesia() {
        let (mt, mh, mm) = score(published(rule: "mabims", scope: "Malaysia")) { start, next in
            HijriRegional.monthLength(start: start, next: next, method: .malaysia)
        }
        let (rt, rh, rm) = score(published(rule: "mabims", scope: "Malaysia")) { start, next in
            HijriRegional.malaysiaMonthLength(start: start, next: next, corrections: false)
        }
        print("REGIONAL|Malaysia (MY)|\(mh)/\(mt) with corrections, \(rh)/\(rt) by rule|rule misses: \(rm.joined(separator: "; "))")
        let (it, ih, im) = score(published(rule: "mabims", scope: "Indonesia")) { start, next in
            HijriRegional.monthLength(start: start, next: next, method: .indonesia)
        }
        print("REGIONAL|Indonesia (ID)|\(ih)/\(it)|\(im.joined(separator: "; "))")
        #expect(mt == 98 && mh == mt, "\(mm)")
        #expect(it == 25 && ih == it, "\(im)")
    }

    /// Announced dates per region through the dispatcher: the first day predicted for the lunation vs the announced one.
    @Test func announcedDatesByRegion() {
        guard let path = ProcessInfo.processInfo.environment["ANNOUNCED_CSV"], let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let iso: [String: String] = ["Pakistan": "PK", "Morocco": "MA", "Oman": "OM", "India": "IN", "Bangladesh": "BD", "Iran": "IR", "Egypt": "EG",
            "Saudi Arabia": "SA", "Indonesia": "ID", "Malaysia": "MY", "Turkey": "TR", "Algeria": "DZ", "Tunisia": "TN", "Libya": "LY", "Nigeria": "NG",
            "South Africa": "ZA", "Brunei": "BN", "Sri Lanka": "LK", "Jordan": "JO", "Kuwait": "KW", "Australia": "AU", "New Zealand": "NZ", "Nepal": "NP",
            "Mauritius": "MU", "Kenya": "KE", "Tanzania": "TZ", "Senegal": "SN", "Ghana": "GH", "Guyana": "GY", "Trinidad": "TT", "Barbados": "BB",
            "Yemen": "YE", "Sudan": "SD", "Iraq": "IQ", "Syria": "SY", "Lebanon": "LB", "Palestine": "PS", "Qatar": "QA", "Bahrain": "BH", "UAE": "AE",
            "Afghanistan": "AF", "Chile": "CL", "Namibia": "NA", "Zambia": "ZM", "Zimbabwe": "ZW", "Mozambique": "MZ", "Maldives": "MV", "Somalia": "SO"]
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let header = lines.removeFirst().split(separator: ",").map(String.init)
        func col(_ n: String) -> Int { header.firstIndex(of: n)! }
        func fields(_ s: String) -> [String] {
            var out: [String] = [], cur = "", q = false
            for ch in s { if ch == "\"" { q.toggle() } else if ch == "," && !q { out.append(cur); cur = "" } else { cur.append(ch) } }
            out.append(cur); return out
        }
        var tally: [String: (n: Int, exact: Int, later: Int, earlier: Int)] = [:]
        var seen: Set<String> = []
        for line in lines {
            let f = fields(line)
            guard f.count == header.count, f[col("subgroup")] == "no", let code = iso[f[col("country_key")]] else { continue }
            let y = Int(f[col("ah_year")])!, m = Int(f[col("ah_month")])!
            let key = "\(code)|\(y)|\(m)"; guard !seen.contains(key) else { continue }; seen.insert(key)
            let g = f[col("first_day")].split(separator: "-").compactMap { Int($0) }; guard g.count == 3 else { continue }
            let announced = rd(g[0], g[1], g[2])
            let method = HijriRegional.method(forRegion: code)
            var predicted: Int64? = nil
            if case .ummAlQuraTable = method, let t = HijriRegional.ummAlQuraTableFirstDay(year: y, month: m) {
                predicted = t.dayNumber
            } else {
                let conj = Astronomical.newMoonBefore(Moment(Double(announced) + 0.5))
                let first = Int64(floor(conj.inner)) - 1
                for e in first...(first + 5) where HijriRegional.monthLength(start: RataDie(e - 28), next: (y, m), method: method) == 29 {
                    predicted = e + 1; break
                }
            }
            var t = tally[code] ?? (0, 0, 0, 0)
            t.n += 1
            if let p = predicted {
                if p == announced { t.exact += 1 } else if announced > p { t.later += 1 } else { t.earlier += 1 }
            }
            tally[code] = t
        }
        var groups: [String: (Int, Int)] = [:]
        for (code, t) in tally.sorted(by: { $0.key < $1.key }) {
            let m = HijriRegional.method(forRegion: code)
            let group: String
            switch m { case .ummAlQuraTable: group = "Saudi bloc / table"; case .visibility: group = "sighting / Odeh"; default: group = "computed authority" }
            print(String(format: "REGION|%@|%@|n %d|exact %d|later %d|earlier %d", code, group, t.n, t.exact, t.later, t.earlier))
            groups[group, default: (0, 0)].0 += t.n; groups[group, default: (0, 0)].1 += t.exact
        }
        for (g, v) in groups.sorted(by: { $0.key < $1.key }) {
            print(String(format: "REGIONGROUP|%@|%d/%d|%.0f%%", g, v.1, v.0, 100.0 * Double(v.1) / Double(max(v.0, 1))))
        }
    }
}
