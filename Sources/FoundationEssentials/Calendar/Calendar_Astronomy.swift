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
