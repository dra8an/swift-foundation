// EXPERIMENT: ICU chnsecal RULES layer (verbatim from ChineseAstro.swift)
// driven by REINGOLD (Meeus) astronomy instead of Duffett-Smith.
// This is the prototype of the port's actual fallback design: if its labels
// match ICU at the contested leap-placement years, the CNY-month pathologies
// belong to icu4swift's simplified findNewYear heuristic, not to the engine.
// UTC+8 flat meridian (ICU convention). No Apple tables, no HKO snap.

import Foundation
import CalendarCore
import CalendarSimple
import AstronomicalEngine

final class ReingoldChineseAstro {
    static let SYNODIC_GAP = 25
    private let engine = ReingoldEngine()

    private var winterSolsticeCache: [Int: Int] = [:]
    private var newYearCache: [Int: Int] = [:]

    // epoch-day (1970) -> local UTC+8 midnight as universal Moment
    private func midnight(_ day: Int) -> Moment {
        Moment(Double(day + 719_163)) - 8.0 / 24.0
    }

    private func toLocalDay(_ moment: Moment) -> Int {
        Int(((moment + 8.0 / 24.0).inner).rounded(.down)) - 719_163
    }

    // chnsecal winterSolstice: solstice day on or after Dec 1, local day
    func winterSolstice(_ gyear: Int) -> Int {
        if let cached = winterSolsticeCache[gyear] { return cached }
        var day = ChineseAstro.gregorianEpochDay(gyear, 12, 15) - 5
        while true {
            let lon = engine.solarLongitude(at: midnight(day + 1))
            if lon >= 270.0 && lon < 350.0 { break }
            day += 1
        }
        winterSolsticeCache[gyear] = day
        return day
    }

    func newMoonNear(_ days: Double, _ after: Bool) -> Int {
        let m = midnight(Int(days.rounded(.down)))
            + (days - days.rounded(.down))
        let nm = after ? engine.newMoonAtOrAfter(m) : engine.newMoonBefore(m)
        return toLocalDay(nm)
    }

    static func synodicMonthsBetween(_ day1: Int, _ day2: Int) -> Int {
        let roundme = Double(day2 - day1) / 29.530588853
        return Int(roundme + (roundme >= 0 ? 0.5 : -0.5))
    }

    func majorSolarTerm(_ days: Int) -> Int {
        let lon = engine.solarLongitude(at: midnight(days))
        var term = (Int(lon / 30.0) + 2) % 12
        if term < 1 { term += 12 }
        return term
    }

    func hasNoMajorSolarTerm(_ newMoon: Int) -> Bool {
        majorSolarTerm(newMoon) ==
            majorSolarTerm(newMoonNear(Double(newMoon + Self.SYNODIC_GAP), true))
    }

    func isLeapMonthBetween(_ newMoon1: Int, _ newMoon2: Int) -> Bool {
        var newMoon2 = newMoon2
        while newMoon2 >= newMoon1 {
            if hasNoMajorSolarTerm(newMoon2) { return true }
            newMoon2 = newMoonNear(Double(newMoon2 - Self.SYNODIC_GAP), false)
        }
        return false
    }

    func newYear(_ gyear: Int) -> Int {
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
