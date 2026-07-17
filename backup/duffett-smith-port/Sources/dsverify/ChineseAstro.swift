// Faithful Swift port of the Chinese-calendar astronomy glue from
// icu4c/source/i18n/chnsecal.cpp (winterSolstice, newMoonNear, majorSolarTerm,
// hasNoMajorSolarTerm, isLeapMonthBetween, computeMonthInfo, newYear).
// ⚠ CONTINGENCY ARTIFACT — not for the feature branch without explicit agreement.
//
// "days" throughout = days after 1970-01-01 00:00 in the astronomical base
// zone (flat UTC+8, ICU's CHINA_OFFSET; ICU deliberately does not use the
// historical pre-1929 GMT+7:45:40 — chnsecal.cpp:76-81).

import Foundation

struct MonthInfo {
    var month: Int = 0
    var ordinalMonth: Int = 0
    var thisMoon: Int = 0
    var isLeapMonth = false
    var hasLeapMonthBetweenWinterSolstices = false
}

final class ChineseAstro {
    static let CHINA_OFFSET = 8.0 * 3_600_000.0
    static let kOneDay = 86_400_000.0
    static let SYNODIC_GAP = 25

    // Apple ICU (swift-foundation-icu) APPLE_ICU_CHANGES, rdar://17888673:
    // for 1900-2100 the winter solstice and Chinese new year come from
    // linear estimates + these correction tables, NOT live astronomy.
    // rdar://136543653: the newYearAdj table applies to chinese but NOT dangi.
    //
    // NOTE: these two chnsecal-level tables alone do NOT reproduce Apple's
    // in-range (1900-2100) month/day/leap fields — Apple ALSO bakes ~2,500
    // new-moon instants and sun-longitude corrections into astro.cpp
    // (rdar://15539491&16688723, newMoonDates[]/sunLongitudeAdjustmts[],
    // "accurate to one minute of time instead of 25, 60, or worse").
    // In-range parity comes from the baked-year-table strategy (swept from
    // _CalendarICU), not from this port. This port's domain is OUT of range,
    // where Apple ICU = pure upstream astronomy — verified 0 divergent days
    // vs system ICU over 1500-1700 + 2150-2350 (146,827 days).
    // Default false = pure upstream behavior.
    var useAppleAdjustmentTables = false

    // bit array for gregorian 1900-2100: years where the solstice linear
    // estimate needs -1 (chnsecal.cpp APPLE_ICU_CHANGES)
    static let winterSolsticeAdj: [UInt16] = [
        0x0001, 0x0444, 0x0000, 0x8880, 0x0000, 0x1100, 0x0011,
        0x2200, 0x0022, 0x4000, 0x0444, 0x8000, 0x0088,
    ]

    // for gyear 1900-2100, corrections to linear estimate of newYear
    static let newYearAdj: [Int8] = [
         -5,  14,   3,  -7,  11,  -1, -11,   8,  -3, -14,   5,  -6,  13,   1, -10,   9,  -1, -13,   6,  -4, // 1900-1919
         15,   3,  -8,  11,   0, -12,   8,  -3, -13,   5,  -6,  12,   1, -10,   9,  -1, -12,   6,  -5,  14, // 1920-1939
          3,  -9,  10,   0, -11,   9,  -3, -14,   5,  -6,  12,   1,  -9,  10,  -2, -12,   7,  -4,  13,   3, // 1940-1959
         -8,  11,   0, -11,   8,  -2, -15,   4,  -6,  13,   1,  -9,  10,  -1, -13,   6,  -5,  14,   2,  -8, // 1960-1979
         11,   1, -11,   8,  -3,  16,   5,  -7,  12,   2,  -8,  10,  -1, -12,   6,  -5,  14,   3,  -7,  11, // 1980-1999
          0, -11,   8,  -4, -14,   5,  -6,  13,   2,  -9,  10,  -2, -13,   6,  -4,  14,   3,  -7,  12,   0, // 2000-2019
        -11,   8,  -3, -14,   5,  -6,  13,   2, -10,   9,  -1, -12,   6,  -4,  15,   4,  -8,  11,   0, -11, // 2020-2039
          7,  -3, -13,   6,  -6,  13,   2,  -9,   9,  -2, -12,   7,  -4,  15,   4,  -7,  10,   0, -11,   8, // 2040-2059
         -3, -14,   5,  -6,  12,   1,  -9,  10,  -1, -12,   7,  -4,  15,   3,  -8,  11,   1, -11,   8,  -2, // 2060-2079
        -13,   5,  -6,  13,   2,  -9,  10,  -1, -11,   6,  -5,  14,   3,  -8,  11,   1, -10,   8,  -3, -14, // 2080-2099
          5, // 2100
    ]

    private var winterSolsticeCache: [Int: Int] = [:]
    private var newYearCache: [Int: Int] = [:]

    // Grego::fieldsToDay equivalent: proleptic Gregorian y/m/d (1-based month)
    // to days since 1970-01-01.
    static func gregorianEpochDay(_ y: Int, _ m: Int, _ d: Int) -> Int {
        func floorDiv(_ a: Int, _ b: Int) -> Int {
            a >= 0 ? a / b : -((-a + b - 1) / b)
        }
        let ym1 = y - 1
        let isLeap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        var rd = 365 * ym1 + floorDiv(ym1, 4) - floorDiv(ym1, 100) + floorDiv(ym1, 400)
        rd += floorDiv(367 * m - 362, 12)
        rd += m <= 2 ? 0 : (isLeap ? -1 : -2)
        rd += d
        return rd - 719_163  // RD of 1970-01-01
    }

    static func daysToMillis(_ days: Double) -> Double {
        days * kOneDay - CHINA_OFFSET
    }

    static func millisToDays(_ millis: Double) -> Double {
        ((millis + CHINA_OFFSET) / kOneDay).rounded(.down)
    }

    // chnsecal.cpp:596-637 (+ Apple table branch)
    func winterSolstice(_ gyear: Int) -> Int {
        if useAppleAdjustmentTables && gyear >= 1900 && gyear <= 2100 {
            let gyearadj = gyear - 1900
            var result = Int(365.243 * Double(gyearadj) - 0.3) - 25211
            let bitmap = Self.winterSolsticeAdj[gyearadj / 16]
            if bitmap != 0 {
                let bitmask = UInt16(1) << (gyearadj % 16)
                if (bitmask & bitmap) != 0 {
                    result -= 1
                }
            }
            return result
        }
        if let cached = winterSolsticeCache[gyear] { return cached }
        // In books December 15 is used, but it fails for some years with
        // this algorithm (1298, 1391, 1492, 1553, 1560) — ICU uses Dec 1.
        let ms = Self.daysToMillis(Double(Self.gregorianEpochDay(gyear, 12, 1)))
        var astro = DuffettSmithAstronomer(ms)
        let days = Self.millisToDays(astro.getSunTime(DuffettSmithAstronomer.WINTER_SOLSTICE(), true))
        let value = Int(days)
        winterSolsticeCache[gyear] = value
        return value
    }

    // chnsecal.cpp:650-663
    func newMoonNear(_ days: Double, _ after: Bool) -> Int {
        let ms = Self.daysToMillis(days)
        var astro = DuffettSmithAstronomer(ms)
        return Int(Self.millisToDays(astro.getMoonTime(DuffettSmithAstronomer.NEW_MOON, after)))
    }

    // chnsecal.cpp:672-675
    static func synodicMonthsBetween(_ day1: Int, _ day2: Int) -> Int {
        let roundme = Double(day2 - day1) / DuffettSmithAstronomer.SYNODIC_MONTH
        return Int(roundme + (roundme >= 0 ? 0.5 : -0.5))
    }

    // chnsecal.cpp:684-702
    func majorSolarTerm(_ days: Int) -> Int {
        let ms = Self.daysToMillis(Double(days))
        var astro = DuffettSmithAstronomer(ms)
        var term = (Int(6 * astro.getSunLongitude() / DuffettSmithAstronomer.PI) + 2) % 12
        if term < 1 { term += 12 }
        return term
    }

    // chnsecal.cpp:710-721
    func hasNoMajorSolarTerm(_ newMoon: Int) -> Bool {
        let term1 = majorSolarTerm(newMoon)
        let term2 = majorSolarTerm(newMoonNear(Double(newMoon + Self.SYNODIC_GAP), true))
        return term1 == term2
    }

    // chnsecal.cpp:737-762
    func isLeapMonthBetween(_ newMoon1: Int, _ newMoon2: Int) -> Bool {
        var newMoon2 = newMoon2
        while newMoon2 >= newMoon1 {
            if hasNoMajorSolarTerm(newMoon2) { return true }
            newMoon2 = newMoonNear(Double(newMoon2 - Self.SYNODIC_GAP), false)
        }
        return false
    }

    // chnsecal.cpp:997-1041 (+ Apple table branch)
    func newYear(_ gyear: Int) -> Int {
        if useAppleAdjustmentTables && gyear >= 1900 && gyear <= 2100 {
            let gyearadj = gyear - 1900
            return Int(365.244 * Double(gyearadj)) - 25532 + Int(Self.newYearAdj[gyearadj])
        }
        if let cached = newYearCache[gyear] { return cached }
        let solsticeBefore = winterSolstice(gyear - 1)
        let solsticeAfter = winterSolstice(gyear)
        let newMoon1 = newMoonNear(Double(solsticeBefore + 1), true)
        let newMoon2 = newMoonNear(Double(newMoon1 + Self.SYNODIC_GAP), true)
        let newMoon11 = newMoonNear(Double(solsticeAfter + 1), false)

        let value: Int
        if Self.synodicMonthsBetween(newMoon1, newMoon11) == 12 &&
            (hasNoMajorSolarTerm(newMoon1) || hasNoMajorSolarTerm(newMoon2)) {
            value = newMoonNear(Double(newMoon2 + Self.SYNODIC_GAP), true)
        } else {
            value = newMoon2
        }
        newYearCache[gyear] = value
        return value
    }

    // chnsecal.cpp:773-866
    func computeMonthInfo(gyear: Int, days: Int) -> MonthInfo {
        var output = MonthInfo()
        var solsticeBefore: Int
        var solsticeAfter = winterSolstice(gyear)
        if days < solsticeAfter {
            solsticeBefore = winterSolstice(gyear - 1)
        } else {
            solsticeBefore = solsticeAfter
            solsticeAfter = winterSolstice(gyear + 1)
        }
        precondition(solsticeBefore <= days && days < solsticeAfter)

        let firstMoon = newMoonNear(Double(solsticeBefore + 1), true)
        let lastMoon = newMoonNear(Double(solsticeAfter + 1), false)
        output.thisMoon = newMoonNear(Double(days + 1), false)
        output.hasLeapMonthBetweenWinterSolstices = Self.synodicMonthsBetween(firstMoon, lastMoon) == 12

        output.month = Self.synodicMonthsBetween(firstMoon, output.thisMoon)
        var theNewYear = newYear(gyear)
        if days < theNewYear {
            theNewYear = newYear(gyear - 1)
        }
        if output.hasLeapMonthBetweenWinterSolstices &&
            isLeapMonthBetween(firstMoon, output.thisMoon) {
            output.month -= 1
        }
        if output.month < 1 {
            output.month += 12
        }
        output.ordinalMonth = Self.synodicMonthsBetween(theNewYear, output.thisMoon)
        if output.ordinalMonth < 0 {
            output.ordinalMonth += 12
        }
        output.isLeapMonth = output.hasLeapMonthBetweenWinterSolstices &&
            hasNoMajorSolarTerm(output.thisMoon) &&
            !isLeapMonthBetween(firstMoon, newMoonNear(Double(output.thisMoon - Self.SYNODIC_GAP), false))
        return output
    }
}
