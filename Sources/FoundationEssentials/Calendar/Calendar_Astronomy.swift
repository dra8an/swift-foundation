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

// Below is for sin/cos

#if canImport(Darwin)
import Darwin
#elseif canImport(Bionic)
@preconcurrency import Bionic
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(CRT)
import CRT
#elseif os(WASI)
@preconcurrency import WASILibc
#elseif os(Emscripten)
@preconcurrency import EmscriptenLibc
#endif

/// `Docs/Chinese_Calendar_Math.md` explains how all of this works: the two time scales and delta-T, the solar longitude and new-moon series, how a moment becomes a day, and the precision limits. Shared astronomical and Gregorian day-number toolkit for the non-arithmetic calendars (Chinese today; Islamic and Hindu variants can build on it). Solar/lunar theory follows Reingold & Dershowitz, Calendrical Calculations (built on the Meeus and Bretagnon & Simon series); all APIs are calendar-agnostic.
internal enum _CalendarAstronomy {
    static let meanSynodicMonth = 29.530588861
    static let j2000 = 730120.5
    static let newMoonZero = 11.458922815770109

    static func polynomial<let count: Int>(_ x: Double, _ coefficients: InlineArray<count, Double>) -> Double {
        var result = 0.0
        var power = 1.0
        for i in 0..<count {
            result += coefficients[i] * power
            power *= x
        }
        return result
    }

    static func mod360(_ x: Double) -> Double {
        var r = x.truncatingRemainder(dividingBy: 360.0)
        if r < 0 { r += 360.0 }
        return r
    }

    static func sinDegrees(_ d: Double) -> Double { sin(d * .pi / 180.0) }
    static func cosDegrees(_ d: Double) -> Double { cos(d * .pi / 180.0) }

    // Proleptic Gregorian y/m/d -> Rata Die (day 1 = 0001-01-01).
    static func gregorianRataDie(_ y: Int, _ m: Int, _ d: Int) -> Int {
        func floorDivide(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
        let ym1 = y - 1
        let leap = (floorDivide(y, 4) * 4 == y && floorDivide(y, 100) * 100 != y) || floorDivide(y, 400) * 400 == y
        var r = 365 * ym1 + floorDivide(ym1, 4) - floorDivide(ym1, 100) + floorDivide(ym1, 400)
        r += floorDivide(367 * m - 362, 12) + (m <= 2 ? 0 : (leap ? -1 : -2)) + d
        return r
    }

    static func gregorianYear(ofRataDie day: Int) -> Int {
        var y = Int((Double(day) / 365.2425).rounded(.down)) + 1
        while gregorianRataDie(y, 1, 1) > day { y -= 1 }
        while gregorianRataDie(y + 1, 1, 1) <= day { y += 1 }
        return y
    }

    // Delta-T (dynamical minus universal time) as a fraction of a day. Espenak & Meeus polynomial expressions, published by NASA Goddard.
    static func ephemerisCorrection(_ moment: Double) -> Double {
        let year = moment / 365.2425
        let yearInt = Int(year > 0 ? year + 1 : year)
        let fixedMidYear = gregorianRataDie(yearInt, 7, 1)
        let c = (Double(fixedMidYear) - 693596.0) / 36525.0
        let y2000 = Double(yearInt - 2000)
        let y1700 = Double(yearInt - 1700)
        let y1600 = Double(yearInt - 1600)
        let y1000 = Double(yearInt - 1000) / 100.0
        let y0 = Double(yearInt) / 100.0
        let y1820 = Double(yearInt - 1820) / 100.0

        switch yearInt {
        case 2051...2150:
            return (-20.0 + 32.0 * Double((yearInt - 1820) * (yearInt - 1820)) / 10000.0
                    + 0.5628 * Double(2150 - yearInt)) / 86400.0
        case 2006...2050:
            return (62.92 + 0.32217 * y2000 + 0.005589 * y2000 * y2000) / 86400.0
        case 1987...2005:
            return polynomial(y2000, [63.86, 0.3345, -0.060374, 0.0017275,
                                0.000651814, 0.00002373599]) / 86400.0
        case 1900...1986:
            return polynomial(c, [-0.00002, 0.000297, 0.025184, -0.181133,
                            0.553040, -0.861938, 0.677066, -0.212591])
        case 1800...1899:
            return polynomial(c, [-0.000009, 0.003844, 0.083563, 0.865736,
                            4.867575, 15.845535, 31.332267, 38.291999,
                            28.316289, 11.636204, 2.043794])
        case 1700...1799:
            return polynomial(y1700, [8.118780842, -0.005092142, 0.003336121,
                                -0.0000266484]) / 86400.0
        case 1600...1699:
            return polynomial(y1600, [120.0, -0.9808, -0.01532, 0.000140272128]) / 86400.0
        case 500...1599:
            return polynomial(y1000, [1574.2, -556.01, 71.23472, 0.319781,
                                -0.8503463, -0.005050998, 0.0083572073]) / 86400.0
        case -499...499:
            return polynomial(y0, [10583.6, -1014.41, 33.78311, -5.952053,
                             -0.1798452, 0.022174192, 0.0090316521]) / 86400.0
        default:
            return (-20.0 + 32.0 * y1820 * y1820) / 86400.0
        }
    }

    static func universalFromDynamical(_ dynamical: Double) -> Double {
        dynamical - ephemerisCorrection(dynamical)
    }

    static func julianCenturies(_ moment: Double) -> Double {
        (moment + ephemerisCorrection(moment) - j2000) / 36525.0
    }

    static func nutation(_ c: Double) -> Double {
        let a = 124.90 - 1934.134 * c + 0.002063 * c * c
        let b = 201.11 + 72001.5377 * c + 0.00057 * c * c
        return -0.004778 * sinDegrees(a) - 0.0003667 * sinDegrees(b)
    }

    static func aberration(_ c: Double) -> Double {
        0.0000974 * cosDegrees(177.63 + 35999.01848 * c) - 0.005575
    }

    private static let solarTerms: InlineArray<49, (coefficient: Double, addend: Double, multiplier: Double)> = [
        (403406, 270.54861, 0.9287892),
        (195207, 340.19128, 35999.1376958),
        (119433, 63.91854, 35999.4089666),
        (112392, 331.26220, 35998.7287385),
        (3891, 317.843, 71998.20261),
        (2819, 86.631, 71998.4403),
        (1721, 240.052, 36000.35726),
        (660, 310.26, 71997.4812),
        (350, 247.23, 32964.4678),
        (334, 260.87, -19.4410),
        (314, 297.82, 445267.1117),
        (268, 343.14, 45036.8840),
        (242, 166.79, 3.1008),
        (234, 81.53, 22518.4434),
        (158, 3.50, -19.9739),
        (132, 132.75, 65928.9345),
        (129, 182.95, 9038.0293),
        (114, 162.03, 3034.7684),
        (99, 29.8, 33718.148),
        (93, 266.4, 3034.448),
        (86, 249.2, -2280.773),
        (78, 157.6, 29929.992),
        (72, 257.8, 31556.493),
        (68, 185.1, 149.588),
        (64, 69.9, 9037.750),
        (46, 8.0, 107997.405),
        (38, 197.1, -4444.176),
        (37, 250.4, 151.771),
        (32, 65.3, 67555.316),
        (29, 162.7, 31556.080),
        (28, 341.5, -4561.540),
        (27, 291.6, 107996.706),
        (27, 98.5, 1221.655),
        (25, 146.7, 62894.167),
        (24, 110.0, 31437.369),
        (21, 5.2, 14578.298),
        (21, 342.6, -31931.757),
        (20, 230.9, 34777.243),
        (18, 256.1, 1221.999),
        (17, 45.3, 62894.511),
        (14, 242.9, -4442.039),
        (13, 115.2, 107997.909),
        (13, 151.8, 119.066),
        (13, 285.3, 16859.071),
        (12, 53.3, -4.578),
        (10, 126.6, 26895.292),
        (10, 205.7, -39.127),
        (10, 85.9, 12297.536),
        (10, 146.1, 90073.778),
    ]

    // Solar longitude in degrees [0, 360), 49-term Bretagnon & Simon series.
    static func solarLongitude(at moment: Double) -> Double {
        let c = julianCenturies(moment)
        var lambda = 0.0
        for i in 0..<49 {
            let term = solarTerms[i]
            lambda += term.coefficient * sinDegrees(term.addend + term.multiplier * c)
        }
        lambda *= 0.000005729577951308232
        lambda += 282.7771834 + 36000.76953744 * c
        return mod360(lambda + aberration(c) + nutation(c))
    }


    private static let newMoonTerms: InlineArray<24, (sine: Double, solar: Double, lunar: Double, argument: Double)> = [
        (sine: -0.40720, solar: 0, lunar: 1, argument: 0),
        (sine: 0.17241, solar: 1, lunar: 0, argument: 0),
        (sine: 0.01608, solar: 0, lunar: 2, argument: 0),
        (sine: 0.01039, solar: 0, lunar: 0, argument: 2),
        (sine: 0.00739, solar: -1, lunar: 1, argument: 0),
        (sine: -0.00514, solar: 1, lunar: 1, argument: 0),
        (sine: 0.00208, solar: 2, lunar: 0, argument: 0),
        (sine: -0.00111, solar: 0, lunar: 1, argument: -2),
        (sine: -0.00057, solar: 0, lunar: 1, argument: 2),
        (sine: 0.00056, solar: 1, lunar: 2, argument: 0),
        (sine: -0.00042, solar: 0, lunar: 3, argument: 0),
        (sine: 0.00042, solar: 1, lunar: 0, argument: 2),
        (sine: 0.00038, solar: 1, lunar: 0, argument: -2),
        (sine: -0.00024, solar: -1, lunar: 2, argument: 0),
        (sine: -0.00007, solar: 2, lunar: 1, argument: 0),
        (sine: 0.00004, solar: 0, lunar: 2, argument: -2),
        (sine: 0.00004, solar: 3, lunar: 0, argument: 0),
        (sine: 0.00003, solar: 1, lunar: 1, argument: -2),
        (sine: 0.00003, solar: 0, lunar: 2, argument: 2),
        (sine: -0.00003, solar: 1, lunar: 1, argument: 2),
        (sine: 0.00003, solar: -1, lunar: 1, argument: 2),
        (sine: -0.00002, solar: -1, lunar: 1, argument: -2),
        (sine: -0.00002, solar: 1, lunar: 3, argument: 0),
        (sine: 0.00002, solar: 0, lunar: 4, argument: 0),
    ]

    private static let newMoonExtraTerms: InlineArray<13, (addend: Double, multiplier: Double, coefficient: Double)> = [
        (addend: 251.88, multiplier: 0.016321, coefficient: 0.000165),
        (addend: 251.83, multiplier: 26.651886, coefficient: 0.000164),
        (addend: 349.42, multiplier: 36.412478, coefficient: 0.000126),
        (addend: 84.66, multiplier: 18.206239, coefficient: 0.000110),
        (addend: 141.74, multiplier: 53.303771, coefficient: 0.000062),
        (addend: 207.14, multiplier: 2.453732, coefficient: 0.000060),
        (addend: 154.84, multiplier: 7.306860, coefficient: 0.000056),
        (addend: 34.52, multiplier: 27.261239, coefficient: 0.000047),
        (addend: 207.19, multiplier: 0.121824, coefficient: 0.000042),
        (addend: 291.34, multiplier: 1.844379, coefficient: 0.000040),
        (addend: 161.72, multiplier: 24.198154, coefficient: 0.000037),
        (addend: 239.56, multiplier: 25.513099, coefficient: 0.000035),
        (addend: 331.55, multiplier: 3.592518, coefficient: 0.000023),
    ]

    // Moment of the nth new moon since the 24724-indexed epoch; Meeus 24+13 terms.
    static func nthNewMoon(_ n: Int) -> Double {
        let k = Double(n) - 24724.0
        let c = k / 1236.85
        let approx = j2000
            + (5.09766 + meanSynodicMonth * 1236.85 * c
               + 0.00015437 * c * c
               - 0.00000015 * c * c * c
               + 0.00000000073 * c * c * c * c)
        let e = 1.0 - 0.002516 * c - 0.0000074 * c * c
        let solarAnomaly = 2.5534 + 1236.85 * 29.10535670 * c
            - 0.0000014 * c * c - 0.00000011 * c * c * c
        let lunarAnomaly = 201.5643 + 385.81693528 * 1236.85 * c
            + 0.0107582 * c * c + 0.00001238 * c * c * c
            - 0.000000058 * c * c * c * c
        let moonArgument = 160.7108 + 390.67050284 * 1236.85 * c
            - 0.0016118 * c * c - 0.00000227 * c * c * c
            + 0.000000011 * c * c * c * c
        let omega = 124.7746 + (-1.56375588) * 1236.85 * c
            + 0.0020672 * c * c + 0.00000215 * c * c * c

        var correction = -0.00017 * sinDegrees(omega)
        for i in 0..<24 {
            let term = newMoonTerms[i]
            let ePow = pow(e, term.solar.magnitude)
            let arg = term.solar * solarAnomaly + term.lunar * lunarAnomaly + term.argument * moonArgument
            correction += term.sine * ePow * sinDegrees(arg)
        }
        let extra = 0.000325 * sinDegrees(299.77 + 132.8475848 * c - 0.009173 * c * c)
        var additional = 0.0
        for i in 0..<13 {
            let term = newMoonExtraTerms[i]
            additional += term.coefficient * sinDegrees(term.addend + term.multiplier * k)
        }
        return universalFromDynamical(approx + correction + extra + additional)
    }

    static func numberOfNewMoonAtOrAfter(_ moment: Double) -> Int {
        let rawN = ((moment - newMoonZero) / meanSynodicMonth).rounded()
        var n = Int(rawN)
        while nthNewMoon(n) < moment { n += 1 }
        while nthNewMoon(n - 1) >= moment { n -= 1 }
        return n
    }

    static func newMoonAtOrAfter(_ moment: Double) -> Double {
        nthNewMoon(numberOfNewMoonAtOrAfter(moment))
    }

    static func newMoonBefore(_ moment: Double) -> Double {
        nthNewMoon(numberOfNewMoonAtOrAfter(moment) - 1)
    }
}

// MARK: - The moon age of ICU

extension _CalendarAstronomy {
    /// A copy of the moon age that ICU uses for the `.islamic` calendar (`astro.cpp`, after Duffett-Smith, "Practical Astronomy with your Calculator"), with Apple's corrections of the sun longitude for the years 1899 to 2100.
    /// It is less exact than the functions above, but it gives the same `.islamic` dates as ICU. Do not replace it with them, because some month starts would move by a day.
    enum ICUMoon {
        /// The angle from the sun to the moon along the ecliptic, in degrees from -180 to 180, at a time in milliseconds since 1970. It is 0 at the new moon and positive after it.
        static func age(atMilliseconds time: Double) -> Double {
            let day = (time - julianEpochMilliseconds) / 86_400_000.0 - epochJulianDay

            // The sun: its mean anomaly, then its longitude from Kepler's equation.
            let epochAngle = norm2Pi(Double.pi * 2.0 / tropicalYear * day)
            let meanAnomalySun = norm2Pi(epochAngle + sunLongitudeAtEpoch - sunLongitudeOfPerigee)
            let sunLongitude = correctedSunLongitude(norm2Pi(trueAnomaly(meanAnomalySun, eccentricity: sunEccentricity) + sunLongitudeOfPerigee), atMilliseconds: time)

            // The moon: its mean longitude and anomaly, with the corrections for evection, the annual equation, the equation of the center and the variation.
            let meanLongitude = norm2Pi(13.1763966 * Double.pi / 180 * day + moonLongitudeAtEpoch)
            var meanAnomalyMoon = norm2Pi(meanLongitude - 0.1114041 * Double.pi / 180 * day - moonLongitudeOfPerigee)
            let evection = 1.2739 * Double.pi / 180 * sin(2 * (meanLongitude - sunLongitude) - meanAnomalyMoon)
            let annual = 0.1858 * Double.pi / 180 * sin(meanAnomalySun)
            let a3 = 0.3700 * Double.pi / 180 * sin(meanAnomalySun)
            meanAnomalyMoon += evection - annual - a3
            let center = 6.2886 * Double.pi / 180 * sin(meanAnomalyMoon)
            let a4 = 0.2140 * Double.pi / 180 * sin(2 * meanAnomalyMoon)
            var moonLongitude = meanLongitude + evection + center - annual + a4
            moonLongitude += 0.6583 * Double.pi / 180 * sin(2 * (moonLongitude - sunLongitude))

            // From the plane of the moon's orbit to the ecliptic.
            var nodeLongitude = norm2Pi(moonLongitudeOfNode - 0.0529539 * Double.pi / 180 * day)
            nodeLongitude -= 0.16 * Double.pi / 180 * sin(meanAnomalySun)
            let y = sin(moonLongitude - nodeLongitude)
            let x = cos(moonLongitude - nodeLongitude)
            let moonEclipticLongitude = atan2(y * cos(moonInclination), x) + nodeLongitude

            let age = norm2Pi(moonEclipticLongitude - sunLongitude) * 180 / Double.pi
            return age > 180 ? age - 360 : age
        }

        private static let julianEpochMilliseconds = -210_866_760_000_000.0
        private static let epochJulianDay = 2_447_891.5
        private static let tropicalYear = 365.242191
        private static let sunLongitudeAtEpoch = 279.403303 * Double.pi / 180
        private static let sunLongitudeOfPerigee = 282.768422 * Double.pi / 180
        private static let sunEccentricity = 0.016713
        private static let moonLongitudeAtEpoch = 318.351648 * Double.pi / 180
        private static let moonLongitudeOfPerigee = 36.340410 * Double.pi / 180
        private static let moonLongitudeOfNode = 318.510107 * Double.pi / 180
        private static let moonInclination = 5.145366 * Double.pi / 180

        private static func norm2Pi(_ angle: Double) -> Double {
            angle - Double.pi * 2.0 * (angle / (Double.pi * 2.0)).rounded(.down)
        }

        // Solves Kepler's equation by Newton's method, then gives the true anomaly.
        private static func trueAnomaly(_ meanAnomaly: Double, eccentricity: Double) -> Double {
            var eccentricAnomaly = meanAnomaly
            var delta: Double
            repeat {
                delta = eccentricAnomaly - eccentricity * sin(eccentricAnomaly) - meanAnomaly
                eccentricAnomaly = eccentricAnomaly - delta / (1 - eccentricity * cos(eccentricAnomaly))
            } while abs(delta) > 1e-5
            return 2.0 * atan(tan(eccentricAnomaly / 2) * ((1 + eccentricity) / (1 - eccentricity)).squareRoot())
        }

        // Apple's correction of the computed sun longitude. Between two winter solstices, it changes in straight lines between the values at the solstice, the equinoxes and the summer solstice.
        private static func correctedSunLongitude(_ longitude: Double, atMilliseconds time: Double) -> Double {
            let first = 10_000.0 * Double(winterSolstices[0])
            let last = 10_000.0 * Double(winterSolstices[winterSolstices.count - 1])
            guard time >= first && time < last else { return longitude }
            var index = Int(Int32(Double(winterSolstices.count) * (time - first) / (last - first)))
            var current = Int32(time / 10_000.0)
            while current < winterSolstices[index] { index -= 1 }
            while current >= winterSolstices[index + 1] { index += 1 }
            current -= winterSolstices[index]
            // The average times from a winter solstice to the next equinoxes and summer solstice, in units of 10 seconds.
            let springEquinox: Int32 = 768_903, summerSolstice: Int32 = 1_570_332, autumnEquinox: Int32 = 2_379_459
            let factor: Double
            let (start, end): (Int8, Int8)
            if current < springEquinox {
                factor = Double(current) / Double(springEquinox)
                (start, end) = (sunCorrections[4 * index], sunCorrections[4 * index + 1])
            } else if current < summerSolstice {
                factor = Double(current - springEquinox) / Double(summerSolstice - springEquinox)
                (start, end) = (sunCorrections[4 * index + 1], sunCorrections[4 * index + 2])
            } else if current < autumnEquinox {
                factor = Double(current - summerSolstice) / Double(autumnEquinox - summerSolstice)
                (start, end) = (sunCorrections[4 * index + 2], sunCorrections[4 * index + 3])
            } else {
                factor = Double(current - autumnEquinox) / Double(winterSolstices[index + 1] - winterSolstices[index] - autumnEquinox)
                (start, end) = (sunCorrections[4 * index + 3], sunCorrections[4 * index + 4])
            }
            var corrected = longitude + (Double(start) + factor * Double(Int(end) - Int(start))) / 100_000.0
            if corrected >= 2 * Double.pi {
                corrected -= 2 * Double.pi
            } else if corrected < 0 {
                corrected += 2 * Double.pi
            }
            return corrected
        }

        // The December solstices of 1899 to 2100, in units of 10 seconds since 1970.
        private static let winterSolstices: InlineArray<202, Int32> = [
            -220984944, -217829274, -214673538, -211517790, -208362120, -205206396, -202050696, -198895002, // 1899-1906
            -195739254, -192583602, -189427920, -186272208, -183116562, -179960850, -176805150, -173649468, // 1907-1914
            -170493744, -167338086, -164182404, -161026674, -157870998, -154715298, -151559592, -148403898, // 1915-1922
            -145248162, -142092450, -138936738, -135781002, -132625332, -129469656, -126313962, -123158286, // 1923-1930
            -120002586, -116846916, -113691252, -110535546, -107379858, -104224158, -101068428, -97912722, // 1931-1938
            -94757004, -91601310, -88445616, -85289886, -82134186, -78978510, -75822822, -72667122, // 1939-1946
            -69511422, -66355722, -63200022, -60044322, -56888640, -53732982, -50577294, -47421576, // 1947-1954
            -44265894, -41110200, -37954506, -34798800, -31643076, -28487364, -25331646, -22175910, // 1955-1962
            -19020228, -15864546, -12708840, -9553152, -6397464, -3241800, -86136, 3069576, // 1963-1970
            6225264, 9380958, 12536688, 15692376, 18848070, 22003770, 25159458, 28315206, // 1971-1978
            31470900, 34626576, 37782306, 40937988, 44093700, 47249418, 50405088, 53560812, // 1979-1986
            56716476, 59872128, 63027852, 66183522, 69339198, 72494898, 75650556, 78806298, // 1987-1994
            81962022, 85117716, 88273482, 91429176, 94584864, 97740588, 100896246, 104051964, // 1995-2002
            107207664, 110363292, 113519010, 116674692, 119830362, 122986104, 126141762, 129297468, // 2003-2010
            132453180, 135608832, 138764586, 141920298, 145075968, 148231704, 151387368, 154543092, // 2011-2018
            157698834, 160854492, 164010234, 167165928, 170321562, 173477280, 176632938, 179788620, // 2019-2026
            182944332, 186099960, 189255684, 192411414, 195567090, 198722856, 201878550, 205034244, // 2027-2034
            208189986, 211345638, 214501362, 217657092, 220812720, 223968438, 227124108, 230279784, // 2035-2042
            233435526, 236591184, 239746890, 242902608, 246058242, 249213972, 252369672, 255525348, // 2043-2050
            258681078, 261836742, 264992454, 268148214, 271303890, 274459626, 277615332, 280770990, // 2051-2058
            283926708, 287082366, 290238048, 293393772, 296549406, 299705088, 302860800, 306016470, // 2059-2066
            309172218, 312327912, 315483612, 318639354, 321795018, 324950736, 328106460, 331262130, // 2067-2074
            334417842, 337573518, 340729200, 343884942, 347040624, 350196312, 353352012, 356507664, // 2075-2082
            359663358, 362819046, 365974728, 369130452, 372286128, 375441816, 378597552, 381753258, // 2083-2090
            384908988, 388064706, 391220400, 394376118, 397531800, 400687476, 403843176, 406998840, // 2091-2098
            410154504, 413310186, // 2099-2100
        ]

        // The corrections of the sun longitude in radians times 100,000, at the winter solstice, the spring equinox, the summer solstice and the autumn equinox that follow each winter solstice above.
        private static let sunCorrections: InlineArray<808, Int8> = [
            85, 25, -89, -32, 90, 30, -88, -33, 81, 26, -86, -29, 69, 14, -87, -30, // 1899-1902
            74, 21, -84, -38, 68, 7, -98, -40, 66, 0, -100, -35, 66, 10, -91, -41, // 1903-1906
            54, 3, -100, -42, 63, 7, -97, -40, 65, 6, -90, -36, 61, 3, -88, -33, // 1907-1910
            70, 20, -79, -36, 66, 19, -84, -31, 65, 14, -80, -22, 67, 25, -64, -24, // 1911-1914
            61, 16, -71, -26, 68, 14, -72, -22, 70, 15, -68, -19, 62, 9, -74, -20, // 1915-1918
            66, 20, -71, -24, 64, 16, -80, -28, 61, 6, -82, -29, 61, 15, -67, -34, // 1919-1922
            52, 12, -76, -43, 48, 8, -78, -37, 44, 8, -68, -32, 35, -2, -72, -33, // 1923-1926
            40, 2, -67, -32, 43, 0, -74, -30, 43, -6, -78, -24, 46, 7, -62, -22, // 1927-1930
            45, 8, -69, -27, 49, 7, -69, -23, 55, 13, -54, -17, 52, 10, -56, -22, // 1931-1934
            53, 22, -49, -21, 52, 23, -52, -19, 44, 12, -54, -17, 41, 16, -40, -18, // 1935-1938
            36, 8, -49, -26, 36, 0, -59, -25, 35, -2, -52, -20, 28, -7, -60, -26, // 1939-1942
            26, -2, -62, -27, 30, -2, -63, -28, 31, -11, -68, -30, 29, -1, -51, -29, // 1943-1946
            27, 4, -55, -34, 26, 1, -59, -29, 24, 3, -40, -16, 23, 1, -41, -21, // 1947-1950
            25, 3, -40, -19, 32, 4, -38, -11, 33, 0, -44, -12, 28, 8, -31, -8, // 1951-1954
            30, 11, -35, -14, 30, 4, -45, -17, 29, 4, -30, -10, 27, 2, -35, -22, // 1955-1958
            20, 3, -39, -25, 16, 3, -38, -18, 11, -6, -44, -24, 2, -9, -34, -23, // 1959-1962
            4, -10, -39, -28, 6, -18, -50, -29, 4, -16, -37, -15, 4, -11, -38, -22, // 1963-1966
            5, -7, -40, -21, 11, -4, -32, -12, 17, -3, -31, -16, 13, 5, -16, -13, // 1967-1970
            14, 11, -14, -12, 14, 9, -21, -11, 6, 2, -7, 1, 7, 0, -7, -7, // 1971-1974
            7, -3, -18, -12, 5, -8, -19, -2, 6, -11, -28, -12, -4, -11, -24, -14, // 1975-1978
            -5, -10, -27, -18, -1, -15, -38, -27, -9, -19, -25, -18, -7, -14, -21, -26, // 1979-1982
            -11, -9, -27, -29, -16, -11, -19, -12, -11, -11, -16, -16, -18, -11, -7, -12, // 1983-1986
            -12, -9, -3, -7, -4, -9, -12, -10, -10, -12, -2, 6, -6, -5, 0, 1, // 1987-1990
            -2, -2, -6, -6, -4, -7, -3, 5, 2, -5, -2, -4, -7, -3, 0, -10, // 1991-1994
            -13, -2, 0, -8, -13, -6, -9, -17, -29, -18, -2, -9, -29, -22, 0, -14, // 1995-1998
            -28, -22, -11, -23, -34, -31, -12, -9, -27, -26, -10, -11, -33, -21, -7, -15, // 1999-2002
            -34, -20, -4, -8, -21, -15, -4, -13, -26, -19, 5, -4, -24, -11, 15, -2, // 2003-2006
            -19, -2, 10, -7, -29, -10, 12, 9, -22, -10, 19, 7, -25, -10, 21, 0, // 2007-2010
            -29, -15, 17, 4, -21, -14, 9, -2, -33, -22, 11, 1, -37, -21, 13, 0, // 2011-2014
            -33, -16, 5, -15, -42, -29, 3, -6, -36, -25, 10, -10, -42, -18, 12, -18, // 2015-2018
            -53, -22, 12, -9, -45, -20, 11, -10, -56, -29, 19, -4, -56, -31, 26, 0, // 2019-2022
            -44, -23, 20, -7, -49, -31, 17, 8, -42, -25, 24, 12, -40, -15, 27, 3, // 2023-2026
            -44, -19, 24, 9, -31, -13, 28, 4, -37, -15, 34, 4, -45, -16, 37, 5, // 2027-2030
            -41, -6, 34, -3, -56, -21, 30, 5, -57, -27, 37, 7, -57, -24, 36, -5, // 2031-2034
            -67, -37, 24, -1, -59, -36, 23, -1, -65, -37, 25, -1, -73, -41, 26, 0, // 2035-2038
            -60, -29, 26, -8, -65, -37, 24, 0, -60, -35, 34, 5, -57, -17, 42, -1, // 2039-2042
            -67, -22, 37, 6, -60, -20, 45, 10, -63, -23, 53, 10, -68, -29, 54, 13, // 2043-2046
            -56, -20, 51, 9, -64, -27, 46, 17, -65, -30, 49, 20, -62, -19, 54, 8, // 2047-2050
            -70, -29, 43, 9, -64, -31, 44, 6, -68, -30, 51, 1, -82, -36, 47, 0, // 2051-2054
            -78, -28, 47, -1, -87, -39, 44, 4, -90, -48, 48, 9, -83, -37, 56, 1, // 2055-2058
            -88, -44, 44, 6, -81, -41, 46, 12, -79, -33, 58, 12, -85, -37, 55, 13, // 2059-2062
            -73, -26, 62, 14, -71, -27, 64, 17, -75, -30, 69, 22, -70, -13, 80, 18, // 2063-2066
            -82, -21, 70, 19, -82, -28, 71, 24, -84, -30, 80, 19, -94, -43, 69, 13, // 2067-2070
            -88, -40, 63, 12, -93, -45, 58, 14, -100, -53, 55, 15, -95, -40, 63, 7, // 2071-2074
            -99, -43, 55, 3, -96, -47, 57, 8, -94, -37, 73, 8, -104, -38, 70, 7, // 2075-2078
            -102, -33, 74, 14, -101, -34, 82, 22, -102, -43, 84, 27, -94, -32, 94, 27, // 2079-2082
            -94, -33, 85, 28, -93, -39, 81, 34, -91, -31, 95, 34, -97, -36, 85, 25, // 2083-2086
            -94, -35, 83, 24, -93, -36, 86, 23, -102, -44, 81, 19, -105, -33, 89, 17, // 2087-2090
            -113, -37, 80, 14, -118, -52, 75, 15, -118, -50, 91, 17, -123, -56, 83, 10, // 2091-2094
            -121, -54, 79, 17, -118, -51, 86, 26, -119, -55, 84, 25, -113, -41, 97, 28, // 2095-2098
            -108, -39, 94, 27, -105, 0, 0, 0, // 2099-2100
        ]
    }
}

// MARK: - The moon and the sun seen from a place, and the first crescent

extension _CalendarAstronomy {
    /// A place: latitude and longitude in degrees (north and east are positive), elevation in meters. The UTC offset (days, by default from the longitude) gives the start of the local day.
    struct Location {
        var latitude: Double
        var longitude: Double
        var elevation: Double
        var utcOffset: Double

        init(latitude: Double, longitude: Double, elevation: Double = 0, utcOffsetHours: Double? = nil) {
            (self.latitude, self.longitude, self.elevation, utcOffset) = (latitude, longitude, elevation, (utcOffsetHours ?? longitude / 15) / 24)
        }
    }

    static func tanDegrees(_ angle: Double) -> Double { tan(angle * .pi / 180.0) }
    static func degrees(_ radians: Double) -> Double { radians * 180.0 / .pi }

    /// The Earth's equatorial radius in meters, for the moon's parallax (Meeus, chapter 40).
    static let earthEquatorialRadius = 6_378_140.0
    /// The Earth's mean radius in meters, for the dip of the horizon seen from a height (Calendrical Calculations).
    static let earthMeanRadius = 6.372e6
    /// The degrees that the Earth turns against the stars in one day of the mean sun.
    static let siderealDegreesPerDay = 360.98564736629
    /// The apparent radius of the sun and of the moon in degrees, 16 minutes of arc (Calendrical Calculations).
    static let apparentRadius = 16.0 / 60
    /// The depression of the sun's center at the standard sunset: 34 minutes of arc of refraction and 16 of the sun's radius.
    static let standardSunset = 50.0 / 60

    // Multiples of the moon's elongation, the sun's and the moon's anomalies and the moon's argument of latitude, then the coefficients of longitude and distance. Meeus, table 47.A.
    private static let lunarTerms: InlineArray<60, (multiples: (Double, Double, Double, Double), longitude: Double, distance: Double)> = [
        ((0, 0, 1, 0), 6288774, -20905355), ((2, 0, -1, 0), 1274027, -3699111), ((2, 0, 0, 0), 658314, -2955968), ((0, 0, 2, 0), 213618, -569925),
        ((0, 1, 0, 0), -185116, 48888), ((0, 0, 0, 2), -114332, -3149), ((2, 0, -2, 0), 58793, 246158), ((2, -1, -1, 0), 57066, -152138),
        ((2, 0, 1, 0), 53322, -170733), ((2, -1, 0, 0), 45758, -204586), ((0, 1, -1, 0), -40923, -129620), ((1, 0, 0, 0), -34720, 108743),
        ((0, 1, 1, 0), -30383, 104755), ((2, 0, 0, -2), 15327, 10321), ((0, 0, 1, 2), -12528, 0), ((0, 0, 1, -2), 10980, 79661),
        ((4, 0, -1, 0), 10675, -34782), ((0, 0, 3, 0), 10034, -23210), ((4, 0, -2, 0), 8548, -21636), ((2, 1, -1, 0), -7888, 24208),
        ((2, 1, 0, 0), -6766, 30824), ((1, 0, -1, 0), -5163, -8379), ((1, 1, 0, 0), 4987, -16675), ((2, -1, 1, 0), 4036, -12831),
        ((2, 0, 2, 0), 3994, -10445), ((4, 0, 0, 0), 3861, -11650), ((2, 0, -3, 0), 3665, 14403), ((0, 1, -2, 0), -2689, -7003),
        ((2, 0, -1, 2), -2602, 0), ((2, -1, -2, 0), 2390, 10056), ((1, 0, 1, 0), -2348, 6322), ((2, -2, 0, 0), 2236, -9884),
        ((0, 1, 2, 0), -2120, 5751), ((0, 2, 0, 0), -2069, 0), ((2, -2, -1, 0), 2048, -4950), ((2, 0, 1, -2), -1773, 4130),
        ((2, 0, 0, 2), -1595, 0), ((4, -1, -1, 0), 1215, -3958), ((0, 0, 2, 2), -1110, 0), ((3, 0, -1, 0), -892, 3258),
        ((2, 1, 1, 0), -810, 2616), ((4, -1, -2, 0), 759, -1897), ((0, 2, -1, 0), -713, -2117), ((2, 2, -1, 0), -700, 2354),
        ((2, 1, -2, 0), 691, 0), ((2, -1, 0, -2), 596, 0), ((4, 0, 1, 0), 549, -1423), ((0, 0, 4, 0), 537, -1117),
        ((4, -1, 0, 0), 520, -1571), ((1, 0, -2, 0), -487, -1739), ((2, 1, 0, -2), -399, 0), ((0, 0, 2, -2), -381, -4421),
        ((1, 1, 1, 0), 351, 0), ((3, 0, -2, 0), -340, 0), ((4, 0, -3, 0), 330, 0), ((2, -1, 2, 0), 327, 0),
        ((0, 2, 1, 0), -323, 1165), ((1, 1, -1, 0), 299, 0), ((2, 0, 3, 0), 294, 0), ((2, 0, -1, -2), 0, 8752),
    ]

    // The same multiples with the coefficients of the moon's latitude (sine, 0.000001 degrees). Meeus, table 47.B.
    private static let latitudeTerms: InlineArray<60, (multiples: (Double, Double, Double, Double), latitude: Double)> = [
        ((0, 0, 0, 1), 5128122), ((0, 0, 1, 1), 280602), ((0, 0, 1, -1), 277693), ((2, 0, 0, -1), 173237), ((2, 0, -1, 1), 55413),
        ((2, 0, -1, -1), 46271), ((2, 0, 0, 1), 32573), ((0, 0, 2, 1), 17198), ((2, 0, 1, -1), 9266), ((0, 0, 2, -1), 8822),
        ((2, -1, 0, -1), 8216), ((2, 0, -2, -1), 4324), ((2, 0, 1, 1), 4200), ((2, 1, 0, -1), -3359), ((2, -1, -1, 1), 2463),
        ((2, -1, 0, 1), 2211), ((2, -1, -1, -1), 2065), ((0, 1, -1, -1), -1870), ((4, 0, -1, -1), 1828), ((0, 1, 0, 1), -1794),
        ((0, 0, 0, 3), -1749), ((0, 1, -1, 1), -1565), ((1, 0, 0, 1), -1491), ((0, 1, 1, 1), -1475), ((0, 1, 1, -1), -1410),
        ((0, 1, 0, -1), -1344), ((1, 0, 0, -1), -1335), ((0, 0, 3, 1), 1107), ((4, 0, 0, -1), 1021), ((4, 0, -1, 1), 833),
        ((0, 0, 1, -3), 777), ((4, 0, -2, 1), 671), ((2, 0, 0, -3), 607), ((2, 0, 2, -1), 596), ((2, -1, 1, -1), 491),
        ((2, 0, -2, 1), -451), ((0, 0, 3, -1), 439), ((2, 0, 2, 1), 422), ((2, 0, -3, -1), 421), ((2, 1, -1, 1), -366),
        ((2, 1, 0, 1), -351), ((4, 0, 0, 1), 331), ((2, -1, 1, 1), 315), ((2, -2, 0, -1), 302), ((0, 0, 1, 3), -283),
        ((2, 1, 1, -1), -229), ((1, 1, 0, -1), 223), ((1, 1, 0, 1), 223), ((0, 1, -2, -1), -220), ((2, 1, -1, -1), -220),
        ((1, 0, 1, 1), -185), ((2, -1, -2, -1), 181), ((0, 1, 2, 1), -177), ((4, 0, -2, -1), 176), ((4, -1, -1, -1), 166),
        ((1, 0, 1, -1), -164), ((4, 0, 1, -1), 132), ((1, 0, -1, -1), -119), ((4, -1, 0, -1), 115), ((2, -2, 0, 1), 107),
    ]

    /// The moon's apparent ecliptic longitude and latitude in degrees, and its distance from the center of the Earth in meters. Meeus, chapter 47.
    static func lunarPosition(at moment: Double) -> (longitude: Double, latitude: Double, distance: Double) {
        let centuries = julianCenturies(moment)
        let meanLongitude = mod360(polynomial(centuries, [218.3164477, 481267.88123421, -0.0015786, 1 / 538841.0, -1 / 65194000.0]))
        let arguments = (mod360(polynomial(centuries, [297.85019021, 445267.1114034, -0.0018819, 1 / 545868.0, -1 / 113065000.0])), mod360(polynomial(centuries, [357.5291092, 35999.0502909, -0.0001536, 1 / 24490000.0])), mod360(polynomial(centuries, [134.9633964, 477198.8675055, 0.0087414, 1 / 69699.0, -1 / 14712000.0])), mod360(polynomial(centuries, [93.2720950, 483202.0175233, -0.0036539, -1 / 3526000.0, 1 / 863310000.0])))
        let eccentricity = 1.0 - 0.002516 * centuries - 0.0000074 * centuries * centuries
        // A term with the sun's anomaly is multiplied by the eccentricity factor once for each multiple of it.
        func angle(_ multiples: (Double, Double, Double, Double)) -> (degrees: Double, factor: Double) {
            (multiples.0 * arguments.0 + multiples.1 * arguments.1 + multiples.2 * arguments.2 + multiples.3 * arguments.3, pow(eccentricity, multiples.1.magnitude))
        }
        var (longitude, latitude, distance) = (0.0, 0.0, 0.0)
        for index in 0..<60 {
            let term = angle(lunarTerms[index].multiples), latitudeTerm = angle(latitudeTerms[index].multiples)
            longitude += lunarTerms[index].longitude * term.factor * sinDegrees(term.degrees)
            distance += lunarTerms[index].distance * term.factor * cosDegrees(term.degrees)
            latitude += latitudeTerms[index].latitude * latitudeTerm.factor * sinDegrees(latitudeTerm.degrees)
        }
        let venus = 119.75 + centuries * 131.849, node = arguments.3, moonAnomaly = arguments.2
        longitude = mod360(meanLongitude + (longitude + 3958 * sinDegrees(venus) + 318 * sinDegrees(53.09 + centuries * 479264.29) + 1962 * sinDegrees(meanLongitude - node)) / 1_000_000 + nutation(centuries))
        latitude = (latitude + 175 * (sinDegrees(venus + node) + sinDegrees(venus - node)) - 2235 * sinDegrees(meanLongitude) + 127 * sinDegrees(meanLongitude - moonAnomaly) - 115 * sinDegrees(meanLongitude + moonAnomaly) + 382 * sinDegrees(313.45 + centuries * 481266.484)) / 1_000_000
        return (longitude, latitude, 385_000_560 + distance)
    }

    /// The angle from the sun to the moon along the ecliptic, in degrees from 0 to 360. It is 0 at the new moon.
    static func lunarPhase(at moment: Double) -> Double {
        let phase = mod360(lunarPosition(at: moment).longitude - solarLongitude(at: moment))
        let months = (moment - nthNewMoon(Int(((moment - newMoonZero) / meanSynodicMonth).rounded()))) / meanSynodicMonth
        let meanPhase = 360 * (months - months.rounded(.down))
        return abs(phase - meanPhase) > 180 ? meanPhase : phase
    }

    /// The last moment at or before `moment` when the phase was `phase` degrees.
    static func lunarPhase(_ phase: Double, atOrBefore moment: Double) -> Double {
        let estimate = moment - meanSynodicMonth / 360 * (lunarPhase(at: moment) - phase).truncatingRemainder(dividingBy: 360)
        return binarySearch(estimate - 2, min(moment, estimate + 2), precision: 1e-5) { mod360(lunarPhase(at: $0) - phase) < 180 }
    }

    // The middle of the last interval narrower than `precision`. `isPast` is true for the values after the result.
    static func binarySearch(_ low: Double, _ high: Double, precision: Double, isPast: (Double) -> Bool) -> Double {
        var (low, high) = (low, high)
        while true {
            let middle = low + (high - low) / 2
            if isPast(middle) { high = middle } else { low = middle }
            if high - low < precision { return middle }
        }
    }

    static func obliquity(at moment: Double) -> Double {
        23.0 + 26.0 / 60.0 + 21.448 / 3600.0 + polynomial(julianCenturies(moment), [0, -46.8150 / 3600, -0.00059 / 3600, 0.001813 / 3600])
    }

    /// The right ascension and declination, in degrees, of a point at the given ecliptic latitude and longitude.
    static func equatorial(at moment: Double, latitude: Double, longitude: Double) -> (rightAscension: Double, declination: Double) {
        let obliquity = obliquity(at: moment)
        return (mod360(degrees(atan2(sinDegrees(longitude) * cosDegrees(obliquity) - tanDegrees(latitude) * sinDegrees(obliquity), cosDegrees(longitude)))), mod360(degrees(asin(sinDegrees(latitude) * cosDegrees(obliquity) + cosDegrees(latitude) * sinDegrees(obliquity) * sinDegrees(longitude)))))
    }

    /// The mean sidereal time at Greenwich in degrees, for a moment in universal time.
    static func siderealTime(at moment: Double) -> Double {
        mod360(polynomial((moment - j2000) / 36525, [280.46061837, 36525 * siderealDegreesPerDay, 0.000387933, -1 / 38710000.0]))
    }

    /// The altitude and the azimuth (from the south toward the west) in degrees, at a place, of a point at the given ecliptic latitude and longitude, seen from the center of the Earth.
    static func horizontal(at moment: Double, _ location: Location, latitude: Double, longitude: Double) -> (altitude: Double, azimuth: Double) {
        let sky = equatorial(at: moment, latitude: latitude, longitude: longitude)
        let hourAngle = mod360(siderealTime(at: moment) + location.longitude - sky.rightAscension)
        let altitude = degrees(asin(sinDegrees(location.latitude) * sinDegrees(sky.declination) + cosDegrees(location.latitude) * cosDegrees(sky.declination) * cosDegrees(hourAngle)))
        return (mod360(altitude + 180) - 180, degrees(atan2(sinDegrees(hourAngle), cosDegrees(hourAngle) * sinDegrees(location.latitude) - tanDegrees(sky.declination) * cosDegrees(location.latitude))))
    }

    // The moon's altitude seen from the surface: the altitude from the center less the parallax.
    private static func topocentric(_ altitude: Double, distance: Double) -> Double {
        altitude - mod360(degrees(asin(earthEquatorialRadius / distance * cosDegrees(altitude))))
    }

    /// The moon's altitude in degrees at a place, of the kind that a rule asks for.
    static func lunarAltitude(at moment: Double, _ location: Location, _ kind: VisibilityRule.Altitude = .geocentric) -> Double {
        let moon = lunarPosition(at: moment)
        var altitude = horizontal(at: moment, location, latitude: moon.latitude, longitude: moon.longitude).altitude
        if kind.fromSurface { altitude = topocentric(altitude, distance: moon.distance) }
        switch kind.refraction {
        case .none: break
        case .horizon: altitude += refraction(location)
        case .forAltitude: altitude += refraction(atAltitude: altitude)
        }
        return altitude + kind.edge.rawValue * apparentRadius
    }

    /// The angle between the sun and the moon in degrees, of the kind that a rule asks for.
    static func elongation(at moment: Double, _ location: Location, _ kind: VisibilityRule.Elongation) -> Double {
        guard kind != .geocentric else { return geocentricElongation(at: moment) }
        let moon = lunarPosition(at: moment)
        let sky = horizontal(at: moment, location, latitude: moon.latitude, longitude: moon.longitude), sun = horizontal(at: moment, location, latitude: 0, longitude: solarLongitude(at: moment))
        var altitude = topocentric(sky.altitude, distance: moon.distance), sunAltitude = sun.altitude
        if kind == .refracted { (altitude, sunAltitude) = (altitude + refraction(atAltitude: altitude), sunAltitude + refraction(atAltitude: sunAltitude)) }
        return degrees(acos(sinDegrees(sunAltitude) * sinDegrees(altitude) + cosDegrees(sunAltitude) * cosDegrees(altitude) * cosDegrees(sun.azimuth - sky.azimuth)))
    }

    /// The refraction in degrees for a body whose altitude without air is `altitude` degrees: Saemundsson's formula, and below -1° the value at -1°.
    static func refraction(atAltitude altitude: Double) -> Double {
        let bounded = max(altitude, -1)
        return 1.02 / tanDegrees(bounded + 10.3 / (bounded + 5.11)) / 60
    }

    /// The angle between the centers of the sun and the moon seen from the center of the Earth, in degrees (Calendrical Calculations' arc of light).
    static func geocentricElongation(at moment: Double) -> Double {
        degrees(acos(cosDegrees(lunarPosition(at: moment).latitude) * cosDegrees(lunarPhase(at: moment))))
    }

    /// The angle in degrees by which the air lifts a body at the horizon, plus the dip of the horizon seen from the elevation of the place.
    static func refraction(_ location: Location) -> Double {
        let height = max(location.elevation, 0)
        return 34.0 / 60 + degrees(acos(earthMeanRadius / (earthMeanRadius + height))) + 19.0 / 3600 * height.squareRoot()
    }

    /// The moment (UT) on the local day `date` when the center of the sun is `depression` degrees below the horizon, or nil if it never is that day (near the poles).
    /// It steps the sun's hour angle until the step is shorter than 0.01 second.
    static func sunDepression(_ depression: Double, on date: Double, _ location: Location, morning: Bool = false) -> Double? {
        var moment = date + (morning ? 0.25 : 0.75) - location.longitude / 360
        for _ in 0..<10 {
            let sun = equatorial(at: moment, latitude: 0, longitude: solarLongitude(at: moment))
            guard let setting = hourAngle(depression: depression, latitude: location.latitude, declination: sun.declination) else { return nil }
            let step = ((morning ? -setting : setting) - (mod360(siderealTime(at: moment) + location.longitude - sun.rightAscension + 180) - 180)) / siderealDegreesPerDay
            moment += step
            if abs(step) < 1e-7 { break }
        }
        return moment
    }

    /// The longitude (east positive) where the sun sets at the standard sunset at `moment`, on `latitude`, or nil if the sun does not set there that day.
    static func sunsetLongitude(at moment: Double, latitude: Double) -> Double? {
        let sun = equatorial(at: moment, latitude: 0, longitude: solarLongitude(at: moment))
        guard let setting = hourAngle(depression: standardSunset, latitude: latitude, declination: sun.declination) else { return nil }
        return mod360(setting - siderealTime(at: moment) + sun.rightAscension + 180) - 180
    }

    // The sun's hour angle in degrees, after noon, when its center is `depression` degrees below the horizon, or nil if it never is.
    private static func hourAngle(depression: Double, latitude: Double, declination: Double) -> Double? {
        let cosine = (sinDegrees(-depression) - sinDegrees(latitude) * sinDegrees(declination)) / (cosDegrees(latitude) * cosDegrees(declination))
        return abs(cosine) <= 1 ? degrees(acos(cosine)) : nil
    }

    /// The moment (UT) of sunset on the local day `date`: the upper limb of the sun at the horizon, after refraction.
    static func sunset(on date: Double, _ location: Location) -> Double? {
        sunDepression(refraction(location) + apparentRadius, on: date, location)
    }

    /// A rule that says, from the evening before a day, whether that day starts a month.
    protocol CrescentRule {
        func isFirstDay(_ day: Int) -> Bool
    }

    /// The number of months between the start found by `firstVisibleDay(onOrBefore:)` and `day`, for the walk of `monthStart(onOrBefore:)`.
    static let walkMonths = 6

    /// A rule for the first evening on which the crescent counts as seen. Each input of a rule that a published text could change is one field, so a correction changes only the value of the rule.
    struct VisibilityRule: CrescentRule {
        /// When the sky is checked on the evening before the first day.
        enum Observation { case sunset, sunDepression(Double) }
        /// The moon's altitude: from the surface (parallax removed) or from the center of the Earth, with or without refraction, to the lower edge, the center or the upper edge of the moon.
        struct Altitude {
            /// The edge of the moon, in steps of 16 minutes of arc from its center.
            enum Edge: Double { case lower = -1, center = 0, upper = 1 }
            /// None, the standard 34 minutes of arc at the horizon with the dip of the horizon (as for sunset), or a value for the moon's altitude.
            enum Refraction { case none, horizon, forAltitude }
            var fromSurface = true
            var refraction = Refraction.none
            var edge = Edge.center
            static let geocentric = Altitude(fromSurface: false), topocentric = Altitude(), observedUpperLimb = Altitude(refraction: .horizon, edge: .upper)
        }
        /// The angle between the sun and the moon: from the center of the Earth, from the surface (the moon's parallax removed), or from the surface between the refracted positions.
        enum Elongation { case geocentric, topocentric, refracted }
        /// Conditions on the moon at the observation. A value of nil is no condition.
        struct Criterion {
            var minimumAltitude: Double?
            var elongation: ClosedRange<Double>?
            /// The hours from the new moon to the observation.
            var minimumMoonAgeHours: Double?
            /// The moon, with the rule's altitude setting, is still at or above the horizon this many minutes after the observation.
            var minimumMinutesAboveHorizon: Double?
            /// The moon was new before the local day of the evening started.
            var isNewBeforeTheDay = false
        }
        var observation = Observation.sunset
        /// When the moon must be new, if not at the observation.
        var newMoonBefore: Observation?
        var altitude = Altitude.topocentric
        var elongationKind = Elongation.geocentric
        /// The evening counts if one of these passes.
        var criteria: [Criterion]
        /// The crescent must be seen at one of these places.
        var places: [Location]
        /// The rules that applied before, sorted by `until`. For a first day before `until`, the first such rule applies.
        var earlier: [(until: Int, rule: VisibilityRule)] = []
        /// Days that the authority published as first days of a month although the rule does not give them.
        var firstDays: Set<Int> = []

        /// Whether the crescent counts as seen on the evening before `day`, the first day of a month.
        /// In every rule, the moon is new before the observation (or `newMoonBefore`) and less than a quarter old.
        func isFirstDay(_ day: Int) -> Bool {
            if firstDays.contains(day) { return true }
            if let rule = earlier.first(where: { day < $0.until })?.rule { return rule.isFirstDay(day) }
            return places.contains { isSeen(beforeDay: day, at: $0) }
        }

        private func isSeen(beforeDay day: Int, at place: Location) -> Bool {
            let evening = Double(day - 1)
            func time(_ observation: Observation) -> Double? {
                switch observation {
                case .sunset: sunset(on: evening, place)
                case .sunDepression(let depression): sunDepression(depression, on: evening, place)
                }
            }
            guard let moment = time(observation), let newMoonMoment = newMoonBefore.map(time) ?? moment else { return false }
            let phase = lunarPhase(at: newMoonMoment)
            guard phase > 0 && phase < 90 else { return false }
            return criteria.contains { criterion in
                if let minimum = criterion.minimumAltitude, lunarAltitude(at: moment, place, altitude) < minimum { return false }
                if let range = criterion.elongation, !range.contains(_CalendarAstronomy.elongation(at: moment, place, elongationKind)) { return false }
                if let minimum = criterion.minimumMoonAgeHours, (moment - lunarPhase(0, atOrBefore: moment)) * 24 < minimum { return false }
                if let minutes = criterion.minimumMinutesAboveHorizon, lunarAltitude(at: moment + minutes / 1440, place, altitude) < 0 { return false }
                if criterion.isNewBeforeTheDay, lunarPhase(0, atOrBefore: moment) >= evening - place.utcOffset { return false }
                return true
            }
        }
    }
}

extension _CalendarAstronomy.CrescentRule {
    /// The first day on or before `day` whose evening before has the crescent, as Calendrical Calculations finds it (`phasis-on-or-before`). Its months can have 28 to 31 days.
    func firstVisibleDay(onOrBefore day: Int) -> Int {
        let newMoon = Int(_CalendarAstronomy.lunarPhase(0, atOrBefore: Double(day)).rounded(.down))
        var start = day - newMoon <= 3 && !isFirstDay(day) ? newMoon - 30 : newMoon
        while !isFirstDay(start) { start += 1 }
        return start
    }

    /// The first day of the month that contains `day`. The authorities test only the evening of the 29th day, so a month has 29 or 30 days. The walk starts `walkMonths` months earlier.
    func monthStart(onOrBefore day: Int) -> Int {
        var start = firstVisibleDay(onOrBefore: day - Int(Double(_CalendarAstronomy.walkMonths) * _CalendarAstronomy.meanSynodicMonth))
        while true {
            let next = start + (isFirstDay(start + 29) ? 29 : 30)
            if next > day { return start }
            start = next
        }
    }
}

// MARK: - The rules of the authorities. "Official" means the authority's own text, "secondary" another source.

extension _CalendarAstronomy.VisibilityRule {
    typealias Location = _CalendarAstronomy.Location
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Int { _CalendarAstronomy.gregorianRataDie(year, month, day) }
    private func with(_ criteria: [Criterion], at places: [Location], earlier: [(until: Int, rule: Self)] = [], firstDays: Set<Int> = []) -> Self {
        var rule = self
        (rule.criteria, rule.places, rule.earlier, rule.firstDays) = (criteria, places, earlier, firstDays)
        return rule
    }

    /// MABIMS 1992: the moon at least 2° high and 3° from the sun, or at least 8 hours old at sunset and above the horizon. MABIMS 2021: at least 3° high and 6.4° from the sun. Both official.
    static let mabims1992 = [Criterion(minimumAltitude: 2, elongation: 3...180), Criterion(minimumAltitude: 0, minimumMoonAgeHours: 8)], mabims2021 = [Criterion(minimumAltitude: 3, elongation: 6.4...180)]

    /// Malaysia (JAKIM): MABIMS 2021 in the takwim from 2022, and MABIMS 1992 before (official).
    /// Judged at Pulau Perak (5°41′05″ N, 98°56′14″ E) from 1 Muharram 1444, before that at Tanjung Chinchin (6°26′10″ N, 99°38′30″ E) (secondary).
    /// JAKIM published two first days that the rule does not give: 1 Syawal 1443 after a sighting in Labuan, and 1 Syaaban 1449, where the elongation is 0.015° below the limit.
    static let malaysia = malaysian.with(mabims2021, at: [Location(latitude: 5.6847, longitude: 98.9372, utcOffsetHours: 8)], earlier: [(day(2022, 1, 1), malaysian.with(mabims1992, at: [tanjungChinchin])), (day(2022, 7, 30), malaysian.with(mabims2021, at: [tanjungChinchin]))], firstDays: [day(2022, 5, 2), day(2027, 12, 29)])
    // Secondary source (eKITAB): the altitude of the center of the moon from the surface, with refraction. The elongation between the refracted positions matches JAKIM's published months.
    private static let malaysian = Self(altitude: Altitude(refraction: .forAltitude), elongationKind: .refracted, criteria: [], places: []), tanjungChinchin = Location(latitude: 6.4361, longitude: 99.6417, utcOffsetHours: 8)

    /// Indonesia (Kemenag): MABIMS 2021 from 1 Ramadan 1443 (official), judged anywhere in the country, in practice the far northwest. Before: altitude 2°, elongation 3° and age 8 hours, all three.
    /// The regulation of 2026 says topocentric altitude, but the official dates match the geocentric altitude (65 of 65 months, topocentric 62).
    static let indonesia = Self(altitude: .geocentric, criteria: mabims2021, places: northwestIndonesia, earlier: [(day(2022, 4, 3), Self(altitude: .geocentric, criteria: [Criterion(minimumAltitude: 2, elongation: 3...180, minimumMoonAgeHours: 8)], places: northwestIndonesia))])
    // Not verified: Sabang and Banda Aceh.
    private static let northwestIndonesia = [Location(latitude: 5.894, longitude: 95.316, utcOffsetHours: 7), Location(latitude: 5.548, longitude: 95.323, utcOffsetHours: 7)]

    /// Singapore (MUIS): MABIMS 2021 from 2022 (official, with no day given, so 1 Muharram 1443 as for Malaysia), judged at Tuas (official).
    /// No definitions are published. The elongation without refraction matches all 33 official months, the Malaysian one only 31.
    static let singapore = singaporean.with(mabims2021, at: tuas, earlier: [(day(2021, 8, 10), singaporean.with(mabims1992, at: tuas))])
    // The definitions of eKITAB, with the elongation between the positions without refraction.
    private static let singaporean = Self(altitude: Altitude(refraction: .forAltitude), elongationKind: .topocentric, criteria: [], places: [])
    private static let tuas = [Location(latitude: 1.2949, longitude: 103.6305, utcOffsetHours: 8)]

    /// Saudi Arabia (the Umm al-Qura calendar, official since AH 1423): at sunset in Mecca the moon is new and sets after the sun.
    /// No definitions are published. These match every month of the table from AH 1423 to 1450.
    /// The new moon comes before the geometric sunset, and the centers of the sun and the moon set with refraction and the dip of the horizon.
    static let ummAlQura = Self(observation: .sunDepression(_CalendarAstronomy.refraction(mecca)), newMoonBefore: .sunDepression(0), altitude: Altitude(refraction: .horizon), criteria: [Criterion(minimumAltitude: 0)], places: [mecca])
    /// The rule of the Umm al-Qura table outside AH 1420 to 1450, found from the table: it matches every month of AH 1451 to 1600, and all but two of AH 1300 to 1419. Only to check the table.
    /// At the geometric sunset in Mecca, the moon was new before the day started, or the moon is more than 5.5 hours old and its center sets more than 19.515 minutes after the sun's center.
    /// Each limit is the middle of the values that match the table: 19.50 to 19.53 minutes and 5.35 to 5.64 hours.
    static let ummAlQuraTable = Self(observation: .sunDepression(0), criteria: [Criterion(minimumMoonAgeHours: 5.5, minimumMinutesAboveHorizon: 19.515), Criterion(isNewBeforeTheDay: true)], places: [mecca])
    // Official: 21°25′21″ N, 39°49′32″ E, 295 meters.
    private static let mecca = Location(latitude: 21.4225, longitude: 39.8256, elevation: 295, utcOffsetHours: 3)
}

// MARK: - Türkiye (Diyanet)

extension _CalendarAstronomy {
    /// Türkiye (Diyanet), found from every month that Diyanet published for AH 1399 to 1457 (1978 to 2035).
    /// At sunset somewhere on Earth, the moon's apparent altitude is at least 5° and its geocentric elongation at least 8° (the Istanbul conference of 1978, official).
    /// A sunset before 00:00 UTC counts in every year. After 00:00 UTC, by the year of the first day: in 2009 to 2013 a sunset at the date line north of 10° N.
    /// From 2017, a sunset on the American mainland if the moon was new before dawn in Wellington (the Istanbul congress of 2016, official).
    struct Diyanet: CrescentRule {
        /// The first days that the rule gives one day early. Diyanet published these months one day later, and no rule gives them.
        /// They are 1 Ramazan 1399, 1 Şaban 1401, 1 Cemaziyelevvel 1411, 1 Zilkade 1444 and 1 Zilhicce 1453.
        static let corrections = Set([(1979, 7, 25), (1981, 6, 3), (1990, 11, 18), (2023, 5, 20), (2032, 3, 12)].map { gregorianRataDie($0.0, $0.1, $0.2) })
        private static let from2009 = gregorianRataDie(2009, 1, 1), from2014 = gregorianRataDie(2014, 1, 1), from2017 = gregorianRataDie(2017, 1, 1)
        private static let wellington = Location(latitude: -41.2865, longitude: 174.7762, utcOffsetHours: 12)
        private static let dateLine = (40...352).map { Location(latitude: Double($0) / 4, longitude: -179.999) }

        func isFirstDay(_ day: Int) -> Bool {
            !Self.corrections.contains(day) && isFirstDayByRule(day)
        }

        /// Whether the rule alone, without `corrections`, makes `day` the first day of a month.
        func isFirstDayByRule(_ day: Int) -> Bool {
            let midnight = Double(day), conjunction = lunarPhase(0, atOrBefore: midnight + 0.5)
            guard midnight + 0.5 - conjunction < 3 else { return false }
            func isSeen(at moment: Double, _ place: Location) -> Bool {
                moment > conjunction && moment - conjunction < 3 && lunarAltitude(at: moment, place, .init(refraction: .forAltitude)) >= 5
            }
            // Before 00:00 UTC, the latest sunset on each latitude is the best one: where the sun sets at 00:00 UTC.
            if geocentricElongation(at: midnight) >= 8, (-880...880).contains(where: { tenths in
                let latitude = Double(tenths) / 10
                return sunsetLongitude(at: midnight, latitude: latitude).map { isSeen(at: midnight, Location(latitude: latitude, longitude: $0)) } ?? false
            }) { return true }
            let places: [Location]
            switch day {
            case ..<Self.from2009, Self.from2014..<Self.from2017: return false
            case ..<Self.from2014: places = Self.dateLine
            default:
                let newMoon = lunarPhase(0, atOrBefore: midnight)
                guard let dawn = sunDepression(18, on: midnight, Self.wellington, morning: true), newMoon < dawn, dawn - newMoon < 2 else { return false }
                places = Self.mainlandAmericas
            }
            guard geocentricElongation(at: midnight + 0.5) >= 8 else { return false }
            return places.contains { place in
                guard let sunset = sunDepression(standardSunset, on: midnight - 1, place), sunset >= midnight, geocentricElongation(at: sunset) >= 8 else { return false }
                return isSeen(at: sunset, place)
            }
        }

        // The westernmost point of the American mainland every 0.05° of latitude from 71.95° N to 53.85° S (Natural Earth 1:10m land, version 5.1.2, public domain). Islands do not count.
        private static let mainlandAmericas = [
            -95.219, -95.254, -95.198, -95.252, -95.287, -95.560, -95.685, -95.906, -95.935, -95.658, -95.523, -156.506, -156.690, -156.830, -156.931, -157.030, -157.096, -157.182, -157.290, -157.426,
            -157.574, -157.751, -159.376, -159.678, -159.768, -159.915, -160.074, -160.182, -160.292, -160.422, -160.620, -160.785, -160.853, -161.965, -162.046, -162.133, -162.256, -162.346, -162.490, -162.491,
            -162.562, -162.680, -162.800, -162.926, -163.011, -162.947, -163.059, -163.149, -163.070, -163.090, -163.122, -163.207, -163.246, -163.305, -163.393, -163.481, -163.569, -163.676, -163.816, -163.981,
            -164.217, -164.901, -166.228, -166.198, -166.200, -166.205, -166.224, -166.239, -166.262, -166.303, -166.357, -166.634, -166.819, -166.299, -166.149, -166.037, -165.957, -165.700, -165.404, -165.240,
            -165.101, -164.976, -164.857, -164.647, -164.530, -164.414, -164.251, -164.115, -164.029, -163.963, -163.915, -163.867, -163.821, -163.797, -163.781, -163.774, -163.768, -163.643, -163.120, -162.464,
            -162.501, -162.638, -162.613, -162.536, -162.505, -162.196, -162.117, -164.303, -164.722, -164.832, -164.954, -165.496, -165.673, -165.816, -165.883, -165.669, -166.396, -166.599, -166.746, -166.882,
            -166.888, -167.334, -167.470, -167.569, -167.916, -168.086, -168.132, -168.093, -167.900, -167.709, -167.591, -167.369, -166.855, -166.219, -166.922, -166.948, -166.954, -166.872, -166.725, -166.698,
            -166.570, -166.449, -166.409, -166.480, -166.475, -166.454, -166.387, -166.240, -165.887, -165.369, -165.046, -162.817, -162.806, -161.083, -160.973, -160.951, -160.948, -160.946, -160.929, -160.887,
            -160.844, -160.803, -160.779, -160.775, -160.791, -160.847, -160.934, -161.039, -162.295, -162.276, -162.359, -162.434, -162.500, -162.566, -164.227, -164.439, -164.553, -164.537, -164.340, -164.741,
            -164.794, -164.833, -164.867, -164.767, -164.867, -164.841, -164.826, -164.751, -164.806, -165.154, -165.246, -165.317, -165.371, -165.451, -165.510, -165.569, -165.665, -165.710, -165.746, -165.756,
            -165.727, -165.658, -165.663, -166.088, -166.030, -166.169, -166.185, -166.197, -166.166, -166.109, -165.801, -165.921, -165.886, -165.686, -165.640, -165.623, -165.625, -165.562, -164.952, -165.149,
            -165.177, -164.948, -164.876, -164.976, -165.002, -165.018, -165.148, -165.268, -165.427, -165.233, -165.143, -165.092, -165.011, -164.792, -164.645, -164.530, -164.488, -164.422, -164.273, -164.122,
            -164.211, -164.193, -164.139, -163.880, -161.938, -161.884, -161.866, -161.827, -161.770, -161.715, -161.831, -161.901, -161.969, -162.023, -162.044, -162.013, -161.984, -161.941, -161.702, -161.829,
            -161.792, -161.791, -161.771, -161.764, -161.800, -161.859, -162.161, -161.770, -159.178, -159.127, -159.034, -158.949, -157.564, -157.546, -157.518, -157.398, -157.568, -157.607, -157.614, -157.625,
            -157.633, -157.639, -157.655, -157.677, -157.702, -157.705, -157.709, -157.600, -157.799, -157.930, -157.993, -158.073, -158.214, -158.333, -158.402, -158.471, -158.540, -158.609, -158.660, -158.690,
            -158.691, -158.689, -158.978, -159.064, -159.202, -159.219, -159.395, -159.666, -159.823, -159.911, -160.008, -160.150, -160.226, -160.320, -160.389, -160.425, -160.461, -160.474, -160.527, -161.239,
            -161.472, -161.729, -161.883, -161.987, -162.110, -162.220, -162.292, -162.359, -162.427, -162.494, -162.568, -162.494, -162.671, -162.792, -162.890, -163.112, -163.243, -163.320, -163.298, -163.287,
            -163.341, -163.325, -163.381, -130.913, -130.196, -130.316, -130.367, -130.414, -130.440, -130.433, -130.452, -130.480, -130.460, -130.241, -130.261, -130.215, -130.053, -130.085, -130.089, -130.084,
            -130.102, -130.056, -129.990, -129.915, -129.799, -129.724, -129.700, -129.646, -129.560, -129.487, -129.413, -129.339, -128.871, -128.870, -128.789, -128.703, -128.575, -128.500, -128.523, -128.514,
            -128.504, -128.498, -128.450, -128.278, -128.127, -128.155, -128.192, -128.224, -128.240, -128.232, -128.233, -128.307, -128.339, -128.388, -127.886, -127.395, -127.523, -127.622, -127.649, -127.658,
            -127.778, -127.863, -127.881, -127.885, -127.874, -127.878, -127.842, -127.827, -127.792, -127.753, -127.612, -127.662, -127.790, -127.573, -127.754, -127.794, -127.738, -127.667, -127.516, -127.523,
            -127.441, -127.249, -127.102, -126.196, -126.122, -126.219, -126.106, -126.250, -126.186, -126.232, -125.726, -125.064, -125.089, -124.653, -124.608, -124.621, -124.656, -124.699, -124.827, -124.785,
            -124.723, -124.631, -124.540, -124.516, -124.295, -124.040, -124.067, -124.025, -123.993, -123.914, -123.735, -123.585, -123.276, -123.162, -123.236, -123.201, -123.200, -123.085, -123.131, -123.092,
            -122.813, -122.766, -122.734, -122.703, -122.664, -122.523, -122.496, -122.444, -122.509, -122.669, -122.666, -122.553, -124.707, -124.674, -124.703, -124.696, -124.723, -124.689, -124.688, -124.675,
            -124.655, -124.631, -124.553, -124.481, -124.446, -124.412, -124.391, -124.372, -124.352, -124.349, -124.338, -124.327, -124.281, -124.252, -124.222, -124.204, -124.190, -124.178, -124.173, -124.172,
            -124.176, -124.125, -124.115, -124.101, -124.096, -123.821, -124.067, -124.064, -124.062, -124.061, -124.061, -124.062, -124.065, -124.076, -123.920, -123.990, -123.966, -123.943, -123.931, -123.927,
            -123.978, -123.961, -123.958, -123.965, -123.968, -123.938, -123.940, -123.950, -123.953, -123.968, -123.969, -123.965, -123.981, -123.960, -123.969, -123.969, -123.972, -123.989, -124.011, -124.011,
            -124.022, -124.032, -124.049, -124.068, -124.061, -124.065, -124.060, -124.065, -124.075, -124.084, -124.082, -124.086, -124.096, -124.113, -124.114, -124.114, -124.119, -124.126, -124.133, -124.123,
            -124.144, -124.149, -124.158, -124.168, -124.180, -124.197, -124.211, -124.221, -124.237, -124.260, -124.283, -124.311, -124.346, -124.395, -124.390, -124.403, -124.416, -124.429, -124.439, -124.460,
            -124.483, -124.512, -124.545, -124.531, -124.515, -124.465, -124.410, -124.403, -124.399, -124.416, -124.428, -124.427, -124.430, -124.412, -124.412, -124.377, -124.366, -124.352, -124.296, -124.215,
            -124.204, -124.210, -124.219, -124.243, -124.216, -124.144, -124.132, -124.103, -124.090, -124.078, -124.066, -124.068, -124.080, -124.089, -124.104, -124.119, -124.141, -124.161, -124.138, -124.115,
            -124.130, -124.151, -124.175, -124.208, -124.244, -124.274, -124.309, -124.334, -124.364, -124.384, -124.405, -124.385, -124.365, -124.354, -124.351, -124.281, -124.205, -124.109, -124.081, -124.021,
            -123.971, -123.926, -123.888, -123.842, -123.833, -123.801, -123.787, -123.787, -123.770, -123.793, -123.814, -123.821, -123.825, -123.800, -123.785, -123.770, -123.737, -123.710, -123.693, -123.700,
            -123.739, -123.697, -123.649, -123.579, -123.525, -123.449, -123.405, -123.364, -123.306, -123.225, -123.130, -123.097, -123.069, -123.064, -122.969, -122.966, -122.950, -122.969, -122.990, -123.022,
            -122.781, -122.713, -122.566, -122.481, -122.513, -122.501, -122.495, -122.505, -122.517, -122.501, -122.446, -122.425, -122.401, -122.407, -122.418, -122.405, -122.359, -122.285, -122.241, -122.184,
            -122.070, -121.843, -121.813, -121.792, -121.802, -121.812, -121.830, -121.964, -121.932, -121.943, -121.929, -121.912, -121.900, -121.883, -121.836, -121.733, -121.665, -121.625, -121.592, -121.504,
            -121.483, -121.463, -121.411, -121.355, -121.321, -121.301, -121.226, -121.130, -121.102, -121.049, -120.952, -120.870, -120.864, -120.881, -120.898, -120.843, -120.658, -120.635, -120.633, -120.643,
            -120.660, -120.668, -120.617, -120.625, -120.633, -120.604, -120.619, -120.642, -120.572, -120.497, -120.472, -119.738, -119.426, -119.346, -119.268, -119.250, -119.219, -119.127, -118.958, -118.808,
            -118.445, -118.422, -118.399, -118.405, -118.414, -118.054, -117.995, -117.904, -117.807, -117.749, -117.667, -117.607, -117.532, -117.478, -117.435, -117.391, -117.351, -117.319, -117.303, -117.277,
            -117.266, -117.256, -117.275, -117.266, -117.255, -117.257, -117.152, -117.135, -117.128, -117.124, -117.115, -117.087, -117.063, -117.037, -116.954, -116.914, -116.894, -116.883, -116.877, -116.854,
            -116.757, -116.716, -116.616, -116.613, -116.749, -116.672, -116.651, -116.663, -116.671, -116.608, -116.547, -116.493, -116.461, -116.418, -116.370, -116.333, -116.310, -116.317, -116.323, -116.336,
            -116.245, -116.208, -116.143, -116.058, -116.043, -116.035, -116.032, -116.034, -116.041, -116.047, -116.034, -116.015, -115.842, -115.816, -115.800, -115.797, -115.804, -115.785, -115.789, -115.802,
            -115.751, -115.702, -115.690, -115.689, -115.690, -115.628, -115.546, -115.429, -115.349, -115.246, -115.203, -115.043, -114.944, -114.892, -114.844, -114.792, -114.734, -114.708, -114.611, -114.604,
            -114.548, -114.447, -114.405, -114.365, -114.347, -114.287, -114.168, -114.155, -114.095, -114.070, -114.045, -114.062, -114.079, -114.103, -114.117, -114.064, -114.095, -114.102, -114.165, -114.207,
            -114.256, -114.276, -115.083, -115.047, -115.028, -114.939, -114.847, -114.781, -114.750, -114.661, -114.574, -114.504, -114.489, -114.486, -114.487, -114.430, -114.327, -114.109, -114.063, -114.030,
            -113.818, -113.779, -113.749, -113.725, -113.653, -113.096, -113.057, -113.061, -113.004, -112.917, -112.847, -112.778, -112.712, -112.606, -112.522, -112.362, -112.330, -112.313, -112.293, -112.204,
            -112.177, -112.162, -112.138, -112.120, -112.105, -112.102, -112.101, -112.100, -112.103, -112.063, -112.079, -112.084, -112.075, -112.076, -112.082, -112.117, -112.137, -112.138, -112.126, -112.136,
            -112.165, -112.159, -112.101, -112.097, -112.021, -111.895, -111.847, -111.826, -111.818, -111.627, -111.602, -111.517, -111.471, -111.395, -111.295, -111.202, -111.113, -111.035, -110.978, -110.917,
            -110.867, -110.808, -110.763, -110.714, -110.664, -110.602, -110.504, -110.389, -110.318, -110.284, -110.249, -110.222, -110.192, -110.162, -110.155, -110.144, -110.129, -110.115, -110.107, -110.086,
            -110.059, -110.007, -106.049, -105.974, -105.912, -105.867, -105.813, -105.773, -105.760, -105.731, -105.714, -105.699, -105.683, -105.668, -105.654, -105.649, -105.650, -105.654, -105.657, -105.650,
            -105.629, -105.596, -105.562, -105.533, -105.506, -105.478, -105.455, -105.412, -105.327, -105.204, -105.186, -105.224, -105.241, -105.231, -105.222, -105.219, -105.232, -105.231, -105.244, -105.327,
            -105.376, -105.419, -105.462, -105.485, -105.459, -105.298, -105.248, -105.238, -105.287, -105.439, -105.639, -105.696, -105.674, -105.629, -105.596, -105.553, -105.547, -105.545, -105.531, -105.502,
            -105.466, -105.437, -105.388, -105.349, -105.318, -105.281, -105.232, -105.168, -105.087, -105.081, -105.070, -105.025, -105.001, -104.922, -104.805, -104.690, -104.594, -104.449, -104.329, -104.266,
            -104.136, -104.032, -103.954, -103.881, -103.807, -103.752, -103.698, -103.710, -103.632, -103.582, -103.556, -103.534, -103.508, -103.418, -103.293, -103.120, -102.939, -102.824, -102.609, -102.426,
            -102.265, -101.834, -101.775, -101.749, -101.687, -101.647, -101.599, -101.479, -101.442, -101.380, -101.252, -101.177, -101.105, -101.055, -100.999, -100.838, -100.706, -100.549, -100.401, -100.259,
            -100.120, -99.973, -99.924, -99.837, -99.767, -99.669, -99.297, -99.108, -98.946, -98.725, -98.685, -98.628, -98.574, -98.507, -98.297, -98.163, -98.057, -97.966, -97.891, -97.807,
            -97.474, -97.154, -97.056, -96.991, -96.875, -96.659, -93.409, -93.348, -93.287, -93.224, -93.171, -93.125, -93.079, -93.007, -92.954, -92.875, -92.834, -92.792, -92.746, -92.701,
            -92.651, -92.601, -92.551, -92.501, -92.449, -92.398, -92.344, -92.293, -92.250, -92.180, -92.109, -92.040, -91.984, -91.927, -91.861, -91.790, -91.713, -91.629, -91.535, -91.419,
            -91.287, -90.523, -90.382, -90.267, -90.144, -90.031, -89.926, -89.841, -89.827, -89.551, -89.200, -89.112, -89.016, -88.906, -88.796, -88.536, -87.422, -87.310, -87.588, -87.646,
            -87.684, -87.675, -87.608, -87.525, -87.458, -87.416, -87.372, -87.309, -87.238, -87.193, -87.168, -87.082, -87.009, -86.933, -86.850, -86.776, -86.751, -86.732, -86.705, -86.670,
            -86.625, -86.602, -86.552, -86.523, -86.484, -86.417, -86.370, -86.310, -86.222, -86.169, -86.110, -86.048, -86.002, -85.918, -85.873, -85.828, -85.799, -85.748, -85.669, -85.713,
            -85.714, -85.941, -85.795, -85.689, -85.663, -85.661, -85.681, -85.652, -85.723, -85.801, -85.777, -85.836, -85.867, -85.846, -85.846, -85.831, -85.811, -85.787, -85.754, -85.713,
            -85.674, -85.629, -85.399, -85.292, -85.253, -85.211, -85.174, -85.140, -84.574, -84.364, -84.191, -84.177, -84.034, -83.930, -83.871, -83.788, -83.759, -83.690, -83.640, -83.616,
            -83.621, -83.606, -83.585, -83.637, -83.642, -83.654, -83.723, -83.737, -83.678, -83.624, -83.581, -83.372, -83.131, -83.067, -82.998, -82.956, -82.927, -82.899, -82.911, -81.665,
            -81.639, -81.621, -81.567, -81.586, -81.554, -81.481, -81.289, -80.972, -80.947, -80.960, -80.913, -80.921, -80.892, -80.917, -80.906, -77.854, -77.789, -77.741, -77.698, -77.660,
            -77.686, -77.700, -77.696, -77.573, -77.549, -77.537, -77.414, -77.376, -77.344, -77.361, -77.378, -77.385, -77.378, -77.477, -77.479, -77.484, -77.464, -77.423, -77.388, -77.367,
            -77.325, -77.313, -77.279, -77.252, -77.244, -77.262, -77.318, -77.456, -77.517, -77.557, -77.403, -77.408, -77.379, -77.360, -77.355, -77.363, -77.373, -77.371, -77.369, -77.367,
            -77.358, -77.353, -77.348, -77.315, -77.325, -77.300, -77.319, -77.319, -77.320, -77.330, -77.342, -77.354, -77.385, -77.359, -77.248, -77.376, -77.435, -77.432, -77.412, -77.419,
            -77.380, -77.296, -77.271, -77.151, -77.198, -77.147, -77.193, -77.223, -77.311, -77.329, -77.343, -77.367, -77.463, -77.469, -77.539, -77.529, -77.565, -77.617, -77.668, -77.707,
            -77.631, -77.715, -77.695, -77.783, -77.812, -77.798, -78.261, -78.406, -78.458, -78.499, -78.541, -78.587, -78.613, -78.639, -78.677, -78.698, -78.701, -78.689, -78.678, -78.667,
            -78.594, -78.593, -78.549, -78.871, -78.918, -78.952, -79.018, -78.985, -78.904, -78.855, -78.816, -78.827, -78.864, -78.862, -78.892, -79.079, -79.117, -79.165, -79.481, -79.661,
            -79.771, -79.820, -79.952, -80.085, -80.105, -80.108, -80.085, -80.030, -80.018, -80.043, -80.040, -80.013, -80.039, -80.048, -80.046, -80.038, -80.040, -80.049, -80.073, -80.114,
            -80.153, -80.195, -80.246, -80.340, -80.384, -80.407, -80.446, -80.491, -80.464, -80.450, -80.438, -80.423, -80.476, -80.500, -80.517, -80.528, -80.538, -80.558, -80.826, -80.865,
            -80.911, -80.901, -80.880, -80.851, -80.818, -80.776, -80.744, -80.763, -80.767, -80.820, -80.817, -80.854, -80.829, -80.807, -80.778, -80.760, -80.747, -80.734, -80.733, -80.755,
            -80.738, -80.745, -80.795, -80.994, -80.942, -80.923, -80.841, -80.700, -80.620, -80.568, -80.526, -80.483, -80.395, -80.333, -79.805, -79.831, -79.848, -79.863, -79.876, -79.878,
            -79.899, -79.926, -79.938, -79.955, -80.086, -80.112, -80.322, -80.341, -80.362, -80.517, -80.559, -80.597, -80.671, -80.755, -80.816, -80.848, -80.862, -80.906, -80.972, -81.011,
            -81.045, -81.087, -81.139, -81.196, -81.262, -81.290, -81.285, -81.281, -81.311, -81.321, -81.308, -81.316, -81.312, -81.320, -81.276, -81.230, -81.191, -81.161, -81.109, -81.073,
            -81.067, -81.169, -81.172, -81.194, -81.168, -81.132, -81.045, -80.993, -80.944, -80.915, -80.892, -80.873, -80.856, -80.860, -80.867, -81.085, -81.125, -81.149, -81.150, -81.143,
            -81.119, -81.065, -80.995, -80.911, -80.842, -80.790, -80.686, -80.586, -80.486, -80.386, -80.288, -80.202, -80.120, -80.056, -79.996, -79.959, -79.946, -79.912, -79.866, -79.815,
            -79.765, -79.715, -79.690, -79.676, -79.628, -79.600, -79.588, -79.578, -79.584, -79.552, -79.516, -79.480, -79.449, -79.444, -79.433, -79.394, -79.373, -79.334, -79.285, -79.218,
            -79.147, -79.112, -79.054, -79.001, -78.977, -78.955, -78.920, -78.902, -78.928, -78.850, -78.803, -78.765, -78.749, -78.743, -78.756, -78.745, -78.708, -78.672, -78.651, -78.650,
            -78.641, -78.571, -78.560, -78.589, -78.496, -78.507, -78.432, -78.430, -78.386, -78.400, -78.381, -78.372, -78.344, -78.307, -78.276, -78.230, -78.241, -78.230, -78.235, -78.198,
            -78.177, -78.179, -78.157, -78.106, -78.092, -78.061, -78.052, -78.010, -77.982, -77.961, -77.912, -77.892, -77.862, -77.820, -77.776, -77.752, -77.712, -77.689, -77.663, -77.651,
            -77.637, -77.627, -77.604, -77.596, -77.649, -77.638, -77.556, -77.460, -77.378, -77.316, -77.282, -77.267, -77.209, -77.191, -77.168, -77.182, -77.179, -77.157, -77.144, -77.141,
            -77.164, -77.074, -77.040, -77.041, -76.949, -76.858, -76.827, -76.787, -76.790, -76.803, -76.740, -76.699, -76.682, -76.656, -76.630, -76.581, -76.528, -76.513, -76.516, -76.499,
            -76.471, -76.429, -76.389, -76.351, -76.312, -76.265, -76.227, -76.206, -76.191, -76.185, -76.183, -76.194, -76.208, -76.223, -76.229, -76.337, -76.384, -76.394, -76.275, -76.282,
            -76.268, -76.284, -76.285, -76.272, -76.134, -76.110, -76.136, -76.062, -76.003, -75.968, -75.952, -75.931, -75.930, -75.857, -75.793, -75.712, -75.624, -75.531, -75.504, -75.454,
            -75.425, -75.392, -75.324, -75.247, -75.241, -75.186, -75.169, -75.142, -75.064, -74.944, -74.860, -74.763, -74.662, -74.544, -74.457, -74.439, -74.262, -74.166, -74.069, -74.033,
            -73.986, -73.914, -73.835, -73.724, -73.569, -73.406, -73.314, -73.255, -73.115, -73.046, -72.902, -72.823, -72.723, -72.471, -72.379, -72.328, -72.298, -72.248, -72.165, -72.123,
            -71.990, -71.921, -71.877, -71.772, -71.614, -71.496, -71.454, -71.401, -71.390, -71.377, -71.372, -71.367, -71.363, -71.316, -71.223, -71.169, -71.107, -70.989, -70.913, -70.894,
            -70.811, -70.743, -70.696, -70.609, -70.522, -70.447, -70.382, -70.337, -70.304, -70.323, -70.335, -70.337, -70.343, -70.342, -70.349, -70.353, -70.341, -70.327, -70.318, -70.313,
            -70.301, -70.281, -70.279, -70.277, -70.281, -70.288, -70.256, -70.230, -70.220, -70.206, -70.203, -70.241, -70.177, -70.159, -70.151, -70.159, -70.137, -70.142, -70.134, -70.123,
            -70.135, -70.132, -70.150, -70.163, -70.142, -70.141, -70.180, -70.177, -70.167, -70.184, -70.203, -70.198, -70.194, -70.204, -70.205, -70.195, -70.160, -70.137, -70.135, -70.169,
            -70.158, -70.125, -70.115, -70.095, -70.087, -70.071, -70.094, -70.077, -70.062, -70.079, -70.088, -70.100, -70.148, -70.150, -70.150, -70.148, -70.149, -70.183, -70.177, -70.192,
            -70.188, -70.211, -70.225, -70.226, -70.231, -70.237, -70.248, -70.248, -70.254, -70.245, -70.275, -70.269, -70.283, -70.283, -70.303, -70.311, -70.293, -70.291, -70.324, -70.337,
            -70.553, -70.578, -70.571, -70.568, -70.600, -70.597, -70.602, -70.600, -70.615, -70.629, -70.405, -70.393, -70.405, -70.431, -70.478, -70.497, -70.505, -70.502, -70.514, -70.525,
            -70.506, -70.501, -70.513, -70.519, -70.532, -70.534, -70.542, -70.546, -70.554, -70.568, -70.575, -70.556, -70.575, -70.576, -70.564, -70.556, -70.542, -70.527, -70.494, -70.469,
            -70.492, -70.499, -70.451, -70.437, -70.436, -70.448, -70.447, -70.520, -70.530, -70.600, -70.650, -70.636, -70.658, -70.693, -70.694, -70.732, -70.705, -70.683, -70.646, -70.632,
            -70.643, -70.658, -70.666, -70.665, -70.652, -70.680, -70.646, -70.698, -70.686, -70.706, -70.693, -70.711, -70.724, -70.753, -70.734, -70.792, -70.815, -70.816, -70.800, -70.792,
            -70.849, -70.871, -70.955, -70.952, -70.953, -70.933, -70.945, -70.927, -70.902, -70.894, -70.919, -70.915, -70.948, -71.043, -71.061, -71.082, -71.103, -71.123, -71.138, -71.143,
            -71.148, -71.170, -71.157, -71.160, -71.170, -71.186, -71.173, -71.187, -71.214, -71.267, -71.285, -71.294, -71.296, -71.328, -71.371, -71.392, -71.490, -71.513, -71.520, -71.498,
            -71.492, -71.482, -71.495, -71.492, -71.433, -71.358, -71.342, -71.316, -71.315, -71.332, -71.330, -71.292, -71.319, -71.323, -71.332, -71.319, -71.282, -71.285, -71.360, -71.407,
            -71.382, -71.377, -71.383, -71.469, -71.639, -71.659, -71.677, -71.682, -71.686, -71.702, -71.697, -71.711, -71.709, -71.703, -71.704, -71.701, -71.688, -71.680, -71.662, -71.653,
            -71.652, -71.659, -71.668, -71.648, -71.639, -71.630, -71.621, -71.612, -71.592, -71.576, -71.570, -71.567, -71.551, -71.537, -71.522, -71.519, -71.527, -71.514, -71.521, -71.512,
            -71.521, -71.527, -71.540, -71.543, -71.499, -71.471, -71.436, -71.418, -71.437, -71.457, -71.468, -71.449, -71.447, -71.467, -71.496, -71.546, -71.527, -71.523, -71.555, -71.568,
            -71.674, -71.760, -71.728, -71.715, -71.706, -71.677, -71.671, -71.707, -71.691, -71.641, -71.631, -71.646, -71.653, -71.673, -71.735, -71.823, -71.842, -71.857, -71.883, -71.905,
            -71.949, -71.980, -72.022, -72.004, -71.990, -71.988, -71.989, -72.043, -72.053, -72.043, -72.050, -72.055, -72.057, -72.075, -72.098, -72.136, -72.160, -72.191, -72.197, -72.200,
            -72.206, -72.223, -72.262, -72.349, -72.411, -72.425, -72.459, -72.491, -72.506, -72.541, -72.627, -72.650, -72.624, -72.597, -72.585, -72.594, -72.667, -72.708, -72.777, -72.795,
            -72.797, -72.824, -72.812, -72.837, -72.827, -72.830, -72.855, -72.876, -72.902, -72.921, -72.988, -73.119, -73.133, -73.147, -73.184, -73.159, -73.147, -73.152, -73.157, -73.179,
            -73.172, -73.183, -73.205, -73.644, -73.646, -73.659, -73.679, -73.627, -73.599, -73.600, -73.653, -73.685, -73.671, -73.667, -73.634, -73.592, -73.555, -73.524, -73.496, -73.476,
            -73.463, -73.464, -73.472, -73.479, -73.515, -73.510, -73.528, -73.542, -73.534, -73.523, -73.511, -73.494, -73.476, -73.458, -73.449, -73.397, -73.382, -73.366, -73.344, -73.320,
            -73.296, -73.277, -73.263, -73.249, -73.235, -73.229, -73.223, -73.236, -73.250, -73.257, -73.288, -73.312, -73.354, -73.403, -73.381, -73.401, -73.475, -73.555, -73.690, -73.700,
            -73.668, -73.661, -73.709, -73.724, -73.746, -73.755, -73.763, -73.765, -73.767, -73.748, -73.733, -73.758, -73.826, -73.814, -73.853, -73.871, -73.888, -73.859, -73.905, -73.940,
            -73.941, -73.928, -73.919, -73.888, -73.866, -73.850, -73.842, -73.845, -73.846, -73.812, -73.809, -73.550, -73.695, -73.712, -73.755, -73.523, -72.814, -72.855, -72.841, -72.769,
            -72.483, -72.490, -72.432, -72.653, -72.816, -72.838, -72.779, -72.716, -72.703, -72.812, -72.854, -72.866, -72.833, -72.864, -72.865, -72.852, -72.829, -72.754, -72.749, -72.757,
            -72.888, -72.934, -72.921, -72.907, -72.962, -73.074, -73.085, -73.090, -73.112, -73.078, -73.051, -72.910, -72.982, -73.046, -72.985, -73.019, -73.049, -73.063, -73.118, -73.139,
            -73.132, -73.221, -73.290, -73.131, -73.181, -72.958, -72.931, -72.855, -72.749, -72.725, -72.680, -72.692, -72.715, -72.725, -72.725, -72.852, -72.919, -73.046, -73.193, -73.403,
            -73.394, -73.338, -73.312, -73.450, -73.462, -73.152, -73.328, -73.400, -73.509, -73.524, -73.537, -73.551, -73.569, -73.573, -73.581, -74.391, -74.694, -74.713, -74.728, -74.730,
            -74.784, -74.815, -74.909, -74.939, -75.116, -75.200, -75.214, -75.353, -75.398, -75.446, -75.520, -75.659, -75.707, -75.710, -75.711, -75.690, -75.653, -75.592, -74.169, -73.979,
            -73.949, -73.999, -74.050, -74.126, -74.341, -74.384, -74.435, -74.494, -74.518, -74.440, -74.556, -74.624, -74.675, -74.732, -74.672, -74.045, -73.614, -73.654, -73.646, -74.614,
            -74.629, -74.504, -74.466, -74.394, -74.299, -74.263, -74.238, -74.045, -74.028, -74.250, -74.329, -74.393, -74.371, -74.317, -74.393, -74.443, -74.447, -74.431, -74.416, -74.413,
            -74.467, -74.408, -74.406, -74.406, -74.407, -74.397, -74.407, -74.411, -74.326, -74.281, -74.130, -74.294, -74.324, -74.321, -74.202, -74.349, -74.334, -74.183, -74.364, -74.358,
            -74.310, -74.576, -74.668, -74.687, -74.547, -74.533, -74.459, -74.317, -74.095, -74.272, -74.211, -74.232, -74.198, -74.161, -74.099, -74.081, -73.851, -74.220, -74.233, -74.239,
            -74.146, -74.134, -74.135, -74.090, -73.751, -73.720, -73.721, -73.934, -73.924, -73.920, -73.830, -73.901, -73.735, -73.791, -73.746, -73.529, -73.645, -73.606, -73.599, -73.579,
            -73.741, -73.715, -73.671, -73.602, -73.594, -73.601, -73.584, -73.665, -73.531, -73.582, -73.553, -73.687, -73.582, -73.693, -73.307, -73.559, -73.379, -73.290, -73.323, -73.450,
            -73.359, -73.219, -72.845, -73.239, -73.183, -73.051, -72.949, -72.804, -72.732, -72.632, -72.299, -72.229, -72.157, -72.063, -71.831, -71.713, -71.411
        ].enumerated().map { Location(latitude: 71.95 - 0.05 * Double($0.offset), longitude: $0.element) }
    }
}
