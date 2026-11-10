// Hijri month-start rules decided by an astronomical criterion on the evening of the 29th day.
//
// Research code for checking the rules against officially announced dates. Each rule answers one
// question: on the evening of `day` (the 29th of a month), does the next month start tomorrow? If not,
// the month has 30 days. The criteria follow the official texts collected in
// swift-foundation's Docs/TEMP_Islamic_References (branch port/islamic-family); where a text leaves a
// definition open, the variants below try each reading.

import AstronomicalEngine
import CalendarCore
import Foundation

public enum CrescentRules {

    // MARK: - Places

    /// KACST / Umm al-Qura: the Kaaba, 21 25 21 N, 39 49 32 E, 295 m (official printed table).
    public static let makkah = Location(latitude: 21 + 25.0 / 60 + 21.0 / 3600, longitude: 39 + 49.0 / 60 + 32.0 / 3600, elevation: 295, utcOffset: 3.0 / 24)
    public static let bandaAceh = Location(latitude: 5.55, longitude: 95.32, elevation: 0, utcOffset: 7.0 / 24)
    /// Malaysia's westernmost reference point up to the end of AH 1443 (coordinates from Utusan, secondary).
    public static let tanjungChinchin = Location(latitude: 6 + 26.0 / 60 + 10.0 / 3600, longitude: 99 + 38.0 / 60 + 30.0 / 3600, elevation: 0, utcOffset: 8.0 / 24)
    /// Malaysia's westernmost reference point from 1 Muharram AH 1444 (coordinates from Utusan, secondary).
    public static let pulauPerak = Location(latitude: 5 + 41.0 / 60 + 5.0 / 3600, longitude: 98 + 56.0 / 60 + 14.0 / 3600, elevation: 0, utcOffset: 8.0 / 24)
    /// Singapore, MUIS: Tuas, 1.2949 N, 103.6305 E (official).
    public static let tuas = Location(latitude: 1.2949, longitude: 103.6305, elevation: 0, utcOffset: 8.0 / 24)
    public static let cairo = Location(latitude: 30.0444, longitude: 31.2357, elevation: 23, utcOffset: 2.0 / 24)
    /// Dar al-Ifta's 2011 list of sighting sites. No official coordinates exist; these are approximate town
    /// coordinates, good to a few kilometers.
    public static let egyptSites: [Location] = [
        Location(latitude: 29.86, longitude: 31.34, elevation: 0, utcOffset: 2.0 / 24),  // Helwan
        Location(latitude: 29.93, longitude: 31.83, elevation: 0, utcOffset: 2.0 / 24),  // Qatamiya
        Location(latitude: 29.97, longitude: 30.93, elevation: 0, utcOffset: 2.0 / 24),  // 6 October
        Location(latitude: 31.55, longitude: 25.15, elevation: 0, utcOffset: 2.0 / 24),  // Salloum
        Location(latitude: 26.16, longitude: 32.73, elevation: 0, utcOffset: 2.0 / 24),  // Qena
        Location(latitude: 24.09, longitude: 32.90, elevation: 0, utcOffset: 2.0 / 24),  // Aswan
        Location(latitude: 25.44, longitude: 30.55, elevation: 0, utcOffset: 2.0 / 24),  // al-Wahat (Kharga)
        Location(latitude: 22.60, longitude: 31.50, elevation: 0, utcOffset: 2.0 / 24),  // Toshka
        Location(latitude: 25.07, longitude: 34.89, elevation: 0, utcOffset: 2.0 / 24),  // Marsa Alam
        Location(latitude: 28.56, longitude: 33.95, elevation: 0, utcOffset: 2.0 / 24),  // St Catherine
    ]
    public static let wellington = Location(latitude: -41.2865, longitude: 174.7762, elevation: 0, utcOffset: 12.0 / 24)

    // MARK: - What the sky looks like at sunset

    public struct Evening: Sendable {
        public let sunset: Moment
        public let conjunction: Moment
        public let moonset: Moment?
        /// Moon centre altitude: geocentric; topocentric (no refraction); topocentric with refraction.
        public let altitudeGeocentric: Double
        public let altitudeTopocentric: Double
        public let altitudeApparent: Double
        public let semiDiameter: Double
        public let elongationGeocentric: Double
        public let elongationTopocentric: Double
        /// Hours from conjunction to sunset (negative if the conjunction is after sunset).
        public var ageHours: Double { (sunset - conjunction) * 24 }
        /// Minutes from sunset to moonset (negative if the moon sets first).
        public var lagMinutes: Double? { moonset.map { ($0 - sunset) * 1440 } }
    }

    /// The sky at sunset on the local date `day` at `location`, or nil if the sun does not set.
    public static func evening(_ day: RataDie, at location: Location, withMoonset: Bool = true) -> Evening? {
        guard let sunset = Astronomical.sunsetUT(nearLocalNoonOf: day, location: location) else { return nil }
        return evening(sunset: sunset, at: location, withMoonset: withMoonset)
    }

    static func evening(sunset: Moment, at location: Location, withMoonset: Bool) -> Evening {
        let geo = Astronomical.lunarHorizontal(sunset, location: location)
        let parallax = Astronomical.lunarParallax(altitude: geo.altitude, moment: sunset)
        let topo = geo.altitude - parallax
        let semiDiameter = 0.2725 * Astronomical.lunarParallaxHorizontal(sunset)
        let moonset = withMoonset ? Astronomical.moonsetUT(after: sunset - 8.0 / 24, location: location) : nil
        return Evening(
            sunset: sunset,
            conjunction: Astronomical.newMoonBefore(sunset + 0.5),
            moonset: moonset,
            altitudeGeocentric: geo.altitude,
            altitudeTopocentric: topo,
            altitudeApparent: topo + Astronomical.refraction(atTrueAltitude: topo),
            semiDiameter: semiDiameter,
            elongationGeocentric: Astronomical.geocentricElongation(sunset),
            elongationTopocentric: Astronomical.topocentricElongation(sunset, location: location))
    }

    // MARK: - Umm al-Qura (Saudi Arabia)

    public enum UmmAlQuraVariant: String, CaseIterable, Sendable {
        /// Website text: conjunction before sunset, moon sets after the sun, at Makkah.
        case twoConditions
        /// Printed 1420-1450 table: also the whole disc of the moon above the horizon after sunset
        /// (lower limb, apparent altitude, above 0).
        case threeConditions
    }

    public static func ummAlQura(_ day: RataDie, _ variant: UmmAlQuraVariant) -> Bool {
        guard let e = evening(day, at: makkah) else { return false }
        let base = e.conjunction < e.sunset && (e.moonset.map { $0 > e.sunset } ?? false)
        switch variant {
        case .twoConditions: return base
        case .threeConditions: return base && e.altitudeApparent - e.semiDiameter > 0
        }
    }

    /// The published Umm al-Qura month starts that the rule does not reproduce, as (Hijri year, month, days of the month
    /// before it). AH 1446-6 (1 Jumada II 1446 = 2 Dec 2024): on the evening of 1 Dec 2024 the moon and the sun set at
    /// the Kaaba within seconds of each other (our moonset 7 s before sunset), so the rule gives Jumada I 30 days where
    /// the published table gives 29. A precision-floor case, like Diyanet's AH 1411-5.
    public static let ummAlQuraCorrections: [(year: Int, month: Int, days: Int)] = [(1446, 6, 29)]

    /// Length in days (29 or 30) of the Umm al-Qura month that begins on `start`; `next` is the Hijri year and month of
    /// the following month. With `corrections` the result equals every published first day AH 1440–1450 (131 of 131);
    /// without them the rule alone gives 130. The rule (conjunction before sunset and moonset after sunset at the Kaaba)
    /// is the one in force since AH 1420; earlier years used other rules and are not covered.
    public static func ummAlQuraMonthLength(start: RataDie, next: (year: Int, month: Int), corrections: Bool = true) -> Int {
        if corrections, let c = ummAlQuraCorrections.first(where: { $0.year == next.year && $0.month == next.month }) { return c.days }
        return ummAlQura(start + 28, .twoConditions) ? 29 : 30
    }

    // MARK: - Egypt (Dar al-Ifta fatwa 3420, 2016)

    /// The calculation filter only: the moon sets after the sun, and moonset is at least 15 h 40 min after the
    /// conjunction. Egypt then also requires an actual sighting, which no calculation can reproduce.
    public static func egyptFilter(_ day: RataDie, at location: Location) -> Bool {
        guard let e = evening(day, at: location), let moonset = e.moonset else { return false }
        return moonset > e.sunset && (moonset - e.conjunction) * 24 >= 15 + 40.0 / 60
    }

    public static func egyptFilter(_ day: RataDie, anyOf sites: [Location]) -> Bool {
        sites.contains { egyptFilter(day, at: $0) }
    }

    /// Computed reading that the announcements suggest: the conjunction is before sunset and the moon sets at least
    /// `minimumLagMinutes` after the sun.
    public static func moonsetLag(_ day: RataDie, at location: Location, minimumLagMinutes: Double) -> Bool {
        guard let e = evening(day, at: location), let lag = e.lagMinutes else { return false }
        return e.conjunction < e.sunset && lag >= minimumLagMinutes
    }

    // MARK: - MABIMS

    public enum AltitudeKind: String, CaseIterable, Sendable { case geocentric, topocentric, apparent }
    public enum ElongationKind: String, CaseIterable, Sendable { case geocentric, topocentric }

    /// The 2021 criterion: altitude >= 3 and elongation >= 6.4 degrees at sunset at `location`.
    public static func mabims2021(_ day: RataDie, at location: Location, altitude: AltitudeKind, elongation: ElongationKind) -> Bool {
        guard let e = evening(day, at: location, withMoonset: false) else { return false }
        return value(e, altitude) >= 3 && value(e, elongation) >= 6.4
    }

    /// The 1992 criterion: altitude >= 2 and elongation >= 3 degrees, or the moon at least 8 hours old, at sunset.
    public static func mabims1992(_ day: RataDie, at location: Location, altitude: AltitudeKind, elongation: ElongationKind) -> Bool {
        guard let e = evening(day, at: location, withMoonset: false) else { return false }
        return (value(e, altitude) >= 2 && value(e, elongation) >= 3) || (e.ageHours >= 8 && value(e, altitude) > 0)
    }

    static func value(_ e: Evening, _ kind: AltitudeKind) -> Double {
        switch kind {
        case .geocentric: return e.altitudeGeocentric
        case .topocentric: return e.altitudeTopocentric
        case .apparent: return e.altitudeApparent
        }
    }

    static func value(_ e: Evening, _ kind: ElongationKind) -> Double {
        switch kind {
        case .geocentric: return e.elongationGeocentric
        case .topocentric: return e.elongationTopocentric
        }
    }

    // MARK: - Malaysia, JUPEM / eKITAB style (round 2 research)

    public struct MalaysiaOptions: Sendable, CustomStringConvertible {
        /// Take the values at the whole minute of sunset (JUPEM lists sunset as hh:mm and quotes values at it).
        public var floorToMinute = false
        /// Refraction from the Almanak Falak Syarie, modelled as 0.945 x Saemundsson at the geocentric altitude
        /// (fits the two table values eKITAB quotes: 7'54" at 6 01 43 and 5'26" at 9 21 30).
        public var almanakRefraction = false
        /// Elongation between the refracted (apparent) positions instead of the airless topocentric ones.
        public var elongationFromApparent = false
        /// Experimental, fitted to two JUPEM sheets: elongation = apparent + blend * (airless - apparent).
        public var elongationBlend: Double? = nil
        public init(floorToMinute: Bool = false, almanakRefraction: Bool = false, elongationFromApparent: Bool = false, elongationBlend: Double? = nil) {
            self.floorToMinute = floorToMinute
            self.almanakRefraction = almanakRefraction
            self.elongationFromApparent = elongationFromApparent
            self.elongationBlend = elongationBlend
        }
        public var description: String {
            "minute \(floorToMinute ? "floored" : "exact"), refraction \(almanakRefraction ? "almanak" : "standard"), elongation \(elongationBlend.map { "blend \($0)" } ?? (elongationFromApparent ? "apparent" : "airless"))"
        }
    }

    public struct MalaysiaValues: Sendable {
        public let altitude: Double
        public let elongation: Double
        public let ageHours: Double
    }

    public static func malaysiaValues(_ day: RataDie, at location: Location, _ o: MalaysiaOptions) -> MalaysiaValues? {
        guard let sunset = Astronomical.sunsetUT(nearLocalNoonOf: day, location: location) else { return nil }
        let t = o.floorToMinute ? Moment((sunset.inner * 1440).rounded(.down) / 1440) : sunset
        let moon = Astronomical.lunarHorizontal(t, location: location)
        let topo = moon.altitude - Astronomical.lunarParallax(altitude: moon.altitude, moment: t)
        let refraction = o.almanakRefraction ? 0.945 * Astronomical.refraction(atTrueAltitude: moon.altitude)
                                              : Astronomical.refraction(atTrueAltitude: topo)
        let apparent = topo + refraction
        let sun = Astronomical.solarHorizontal(t, location: location)
        func separation(_ moonAltitude: Double, _ sunAltitude: Double) -> Double {
            let cosE = sinDeg(moonAltitude) * sinDeg(sunAltitude) + cosDeg(moonAltitude) * cosDeg(sunAltitude) * cosDeg(moon.azimuth - sun.azimuth)
            return acos(min(1, max(-1, cosE))) * 180 / .pi
        }
        let airless = separation(topo, sun.altitude)
        let refracted = separation(apparent, sun.altitude + Astronomical.refraction(atTrueAltitude: sun.altitude))
        let elongation = o.elongationBlend.map { refracted + $0 * (airless - refracted) } ?? (o.elongationFromApparent ? refracted : airless)
        return MalaysiaValues(altitude: apparent, elongation: elongation, ageHours: (t - Astronomical.newMoonBefore(t + 0.5)) * 24)
    }

    /// Malaysia's rule with the options: 2021 criterion from AH 1443, 1992 criterion before.
    public static func malaysia(_ day: RataDie, at location: Location, newCriterion: Bool, _ o: MalaysiaOptions) -> Bool {
        guard let v = malaysiaValues(day, at: location, o) else { return false }
        if newCriterion { return v.altitude >= 3 && v.elongation >= 6.4 }
        return (v.altitude >= 2 && v.elongation >= 3) || (v.ageHours >= 8 && v.altitude > 0)
    }

    static func sinDeg(_ x: Double) -> Double { sin(x * .pi / 180) }
    static func cosDeg(_ x: Double) -> Double { cos(x * .pi / 180) }

    // MARK: - Diyanet (2016 Istanbul congress, 1978 thresholds)

    public struct DiyanetResult: Sendable {
        /// Criterion met at some sunset before 00:00 UTC, by latitude limit (nil = no limit) and altitude kind.
        public var beforeMidnight: [String: Bool] = [:]
        /// Criterion met at a sunset in mainland America after 00:00 UTC, by latitude limit and altitude kind.
        public var americas: [String: Bool] = [:]
        /// Criterion met at a sunset after 00:00 UTC anywhere (ocean included) on the same local evening; the
        /// 1978 reading of "anywhere on Earth" without the 2016 clauses. Keyed like `americas`.
        public var anywhereLate: [String: Bool] = [:]
        /// The conjunction comes before dawn (sun 18 degrees below) in Wellington.
        public var conjunctionBeforeWellingtonDawn = false
    }

    /// Evaluates every Diyanet reading for the evening of UTC date `day`, without a search grid.
    ///
    /// Main test (a sunset before 00:00 UTC anywhere): along a latitude the moon at sunset is higher and further from
    /// the sun the later the sunset, so the best place on each latitude is where the sun sets at exactly 00:00 UTC.
    /// The test therefore looks at the moon at 00:00 UTC along that sunset line, every 0.1 degree of latitude.
    ///
    /// America exception (a sunset after 00:00 UTC on the American mainland): by the same argument the best place on
    /// each latitude is the westernmost point of the mainland, checked every 0.05 degree of latitude.
    public static func diyanet(_ day: RataDie, refractionScale: Double = 1) -> DiyanetResult {
        var result = DiyanetResult()
        let midnight = Moment(Double(day.dayNumber) + 1)
        let kinds: [AltitudeKind] = [.geocentric, .topocentric, .apparent]
        let conjunctionBeforeMidnight = Astronomical.newMoonBefore(midnight)
        result.conjunctionBeforeWellingtonDawn = wellingtonDawnCheck(day, conjunction: conjunctionBeforeMidnight)

        // A new crescent only: the moment must come after this lunation's conjunction. Without this check the old,
        // waning moon passes the criterion at polar sunsets before the conjunction (that was what the unofficial
        // 60-degree latitude limit used to hide on the search grid).
        let conjunction = Astronomical.newMoonBefore(midnight + 0.5)
        func record(_ moment: Moment, _ location: Location, americas: Bool, late: Bool = false) {
            guard moment > conjunction, moment - conjunction < 3 else { return }
            let geo = Astronomical.lunarHorizontal(moment, location: location).altitude
            guard geo >= 4 else { return }
            let topo = geo - Astronomical.lunarParallax(altitude: geo, moment: moment)
            let apparent = topo + refractionScale * Astronomical.refraction(atTrueAltitude: topo)
            for kind in kinds {
                let altitude = kind == .geocentric ? geo : (kind == .topocentric ? topo : apparent)
                guard altitude >= 5 else { continue }
                if late {
                    result.anywhereLate["none/\(kind)"] = true
                    if abs(location.latitude) <= 60 { result.anywhereLate["60/\(kind)"] = true }
                } else if americas {
                    result.americas["none/\(kind)"] = true
                    if abs(location.latitude) <= 60 { result.americas["60/\(kind)"] = true }
                } else {
                    result.beforeMidnight["none/\(kind)"] = true
                    if abs(location.latitude) <= 60 { result.beforeMidnight["60/\(kind)"] = true }
                }
            }
        }

        // Main test. Geocentric elongation does not depend on the place.
        if Astronomical.geocentricElongation(midnight) >= 8 {
            for k in -880...880 {
                let lat = Double(k) / 10
                guard let lon = sunsetLongitude(at: midnight, latitude: lat) else { continue }
                record(midnight, Location(latitude: lat, longitude: lon, elevation: 0, utcOffset: 0), americas: false)
            }
        }
        // America exception. American sunsets come before midnight + 12 h, and the elongation only grows.
        if Astronomical.geocentricElongation(midnight + 0.5) >= 8 {
            for (i, lon) in americanWestCoast.enumerated() {
                let location = Location(latitude: 71.95 - 0.05 * Double(i), longitude: lon, elevation: 0, utcOffset: 0)
                guard let sunset = Astronomical.sunsetUT(nearLocalNoonOf: day, location: location), sunset >= midnight,
                      Astronomical.geocentricElongation(sunset) >= 8 else { continue }
                record(sunset, location, americas: true)
            }
            // Anywhere after 00:00 UTC: the latest sunset of this local evening is just east of the date line.
            for k in -352...352 {
                let location = Location(latitude: Double(k) / 4, longitude: -179.999, elevation: 0, utcOffset: 0)
                guard let sunset = Astronomical.sunsetUT(nearLocalNoonOf: day, location: location), sunset >= midnight,
                      Astronomical.geocentricElongation(sunset) >= 8 else { continue }
                record(sunset, location, americas: false, late: true)
            }
        }
        return result
    }

    /// Longitude (degrees east) where the sun is setting (upper limb at the standard -50' horizon) at `moment`, at
    /// latitude `lat`, or nil if the sun does not set there that day.
    static func sunsetLongitude(at moment: Moment, latitude lat: Double) -> Double? {
        let lambda = Astronomical.solarLongitude(Astronomical.julianCenturies(moment))
        let alpha = Astronomical.rightAscension(moment, beta: 0, lambda: lambda)
        let delta = Astronomical.declination(moment, beta: 0, lambda: lambda)
        let cosH0 = (sinDeg(-50.0 / 60) - sinDeg(lat) * sinDeg(delta)) / (cosDeg(lat) * cosDeg(delta))
        guard cosH0 >= -1, cosH0 <= 1 else { return nil }
        // Hour angle = sidereal time + longitude - right ascension; at sunset it is +H0.
        var lon = (acos(cosH0) * 180 / .pi - Astronomical.siderealFromMoment(moment) + alpha).truncatingRemainder(dividingBy: 360)
        if lon < -180 { lon += 360 }
        if lon >= 180 { lon -= 360 }
        return lon
    }

    /// The conjunction comes before dawn (sun 18 degrees below the horizon) in Wellington on the next local
    /// morning, which falls in the afternoon of UTC date `day`.
    static func wellingtonDawnCheck(_ day: RataDie, conjunction: Moment) -> Bool {
        guard let dawn = Astronomical.dawnUT(after: Moment(Double(day.dayNumber) + 0.25), location: wellington, depression: 18) else { return false }
        // Only this lunation's conjunction counts: newMoonBefore returns the previous one when the new moon
        // falls after midnight, about 29 days earlier.
        return conjunction < dawn && dawn - conjunction < 2
    }

    // MARK: - Diyanet's published calendar: the rule of each computation era, and the corrections

    /// How Diyanet decided month starts in each computation era, found by matching every published date AH 1399–1457
    /// (`Docs/CRESCENT_RULES_RESULTS.md`, Rounds 4–6). The era is that of the Gregorian calendar year in which the new
    /// month's first day falls, because Diyanet computes one calendar year at a time.
    public enum DiyanetEra: Sendable {
        /// Through 2008: the month starts when the criterion (apparent altitude ≥ 5° and geocentric elongation ≥ 8°
        /// at sunset) is met somewhere on Earth at a sunset before 00:00 UTC (the 1978 Istanbul conference rule).
        case before2009
        /// 2009–2013: as before, or, after 00:00 UTC, when the criterion is met at a sunset west of 30° W at a
        /// latitude of at least 10° N.
        case years2009to2013
        /// 2014–2016: the 1978 rule only.
        case years2014to2016
        /// 2017 onward: the 2016 Istanbul congress rule: as 1978, or, after 00:00 UTC, when the criterion is met at a
        /// sunset on the American mainland and the conjunction precedes dawn (sun 18° below) in Wellington.
        case from2017

        public init(firstDay: RataDie) {
            let d = firstDay.dayNumber
            if d < 733408 { self = .before2009 }            // before 2009-01-01
            else if d < 735234 { self = .years2009to2013 }  // before 2014-01-01
            else if d < 736330 { self = .years2014to2016 }  // before 2017-01-01
            else { self = .from2017 }
        }
    }

    /// The published Diyanet month starts that the era rules do not reproduce, as (Hijri year, month) of the month that
    /// Diyanet started one day later than the rule. Each is analysed in `Docs/CRESCENT_RULES_RESULTS.md` § Round 6:
    /// 1399-9 (26 Jul 1979, the last year before the computed rule was in force), 1401-8 (4 Jun 1981) and 1411-5
    /// (19 Nov 1990, decisive moment within a minute of the cut-off), 1444-11 (21 May 2023, the 2023–2027 run's
    /// mainland definition), 1453-12 (13 Mar 2032, 3.6 minutes of sunset at the tip of the Seward Peninsula).
    public static let diyanetCorrections: [(year: Int, month: Int)] = [(1399, 9), (1401, 8), (1411, 5), (1444, 11), (1453, 12)]

    /// Length in days (29 or 30) of the Diyanet month that begins on `start`; `next` is the Hijri year and month of the
    /// following month. With `corrections` the result equals every published date AH 1399–1457 (707 of 707); without
    /// them the era rules alone give 702, the five months in `diyanetCorrections` coming out 29 instead of 30.
    public static func diyanetMonthLength(start: RataDie, next: (year: Int, month: Int), corrections: Bool = true) -> Int {
        if corrections, diyanetCorrections.contains(where: { $0.year == next.year && $0.month == next.month }) { return 30 }
        return diyanetStartsTomorrow(evening: start + 28, era: DiyanetEra(firstDay: start + 29)) ? 29 : 30
    }

    /// Does the next month begin on the day after the evening of UTC date `day` (the 29th), under the rule of `era`?
    public static func diyanetStartsTomorrow(evening day: RataDie, era: DiyanetEra) -> Bool {
        let midnight = Moment(Double(day.dayNumber) + 1)
        let conjunction = Astronomical.newMoonBefore(midnight + 0.5)
        guard midnight.inner + 0.5 - conjunction.inner < 3 else { return false }   // no new crescent this evening
        func meets(_ moment: Moment, _ location: Location) -> Bool {
            guard moment > conjunction, moment - conjunction < 3 else { return false }
            let geo = Astronomical.lunarHorizontal(moment, location: location).altitude
            guard geo >= 4 else { return false }
            let topo = geo - Astronomical.lunarParallax(altitude: geo, moment: moment)
            return topo + Astronomical.refraction(atTrueAltitude: topo) >= 5
        }
        // The 1978 rule: on each latitude the best place is where the sun sets at exactly 00:00 UTC.
        if Astronomical.geocentricElongation(midnight) >= 8 {
            for k in -880...880 {
                let lat = Double(k) / 10
                guard let lon = sunsetLongitude(at: midnight, latitude: lat) else { continue }
                if meets(midnight, Location(latitude: lat, longitude: lon, elevation: 0, utcOffset: 0)) { return true }
            }
        }
        switch era {
        case .before2009, .years2014to2016:
            return false
        case .years2009to2013:
            // The latest sunset of this evening west of 30 W is just east of the date line.
            guard Astronomical.geocentricElongation(midnight + 0.5) >= 8 else { return false }
            for k in 40...352 {   // 10 N … 88 N
                let location = Location(latitude: Double(k) / 4, longitude: -179.999, elevation: 0, utcOffset: 0)
                guard let sunset = Astronomical.sunsetUT(nearLocalNoonOf: day, location: location), sunset >= midnight,
                      Astronomical.geocentricElongation(sunset) >= 8 else { continue }
                if meets(sunset, location) { return true }
            }
            return false
        case .from2017:
            guard wellingtonDawnCheck(day, conjunction: Astronomical.newMoonBefore(midnight)),
                  Astronomical.geocentricElongation(midnight + 0.5) >= 8 else { return false }
            for (i, lon) in americanWestCoast.enumerated() {
                let location = Location(latitude: 71.95 - 0.05 * Double(i), longitude: lon, elevation: 0, utcOffset: 0)
                guard let sunset = Astronomical.sunsetUT(nearLocalNoonOf: day, location: location), sunset >= midnight,
                      Astronomical.geocentricElongation(sunset) >= 8 else { continue }
                if meets(sunset, location) { return true }
            }
            return false
        }
    }

    /// Westernmost American mainland longitude at the nearest 0.05-degree latitude row, or nil outside 71.95 N … 53.85 S.
    static func americanWestCoastLongitude(latitude lat: Double) -> Double? {
        let i = Int(((71.95 - lat) / 0.05).rounded())
        guard i >= 0, i < americanWestCoast.count else { return nil }
        return americanWestCoast[i]
    }

    /// Whether a point lies east of (or on) the westernmost American mainland coast at its latitude (nearest 0.05-degree row).
    static func isEastOfAmericanWestCoast(latitude lat: Double, longitude lon: Double) -> Bool {
        let i = Int(((71.95 - lat) / 0.05).rounded())
        guard i >= 0, i < americanWestCoast.count else { return false }
        return lon >= americanWestCoast[i] - 1e-9
    }

    /// Westernmost point of the American mainland (no islands), degrees east, every 0.05 degree of latitude from
    /// 71.95 N down to 53.85 S. Computed from Natural Earth 1:10m land v5.1.2 (public domain): the single polygon
    /// that contains both North and South America (Research/crescent/naturalearth/coast_fine.py).
    static let americanWestCoast: [Double] = [
        -95.219, -95.254, -95.198, -95.252, -95.287, -95.560, -95.685, -95.906, -95.935, -95.658, -95.523, -156.506, -156.690, -156.830,
        -156.931, -157.030, -157.096, -157.182, -157.290, -157.426, -157.574, -157.751, -159.376, -159.678, -159.768, -159.915, -160.074, -160.182,
        -160.292, -160.422, -160.620, -160.785, -160.853, -161.965, -162.046, -162.133, -162.256, -162.346, -162.490, -162.491, -162.562, -162.680,
        -162.800, -162.926, -163.011, -162.947, -163.059, -163.149, -163.070, -163.090, -163.122, -163.207, -163.246, -163.305, -163.393, -163.481,
        -163.569, -163.676, -163.816, -163.981, -164.217, -164.901, -166.228, -166.198, -166.200, -166.205, -166.224, -166.239, -166.262, -166.303,
        -166.357, -166.634, -166.819, -166.299, -166.149, -166.037, -165.957, -165.700, -165.404, -165.240, -165.101, -164.976, -164.857, -164.647,
        -164.530, -164.414, -164.251, -164.115, -164.029, -163.963, -163.915, -163.867, -163.821, -163.797, -163.781, -163.774, -163.768, -163.643,
        -163.120, -162.464, -162.501, -162.638, -162.613, -162.536, -162.505, -162.196, -162.117, -164.303, -164.722, -164.832, -164.954, -165.496,
        -165.673, -165.816, -165.883, -165.669, -166.396, -166.599, -166.746, -166.882, -166.888, -167.334, -167.470, -167.569, -167.916, -168.086,
        -168.132, -168.093, -167.900, -167.709, -167.591, -167.369, -166.855, -166.219, -166.922, -166.948, -166.954, -166.872, -166.725, -166.698,
        -166.570, -166.449, -166.409, -166.480, -166.475, -166.454, -166.387, -166.240, -165.887, -165.369, -165.046, -162.817, -162.806, -161.083,
        -160.973, -160.951, -160.948, -160.946, -160.929, -160.887, -160.844, -160.803, -160.779, -160.775, -160.791, -160.847, -160.934, -161.039,
        -162.295, -162.276, -162.359, -162.434, -162.500, -162.566, -164.227, -164.439, -164.553, -164.537, -164.340, -164.741, -164.794, -164.833,
        -164.867, -164.767, -164.867, -164.841, -164.826, -164.751, -164.806, -165.154, -165.246, -165.317, -165.371, -165.451, -165.510, -165.569,
        -165.665, -165.710, -165.746, -165.756, -165.727, -165.658, -165.663, -166.088, -166.030, -166.169, -166.185, -166.197, -166.166, -166.109,
        -165.801, -165.921, -165.886, -165.686, -165.640, -165.623, -165.625, -165.562, -164.952, -165.149, -165.177, -164.948, -164.876, -164.976,
        -165.002, -165.018, -165.148, -165.268, -165.427, -165.233, -165.143, -165.092, -165.011, -164.792, -164.645, -164.530, -164.488, -164.422,
        -164.273, -164.122, -164.211, -164.193, -164.139, -163.880, -161.938, -161.884, -161.866, -161.827, -161.770, -161.715, -161.831, -161.901,
        -161.969, -162.023, -162.044, -162.013, -161.984, -161.941, -161.702, -161.829, -161.792, -161.791, -161.771, -161.764, -161.800, -161.859,
        -162.161, -161.770, -159.178, -159.127, -159.034, -158.949, -157.564, -157.546, -157.518, -157.398, -157.568, -157.607, -157.614, -157.625,
        -157.633, -157.639, -157.655, -157.677, -157.702, -157.705, -157.709, -157.600, -157.799, -157.930, -157.993, -158.073, -158.214, -158.333,
        -158.402, -158.471, -158.540, -158.609, -158.660, -158.690, -158.691, -158.689, -158.978, -159.064, -159.202, -159.219, -159.395, -159.666,
        -159.823, -159.911, -160.008, -160.150, -160.226, -160.320, -160.389, -160.425, -160.461, -160.474, -160.527, -161.239, -161.472, -161.729,
        -161.883, -161.987, -162.110, -162.220, -162.292, -162.359, -162.427, -162.494, -162.568, -162.494, -162.671, -162.792, -162.890, -163.112,
        -163.243, -163.320, -163.298, -163.287, -163.341, -163.325, -163.381, -130.913, -130.196, -130.316, -130.367, -130.414, -130.440, -130.433,
        -130.452, -130.480, -130.460, -130.241, -130.261, -130.215, -130.053, -130.085, -130.089, -130.084, -130.102, -130.056, -129.990, -129.915,
        -129.799, -129.724, -129.700, -129.646, -129.560, -129.487, -129.413, -129.339, -128.871, -128.870, -128.789, -128.703, -128.575, -128.500,
        -128.523, -128.514, -128.504, -128.498, -128.450, -128.278, -128.127, -128.155, -128.192, -128.224, -128.240, -128.232, -128.233, -128.307,
        -128.339, -128.388, -127.886, -127.395, -127.523, -127.622, -127.649, -127.658, -127.778, -127.863, -127.881, -127.885, -127.874, -127.878,
        -127.842, -127.827, -127.792, -127.753, -127.612, -127.662, -127.790, -127.573, -127.754, -127.794, -127.738, -127.667, -127.516, -127.523,
        -127.441, -127.249, -127.102, -126.196, -126.122, -126.219, -126.106, -126.250, -126.186, -126.232, -125.726, -125.064, -125.089, -124.653,
        -124.608, -124.621, -124.656, -124.699, -124.827, -124.785, -124.723, -124.631, -124.540, -124.516, -124.295, -124.040, -124.067, -124.025,
        -123.993, -123.914, -123.735, -123.585, -123.276, -123.162, -123.236, -123.201, -123.200, -123.085, -123.131, -123.092, -122.813, -122.766,
        -122.734, -122.703, -122.664, -122.523, -122.496, -122.444, -122.509, -122.669, -122.666, -122.553, -124.707, -124.674, -124.703, -124.696,
        -124.723, -124.689, -124.688, -124.675, -124.655, -124.631, -124.553, -124.481, -124.446, -124.412, -124.391, -124.372, -124.352, -124.349,
        -124.338, -124.327, -124.281, -124.252, -124.222, -124.204, -124.190, -124.178, -124.173, -124.172, -124.176, -124.125, -124.115, -124.101,
        -124.096, -123.821, -124.067, -124.064, -124.062, -124.061, -124.061, -124.062, -124.065, -124.076, -123.920, -123.990, -123.966, -123.943,
        -123.931, -123.927, -123.978, -123.961, -123.958, -123.965, -123.968, -123.938, -123.940, -123.950, -123.953, -123.968, -123.969, -123.965,
        -123.981, -123.960, -123.969, -123.969, -123.972, -123.989, -124.011, -124.011, -124.022, -124.032, -124.049, -124.068, -124.061, -124.065,
        -124.060, -124.065, -124.075, -124.084, -124.082, -124.086, -124.096, -124.113, -124.114, -124.114, -124.119, -124.126, -124.133, -124.123,
        -124.144, -124.149, -124.158, -124.168, -124.180, -124.197, -124.211, -124.221, -124.237, -124.260, -124.283, -124.311, -124.346, -124.395,
        -124.390, -124.403, -124.416, -124.429, -124.439, -124.460, -124.483, -124.512, -124.545, -124.531, -124.515, -124.465, -124.410, -124.403,
        -124.399, -124.416, -124.428, -124.427, -124.430, -124.412, -124.412, -124.377, -124.366, -124.352, -124.296, -124.215, -124.204, -124.210,
        -124.219, -124.243, -124.216, -124.144, -124.132, -124.103, -124.090, -124.078, -124.066, -124.068, -124.080, -124.089, -124.104, -124.119,
        -124.141, -124.161, -124.138, -124.115, -124.130, -124.151, -124.175, -124.208, -124.244, -124.274, -124.309, -124.334, -124.364, -124.384,
        -124.405, -124.385, -124.365, -124.354, -124.351, -124.281, -124.205, -124.109, -124.081, -124.021, -123.971, -123.926, -123.888, -123.842,
        -123.833, -123.801, -123.787, -123.787, -123.770, -123.793, -123.814, -123.821, -123.825, -123.800, -123.785, -123.770, -123.737, -123.710,
        -123.693, -123.700, -123.739, -123.697, -123.649, -123.579, -123.525, -123.449, -123.405, -123.364, -123.306, -123.225, -123.130, -123.097,
        -123.069, -123.064, -122.969, -122.966, -122.950, -122.969, -122.990, -123.022, -122.781, -122.713, -122.566, -122.481, -122.513, -122.501,
        -122.495, -122.505, -122.517, -122.501, -122.446, -122.425, -122.401, -122.407, -122.418, -122.405, -122.359, -122.285, -122.241, -122.184,
        -122.070, -121.843, -121.813, -121.792, -121.802, -121.812, -121.830, -121.964, -121.932, -121.943, -121.929, -121.912, -121.900, -121.883,
        -121.836, -121.733, -121.665, -121.625, -121.592, -121.504, -121.483, -121.463, -121.411, -121.355, -121.321, -121.301, -121.226, -121.130,
        -121.102, -121.049, -120.952, -120.870, -120.864, -120.881, -120.898, -120.843, -120.658, -120.635, -120.633, -120.643, -120.660, -120.668,
        -120.617, -120.625, -120.633, -120.604, -120.619, -120.642, -120.572, -120.497, -120.472, -119.738, -119.426, -119.346, -119.268, -119.250,
        -119.219, -119.127, -118.958, -118.808, -118.445, -118.422, -118.399, -118.405, -118.414, -118.054, -117.995, -117.904, -117.807, -117.749,
        -117.667, -117.607, -117.532, -117.478, -117.435, -117.391, -117.351, -117.319, -117.303, -117.277, -117.266, -117.256, -117.275, -117.266,
        -117.255, -117.257, -117.152, -117.135, -117.128, -117.124, -117.115, -117.087, -117.063, -117.037, -116.954, -116.914, -116.894, -116.883,
        -116.877, -116.854, -116.757, -116.716, -116.616, -116.613, -116.749, -116.672, -116.651, -116.663, -116.671, -116.608, -116.547, -116.493,
        -116.461, -116.418, -116.370, -116.333, -116.310, -116.317, -116.323, -116.336, -116.245, -116.208, -116.143, -116.058, -116.043, -116.035,
        -116.032, -116.034, -116.041, -116.047, -116.034, -116.015, -115.842, -115.816, -115.800, -115.797, -115.804, -115.785, -115.789, -115.802,
        -115.751, -115.702, -115.690, -115.689, -115.690, -115.628, -115.546, -115.429, -115.349, -115.246, -115.203, -115.043, -114.944, -114.892,
        -114.844, -114.792, -114.734, -114.708, -114.611, -114.604, -114.548, -114.447, -114.405, -114.365, -114.347, -114.287, -114.168, -114.155,
        -114.095, -114.070, -114.045, -114.062, -114.079, -114.103, -114.117, -114.064, -114.095, -114.102, -114.165, -114.207, -114.256, -114.276,
        -115.083, -115.047, -115.028, -114.939, -114.847, -114.781, -114.750, -114.661, -114.574, -114.504, -114.489, -114.486, -114.487, -114.430,
        -114.327, -114.109, -114.063, -114.030, -113.818, -113.779, -113.749, -113.725, -113.653, -113.096, -113.057, -113.061, -113.004, -112.917,
        -112.847, -112.778, -112.712, -112.606, -112.522, -112.362, -112.330, -112.313, -112.293, -112.204, -112.177, -112.162, -112.138, -112.120,
        -112.105, -112.102, -112.101, -112.100, -112.103, -112.063, -112.079, -112.084, -112.075, -112.076, -112.082, -112.117, -112.137, -112.138,
        -112.126, -112.136, -112.165, -112.159, -112.101, -112.097, -112.021, -111.895, -111.847, -111.826, -111.818, -111.627, -111.602, -111.517,
        -111.471, -111.395, -111.295, -111.202, -111.113, -111.035, -110.978, -110.917, -110.867, -110.808, -110.763, -110.714, -110.664, -110.602,
        -110.504, -110.389, -110.318, -110.284, -110.249, -110.222, -110.192, -110.162, -110.155, -110.144, -110.129, -110.115, -110.107, -110.086,
        -110.059, -110.007, -106.049, -105.974, -105.912, -105.867, -105.813, -105.773, -105.760, -105.731, -105.714, -105.699, -105.683, -105.668,
        -105.654, -105.649, -105.650, -105.654, -105.657, -105.650, -105.629, -105.596, -105.562, -105.533, -105.506, -105.478, -105.455, -105.412,
        -105.327, -105.204, -105.186, -105.224, -105.241, -105.231, -105.222, -105.219, -105.232, -105.231, -105.244, -105.327, -105.376, -105.419,
        -105.462, -105.485, -105.459, -105.298, -105.248, -105.238, -105.287, -105.439, -105.639, -105.696, -105.674, -105.629, -105.596, -105.553,
        -105.547, -105.545, -105.531, -105.502, -105.466, -105.437, -105.388, -105.349, -105.318, -105.281, -105.232, -105.168, -105.087, -105.081,
        -105.070, -105.025, -105.001, -104.922, -104.805, -104.690, -104.594, -104.449, -104.329, -104.266, -104.136, -104.032, -103.954, -103.881,
        -103.807, -103.752, -103.698, -103.710, -103.632, -103.582, -103.556, -103.534, -103.508, -103.418, -103.293, -103.120, -102.939, -102.824,
        -102.609, -102.426, -102.265, -101.834, -101.775, -101.749, -101.687, -101.647, -101.599, -101.479, -101.442, -101.380, -101.252, -101.177,
        -101.105, -101.055, -100.999, -100.838, -100.706, -100.549, -100.401, -100.259, -100.120, -99.973, -99.924, -99.837, -99.767, -99.669,
        -99.297, -99.108, -98.946, -98.725, -98.685, -98.628, -98.574, -98.507, -98.297, -98.163, -98.057, -97.966, -97.891, -97.807,
        -97.474, -97.154, -97.056, -96.991, -96.875, -96.659, -93.409, -93.348, -93.287, -93.224, -93.171, -93.125, -93.079, -93.007,
        -92.954, -92.875, -92.834, -92.792, -92.746, -92.701, -92.651, -92.601, -92.551, -92.501, -92.449, -92.398, -92.344, -92.293,
        -92.250, -92.180, -92.109, -92.040, -91.984, -91.927, -91.861, -91.790, -91.713, -91.629, -91.535, -91.419, -91.287, -90.523,
        -90.382, -90.267, -90.144, -90.031, -89.926, -89.841, -89.827, -89.551, -89.200, -89.112, -89.016, -88.906, -88.796, -88.536,
        -87.422, -87.310, -87.588, -87.646, -87.684, -87.675, -87.608, -87.525, -87.458, -87.416, -87.372, -87.309, -87.238, -87.193,
        -87.168, -87.082, -87.009, -86.933, -86.850, -86.776, -86.751, -86.732, -86.705, -86.670, -86.625, -86.602, -86.552, -86.523,
        -86.484, -86.417, -86.370, -86.310, -86.222, -86.169, -86.110, -86.048, -86.002, -85.918, -85.873, -85.828, -85.799, -85.748,
        -85.669, -85.713, -85.714, -85.941, -85.795, -85.689, -85.663, -85.661, -85.681, -85.652, -85.723, -85.801, -85.777, -85.836,
        -85.867, -85.846, -85.846, -85.831, -85.811, -85.787, -85.754, -85.713, -85.674, -85.629, -85.399, -85.292, -85.253, -85.211,
        -85.174, -85.140, -84.574, -84.364, -84.191, -84.177, -84.034, -83.930, -83.871, -83.788, -83.759, -83.690, -83.640, -83.616,
        -83.621, -83.606, -83.585, -83.637, -83.642, -83.654, -83.723, -83.737, -83.678, -83.624, -83.581, -83.372, -83.131, -83.067,
        -82.998, -82.956, -82.927, -82.899, -82.911, -81.665, -81.639, -81.621, -81.567, -81.586, -81.554, -81.481, -81.289, -80.972,
        -80.947, -80.960, -80.913, -80.921, -80.892, -80.917, -80.906, -77.854, -77.789, -77.741, -77.698, -77.660, -77.686, -77.700,
        -77.696, -77.573, -77.549, -77.537, -77.414, -77.376, -77.344, -77.361, -77.378, -77.385, -77.378, -77.477, -77.479, -77.484,
        -77.464, -77.423, -77.388, -77.367, -77.325, -77.313, -77.279, -77.252, -77.244, -77.262, -77.318, -77.456, -77.517, -77.557,
        -77.403, -77.408, -77.379, -77.360, -77.355, -77.363, -77.373, -77.371, -77.369, -77.367, -77.358, -77.353, -77.348, -77.315,
        -77.325, -77.300, -77.319, -77.319, -77.320, -77.330, -77.342, -77.354, -77.385, -77.359, -77.248, -77.376, -77.435, -77.432,
        -77.412, -77.419, -77.380, -77.296, -77.271, -77.151, -77.198, -77.147, -77.193, -77.223, -77.311, -77.329, -77.343, -77.367,
        -77.463, -77.469, -77.539, -77.529, -77.565, -77.617, -77.668, -77.707, -77.631, -77.715, -77.695, -77.783, -77.812, -77.798,
        -78.261, -78.406, -78.458, -78.499, -78.541, -78.587, -78.613, -78.639, -78.677, -78.698, -78.701, -78.689, -78.678, -78.667,
        -78.594, -78.593, -78.549, -78.871, -78.918, -78.952, -79.018, -78.985, -78.904, -78.855, -78.816, -78.827, -78.864, -78.862,
        -78.892, -79.079, -79.117, -79.165, -79.481, -79.661, -79.771, -79.820, -79.952, -80.085, -80.105, -80.108, -80.085, -80.030,
        -80.018, -80.043, -80.040, -80.013, -80.039, -80.048, -80.046, -80.038, -80.040, -80.049, -80.073, -80.114, -80.153, -80.195,
        -80.246, -80.340, -80.384, -80.407, -80.446, -80.491, -80.464, -80.450, -80.438, -80.423, -80.476, -80.500, -80.517, -80.528,
        -80.538, -80.558, -80.826, -80.865, -80.911, -80.901, -80.880, -80.851, -80.818, -80.776, -80.744, -80.763, -80.767, -80.820,
        -80.817, -80.854, -80.829, -80.807, -80.778, -80.760, -80.747, -80.734, -80.733, -80.755, -80.738, -80.745, -80.795, -80.994,
        -80.942, -80.923, -80.841, -80.700, -80.620, -80.568, -80.526, -80.483, -80.395, -80.333, -79.805, -79.831, -79.848, -79.863,
        -79.876, -79.878, -79.899, -79.926, -79.938, -79.955, -80.086, -80.112, -80.322, -80.341, -80.362, -80.517, -80.559, -80.597,
        -80.671, -80.755, -80.816, -80.848, -80.862, -80.906, -80.972, -81.011, -81.045, -81.087, -81.139, -81.196, -81.262, -81.290,
        -81.285, -81.281, -81.311, -81.321, -81.308, -81.316, -81.312, -81.320, -81.276, -81.230, -81.191, -81.161, -81.109, -81.073,
        -81.067, -81.169, -81.172, -81.194, -81.168, -81.132, -81.045, -80.993, -80.944, -80.915, -80.892, -80.873, -80.856, -80.860,
        -80.867, -81.085, -81.125, -81.149, -81.150, -81.143, -81.119, -81.065, -80.995, -80.911, -80.842, -80.790, -80.686, -80.586,
        -80.486, -80.386, -80.288, -80.202, -80.120, -80.056, -79.996, -79.959, -79.946, -79.912, -79.866, -79.815, -79.765, -79.715,
        -79.690, -79.676, -79.628, -79.600, -79.588, -79.578, -79.584, -79.552, -79.516, -79.480, -79.449, -79.444, -79.433, -79.394,
        -79.373, -79.334, -79.285, -79.218, -79.147, -79.112, -79.054, -79.001, -78.977, -78.955, -78.920, -78.902, -78.928, -78.850,
        -78.803, -78.765, -78.749, -78.743, -78.756, -78.745, -78.708, -78.672, -78.651, -78.650, -78.641, -78.571, -78.560, -78.589,
        -78.496, -78.507, -78.432, -78.430, -78.386, -78.400, -78.381, -78.372, -78.344, -78.307, -78.276, -78.230, -78.241, -78.230,
        -78.235, -78.198, -78.177, -78.179, -78.157, -78.106, -78.092, -78.061, -78.052, -78.010, -77.982, -77.961, -77.912, -77.892,
        -77.862, -77.820, -77.776, -77.752, -77.712, -77.689, -77.663, -77.651, -77.637, -77.627, -77.604, -77.596, -77.649, -77.638,
        -77.556, -77.460, -77.378, -77.316, -77.282, -77.267, -77.209, -77.191, -77.168, -77.182, -77.179, -77.157, -77.144, -77.141,
        -77.164, -77.074, -77.040, -77.041, -76.949, -76.858, -76.827, -76.787, -76.790, -76.803, -76.740, -76.699, -76.682, -76.656,
        -76.630, -76.581, -76.528, -76.513, -76.516, -76.499, -76.471, -76.429, -76.389, -76.351, -76.312, -76.265, -76.227, -76.206,
        -76.191, -76.185, -76.183, -76.194, -76.208, -76.223, -76.229, -76.337, -76.384, -76.394, -76.275, -76.282, -76.268, -76.284,
        -76.285, -76.272, -76.134, -76.110, -76.136, -76.062, -76.003, -75.968, -75.952, -75.931, -75.930, -75.857, -75.793, -75.712,
        -75.624, -75.531, -75.504, -75.454, -75.425, -75.392, -75.324, -75.247, -75.241, -75.186, -75.169, -75.142, -75.064, -74.944,
        -74.860, -74.763, -74.662, -74.544, -74.457, -74.439, -74.262, -74.166, -74.069, -74.033, -73.986, -73.914, -73.835, -73.724,
        -73.569, -73.406, -73.314, -73.255, -73.115, -73.046, -72.902, -72.823, -72.723, -72.471, -72.379, -72.328, -72.298, -72.248,
        -72.165, -72.123, -71.990, -71.921, -71.877, -71.772, -71.614, -71.496, -71.454, -71.401, -71.390, -71.377, -71.372, -71.367,
        -71.363, -71.316, -71.223, -71.169, -71.107, -70.989, -70.913, -70.894, -70.811, -70.743, -70.696, -70.609, -70.522, -70.447,
        -70.382, -70.337, -70.304, -70.323, -70.335, -70.337, -70.343, -70.342, -70.349, -70.353, -70.341, -70.327, -70.318, -70.313,
        -70.301, -70.281, -70.279, -70.277, -70.281, -70.288, -70.256, -70.230, -70.220, -70.206, -70.203, -70.241, -70.177, -70.159,
        -70.151, -70.159, -70.137, -70.142, -70.134, -70.123, -70.135, -70.132, -70.150, -70.163, -70.142, -70.141, -70.180, -70.177,
        -70.167, -70.184, -70.203, -70.198, -70.194, -70.204, -70.205, -70.195, -70.160, -70.137, -70.135, -70.169, -70.158, -70.125,
        -70.115, -70.095, -70.087, -70.071, -70.094, -70.077, -70.062, -70.079, -70.088, -70.100, -70.148, -70.150, -70.150, -70.148,
        -70.149, -70.183, -70.177, -70.192, -70.188, -70.211, -70.225, -70.226, -70.231, -70.237, -70.248, -70.248, -70.254, -70.245,
        -70.275, -70.269, -70.283, -70.283, -70.303, -70.311, -70.293, -70.291, -70.324, -70.337, -70.553, -70.578, -70.571, -70.568,
        -70.600, -70.597, -70.602, -70.600, -70.615, -70.629, -70.405, -70.393, -70.405, -70.431, -70.478, -70.497, -70.505, -70.502,
        -70.514, -70.525, -70.506, -70.501, -70.513, -70.519, -70.532, -70.534, -70.542, -70.546, -70.554, -70.568, -70.575, -70.556,
        -70.575, -70.576, -70.564, -70.556, -70.542, -70.527, -70.494, -70.469, -70.492, -70.499, -70.451, -70.437, -70.436, -70.448,
        -70.447, -70.520, -70.530, -70.600, -70.650, -70.636, -70.658, -70.693, -70.694, -70.732, -70.705, -70.683, -70.646, -70.632,
        -70.643, -70.658, -70.666, -70.665, -70.652, -70.680, -70.646, -70.698, -70.686, -70.706, -70.693, -70.711, -70.724, -70.753,
        -70.734, -70.792, -70.815, -70.816, -70.800, -70.792, -70.849, -70.871, -70.955, -70.952, -70.953, -70.933, -70.945, -70.927,
        -70.902, -70.894, -70.919, -70.915, -70.948, -71.043, -71.061, -71.082, -71.103, -71.123, -71.138, -71.143, -71.148, -71.170,
        -71.157, -71.160, -71.170, -71.186, -71.173, -71.187, -71.214, -71.267, -71.285, -71.294, -71.296, -71.328, -71.371, -71.392,
        -71.490, -71.513, -71.520, -71.498, -71.492, -71.482, -71.495, -71.492, -71.433, -71.358, -71.342, -71.316, -71.315, -71.332,
        -71.330, -71.292, -71.319, -71.323, -71.332, -71.319, -71.282, -71.285, -71.360, -71.407, -71.382, -71.377, -71.383, -71.469,
        -71.639, -71.659, -71.677, -71.682, -71.686, -71.702, -71.697, -71.711, -71.709, -71.703, -71.704, -71.701, -71.688, -71.680,
        -71.662, -71.653, -71.652, -71.659, -71.668, -71.648, -71.639, -71.630, -71.621, -71.612, -71.592, -71.576, -71.570, -71.567,
        -71.551, -71.537, -71.522, -71.519, -71.527, -71.514, -71.521, -71.512, -71.521, -71.527, -71.540, -71.543, -71.499, -71.471,
        -71.436, -71.418, -71.437, -71.457, -71.468, -71.449, -71.447, -71.467, -71.496, -71.546, -71.527, -71.523, -71.555, -71.568,
        -71.674, -71.760, -71.728, -71.715, -71.706, -71.677, -71.671, -71.707, -71.691, -71.641, -71.631, -71.646, -71.653, -71.673,
        -71.735, -71.823, -71.842, -71.857, -71.883, -71.905, -71.949, -71.980, -72.022, -72.004, -71.990, -71.988, -71.989, -72.043,
        -72.053, -72.043, -72.050, -72.055, -72.057, -72.075, -72.098, -72.136, -72.160, -72.191, -72.197, -72.200, -72.206, -72.223,
        -72.262, -72.349, -72.411, -72.425, -72.459, -72.491, -72.506, -72.541, -72.627, -72.650, -72.624, -72.597, -72.585, -72.594,
        -72.667, -72.708, -72.777, -72.795, -72.797, -72.824, -72.812, -72.837, -72.827, -72.830, -72.855, -72.876, -72.902, -72.921,
        -72.988, -73.119, -73.133, -73.147, -73.184, -73.159, -73.147, -73.152, -73.157, -73.179, -73.172, -73.183, -73.205, -73.644,
        -73.646, -73.659, -73.679, -73.627, -73.599, -73.600, -73.653, -73.685, -73.671, -73.667, -73.634, -73.592, -73.555, -73.524,
        -73.496, -73.476, -73.463, -73.464, -73.472, -73.479, -73.515, -73.510, -73.528, -73.542, -73.534, -73.523, -73.511, -73.494,
        -73.476, -73.458, -73.449, -73.397, -73.382, -73.366, -73.344, -73.320, -73.296, -73.277, -73.263, -73.249, -73.235, -73.229,
        -73.223, -73.236, -73.250, -73.257, -73.288, -73.312, -73.354, -73.403, -73.381, -73.401, -73.475, -73.555, -73.690, -73.700,
        -73.668, -73.661, -73.709, -73.724, -73.746, -73.755, -73.763, -73.765, -73.767, -73.748, -73.733, -73.758, -73.826, -73.814,
        -73.853, -73.871, -73.888, -73.859, -73.905, -73.940, -73.941, -73.928, -73.919, -73.888, -73.866, -73.850, -73.842, -73.845,
        -73.846, -73.812, -73.809, -73.550, -73.695, -73.712, -73.755, -73.523, -72.814, -72.855, -72.841, -72.769, -72.483, -72.490,
        -72.432, -72.653, -72.816, -72.838, -72.779, -72.716, -72.703, -72.812, -72.854, -72.866, -72.833, -72.864, -72.865, -72.852,
        -72.829, -72.754, -72.749, -72.757, -72.888, -72.934, -72.921, -72.907, -72.962, -73.074, -73.085, -73.090, -73.112, -73.078,
        -73.051, -72.910, -72.982, -73.046, -72.985, -73.019, -73.049, -73.063, -73.118, -73.139, -73.132, -73.221, -73.290, -73.131,
        -73.181, -72.958, -72.931, -72.855, -72.749, -72.725, -72.680, -72.692, -72.715, -72.725, -72.725, -72.852, -72.919, -73.046,
        -73.193, -73.403, -73.394, -73.338, -73.312, -73.450, -73.462, -73.152, -73.328, -73.400, -73.509, -73.524, -73.537, -73.551,
        -73.569, -73.573, -73.581, -74.391, -74.694, -74.713, -74.728, -74.730, -74.784, -74.815, -74.909, -74.939, -75.116, -75.200,
        -75.214, -75.353, -75.398, -75.446, -75.520, -75.659, -75.707, -75.710, -75.711, -75.690, -75.653, -75.592, -74.169, -73.979,
        -73.949, -73.999, -74.050, -74.126, -74.341, -74.384, -74.435, -74.494, -74.518, -74.440, -74.556, -74.624, -74.675, -74.732,
        -74.672, -74.045, -73.614, -73.654, -73.646, -74.614, -74.629, -74.504, -74.466, -74.394, -74.299, -74.263, -74.238, -74.045,
        -74.028, -74.250, -74.329, -74.393, -74.371, -74.317, -74.393, -74.443, -74.447, -74.431, -74.416, -74.413, -74.467, -74.408,
        -74.406, -74.406, -74.407, -74.397, -74.407, -74.411, -74.326, -74.281, -74.130, -74.294, -74.324, -74.321, -74.202, -74.349,
        -74.334, -74.183, -74.364, -74.358, -74.310, -74.576, -74.668, -74.687, -74.547, -74.533, -74.459, -74.317, -74.095, -74.272,
        -74.211, -74.232, -74.198, -74.161, -74.099, -74.081, -73.851, -74.220, -74.233, -74.239, -74.146, -74.134, -74.135, -74.090,
        -73.751, -73.720, -73.721, -73.934, -73.924, -73.920, -73.830, -73.901, -73.735, -73.791, -73.746, -73.529, -73.645, -73.606,
        -73.599, -73.579, -73.741, -73.715, -73.671, -73.602, -73.594, -73.601, -73.584, -73.665, -73.531, -73.582, -73.553, -73.687,
        -73.582, -73.693, -73.307, -73.559, -73.379, -73.290, -73.323, -73.450, -73.359, -73.219, -72.845, -73.239, -73.183, -73.051,
        -72.949, -72.804, -72.732, -72.632, -72.299, -72.229, -72.157, -72.063, -71.831, -71.713, -71.411,
    ]
}
