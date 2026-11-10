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

import Testing

#if canImport(FoundationEssentials)
@testable import FoundationEssentials
#else
@testable import Foundation
#endif

// The moon and the first crescent. The expected values are what our code produces, and `meeusExamples` checks the engine against published values.
@Suite("Calendar Astronomy")
private struct CalendarAstronomyTests {
    private typealias Astronomy = _CalendarAstronomy

    private static let mecca = Astronomy.Location(latitude: 6427.0 / 300, longitude: 11947.0 / 300, elevation: 298, utcOffsetHours: 3)
    private static let london = Astronomy.Location(latitude: 51.5, longitude: -0.12, elevation: 20, utcOffsetHours: 0)

    // S. K. Shaukat's criterion at Mecca, as Calendrical Calculations gives it. It uses parts of a rule that the rules of the authorities do not use.
    private static let shaukat = Astronomy.VisibilityRule(observation: .sunDepression(4.5), altitude: .geocentric, criteria: [.init(minimumAltitude: 4.1, elongation: 10.6...90)], places: [mecca])

    // Moment (rata die in UT), the moon's longitude, latitude and distance, the phase, the geocentric altitude in Mecca and London, and the last new moon.
    @Test(arguments: [
        (255305.5, 305.3545431964393, -4.279481116057952, 405800799.2905781, 24.271816252084932, 44.02988893892882, 11.170907376182498, 255303.25441385602),
        (584175.25, 299.8690905571855, 0.7346515460834254, 385663647.2371281, 229.1135294877165, 3.598159549542146, 11.636692320088315, 584155.8209188968),
        (693655.75, 344.66661589765704, 5.000168625928376, 356766657.1078752, 3.9407813121345043, -32.83146633951375, 1.9898071886559023, 693655.4758907016),
        (730120.5, 223.32380952197812, 5.171148471564888, 402446863.37486273, 302.9547185481167, -11.165205663286628, 10.191102383733295, 730095.9386657061),
    ])
    func moon(_ row: (moment: Double, longitude: Double, latitude: Double, distance: Double, phase: Double, altitudeMecca: Double, altitudeLondon: Double, newMoon: Double)) {
        let moon = Astronomy.lunarPosition(at: row.moment)
        #expect(abs(moon.longitude - row.longitude) < 1e-9)
        #expect(abs(moon.latitude - row.latitude) < 1e-9)
        #expect(abs(moon.distance - row.distance) < 1e-3)
        #expect(abs(Astronomy.lunarPhase(at: row.moment) - row.phase) < 1e-9)
        #expect(abs(Astronomy.lunarAltitude(at: row.moment, Self.mecca) - row.altitudeMecca) < 1e-9)
        #expect(abs(Astronomy.lunarAltitude(at: row.moment, Self.london) - row.altitudeLondon) < 1e-9)
        // The search stops at a precision of 0.00001 days, so a rounding difference in its last steps can move the result by a few times that.
        #expect(abs(Astronomy.lunarPhase(0, atOrBefore: row.moment) - row.newMoon) < 3e-5)
    }

    // Meeus, Astronomical Algorithms, example 47.a (the moon on 1992 April 12, 0h dynamical time) and example 49.a (the new moon of 1977 February 18, 3h 37m 42s dynamical time).
    // The longitude differs by 0.00009° because Calendrical Calculations uses a shorter formula for the nutation.
    @Test func meeusExamples() {
        let moon = Astronomy.lunarPosition(at: Astronomy.universalFromDynamical(727300))
        #expect(abs(moon.longitude - 133.167265) < 0.0001)
        #expect(abs(moon.latitude - -3.229126) < 0.000001)
        #expect(abs(moon.distance - 368_409_700) < 100)
        let newMoon = Astronomy.universalFromDynamical(721768 + (3 * 3600 + 37 * 60 + 42) / 86400.0)
        #expect(abs(Astronomy.lunarPhase(0, atOrBefore: newMoon + 0.5) - newMoon) < 1.0 / 86400)
    }

    // Day (rata die), Mecca or London, sunset and dusk at 4.5 degrees (UT), and whether the Shaukat rule sees the crescent that evening.
    @Test(arguments: [
        (693655, true, 693655.6442392493, 693655.653325121, false),
        (693655, false, 693655.7369498563, 693655.7527697019, false),
        (726641, false, 726641.849409884, 726641.8713156828, false),
        (739428, false, 739428.8494514182, 739428.8712754974, true),
        (766988, true, 766988.6126361133, 766988.6224698308, false),
    ])
    func evening(_ row: (day: Int, isMecca: Bool, sunset: Double, dusk: Double, shaukat: Bool)) throws {
        let place = row.isMecca ? Self.mecca : Self.london, day = Double(row.day)
        #expect(try abs(#require(Astronomy.sunset(on: day, place)) - row.sunset) < 1e-9)
        #expect(try abs(#require(Astronomy.sunDepression(4.5, on: day, place)) - row.dusk) < 1e-9)
        #expect(Astronomy.VisibilityRule(observation: .sunDepression(4.5), altitude: .geocentric, criteria: [.init(minimumAltitude: 4.1, elongation: 10.6...90)], places: [place]).isFirstDay(row.day + 1) == row.shaukat)
    }

    // Year and month (AH), and the first day (rata die) by the Shaukat rule and by Umm al-Qura. The search starts in the middle of the month, as in Calendrical Calculations.
    @Test(arguments: [
        (1317, 7, 693539, 693539), (1337, 11, 700744, 700743), (1421, 3, 730275, 730274), (1442, 1, 737658, 737657), (1462, 11, 745041, 745040), (1566, 12, 781924, 781923),
    ])
    func monthStart(_ row: (year: Int, month: Int, shaukat: Int, ummAlQura: Int)) {
        let middle = Int(227015 + (Double((row.year - 1) * 12 + row.month) - 0.5) * Astronomy.meanSynodicMonth)
        #expect(Self.shaukat.firstVisibleDay(onOrBefore: middle) == row.shaukat)
        #expect(Astronomy.VisibilityRule.ummAlQura.firstVisibleDay(onOrBefore: middle) == row.ummAlQura)
    }

    // A day near the start of a month (rata die), and the first day of its month by the Shaukat rule and by Umm al-Qura.
    @Test(arguments: [
        (708124, 708097, 708097), (708125, 708097, 708097), (722889, 722863, 722862), (722890, 722863, 722862), (739281, 739253, 739252), (739283, 739282, 739282), (781923, 781894, 781923), (781924, 781924, 781923),
    ])
    func monthStartNearNewMoon(_ row: (day: Int, shaukat: Int, ummAlQura: Int)) {
        #expect(Self.shaukat.firstVisibleDay(onOrBefore: row.day) == row.shaukat)
        #expect(Astronomy.VisibilityRule.ummAlQura.firstVisibleDay(onOrBefore: row.day) == row.ummAlQura)
    }

    // No reference value exists for the topocentric elongation. It can differ from the geocentric one by at most the moon's parallax, about one degree.
    @Test(arguments: [255305.5, 693655.75, 739340.625, 767009.875])
    func topocentricElongation(_ moment: Double) {
        #expect(abs(Astronomy.elongation(at: moment, Self.mecca, .topocentric) - Astronomy.elongation(at: moment, Self.mecca, .geocentric)) < 1.1)
    }

    // The rules of the countries are not verified yet, so this only checks that their months have 29 or 30 days, from February 2025.
    @Test(arguments: [Astronomy.Diyanet(), Astronomy.VisibilityRule.malaysia, Astronomy.VisibilityRule.indonesia, Astronomy.VisibilityRule.singapore, Astronomy.VisibilityRule.ummAlQura] as [any Astronomy.CrescentRule])
    func monthLengths(_ rule: any _CalendarAstronomy.CrescentRule) {
        var start = rule.monthStart(onOrBefore: 739300)
        for _ in 0..<12 {
            let next = rule.monthStart(onOrBefore: start + 45)
            #expect((29...30).contains(next - start))
            start = next
        }
    }

    // The values below are what our code produced when the rules matched the official dates (2026-11-05 and 2026-11-06). They keep the rules from changing by accident.
    private static let rules: [String: any Astronomy.CrescentRule] = ["diyanet": Astronomy.Diyanet(), "malaysia": Astronomy.VisibilityRule.malaysia, "indonesia": Astronomy.VisibilityRule.indonesia, "singapore": Astronomy.VisibilityRule.singapore, "ummAlQura": Astronomy.VisibilityRule.ummAlQura]

    // Authority, Hijri year and month, and the first day (rata die).
    private static let monthStarts: [(authority: String, year: Int, month: Int, first: Int)] = [
        ("diyanet", 1402, 12, 723806), ("diyanet", 1410, 5, 726435), ("diyanet", 1414, 2, 727764), ("diyanet", 1430, 2, 733434), ("diyanet", 1435, 1, 735176),
        ("diyanet", 1439, 3, 736652),
        ("diyanet", 1442, 11, 737952), ("diyanet", 1444, 11, 738661), ("diyanet", 1446, 11, 739370), ("diyanet", 1447, 12, 739754),
        ("diyanet", 1452, 1, 741200), ("diyanet", 1452, 4, 741290), ("diyanet", 1453, 12, 741880), ("diyanet", 1455, 3, 742323), ("malaysia", 1440, 4, 737037),
        ("malaysia", 1442, 6, 737804), ("malaysia", 1443, 10, 738277), ("malaysia", 1448, 11, 740080), ("malaysia", 1449, 8, 740344),
        ("malaysia", 1458, 10, 743593), ("indonesia", 1440, 5, 737066), ("indonesia", 1440, 6, 737096), ("indonesia", 1447, 7, 739606),
        ("indonesia", 1448, 7, 739960), ("singapore", 1442, 4, 737746), ("singapore", 1442, 6, 737804), ("singapore", 1443, 2, 738041),
        ("singapore", 1443, 7, 738189), ("singapore", 1443, 10, 738278), ("singapore", 1454, 6, 742058),
        ("ummAlQura", 1444, 4, 738454), ("ummAlQura", 1447, 9, 739665), ("ummAlQura", 1452, 1, 741200), ("ummAlQura", 1453, 7, 741732),
    ]

    @Test(arguments: monthStarts)
    func authorityMonthStart(_ row: (authority: String, year: Int, month: Int, first: Int)) throws {
        #expect(try #require(Self.rules[row.authority]).monthStart(onOrBefore: row.first + 14) == row.first)
    }

    // Moment, Mecca (the official place of Umm al-Qura) or London, the altitude setting, the moon's altitude, and the topocentric elongation.
    @Test(arguments: [
        (739340.625, true, .geocentric, 23.67526040239727, 15.8070050271215),
        (739340.625, true, .observedUpperLimb, 24.21637995596738, 15.8070050271215),
        (739340.625, true, .init(refraction: .forAltitude), 22.78091448611028, 15.8070050271215),
        (739340.625, false, .topocentric, 43.8147013763784, 16.126899668071026),
        (739340.625, false, .observedUpperLimb, 44.81519127870836, 16.126899668071026),
        (739340.625, false, .init(refraction: .forAltitude), 43.832289886225084, 16.126899668071026),
        (739340.625, false, .init(fromSurface: false, refraction: .horizon, edge: .lower), 45.008861956163386, 16.126899668071026),
        (739428.6734, true, .observedUpperLimb, 15.78655878095741, 16.168425007406462),
        (739428.6734, false, .geocentric, 48.764595546437505, 16.644439589929807),
        (739428.6734, false, .init(refraction: .forAltitude), 48.131559524821945, 16.644439589929807),
    ] as [(Double, Bool, Astronomy.VisibilityRule.Altitude, Double, Double)])
    func altitudeSetting(_ row: (moment: Double, isMecca: Bool, setting: _CalendarAstronomy.VisibilityRule.Altitude, altitude: Double, elongation: Double)) {
        let place = row.isMecca ? Astronomy.Location(latitude: 21.4225, longitude: 39.8256, elevation: 295, utcOffsetHours: 3) : Self.london
        #expect(abs(Astronomy.lunarAltitude(at: row.moment, place, row.setting) - row.altitude) < 1e-9)
        #expect(abs(Astronomy.elongation(at: row.moment, place, .topocentric) - row.elongation) < 1e-9)
    }

    // The first day (rata die) of a Diyanet month and its length, from the evening of its 29th day. The values are what our code produces, and they equal Diyanet's published months.
    @Test(arguments: [
        (722390, 29), (722537, 30), (722626, 30), (722921, 29), (731013, 30), (733405, 29), (733464, 29), (734940, 29),
        (735147, 29), (735590, 30), (736269, 30), (736623, 29), (737923, 29), (738631, 30), (739340, 30), (739636, 30),
        (739724, 30), (742293, 30),
    ])
    func diyanetMonthLength(_ row: (start: Int, days: Int)) {
        #expect(Astronomy.Diyanet().isFirstDay(row.start + 29) == (row.days == 29))
    }

    // The first day (rata die) of a Malaysian month and its length, from the evening of its 29th day. The values are what our code produces, and they equal JAKIM's published months.
    @Test(arguments: [
        (736948, 29), (737215, 29), (737480, 30), (737716, 30), (737746, 29), (737775, 29), (738012, 29), (738248, 29), (738455, 30), (740315, 29),
    ])
    func malaysiaMonthLength(_ row: (start: Int, days: Int)) {
        #expect(Astronomy.VisibilityRule.malaysia.isFirstDay(row.start + 29) == (row.days == 29))
    }

    // Diyanet published these months one day later than its rule gives, so the rule alone makes each of these days a first day.
    @Test(arguments: [722655, 723334, 726789, 738660, 741879])
    func diyanetCorrection(_ day: Int) {
        #expect(Astronomy.Diyanet().isFirstDayByRule(day))
        #expect(!Astronomy.Diyanet().isFirstDay(day))
    }

    // A rule whose earlier rule never passes: the earlier rule applies to first days before `until`, the rule itself from `until` on. Umm al-Qura passes on the evenings before 739282 and 739283.
    @Test func earlierRule() {
        var never = Astronomy.VisibilityRule.ummAlQura, rule = never
        never.criteria = [.init(minimumAltitude: 90)]
        rule.earlier = [(until: 739283, rule: never)]
        #expect(!rule.isFirstDay(739282))
        #expect(rule.isFirstDay(739283))
    }

    // The Umm al-Qura table in Calendar_FixedMonth.swift: the evening of day 29 of each month gives the month length of the table. Today's rule makes AH 1423 to 1450, the table rule the years after.
    @Test(arguments: [(Astronomy.VisibilityRule.ummAlQura, 1423...1450), (.ummAlQuraTable, 1451...1600)])
    func ummAlQuraMonthLengths(_ row: (rule: _CalendarAstronomy.VisibilityRule, years: ClosedRange<Int>)) {
        let table = _CalendarFixedMonth.Arithmetic.islamicUmmAlQura
        for year in row.years {
            for month in 1...12 {
                let start = table.startOfYear(year) + table.daysBeforeMonth(year: year, month: month)
                #expect(row.rule.isFirstDay(start + 29) == (table.daysInMonth(year: year, month: month) == 29), "AH \(year)/\(month)")
            }
        }
    }
}
