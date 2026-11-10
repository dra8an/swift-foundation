// The Hijri calendar by region: one month-length function behind a region-to-method mapping.
//
// Reference implementation for the port's `.islamic` calendar. Without a region, the method is the Umm al-Qura
// table (ICU4X's choice; ICU4C's conjunction clock matches 20% of announced dates). With a region, the method is the
// one measured to reproduce that region's published or announced dates (`Docs/CRESCENT_RULES_RESULTS.md`, Rounds 4–7):
// computed authorities by their own rules, the Saudi-following bloc by the Umm al-Qura table, sighting countries by
// predicted naked-eye visibility (Odeh's criterion) at a national reference point.

import AstronomicalEngine
import CalendarCore
import Foundation

public enum HijriRegional {

    /// How a region's month starts are computed.
    public enum Method: Sendable {
        /// Saudi Arabia's civil calendar: the KACST table for AH 1300–1600, the rule with its correction beyond.
        case ummAlQuraTable
        /// Türkiye: the Diyanet era rules with the five published corrections (`CrescentRules.diyanetMonthLength`).
        case diyanet
        /// Malaysia: MABIMS criteria at the official reference point, with the two published corrections.
        case malaysia
        /// Indonesia: MABIMS criteria at Banda Aceh, geocentric altitude.
        case indonesia
        /// Predicted naked-eye visibility at a national reference point: Odeh's criterion at best time, with the
        /// threshold the authority's announcements were measured to follow (2.0 = zone B, 5.65 = zone A).
        case visibility(Location, minimumOdehValue: Double)
    }

    /// What `.islamic` without a region should compute.
    public static let defaultMethod: Method = .ummAlQuraTable

    static func place(_ lat: Double, _ lon: Double, _ utcHours: Double) -> Location {
        Location(latitude: lat, longitude: lon, elevation: 0, utcOffset: utcHours / 24)
    }

    /// Region (ISO 3166-1 alpha-2) to method. Sighting countries carry the reference point (capital or main city) and the
    /// Odeh threshold their announcements followed in 2009–2026 (results doc, Round 7). Regions not listed follow the
    /// default (Umm al-Qura), which is also what the Saudi-following bloc announces.
    public static func method(forRegion region: String) -> Method {
        switch region.uppercased() {
        case "TR": return .diyanet
        case "MY": return .malaysia
        case "ID": return .indonesia
        // Saudi-following bloc (measured 70–93% on Umm al-Qura's own rule).
        case "SA", "KW", "QA", "BH", "AE", "YE", "JO", "PS", "LB", "SY", "IQ", "SD", "DZ", "TN", "LY", "EG", "AF", "SO":
            return .ummAlQuraTable
        // Sighting countries, zone B unless their announcements followed the stricter zone A.
        case "PK": return .visibility(place(24.86, 67.01, 5), minimumOdehValue: 5.65)       // Karachi
        case "MA": return .visibility(place(34.02, -6.84, 0), minimumOdehValue: 2)          // Rabat
        case "OM": return .visibility(place(23.59, 58.41, 4), minimumOdehValue: 2)          // Muscat
        case "IN": return .visibility(place(28.61, 77.21, 5.5), minimumOdehValue: 2)        // Delhi
        case "BD": return .visibility(place(23.81, 90.41, 6), minimumOdehValue: 2)          // Dhaka
        case "IR": return .visibility(place(35.69, 51.39, 3.5), minimumOdehValue: 2)        // Tehran
        case "ZA": return .visibility(place(-33.93, 18.42, 2), minimumOdehValue: 2)         // Cape Town
        case "LK": return .visibility(place(6.93, 79.85, 5.5), minimumOdehValue: 2)         // Colombo
        case "MU": return .visibility(place(-20.16, 57.5, 4), minimumOdehValue: 5.65)       // Port Louis
        case "TZ": return .visibility(place(-6.79, 39.28, 3), minimumOdehValue: 2)          // Dar es Salaam
        case "KE": return .visibility(place(-1.29, 36.82, 3), minimumOdehValue: 2)          // Nairobi
        case "AU": return .visibility(place(-31.95, 115.86, 8), minimumOdehValue: 2)        // Perth
        case "NZ": return .visibility(place(-36.85, 174.76, 12), minimumOdehValue: 5.65)    // Auckland
        case "NG": return .visibility(place(9.06, 7.49, 1), minimumOdehValue: 2)            // Abuja
        case "BN": return .visibility(place(4.89, 114.94, 8), minimumOdehValue: 2)          // Bandar Seri Begawan
        case "TT": return .visibility(place(10.65, -61.52, -4), minimumOdehValue: 5.65)     // Port of Spain
        case "GY": return .visibility(place(6.8, -58.16, -4), minimumOdehValue: 5.65)       // Georgetown
        case "BB": return .visibility(place(13.1, -59.61, -4), minimumOdehValue: 5.65)      // Bridgetown
        case "CL": return .visibility(place(-33.45, -70.67, -4), minimumOdehValue: 2)       // Santiago
        case "NA": return .visibility(place(-22.56, 17.08, 2), minimumOdehValue: 5.65)      // Windhoek
        case "ZW": return .visibility(place(-17.83, 31.05, 2), minimumOdehValue: 5.65)      // Harare
        case "ZM": return .visibility(place(-15.39, 28.32, 2), minimumOdehValue: 2)         // Lusaka
        case "MZ": return .visibility(place(-25.97, 32.57, 2), minimumOdehValue: 5.65)      // Maputo
        case "SN": return .visibility(place(14.69, -17.44, 0), minimumOdehValue: 5.65)      // Dakar
        case "GH": return .visibility(place(5.6, -0.19, 0), minimumOdehValue: 2)            // Accra
        case "NP": return .visibility(place(27.72, 85.32, 5.75), minimumOdehValue: 2)       // Kathmandu
        case "MV": return .visibility(place(4.18, 73.51, 5), minimumOdehValue: 2)           // Malé
        default: return defaultMethod
        }
    }

    /// Days (29 or 30) in the month that begins on `start`, where `next` is the Hijri year and month of the following
    /// month. For `.ummAlQuraTable` inside AH 1300–1600 the table decides and `start` is not consulted.
    public static func monthLength(start: RataDie, next: (year: Int, month: Int), method: Method) -> Int {
        switch method {
        case .ummAlQuraTable:
            if let a = ummAlQuraTableFirstDay(year: next.year, month: next.month),
               let b = ummAlQuraTableFirstDay(year: next.month == 1 ? next.year - 1 : next.year, month: next.month == 1 ? 12 : next.month - 1) {
                return Int(a - b)
            }
            return CrescentRules.ummAlQuraMonthLength(start: start, next: next)
        case .diyanet:
            return CrescentRules.diyanetMonthLength(start: start, next: next)
        case .malaysia:
            return malaysiaMonthLength(start: start, next: next)
        case .indonesia:
            return indonesiaMonthLength(start: start, next: next)
        case .visibility(let location, let minimum):
            return (odehValue(evening: start + 28, at: location) ?? -99) >= minimum ? 29 : 30
        }
    }

    /// First day of a Hijri month in the KACST Umm al-Qura table (AH 1300–1600), or nil outside it.
    public static func ummAlQuraTableFirstDay(year: Int, month: Int) -> RataDie? {
        guard (1300...1600).contains(year), (1...12).contains(month),
              let date = try? IslamicUmmAlQura().newDate(year: .extended(Int32(year)), month: Month(integerLiteral: UInt8(month)), day: 1) else { return nil }
        return IslamicUmmAlQura().toRataDie(date)
    }

    // MARK: Malaysia (JAKIM)

    /// Published Malaysian month starts the rule does not reproduce: (year, month of the following month, days).
    /// AH 1443-10 (1 Syawal 1443): a documented sighting (Labuan) overrode the computed takwim. AH 1449-8 (evening of
    /// 28 Dec 2027): 0.015° from the criterion, decided the other way from the identical AH 1444-5 case.
    public static let malaysiaCorrections: [(year: Int, month: Int, days: Int)] = [(1443, 10, 29), (1449, 8, 29)]

    /// MABIMS 1992 criteria until the end of 2021 and MABIMS 2021 from the 2022 takwim, judged at Tanjung Chinchin to
    /// AH 1443 and at Pulau Perak from AH 1444, elongation between the refracted positions (results doc, round 2).
    public static func malaysiaMonthLength(start: RataDie, next: (year: Int, month: Int), corrections: Bool = true) -> Int {
        if corrections, let c = malaysiaCorrections.first(where: { $0.year == next.year && $0.month == next.month }) { return c.days }
        let place = next.year >= 1444 ? CrescentRules.pulauPerak : CrescentRules.tanjungChinchin
        let newCriterion = (start + 29).dayNumber >= 738156   // 2022-01-01
        let options = CrescentRules.MalaysiaOptions(elongationFromApparent: true)
        return CrescentRules.malaysia(start + 28, at: place, newCriterion: newCriterion, options) ? 29 : 30
    }

    // MARK: Indonesia (Kemenag)

    /// MABIMS 2021 from Ramadan 1443, MABIMS 1992 before, at Banda Aceh with geocentric altitude and elongation
    /// (25/25 published decisions).
    public static func indonesiaMonthLength(start: RataDie, next: (year: Int, month: Int)) -> Int {
        let isNew = next.year > 1443 || (next.year == 1443 && next.month >= 9)
        let day = start + 28
        let passes = isNew ? CrescentRules.mabims2021(day, at: CrescentRules.bandaAceh, altitude: .geocentric, elongation: .geocentric)
                           : CrescentRules.mabims1992(day, at: CrescentRules.bandaAceh, altitude: .geocentric, elongation: .geocentric)
        return passes ? 29 : 30
    }

    // MARK: Predicted visibility

    /// Odeh's (2004) visibility value at best time (sunset + 4/9 of the sunset-to-moonset lag): the topocentric arc of
    /// vision minus the crescent-width polynomial. Zone A (easily visible to the naked eye) is ≥ 5.65, zone B (naked
    /// eye under perfect conditions) ≥ 2, zone C (optical aid) ≥ −0.96. Nil when the moon sets before the sun or the
    /// conjunction has not happened by sunset.
    public static func odehValue(evening day: RataDie, at location: Location) -> Double? {
        guard let e = CrescentRules.evening(day, at: location), e.conjunction < e.sunset, e.sunset - e.conjunction < 3,
              let moonset = e.moonset, moonset > e.sunset else { return nil }
        let best = e.sunset + (moonset - e.sunset) * 4 / 9
        let moon = Astronomical.topocentricLunarHorizontal(best, location: location).altitude
        let sun = Astronomical.solarHorizontal(best, location: location).altitude
        let arcl = Astronomical.topocentricElongation(best, location: location)
        let semiDiameterArcmin = 0.2725 * Astronomical.lunarParallaxHorizontal(best) * 60
        let w = semiDiameterArcmin * (1 - cos(arcl * .pi / 180))
        return (moon - sun) - (-0.1018 * w * w * w + 0.7319 * w * w - 6.3226 * w + 7.1651)
    }
}
