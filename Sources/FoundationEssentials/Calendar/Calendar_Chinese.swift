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
