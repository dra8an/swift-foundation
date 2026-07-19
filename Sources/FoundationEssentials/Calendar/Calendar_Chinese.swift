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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Chinese lunisolar calendar engine.
// Years 1901-2100 come from a baked table generated from ICU (parity by
// construction). Outside that range, month structure is computed with ICU's
// chnsecal rules over Reingold/Dershowitz (Meeus) astronomy at UTC+8.

// MARK: - Astronomy (Reingold & Dershowitz, via ICU4X calendrical_calculations)

internal enum _ChineseAstro {
    static let meanSynodicMonth = 29.530588861
    static let meanTropicalYear = 365.242189
    static let j2000 = 730120.5
    static let newMoonZero = 11.458922815770109

    static func poly(_ x: Double, _ coefficients: [Double]) -> Double {
        var result = 0.0
        var power = 1.0
        for c in coefficients {
            result += c * power
            power *= x
        }
        return result
    }

    static func mod360(_ x: Double) -> Double {
        var r = x.truncatingRemainder(dividingBy: 360.0)
        if r < 0 { r += 360.0 }
        return r
    }

    static func sinDeg(_ d: Double) -> Double { sin(d * .pi / 180.0) }
    static func cosDeg(_ d: Double) -> Double { cos(d * .pi / 180.0) }

    // Proleptic Gregorian y/m/d -> Rata Die (day 1 = 0001-01-01).
    static func gregorianRD(_ y: Int, _ m: Int, _ d: Int) -> Int {
        func fd(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
        let ym1 = y - 1
        let leap = (fd(y, 4) * 4 == y && fd(y, 100) * 100 != y) || fd(y, 400) * 400 == y
        var r = 365 * ym1 + fd(ym1, 4) - fd(ym1, 100) + fd(ym1, 400)
        r += fd(367 * m - 362, 12) + (m <= 2 ? 0 : (leap ? -1 : -2)) + d
        return r
    }

    static func gregorianYear(ofRD day: Int) -> Int {
        var y = Int((Double(day) / 365.2425).rounded(.down)) + 1
        while gregorianRD(y, 1, 1) > day { y -= 1 }
        while gregorianRD(y + 1, 1, 1) <= day { y += 1 }
        return y
    }

    // Dynamical-minus-universal time (fraction of a day). Meeus/NASA fits.
    static func ephemerisCorrection(_ moment: Double) -> Double {
        let year = moment / 365.2425
        let yearInt = Int(year > 0 ? year + 1 : year)
        let fixedMidYear = gregorianRD(yearInt, 7, 1)
        let c = (Double(fixedMidYear) - 693596.0) / 36525.0
        let y2000 = Double(yearInt - 2000)
        let y1700 = Double(yearInt - 1700)
        let y1600 = Double(yearInt - 1600)
        let y1000 = Double(yearInt - 1000) / 100.0
        let y0 = Double(yearInt) / 100.0
        let y1820 = Double(yearInt - 1820) / 100.0

        if (2051...2150).contains(yearInt) {
            return (-20.0 + 32.0 * Double((yearInt - 1820) * (yearInt - 1820)) / 10000.0
                    + 0.5628 * Double(2150 - yearInt)) / 86400.0
        } else if (2006...2050).contains(yearInt) {
            return (62.92 + 0.32217 * y2000 + 0.005589 * y2000 * y2000) / 86400.0
        } else if (1987...2005).contains(yearInt) {
            return poly(y2000, [63.86, 0.3345, -0.060374, 0.0017275,
                                0.000651814, 0.00002373599]) / 86400.0
        } else if (1900...1986).contains(yearInt) {
            return poly(c, [-0.00002, 0.000297, 0.025184, -0.181133,
                            0.553040, -0.861938, 0.677066, -0.212591])
        } else if (1800...1899).contains(yearInt) {
            return poly(c, [-0.000009, 0.003844, 0.083563, 0.865736,
                            4.867575, 15.845535, 31.332267, 38.291999,
                            28.316289, 11.636204, 2.043794])
        } else if (1700...1799).contains(yearInt) {
            return poly(y1700, [8.118780842, -0.005092142, 0.003336121,
                                -0.0000266484]) / 86400.0
        } else if (1600...1699).contains(yearInt) {
            return poly(y1600, [120.0, -0.9808, -0.01532, 0.000140272128]) / 86400.0
        } else if (500...1599).contains(yearInt) {
            return poly(y1000, [1574.2, -556.01, 71.23472, 0.319781,
                                -0.8503463, -0.005050998, 0.0083572073]) / 86400.0
        } else if (-499...499).contains(yearInt) {
            return poly(y0, [10583.6, -1014.41, 33.78311, -5.952053,
                             -0.1798452, 0.022174192, 0.0090316521]) / 86400.0
        } else {
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
        return -0.004778 * sinDeg(a) - 0.0003667 * sinDeg(b)
    }

    static func aberration(_ c: Double) -> Double {
        0.0000974 * cosDeg(177.63 + 35999.01848 * c) - 0.005575
    }

    // Solar longitude in degrees [0, 360), 49-term Bretagnon & Simon series.
    static func solarLongitude(at moment: Double) -> Double {
        let c = julianCenturies(moment)
        let x: [Double] = [
            403406, 195207, 119433, 112392, 3891, 2819, 1721, 660, 350, 334,
            314, 268, 242, 234, 158, 132, 129, 114, 99, 93, 86, 78, 72,
            68, 64, 46, 38, 37, 32, 29, 28, 27, 27, 25, 24, 21, 21,
            20, 18, 17, 14, 13, 13, 13, 12, 10, 10, 10, 10,
        ]
        let y: [Double] = [
            270.54861, 340.19128, 63.91854, 331.26220, 317.843, 86.631, 240.052, 310.26, 247.23,
            260.87, 297.82, 343.14, 166.79, 81.53, 3.50, 132.75, 182.95, 162.03, 29.8, 266.4,
            249.2, 157.6, 257.8, 185.1, 69.9, 8.0, 197.1, 250.4, 65.3, 162.7, 341.5, 291.6, 98.5,
            146.7, 110.0, 5.2, 342.6, 230.9, 256.1, 45.3, 242.9, 115.2, 151.8, 285.3, 53.3, 126.6,
            205.7, 85.9, 146.1,
        ]
        let z: [Double] = [
            0.9287892, 35999.1376958, 35999.4089666, 35998.7287385, 71998.20261, 71998.4403,
            36000.35726, 71997.4812, 32964.4678, -19.4410, 445267.1117, 45036.8840, 3.1008,
            22518.4434, -19.9739, 65928.9345, 9038.0293, 3034.7684, 33718.148, 3034.448,
            -2280.773, 29929.992, 31556.493, 149.588, 9037.750, 107997.405, -4444.176, 151.771,
            67555.316, 31556.080, -4561.540, 107996.706, 1221.655, 62894.167, 31437.369,
            14578.298, -31931.757, 34777.243, 1221.999, 62894.511, -4442.039, 107997.909,
            119.066, 16859.071, -4.578, 26895.292, -39.127, 12297.536, 90073.778,
        ]
        var lambda = 0.0
        for i in 0..<49 {
            lambda += x[i] * sinDeg(y[i] + z[i] * c)
        }
        lambda *= 0.000005729577951308232
        lambda += 282.7771834 + 36000.76953744 * c
        return mod360(lambda + aberration(c) + nutation(c))
    }

    static func estimatePriorSolarLongitude(angle: Double, moment: Double) -> Double {
        let rate = meanTropicalYear / 360.0
        let lon = solarLongitude(at: moment)
        let tau = moment - rate * mod360(lon - angle)
        let delta = mod360(solarLongitude(at: tau) - angle)
        let result = tau - rate * (delta < 180.0 ? delta : delta - 360.0)
        return min(moment, result)
    }

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

        let v: [Double] = [
            -0.40720, 0.17241, 0.01608, 0.01039, 0.00739, -0.00514, 0.00208, -0.00111, -0.00057,
            0.00056, -0.00042, 0.00042, 0.00038, -0.00024, -0.00007, 0.00004, 0.00004, 0.00003,
            0.00003, -0.00003, 0.00003, -0.00002, -0.00002, 0.00002,
        ]
        let xc: [Double] = [
            0, 1, 0, 0, -1, 1, 2, 0, 0, 1, 0, 1, 1, -1, 2, 0, 3, 1, 0, 1, -1, -1, 1, 0,
        ]
        let yc: [Double] = [
            1, 0, 2, 0, 1, 1, 0, 1, 1, 2, 3, 0, 0, 2, 1, 2, 0, 1, 2, 1, 1, 1, 3, 4,
        ]
        let zc: [Double] = [
            0, 0, 0, 2, 0, 0, 0, -2, 2, 0, 0, 2, -2, 0, 0, -2, 0, -2, 2, 2, 2, -2, 0, 0,
        ]
        var correction = -0.00017 * sinDeg(omega)
        for i in 0..<24 {
            let ePow = pow(e, abs(xc[i]))
            let arg = xc[i] * solarAnomaly + yc[i] * lunarAnomaly + zc[i] * moonArgument
            correction += v[i] * ePow * sinDeg(arg)
        }
        let extra = 0.000325 * sinDeg(299.77 + 132.8475848 * c - 0.009173 * c * c)
        let ic: [Double] = [
            251.88, 251.83, 349.42, 84.66, 141.74, 207.14, 154.84, 34.52, 207.19, 291.34, 161.72, 239.56, 331.55,
        ]
        let jc: [Double] = [
            0.016321, 26.651886, 36.412478, 18.206239, 53.303771, 2.453732, 7.306860, 27.261239,
            0.121824, 1.844379, 24.198154, 25.513099, 3.592518,
        ]
        let lc: [Double] = [
            0.000165, 0.000164, 0.000126, 0.000110, 0.000062, 0.000060, 0.000056, 0.000047,
            0.000042, 0.000040, 0.000037, 0.000035, 0.000023,
        ]
        var additional = 0.0
        for i in 0..<13 {
            additional += lc[i] * sinDeg(ic[i] + jc[i] * k)
        }
        return universalFromDynamical(approx + correction + extra + additional)
    }

    static func numOfNewMoonAtOrAfter(_ moment: Double) -> Int {
        let rawN = ((moment - newMoonZero) / meanSynodicMonth).rounded()
        var n = Int(rawN)
        while nthNewMoon(n) < moment { n += 1 }
        while nthNewMoon(n - 1) >= moment { n -= 1 }
        return n
    }

    static func newMoonAtOrAfter(_ moment: Double) -> Double {
        nthNewMoon(numOfNewMoonAtOrAfter(moment))
    }

    static func newMoonBefore(_ moment: Double) -> Double {
        nthNewMoon(numOfNewMoonAtOrAfter(moment) - 1)
    }
}

// MARK: - chnsecal rules over the astronomy (flat UTC+8, matching ICU)

internal struct _ChineseRules {
    static let synodicGap = 25
    var winterSolsticeCache: [Int: Int] = [:]
    var newYearCache: [Int: Int] = [:]

    // Local UTC+8 midnight of an RD day, as a universal moment.
    private func midnight(_ rd: Int) -> Double {
        Double(rd) - 1.0 + 16.0 / 24.0
    }

    private func toLocalDay(_ moment: Double) -> Int {
        Int((moment + 8.0 / 24.0).rounded(.down))
    }

    // Winter solstice day on or after Dec 1 (chnsecal winterSolstice).
    mutating func winterSolstice(_ gyear: Int) -> Int {
        if let cached = winterSolsticeCache[gyear] { return cached }
        var day = _ChineseAstro.gregorianRD(gyear, 12, 10)
        while true {
            let lon = _ChineseAstro.solarLongitude(at: midnight(day + 1))
            if lon >= 270.0 && lon < 350.0 { break }
            day += 1
        }
        if winterSolsticeCache.count > 32 { winterSolsticeCache.removeAll() }
        winterSolsticeCache[gyear] = day
        return day
    }

    func newMoonNear(_ days: Int, _ after: Bool) -> Int {
        let m = midnight(days)
        let nm = after ? _ChineseAstro.newMoonAtOrAfter(m) : _ChineseAstro.newMoonBefore(m)
        return toLocalDay(nm)
    }

    static func synodicMonthsBetween(_ day1: Int, _ day2: Int) -> Int {
        let r = Double(day2 - day1) / _ChineseAstro.meanSynodicMonth
        return Int(r + (r >= 0 ? 0.5 : -0.5))
    }

    func majorSolarTerm(_ days: Int) -> Int {
        let lon = _ChineseAstro.solarLongitude(at: midnight(days))
        var term = (Int(lon / 30.0) + 2) % 12
        if term < 1 { term += 12 }
        return term
    }

    func hasNoMajorSolarTerm(_ newMoon: Int) -> Bool {
        majorSolarTerm(newMoon) == majorSolarTerm(newMoonNear(newMoon + Self.synodicGap, true))
    }

    func isLeapMonthBetween(_ newMoon1: Int, _ newMoon2: Int) -> Bool {
        var m2 = newMoon2
        while m2 >= newMoon1 {
            if hasNoMajorSolarTerm(m2) { return true }
            m2 = newMoonNear(m2 - Self.synodicGap, false)
        }
        return false
    }

    mutating func newYear(_ gyear: Int) -> Int {
        if let cached = newYearCache[gyear] { return cached }
        let solsticeBefore = winterSolstice(gyear - 1)
        let solsticeAfter = winterSolstice(gyear)
        let newMoon1 = newMoonNear(solsticeBefore + 1, true)
        let newMoon2 = newMoonNear(newMoon1 + Self.synodicGap, true)
        let newMoon11 = newMoonNear(solsticeAfter + 1, false)
        let value: Int
        if Self.synodicMonthsBetween(newMoon1, newMoon11) == 12 &&
            (hasNoMajorSolarTerm(newMoon1) || hasNoMajorSolarTerm(newMoon2)) {
            value = newMoonNear(newMoon2 + Self.synodicGap, true)
        } else {
            value = newMoon2
        }
        if newYearCache.count > 32 { newYearCache.removeAll() }
        newYearCache[gyear] = value
        return value
    }

    // (month, isLeapMonth) label for the month starting at new moon `start`.
    mutating func monthLabel(startingAt start: Int, gyear: Int) -> (month: Int, isLeap: Bool) {
        var solsticeBefore: Int
        var solsticeAfter = winterSolstice(gyear)
        if start < solsticeAfter {
            solsticeBefore = winterSolstice(gyear - 1)
        } else {
            solsticeBefore = solsticeAfter
            solsticeAfter = winterSolstice(gyear + 1)
        }
        let firstMoon = newMoonNear(solsticeBefore + 1, true)
        let lastMoon = newMoonNear(solsticeAfter + 1, false)
        let hasLeap = Self.synodicMonthsBetween(firstMoon, lastMoon) == 12
        var month = Self.synodicMonthsBetween(firstMoon, start)
        if hasLeap && isLeapMonthBetween(firstMoon, start) {
            month -= 1
        }
        if month < 1 { month += 12 }
        let isLeap = hasLeap && hasNoMajorSolarTerm(start) &&
            !isLeapMonthBetween(firstMoon, newMoonNear(start - Self.synodicGap, false))
        return (month, isLeap)
    }
}

// MARK: - Year structure

internal struct _ChineseYear: Sendable {
    let relatedIso: Int
    let newYearRD: Int
    let monthLengthBits: UInt16    // bit i set = ordinal month i+1 has 30 days
    let monthCount: UInt8          // 12 or 13
    let leapDisplay: UInt8         // 0 = none; else leap month repeats this number

    // Ordinal position (1-based) of the leap month, if any.
    var leapOrdinal: Int? { leapDisplay == 0 ? nil : Int(leapDisplay) + 1 }

    func monthLength(ordinal: Int) -> Int {
        (monthLengthBits >> (ordinal - 1)) & 1 == 1 ? 30 : 29
    }

    func monthStartRD(ordinal: Int) -> Int {
        var rd = newYearRD
        for i in 1..<ordinal { rd += monthLength(ordinal: i) }
        return rd
    }

    var daysInYear: Int {
        var days = 0
        for i in 1...Int(monthCount) { days += monthLength(ordinal: i) }
        return days
    }

    var endRD: Int { newYearRD + daysInYear }

    func label(ordinal: Int) -> (month: Int, isLeap: Bool) {
        guard let lo = leapOrdinal else { return (ordinal, false) }
        if ordinal == lo { return (Int(leapDisplay), true) }
        if ordinal > lo { return (ordinal - 1, false) }
        return (ordinal, false)
    }

    func ordinal(month: Int, isLeap: Bool) -> Int? {
        guard month >= 1 && month <= 12 else { return nil }
        guard let lo = leapOrdinal else { return isLeap ? nil : month }
        if isLeap {
            return month == Int(leapDisplay) ? lo : nil
        }
        return month < lo ? month : month + 1
    }

    // (ordinal, dayOfMonth) for an RD inside this year.
    func ordinalAndDay(rd: Int) -> (ordinal: Int, day: Int)? {
        guard rd >= newYearRD && rd < endRD else { return nil }
        var start = newYearRD
        for ordinal in 1...Int(monthCount) {
            let len = monthLength(ordinal: ordinal)
            if rd < start + len { return (ordinal, rd - start + 1) }
            start += len
        }
        return nil
    }
}

// MARK: - Engine: baked table + computed fallback

internal enum _ChineseCalendarEngine {
    // Chinese years keyed by related ISO year (year containing the CNY).
    // Generated from _CalendarICU(.chinese) daily sweep; see the generator probe.
    // bits 0-12 month lengths (1=30d), 13-16 leap display number (0=none),
    // 17-22 new-year offset from Jan 19 of the related ISO year.
    static let tableStart = 1901
    static let table: [UInt32] = [
    0x003E0752, 0x00280EA5, 0x0014B64A, 0x0038064B, // 1901-1904
    0x00200A9B, 0x000C9556, 0x0032056A, 0x001C0B59, // 1905-1908
    0x00065752, 0x002C0752, 0x0016DB25, 0x003C0B25, // 1909-1912
    0x00240A4B, 0x000EB2AB, 0x00340AAD, 0x0020056A, // 1913-1916
    0x00084B69, 0x002E0DA9, 0x001AFD92, 0x00400D92, // 1917-1920
    0x00280D25, 0x0012BA4D, 0x00380A56, 0x002202B6, // 1921-1924
    0x000A95B5, 0x003206D4, 0x001C0EA9, 0x00085E92, // 1925-1928
    0x002C0E92, 0x0016CD26, 0x003A052B, 0x00240A57, // 1929-1932
    0x000EB2B6, 0x00340B5A, 0x002006D4, 0x000A6EC9, // 1933-1936
    0x002E0749, 0x0018F693, 0x003E0A93, 0x0028052B, // 1937-1940
    0x0010CA5B, 0x00360AAD, 0x0022056A, 0x000C9B55, // 1941-1944
    0x00320BA4, 0x001C0B49, 0x00065A93, 0x002C0A95, // 1945-1948
    0x0014F52D, 0x003A0536, 0x00240AAD, 0x0010B5AA, // 1949-1952
    0x003405B2, 0x001E0DA5, 0x000A7D4A, 0x00300D4A, // 1953-1956
    0x00190A95, 0x003C0A97, 0x00280556, 0x0012CAB5, // 1957-1960
    0x00360AD5, 0x002206D2, 0x000C8EA5, 0x00320EA5, // 1961-1964
    0x001C064A, 0x00046C97, 0x002A0A9B, 0x0016F55A, // 1965-1968
    0x003A056A, 0x00240B69, 0x0010B752, 0x00360B52, // 1969-1972
    0x001E0B25, 0x0008964B, 0x002E0A4B, 0x001914AB, // 1973-1976
    0x003C02AD, 0x0026056D, 0x0012CB69, 0x00380DA9, // 1977-1980
    0x00220D92, 0x000C9D25, 0x00320D25, 0x001D5A4D, // 1981-1984
    0x00400A56, 0x002A02B6, 0x0014C5B5, 0x003A06D5, // 1985-1988
    0x00240EA9, 0x0010BE92, 0x00360E92, 0x00200D26, // 1989-1992
    0x00086A56, 0x002C0A57, 0x001914D6, 0x003E035A, // 1993-1996
    0x002606D5, 0x0012B6C9, 0x00380749, 0x00220693, // 1997-2000
    0x000A952B, 0x0030052B, 0x001A0A5B, 0x0006555A, // 2001-2004
    0x002A056A, 0x0014FB55, 0x003C0BA4, 0x00260B49, // 2005-2008
    0x000EBA93, 0x00340A95, 0x001E052D, 0x00088AAD, // 2009-2012
    0x002C0AB5, 0x001935AA, 0x003E05D2, 0x00280DA5, // 2013-2016
    0x0012DD4A, 0x00380D4A, 0x00220C95, 0x000C952E, // 2017-2020
    0x00300556, 0x001A0AB5, 0x000655B2, 0x002C06D2, // 2021-2024
    0x0014CEA5, 0x003A0725, 0x0024064B, 0x000EAC97, // 2025-2028
    0x00320CAB, 0x001E055A, 0x00086AD6, 0x002E0B69, // 2029-2032
    0x00197752, 0x003E0B52, 0x00280B25, 0x0012DA4B, // 2033-2036
    0x00360A4B, 0x002004AB, 0x000AA55B, 0x003005AD, // 2037-2040
    0x001A0B6A, 0x00065B52, 0x002C0D92, 0x0016FD25, // 2041-2044
    0x003A0D25, 0x00240A55, 0x000EB4AD, 0x003404B6, // 2045-2048
    0x001C05B5, 0x00086DAA, 0x002E0EC9, 0x001B1E92, // 2049-2052
    0x003E0E92, 0x00280D26, 0x0012CA56, 0x00360A57, // 2053-2056
    0x00200556, 0x000A86D5, 0x00300755, 0x001C0749, // 2057-2060
    0x00046E93, 0x002A0693, 0x0014F52B, 0x003A052B, // 2061-2064
    0x00220A5B, 0x000EB55A, 0x0034056A, 0x001E0B65, // 2065-2068
    0x0008974A, 0x002E0B4A, 0x00191A95, 0x003E0A95, // 2069-2072
    0x0026052D, 0x0010CAAD, 0x00360AB5, 0x002205AA, // 2073-2076
    0x000A8BA5, 0x00300DA5, 0x001C0D4A, 0x00067C95, // 2077-2080
    0x002A0C96, 0x0014F94E, 0x003A0556, 0x00240AB5, // 2081-2084
    0x000EB5B2, 0x003406D2, 0x001E0EA5, 0x000A8E4A, // 2085-2088
    0x002C068B, 0x00170C97, 0x003C04AB, 0x0026055B, // 2089-2092
    0x0010CAD6, 0x00360B6A, 0x00220752, 0x000C9725, // 2093-2096
    0x00300B45, 0x001A0A8B, 0x0004549B, 0x002A04AB, // 2097-2100
    ]

    static let fallbackCache = LockedState<(rules: _ChineseRules, years: [Int: _ChineseYear])>(
        initialState: (_ChineseRules(), [:]))

    static func year(relatedIso: Int) -> _ChineseYear {
        let idx = relatedIso - tableStart
        if idx >= 0 && idx < table.count {
            let v = table[idx]
            let leap = UInt8((v >> 13) & 0xF)
            return _ChineseYear(
                relatedIso: relatedIso,
                newYearRD: _ChineseAstro.gregorianRD(relatedIso, 1, 19) + Int((v >> 17) & 0x3F),
                monthLengthBits: UInt16(v & 0x1FFF),
                monthCount: leap == 0 ? 12 : 13,
                leapDisplay: leap)
        }
        return fallbackCache.withLock { state in
            if let cached = state.years[relatedIso] { return cached }
            // Tile exactly with the baked table at the seams.
            let ny: Int
            if relatedIso == tableStart + table.count {
                var prev = relatedIso - 1
                var end = 0
                while end == 0 {  // walk back over the table edge year
                    let v = table[prev - tableStart]
                    let leap = UInt8((v >> 13) & 0xF)
                    let py = _ChineseYear(
                        relatedIso: prev,
                        newYearRD: _ChineseAstro.gregorianRD(prev, 1, 19) + Int((v >> 17) & 0x3F),
                        monthLengthBits: UInt16(v & 0x1FFF),
                        monthCount: leap == 0 ? 12 : 13,
                        leapDisplay: leap)
                    end = py.endRD
                    prev -= 1
                }
                ny = end
            } else {
                ny = state.rules.newYear(relatedIso)
            }
            let nyNext: Int
            if relatedIso + 1 == tableStart {
                let v = table[0]
                nyNext = _ChineseAstro.gregorianRD(tableStart, 1, 19) + Int((v >> 17) & 0x3F)
            } else {
                nyNext = state.rules.newYear(relatedIso + 1)
            }
            var starts = [ny]
            var cur = ny
            while true {
                let nxt = state.rules.newMoonNear(cur + _ChineseRules.synodicGap, true)
                if nxt >= nyNext { break }
                starts.append(nxt)
                cur = nxt
            }
            var bits: UInt16 = 0
            var leapDisplay: UInt8 = 0
            for (i, s) in starts.enumerated() {
                let next = (i + 1 < starts.count) ? starts[i + 1] : nyNext
                assert(next - s == 29 || next - s == 30, "non-lunation month length \(next - s) in fallback year \(relatedIso)")
                if next - s == 30 { bits |= UInt16(1) << i }
                let label = state.rules.monthLabel(startingAt: s, gyear: _ChineseAstro.gregorianYear(ofRD: s))
                if label.isLeap { leapDisplay = UInt8(label.month) }
            }
            let year = _ChineseYear(
                relatedIso: relatedIso, newYearRD: ny,
                monthLengthBits: bits, monthCount: UInt8(starts.count),
                leapDisplay: leapDisplay)
            if state.years.count > 16 { state.years.removeAll() }
            state.years[relatedIso] = year
            return year
        }
    }

    static func year(containingRD rd: Int) -> _ChineseYear {
        // CNY falls Jan 19 + [2, 61]; estimate by Gregorian year and adjust.
        var iso = _ChineseAstro.gregorianYear(ofRD: rd)
        var y = year(relatedIso: iso)
        while rd < y.newYearRD {
            iso -= 1
            y = year(relatedIso: iso)
        }
        while rd >= y.endRD {
            iso += 1
            y = year(relatedIso: iso)
        }
        return y
    }
}


// MARK: - _CalendarChinese

/// Pure-Swift implementation of the Chinese lunisolar calendar.
///
/// Field conventions match ICU: era = 60-year cycle number since the 2637 BCE
/// epoch, year = 1...60 within the cycle, month = 1...12 with `isLeapMonth`
/// distinguishing the repeated month, extended year (used by
/// `yearForWeekOfYear`) = related Gregorian year + 2637.
internal final class _CalendarChinese: _CalendarProtocol, @unchecked Sendable {

    init(identifier: Calendar.Identifier, timeZone: TimeZone?, locale: Locale?, firstWeekday: Int?, minimumDaysInFirstWeek: Int?, gregorianStartDate: Date?) {
        assert(identifier == .chinese, "_CalendarChinese only handles .chinese")
        self.identifier = identifier
        self.timeZone = timeZone ?? .default
        self.locale = locale
        if let firstWeekday, (firstWeekday >= 1 && firstWeekday <= 7) {
            _firstWeekday = firstWeekday
        }
        if var minimumDaysInFirstWeek {
            if minimumDaysInFirstWeek < 1 { minimumDaysInFirstWeek = 1 }
            else if minimumDaysInFirstWeek > 7 { minimumDaysInFirstWeek = 7 }
            _minimumDaysInFirstWeek = minimumDaysInFirstWeek
        }
    }

    let identifier: Calendar.Identifier
    var locale: Locale?
    var timeZone: TimeZone

    var _firstWeekday: Int?
    var firstWeekday: Int {
        set { _firstWeekday = _CalendarUtility.validatedFirstWeekday(newValue) }
        get { _CalendarUtility.resolveFirstWeekday(stored: _firstWeekday, locale: locale) }
    }

    var _minimumDaysInFirstWeek: Int?
    var minimumDaysInFirstWeek: Int {
        set { _minimumDaysInFirstWeek = _CalendarUtility.clampedMinimumDaysInFirstWeek(newValue) }
        get { _CalendarUtility.resolveMinimumDaysInFirstWeek(stored: _minimumDaysInFirstWeek, locale: locale) }
    }

    func copy(changingLocale: Locale?, changingTimeZone: TimeZone?, changingFirstWeekday: Int?, changingMinimumDaysInFirstWeek: Int?) -> _CalendarProtocol {
        let args = _CalendarUtility.resolvedCopyArgs(
            currentTimeZone: timeZone, changingTimeZone: changingTimeZone,
            currentLocale: locale, changingLocale: changingLocale,
            currentFirstWeekday: _firstWeekday, changingFirstWeekday: changingFirstWeekday,
            currentMinimumDaysInFirstWeek: _minimumDaysInFirstWeek, changingMinimumDaysInFirstWeek: changingMinimumDaysInFirstWeek
        )
        return _CalendarChinese(identifier: identifier, timeZone: args.timeZone, locale: args.locale, firstWeekday: args.firstWeekday, minimumDaysInFirstWeek: args.minimumDaysInFirstWeek, gregorianStartDate: nil)
    }

    // No fast paths in phase 1 — leap months complicate the matching patterns.
    var supportsNextDateFastPath: Bool { false }

    // MARK: Extended year model

    // extended year = related Gregorian year + 2637; era = 60-year cycle.
    static let extOffset = 2637

    private static func yearData(ext: Int) -> _ChineseYear {
        _ChineseCalendarEngine.year(relatedIso: ext - extOffset)
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }

    private static func eraAndYear(ext: Int) -> (era: Int, year: Int) {
        let e = floorDiv(ext - 1, 60)
        return (e + 1, ext - 1 - e * 60 + 1)
    }

    private static func ext(era: Int, year: Int) -> Int {
        (era - 1) * 60 + year
    }

    // MARK: Range

    func minimumRange(of component: Calendar.Component) -> Range<Int>? {
        switch component {
        case .era: return 1..<83334          // ICU chnsecal LIMITS
        case .year: return 1..<61
        case .month: return 1..<13
        case .day: return 1..<30
        case .hour: return 0..<24
        case .minute: return 0..<60
        case .second: return 0..<60
        case .weekday: return 1..<8
        case .weekdayOrdinal: return -1..<6
        case .quarter: return 1..<5
        case .weekOfMonth: return 1..<6
        case .weekOfYear: return 1..<51
        case .yearForWeekOfYear: return -5_000_000..<5_000_001
        case .nanosecond: return 0..<1_000_000_000
        case .isLeapMonth: return 0..<2
        case .isRepeatedDay: return 0..<1
        case .dayOfYear: return 1..<354
        case .calendar, .timeZone:
            return nil
        }
    }

    func maximumRange(of component: Calendar.Component) -> Range<Int>? {
        switch component {
        case .era: return 1..<83334
        case .year: return 1..<61
        case .month: return 1..<13
        case .day: return 1..<31
        case .hour: return 0..<24
        case .minute: return 0..<60
        case .second: return 0..<60
        case .weekday: return 1..<8
        case .weekdayOrdinal: return -1..<6
        case .quarter: return 1..<5
        case .weekOfMonth: return 1..<7
        case .weekOfYear: return 1..<56
        case .yearForWeekOfYear: return -5_000_000..<5_000_001
        case .nanosecond: return 0..<1_000_000_000
        case .isLeapMonth: return 0..<2
        case .isRepeatedDay: return 0..<1
        case .dayOfYear: return 1..<386
        case .calendar, .timeZone:
            return nil
        }
    }

    func range(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Range<Int>? {
        switch smaller {
        case .weekday:
            switch larger {
            case .second, .minute, .hour, .day, .weekday: return nil
            default: return maximumRange(of: smaller)
            }
        case .hour:
            switch larger {
            case .second, .minute, .hour: return nil
            default: return maximumRange(of: smaller)
            }
        case .minute:
            switch larger {
            case .second, .minute: return nil
            default: return maximumRange(of: smaller)
            }
        case .second:
            switch larger {
            case .second: return nil
            default: return maximumRange(of: smaller)
            }
        case .nanosecond:
            return maximumRange(of: smaller)
        default:
            break
        }
        switch (smaller, larger) {
        case (.month, .year):
            // Number of display months is always 12 (the leap repeats a number).
            return 1..<13
        default:
            break
        }
        guard let interval = dateInterval(of: larger, for: date) else { return nil }
        guard let ord1 = ordinality(of: smaller, in: larger, for: interval.start + 0.1) else { return nil }
        guard let ord2 = ordinality(of: smaller, in: larger, for: interval.start + interval.duration - 0.1) else { return nil }
        if ord2 < ord1 { return ord1..<ord1 }
        return ord1..<(ord2 + 1)
    }

    // MARK: Ordinality

    func ordinality(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Int? {
        let tz = self.timeZone
        let comps = dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond,
             .weekday, .weekOfYear, .weekOfMonth, .weekdayOrdinal, .dayOfYear],
            from: date, in: tz
        )
        guard let day = comps.day, let dayOfYear = comps.dayOfYear else { return nil }
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        let nanosecond = comps.nanosecond ?? 0

        switch (smaller, larger) {
        case (.day, .year):
            return dayOfYear
        case (.day, .month):
            return day
        case (.month, .year):
            // ICU returns the display month number, not the ordinal position.
            return comps.month
        case (.weekOfYear, .year):
            let weekday = comps.weekday ?? 1
            let relStart = (weekday - dayOfYear + 7001 - firstWeekday) % 7
            var unwrapped = (dayOfYear - 1 + relStart) / 7
            if (7 - relStart) >= minimumDaysInFirstWeek { unwrapped += 1 }
            return unwrapped
        case (.weekOfMonth, .month):
            return comps.weekOfMonth
        case (.weekday, .year):
            return (dayOfYear - 1) / 7 + 1
        case (.weekday, .month):
            return (day - 1) / 7 + 1
        case (.weekday, .weekOfYear):
            guard let weekday = comps.weekday else { return nil }
            return ((weekday - firstWeekday + 7) % 7) + 1
        case (.weekdayOrdinal, .month):
            return (day - 1) / 7 + 1
        case (.hour, .day):
            return hour + 1
        case (.minute, .hour):
            return minute + 1
        case (.second, .minute):
            return second + 1
        case (.nanosecond, .second):
            return nanosecond + 1
        default:
            return nil
        }
    }

    // MARK: Internal field extraction

    /// (extended year, month ordinal, day) for a date in the given timezone.
    private func fields(for date: Date, in tz: TimeZone) -> (ext: Int, ordinal: Int, day: Int) {
        let totalOffset = tz.secondsFromGMT(for: date)
        let localSeconds = date.timeIntervalSinceReferenceDate + Double(totalOffset)
        let (rd, _) = Self.rataDieAndSecondsInDay(localSeconds: localSeconds)
        let y = _ChineseCalendarEngine.year(containingRD: rd)
        let (ordinal, day) = y.ordinalAndDay(rd: rd)!
        return (y.relatedIso + Self.extOffset, ordinal, day)
    }

    // MARK: Date intervals

    private static func nextOrdinalMonth(ext: Int, ordinal: Int) -> (Int, Int) {
        let y = yearData(ext: ext)
        if ordinal < Int(y.monthCount) { return (ext, ordinal + 1) }
        return (ext + 1, 1)
    }

    private static func prevOrdinalMonth(ext: Int, ordinal: Int) -> (Int, Int) {
        if ordinal > 1 { return (ext, ordinal - 1) }
        let py = yearData(ext: ext - 1)
        return (ext - 1, Int(py.monthCount))
    }

    private func firstDayOfWeekYear(_ ext: Int) -> Int {
        let rdNY = Self.yearData(ext: ext).newYearRD
        var r = rdNY % 7
        if r < 0 { r += 7 }
        let nyWeekday = r + 1
        let rel = (nyWeekday - firstWeekday + 7) % 7
        let offset: Int
        if (7 - rel) >= minimumDaysInFirstWeek {
            offset = -rel
        } else {
            offset = 7 - rel
        }
        return rdNY + offset
    }

    private func numWeeksInYearForWeekOfYear(_ ext: Int) -> Int {
        (firstDayOfWeekYear(ext + 1) - firstDayOfWeekYear(ext)) / 7
    }

    /// Date at local midnight of (ext, ordinal, day).
    private func localMidnight(ext: Int, ordinal: Int, day: Int, in tz: TimeZone) -> Date {
        let y = Self.yearData(ext: ext)
        let rd = y.monthStartRD(ordinal: ordinal) + day - 1
        return utcDate(fromRataDie: rd, secondsInDay: 0, in: tz,
                       repeatedTimePolicy: .former, skippedTimePolicy: .former)
    }

    func dateInterval(of component: Calendar.Component, for date: Date) -> DateInterval? {
        let tz = self.timeZone
        let (ext, ordinal, day) = fields(for: date, in: tz)

        switch component {
        case .era:
            // One era = one 60-year cycle.
            let (era, _) = Self.eraAndYear(ext: ext)
            let startExt = Self.ext(era: era, year: 1)
            let start = localMidnight(ext: startExt, ordinal: 1, day: 1, in: tz)
            let end = localMidnight(ext: startExt + 60, ordinal: 1, day: 1, in: tz)
            return DateInterval(start: start, duration: end.timeIntervalSince(start))
        case .year:
            let start = localMidnight(ext: ext, ordinal: 1, day: 1, in: tz)
            let end = localMidnight(ext: ext + 1, ordinal: 1, day: 1, in: tz)
            return DateInterval(start: start, duration: end.timeIntervalSince(start))
        case .yearForWeekOfYear:
            // ICU returns nil for the chinese yearForWeekOfYear interval.
            return nil
        case .month:
            let start = localMidnight(ext: ext, ordinal: ordinal, day: 1, in: tz)
            let (ny, nm) = Self.nextOrdinalMonth(ext: ext, ordinal: ordinal)
            let end = localMidnight(ext: ny, ordinal: nm, day: 1, in: tz)
            return DateInterval(start: start, duration: end.timeIntervalSince(start))
        case .weekOfYear, .weekOfMonth:
            let y = Self.yearData(ext: ext)
            let rdHere = y.monthStartRD(ordinal: ordinal) + day - 1
            var r = rdHere % 7
            if r < 0 { r += 7 }
            let weekday = r + 1
            var daysBack = weekday - firstWeekday
            if daysBack < 0 { daysBack += 7 }
            let rdStart = rdHere - daysBack
            let start = utcDate(fromRataDie: rdStart, secondsInDay: 0, in: tz,
                                repeatedTimePolicy: .former, skippedTimePolicy: .former)
            let end = utcDate(fromRataDie: rdStart + 7, secondsInDay: 0, in: tz,
                              repeatedTimePolicy: .former, skippedTimePolicy: .former)
            return DateInterval(start: start, duration: end.timeIntervalSince(start))
        case .day, .weekday, .weekdayOrdinal, .dayOfYear:
            let y = Self.yearData(ext: ext)
            let rdHere = y.monthStartRD(ordinal: ordinal) + day - 1
            let start = utcDate(fromRataDie: rdHere, secondsInDay: 0, in: tz,
                                repeatedTimePolicy: .former, skippedTimePolicy: .former)
            let end = utcDate(fromRataDie: rdHere + 1, secondsInDay: 0, in: tz,
                              repeatedTimePolicy: .former, skippedTimePolicy: .former)
            return DateInterval(start: start, duration: end.timeIntervalSince(start))
        case .hour:
            let ti = Double(tz.secondsFromGMT(for: date))
            let time = date.timeIntervalSinceReferenceDate
            var fixedTime = time + ti
            fixedTime = (fixedTime / 3600.0).rounded(.down) * 3600.0
            fixedTime = fixedTime - ti
            return DateInterval(start: Date(timeIntervalSinceReferenceDate: fixedTime), duration: 3600.0)
        case .minute:
            let time = date.timeIntervalSinceReferenceDate
            return DateInterval(start: Date(timeIntervalSinceReferenceDate: (time / 60.0).rounded(.down) * 60.0), duration: 60.0)
        case .second:
            let time = date.timeIntervalSinceReferenceDate
            return DateInterval(start: Date(timeIntervalSinceReferenceDate: time.rounded(.down)), duration: 1.0)
        case .nanosecond:
            return DateInterval(start: date, duration: 1e-9)
        case .quarter, .isLeapMonth, .isRepeatedDay, .calendar, .timeZone:
            return nil
        }
    }

    // MARK: Weekend

    func isDateInWeekend(_ date: Date) -> Bool {
        let weekendRange = locale?.weekendRange ?? _CalendarUtility.defaultWeekendRange
        let comps = dateComponents([.weekday, .hour, .minute, .second], from: date, in: self.timeZone)
        guard let dayOfWeek = comps.weekday else { return false }
        let timeInDay = TimeInterval(
            (comps.hour ?? 0) * Calendar._kSecondsInHour
            + (comps.minute ?? 0) * 60
            + (comps.second ?? 0)
        )
        return _CalendarUtility.isDateInWeekend(weekday: dayOfWeek, timeInDay: timeInDay, weekendRange: weekendRange)
    }

    // MARK: Date ↔ DateComponents

    internal static let rataDieAtDateReference = 730_486

    private static func rataDieAndSecondsInDay(localSeconds: Double) -> (rd: Int, secondsInDay: Double) {
        let totalDays = (localSeconds / 86400).rounded(.down)
        let rd = Int(totalDays) &+ rataDieAtDateReference
        let secondsInDay = localSeconds - totalDays * 86400
        return (rd, secondsInDay)
    }

    internal func utcDate(fromRataDie rd: Int, secondsInDay: Double, in timeZone: TimeZone,
                          repeatedTimePolicy: TimeZone.DaylightSavingTimePolicy,
                          skippedTimePolicy: TimeZone.DaylightSavingTimePolicy) -> Date {
        _ = skippedTimePolicy
        let daysSinceRef = rd &- Self.rataDieAtDateReference
        let secondsAsIfUTC = Double(daysSinceRef) * 86400 + secondsInDay
        let tmpDate = Date(timeIntervalSinceReferenceDate: secondsAsIfUTC)
        let (tzOffset, dstOffset) = timeZone.rawAndDaylightSavingTimeOffset(
            for: tmpDate, repeatedTimePolicy: repeatedTimePolicy)
        return tmpDate - Double(tzOffset) - dstOffset
    }

    func date(from components: DateComponents) -> Date? {
        // Missing era defaults to the CURRENT date's era (ICU fields default from now).
        let era: Int
        if let e = components.era {
            era = e
        } else {
            let (nowExt, _, _) = fields(for: Date.now, in: components.timeZone ?? timeZone)
            era = Self.eraAndYear(ext: nowExt).era
        }
        guard let yearValue = components.year else { return nil }
        let ext = Self.ext(era: era, year: yearValue)
        guard ext > -5_000_000 && ext < 5_000_000 else { return nil }

        let month = components.month ?? 1
        let isLeap = components.isLeapMonth ?? false
        let day = components.day ?? 1

        let y = Self.yearData(ext: ext)
        guard month >= 1 && month <= 12 else { return nil }
        // A leap month that doesn't exist in this year falls back to the regular month.
        let ordinal: Int
        if let o = y.ordinal(month: month, isLeap: isLeap) {
            ordinal = o
        } else if isLeap, let o = y.ordinal(month: month, isLeap: false) {
            ordinal = o
        } else {
            return nil
        }
        let daysInMonth = y.monthLength(ordinal: ordinal)
        guard day >= 1 && day <= daysInMonth else { return nil }

        let rd = y.monthStartRD(ordinal: ordinal) + day - 1

        var secondsInDay: Double = 0
        if let hour = components.hour { secondsInDay += Double(hour) * 3600 }
        if let minute = components.minute { secondsInDay += Double(minute) * 60 }
        if let second = components.second { secondsInDay += Double(second) }
        if let nanosecond = components.nanosecond { secondsInDay += Double(nanosecond) / 1e9 }

        let tz = components.timeZone ?? timeZone
        return utcDate(fromRataDie: rd, secondsInDay: secondsInDay, in: tz,
                       repeatedTimePolicy: .former, skippedTimePolicy: .former)
    }

    func dateComponents(_ components: Calendar.ComponentSet, from date: Date, in timeZone: TimeZone) -> DateComponents {
        let totalOffset = timeZone.secondsFromGMT(for: date)
        let localSeconds = date.timeIntervalSinceReferenceDate + Double(totalOffset)
        let (rd, secondsInDay) = Self.rataDieAndSecondsInDay(localSeconds: localSeconds)

        let y = _ChineseCalendarEngine.year(containingRD: rd)
        let (ordinal, day) = y.ordinalAndDay(rd: rd)!
        let label = y.label(ordinal: ordinal)
        let ext = y.relatedIso + Self.extOffset
        let (era, yearInCycle) = Self.eraAndYear(ext: ext)

        var result = DateComponents()

        if components.contains(.era) { result.era = era }
        if components.contains(.year) { result.year = yearInCycle }
        if components.contains(.month) { result.month = label.month }
        if components.contains(.day) { result.day = day }
        // ICU populates isLeapMonth iff .month or .isLeapMonth was requested.
        if components.contains(.month) || components.contains(.isLeapMonth) {
            result.isLeapMonth = label.isLeap
        }

        if components.contains(.hour) || components.contains(.minute)
            || components.contains(.second) || components.contains(.nanosecond) {
            let h = Int(secondsInDay / 3600)
            let remAfterH = secondsInDay - Double(h) * 3600
            let m = Int(remAfterH / 60)
            let remAfterM = remAfterH - Double(m) * 60
            let s = Int(remAfterM)
            let ns = Int((localSeconds - localSeconds.rounded(.down)) * 1_000_000_000)
            if components.contains(.hour) { result.hour = h }
            if components.contains(.minute) { result.minute = m }
            if components.contains(.second) { result.second = s }
            if components.contains(.nanosecond) { result.nanosecond = ns }
        }

        if components.contains(.weekday) {
            var r = rd % 7
            if r < 0 { r += 7 }
            result.weekday = r + 1
        }

        if components.contains(.dayOfYear) {
            result.dayOfYear = rd - y.newYearRD + 1
        }

        if components.contains(.timeZone) {
            result.timeZone = timeZone
        }

        let needsWeekFields = components.contains(.weekdayOrdinal) ||
                              components.contains(.weekOfMonth) ||
                              components.contains(.weekOfYear) ||
                              components.contains(.yearForWeekOfYear)
        if needsWeekFields {
            var r = rd % 7
            if r < 0 { r += 7 }
            let weekday = r + 1

            let dayOfYear = rd - y.newYearRD + 1
            let yearLength = y.daysInYear

            let relativeWeekdayForYearStart = (weekday - dayOfYear + 7001 - firstWeekday) % 7
            let relativeWeekday = (weekday + 7 - firstWeekday) % 7

            var weekOfYear = (dayOfYear - 1 + relativeWeekdayForYearStart) / 7
            if (7 - relativeWeekdayForYearStart) >= minimumDaysInFirstWeek {
                weekOfYear += 1
            }

            var yearForWeekOfYear = ext
            if weekOfYear == 0 {
                let previousYearLength = Self.yearData(ext: ext - 1).daysInYear
                let previousDayOfYear = dayOfYear + previousYearLength
                weekOfYear = Self.weekNumber(
                    desiredDay: previousDayOfYear, dayOfPeriod: previousDayOfYear, weekday: weekday,
                    firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek)
                yearForWeekOfYear -= 1
            } else if dayOfYear >= yearLength - 5 {
                var lastRelativeDayOfWeek = (relativeWeekday + yearLength - dayOfYear) % 7
                if lastRelativeDayOfWeek < 0 { lastRelativeDayOfWeek += 7 }
                if ((6 - lastRelativeDayOfWeek) >= minimumDaysInFirstWeek)
                    && ((dayOfYear + 7 - relativeWeekday) > yearLength) {
                    weekOfYear = 1
                    yearForWeekOfYear += 1
                }
            }

            let weekOfMonth = Self.weekNumber(
                desiredDay: day, dayOfPeriod: day, weekday: weekday,
                firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek)
            let weekdayOrdinal = (day - 1) / 7 + 1

            if components.contains(.weekdayOrdinal)    { result.weekdayOrdinal = weekdayOrdinal }
            if components.contains(.weekOfMonth)       { result.weekOfMonth = weekOfMonth }
            if components.contains(.weekOfYear)        { result.weekOfYear = weekOfYear }
            if components.contains(.yearForWeekOfYear) { result.yearForWeekOfYear = yearForWeekOfYear }
        }

        // ICU returns 0 for chinese quarter (bug); match the sentinel.
        if components.contains(.quarter) {
            result.quarter = 0
        }

        return result
    }

    private static func weekNumber(
        desiredDay: Int, dayOfPeriod: Int, weekday: Int,
        firstWeekday: Int, minimumDaysInFirstWeek: Int
    ) -> Int {
        var periodStartDayOfWeek = (weekday - firstWeekday - dayOfPeriod + 1) % 7
        if periodStartDayOfWeek < 0 { periodStartDayOfWeek += 7 }
        var weekNo = (desiredDay + periodStartDayOfWeek - 1) / 7
        if (7 - periodStartDayOfWeek) >= minimumDaysInFirstWeek {
            weekNo += 1
        }
        return weekNo
    }

    func dateComponents(_ components: Calendar.ComponentSet, from date: Date) -> DateComponents {
        dateComponents(components, from: date, in: self.timeZone)
    }

    // MARK: ICU month resolution (chnsecal handleComputeMonthStart semantics)

    /// Start RD of the month for (ext, display month, leap flag), using ICU's
    /// estimate + single-bump algorithm: estimate = CNY + (display-1)*29 days,
    /// take the month starting at the next month-start >= estimate, and bump
    /// exactly once if the display number or leap flag mismatches.
    private static func resolvedMonthStart(ext: Int, display: Int, leap: Bool) -> Int {
        let ny = yearData(ext: ext).newYearRD
        let target = ny + (display - 1) * 29
        var y = _ChineseCalendarEngine.year(containingRD: target)
        var (ordinal, _) = y.ordinalAndDay(rd: target)!
        var est = y.monthStartRD(ordinal: ordinal)
        if est < target {   // target mid-month: next month start
            (est, y, ordinal) = Self.nextMonthStart(after: y, ordinal: ordinal)
        }
        let lbl = y.label(ordinal: ordinal)
        if lbl.month != display || lbl.isLeap != leap {
            (est, y, ordinal) = Self.nextMonthStart(after: y, ordinal: ordinal)
        }
        return est
    }

    private static func nextMonthStart(after y: _ChineseYear, ordinal: Int) -> (Int, _ChineseYear, Int) {
        if ordinal < Int(y.monthCount) {
            return (y.monthStartRD(ordinal: ordinal + 1), y, ordinal + 1)
        }
        let ny = _ChineseCalendarEngine.year(relatedIso: y.relatedIso + 1)
        return (ny.newYearRD, ny, 1)
    }

    // MARK: Adding

    func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool) -> Date? {
        var result = date

        // Wrap-day single-component fast path.
        if wrappingComponents,
           let d = components.day, d != 0,
           (components.era ?? 0) == 0, (components.year ?? 0) == 0, (components.month ?? 0) == 0,
           (components.weekOfYear ?? 0) == 0, (components.weekOfMonth ?? 0) == 0,
           (components.weekdayOrdinal ?? 0) == 0, (components.weekday ?? 0) == 0,
           (components.dayOfYear ?? 0) == 0, (components.yearForWeekOfYear ?? 0) == 0,
           (components.hour ?? 0) == 0, (components.minute ?? 0) == 0,
           (components.second ?? 0) == 0, (components.nanosecond ?? 0) == 0 {
            let tz = self.timeZone
            let (ext, ordinal, curDay) = fields(for: result, in: tz)
            let y = Self.yearData(ext: ext)
            let monthLen = y.monthLength(ordinal: ordinal)
            let newDay = ((curDay - 1 + d) % monthLen + monthLen) % monthLen + 1
            let comps = dateComponents([.hour, .minute, .second, .nanosecond], from: result, in: tz)
            var secondsInDay: Double = 0
            if let h = comps.hour { secondsInDay += Double(h) * 3600 }
            if let m = comps.minute { secondsInDay += Double(m) * 60 }
            if let s = comps.second { secondsInDay += Double(s) }
            if let n = comps.nanosecond { secondsInDay += Double(n) / 1e9 }
            let rd = y.monthStartRD(ordinal: ordinal) + newDay - 1
            return utcDate(fromRataDie: rd, secondsInDay: secondsInDay, in: tz,
                           repeatedTimePolicy: .former, skippedTimePolicy: .former)
        }

        let yearsToAdd = (components.year ?? 0) + (components.era ?? 0) * 60
        let monthsToAdd = components.month ?? 0

        if yearsToAdd != 0 {
            let tz = self.timeZone
            let (ext, ordinal, d) = fields(for: result, in: tz)
            let y = Self.yearData(ext: ext)
            let label = y.label(ordinal: ordinal)
            let newExt = ext + yearsToAdd
            // ICU pin semantics (Calendar::add -> pinField -> getActualMaximum):
            // S1 = single-bump resolution of (source display, source leap);
            // the pin length is a SECOND resolution using S1's display number
            // with the ORIGINAL leap flag (getActualMaximum completes a clone
            // for the month but handleGetMonthLength reads this->isLeapMonth);
            // the final time is S1 + pinned day, spilling leniently.
            let start0 = Self.resolvedMonthStart(ext: newExt, display: label.month, leap: label.isLeap)
            let y1 = _ChineseCalendarEngine.year(containingRD: start0)
            let (ord1, _) = y1.ordinalAndDay(rd: start0)!
            let display1 = y1.label(ordinal: ord1).month
            let start2 = Self.resolvedMonthStart(ext: newExt, display: display1, leap: label.isLeap)
            let y2 = _ChineseCalendarEngine.year(containingRD: start2)
            let (ord2, _) = y2.ordinalAndDay(rd: start2)!
            let maxDom = y2.monthLength(ordinal: ord2)
            let pinnedDay = min(d, maxDom)
            let comps = dateComponents([.hour, .minute, .second, .nanosecond], from: result, in: tz)
            var secondsInDay: Double = 0
            if let h = comps.hour { secondsInDay += Double(h) * 3600 }
            if let m = comps.minute { secondsInDay += Double(m) * 60 }
            if let s = comps.second { secondsInDay += Double(s) }
            if let n = comps.nanosecond { secondsInDay += Double(n) / 1e9 }
            let rd = start0 + pinnedDay - 1
            result = utcDate(fromRataDie: rd, secondsInDay: secondsInDay, in: tz,
                             repeatedTimePolicy: .former, skippedTimePolicy: .former)
        }

        if monthsToAdd != 0 {
            let tz = self.timeZone
            var (ext, ordinal, d) = fields(for: result, in: tz)
            var remaining = monthsToAdd
            while remaining > 0 {
                (ext, ordinal) = Self.nextOrdinalMonth(ext: ext, ordinal: ordinal)
                remaining -= 1
            }
            while remaining < 0 {
                (ext, ordinal) = Self.prevOrdinalMonth(ext: ext, ordinal: ordinal)
                remaining += 1
            }
            let ny = Self.yearData(ext: ext)
            let clampedDay = min(d, ny.monthLength(ordinal: ordinal))
            let comps = dateComponents([.hour, .minute, .second, .nanosecond], from: result, in: tz)
            var secondsInDay: Double = 0
            if let h = comps.hour { secondsInDay += Double(h) * 3600 }
            if let m = comps.minute { secondsInDay += Double(m) * 60 }
            if let s = comps.second { secondsInDay += Double(s) }
            if let n = comps.nanosecond { secondsInDay += Double(n) / 1e9 }
            let rd = ny.monthStartRD(ordinal: ordinal) + clampedDay - 1
            result = utcDate(fromRataDie: rd, secondsInDay: secondsInDay, in: tz,
                             repeatedTimePolicy: .former, skippedTimePolicy: .former)
        }

        var daysToAdd = 0
        if let d = components.day { daysToAdd += d }
        if let doy = components.dayOfYear { daysToAdd += doy }
        if let wom = components.weekOfMonth { daysToAdd += wom * 7 }
        if let woy = components.weekOfYear { daysToAdd += woy * 7 }
        if let wo = components.weekdayOrdinal { daysToAdd += wo * 7 }
        if let w = components.weekday { daysToAdd += w }

        // ICU treats .yearForWeekOfYear adds as a no-op for chinese.

        if daysToAdd != 0 {
            let tz = self.timeZone
            let totalOffset1 = tz.secondsFromGMT(for: result)
            let candidate = result + Double(daysToAdd) * 86400
            let totalOffset2 = tz.secondsFromGMT(for: candidate)
            result = candidate - Double(totalOffset2 - totalOffset1)
        }

        if let h = components.hour, h != 0 { result += Double(h) * 3600 }
        if let m = components.minute, m != 0 { result += Double(m) * 60 }
        if let s = components.second, s != 0 { result += Double(s) }
        if let ns = components.nanosecond, ns != 0 { result += Double(ns) / 1_000_000_000 }

        return result
    }

    // MARK: Difference

    func dateComponents(_ components: Calendar.ComponentSet, from start: Date, to end: Date) -> DateComponents {
        var result = DateComponents()
        var curr = start
        for component in Self.orderedDiffComponents(components) {
            let (diff, newCurr) = difference(inComponent: component, from: curr, to: end)
            result.setValue(diff, for: component)
            curr = newCurr
        }
        return result
    }

    private static func orderedDiffComponents(_ components: Calendar.ComponentSet) -> [Calendar.Component] {
        var out: [Calendar.Component] = []
        if components.contains(.era) { out.append(.era) }
        if components.contains(.year) { out.append(.year) }
        if components.contains(.yearForWeekOfYear) { out.append(.yearForWeekOfYear) }
        if components.contains(.quarter) { out.append(.quarter) }
        if components.contains(.month) { out.append(.month) }
        if components.contains(.weekOfYear) { out.append(.weekOfYear) }
        if components.contains(.weekOfMonth) { out.append(.weekOfMonth) }
        if components.contains(.day) { out.append(.day) }
        if components.contains(.dayOfYear) { out.append(.dayOfYear) }
        if components.contains(.weekday) { out.append(.weekday) }
        if components.contains(.weekdayOrdinal) { out.append(.weekdayOrdinal) }
        if components.contains(.hour) { out.append(.hour) }
        if components.contains(.minute) { out.append(.minute) }
        if components.contains(.second) { out.append(.second) }
        if components.contains(.nanosecond) { out.append(.nanosecond) }
        return out
    }

    private func difference(inComponent component: Calendar.Component, from start: Date, to end: Date) -> (Int, Date) {
        if start == end { return (0, start) }

        switch component {
        case .hour:
            let delta = end.timeIntervalSince(start) / 3600
            let diff = Int(delta.rounded(.towardZero))
            return (diff, start.addingTimeInterval(Double(diff) * 3600))
        case .minute:
            let delta = end.timeIntervalSince(start) / 60
            let diff = Int(delta.rounded(.towardZero))
            return (diff, start.addingTimeInterval(Double(diff) * 60))
        case .second:
            let delta = end.timeIntervalSince(start)
            let diff = Int(delta.rounded(.towardZero))
            return (diff, start.addingTimeInterval(Double(diff)))
        case .nanosecond:
            let delta = end.timeIntervalSince(start) * 1_000_000_000
            let diff = Int(delta.rounded(.towardZero))
            return (diff, start.addingTimeInterval(Double(diff) / 1_000_000_000))
        default:
            break
        }

        let forward = end > start
        let step = forward ? 1 : -1
        var diff = 0
        var current = start
        var safety = 0

        while true {
            let trial = diff + step
            var dc = DateComponents()
            dc.setValue(trial, for: component)
            guard let nextStep = date(byAdding: dc, to: start, wrappingComponents: false) else {
                break
            }
            if nextStep == current {
                break
            }
            let overshoot = forward ? (nextStep > end) : (nextStep < end)
            if overshoot { break }
            current = nextStep
            diff = trial
            safety += 1
            if safety > 1_000_000 { break }
        }
        return (diff, current)
    }

#if FOUNDATION_FRAMEWORK
    func bridgeToNSCalendar() -> NSCalendar {
        _NSSwiftCalendar(calendar: Calendar(inner: self))
    }
#endif
}
