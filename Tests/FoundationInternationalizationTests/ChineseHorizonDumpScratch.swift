import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

// Research scratch: dumps predicted event instants for the horizon measurement (CHINESE_PLAN § 11.28b). Deleted after the measurement.
@Suite("Chinese Horizon Dump Scratch")
private struct ChineseHorizonDumpScratch {

    static let jdOffset = 1721424.5
    static let meanSynodic = 29.5305888531        // Astronomical Almanac (1992)
    static let meanGregorianYear = 365.2425

    // Our continuous solstice instant near the end of `gregorianYear` via bisection on solarLongitude = 270.
    static func ourSolsticeInstant(_ gregorianYear: Int) -> Double {
        var lo = Double(_CalendarAstronomy.gregorianRataDie(gregorianYear, 12, 1))
        var hi = Double(_CalendarAstronomy.gregorianRataDie(gregorianYear + 1, 1, 10))
        func f(_ t: Double) -> Double {
            var d = _CalendarAstronomy.solarLongitude(at: t) - 270.0
            if d < -180 { d += 360 }; if d > 180 { d -= 360 }
            return d
        }
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if f(mid) < 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    @Test func dump() {
        let years = [-12900, -11700, -9300, -6900, -4500, -2100, -900, 100,
                     2500, 3900, 5100, 6300, 8100, 9900, 11700, 13500, 15300, 16500]

        // Anchors from our own astronomy near 2000, per the horizon-anchor design.
        let moonAnchor = _CalendarAstronomy.nthNewMoon(24724)
        let sunAnchor = Self.ourSolsticeInstant(1999)

        for y in years {
            let jan1 = Double(_CalendarAstronomy.gregorianRataDie(y, 1, 1))
            // Ours, solar: our longitude at a fixed instant.
            let ourLong = _CalendarAstronomy.solarLongitude(at: jan1)
            print("SWEOURSOLAR \(y) \(jan1 + Self.jdOffset) \(ourLong)")
            // Ours, lunar: our first new moon of the year, truth elongation should be 0 there.
            let n = _CalendarAstronomy.numberOfNewMoonAtOrAfter(jan1)
            print("SWEOURMOON \(y) \(_CalendarAstronomy.nthNewMoon(n) + Self.jdOffset) 0")
            // Pingqi, solar: mean longitude at the same fixed instant.
            let meanLong = (270.0 + 360.0 * (jan1 - sunAnchor) / Self.meanGregorianYear)
                .truncatingRemainder(dividingBy: 360.0)
            print("SWEPQSOLAR \(y) \(jan1 + Self.jdOffset) \((meanLong + 360).truncatingRemainder(dividingBy: 360))")
            // Pingqi, lunar: nearest mean new moon after Jan 1, truth elongation should be 0 there.
            let k = ((jan1 - moonAnchor) / Self.meanSynodic).rounded(.up)
            print("SWEPQMOON \(y) \(moonAnchor + k * Self.meanSynodic + Self.jdOffset) 0")
        }
        #expect(true)
    }
}
