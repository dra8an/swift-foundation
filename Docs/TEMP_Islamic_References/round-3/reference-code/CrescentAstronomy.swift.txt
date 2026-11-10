// Moon and sun positions for crescent-visibility rules.
//
// The first part ports functions from ICU4X utils/calendrical_calculations/src/astronomy.rs
// (Apache-2.0), which implements Calendrical Calculations by Reingold & Dershowitz (4th ed., 2018),
// after Meeus, Astronomical Algorithms, ch. 47. The second part ("Additions") is new: an
// altitude-dependent refraction, azimuth, and topocentric elongation, which the crescent rules need
// but Calendrical Calculations does not provide.

import CalendarCore
import Foundation

extension Astronomical {

    // MARK: - Mean elements (Meeus ch. 47)

    static func meanLunarLongitude(_ c: Double) -> Double {
        mod360(218.3164477 + 481267.88123421 * c - 0.0015786 * c * c + c * c * c / 538841.0 - c * c * c * c / 65194000.0)
    }

    static func lunarElongationArgument(_ c: Double) -> Double {
        mod360(297.8501921 + 445267.1114034 * c - 0.0018819 * c * c + c * c * c / 545868.0 - c * c * c * c / 113065000.0)
    }

    static func solarAnomaly(_ c: Double) -> Double {
        mod360(357.5291092 + 35999.0502909 * c - 0.0001536 * c * c + c * c * c / 24490000.0)
    }

    static func lunarAnomaly(_ c: Double) -> Double {
        mod360(134.9633964 + 477198.8675055 * c + 0.0087414 * c * c + c * c * c / 69699.0 - c * c * c * c / 14712000.0)
    }

    static func moonNode(_ c: Double) -> Double {
        mod360(93.2720950 + 483202.0175233 * c - 0.0036539 * c * c - c * c * c / 3526000.0 + c * c * c * c / 863310000.0)
    }

    // MARK: - Lunar latitude and distance

    /// Ecliptic latitude of the moon in degrees, for `julianCenturies` from `julianCenturies(_:)`.
    public static func lunarLatitude(_ julianCenturies: Double) -> Double {
        let c = julianCenturies
        let l = meanLunarLongitude(c)
        let d = lunarElongationArgument(c)
        let ms = solarAnomaly(c)
        let ml = lunarAnomaly(c)
        let f = moonNode(c)
        let e = 1.0 - 0.002516 * c - 0.0000074 * c * c

        var correction = 0.0
        for i in 0..<LunarSeries.latCoeff.count {
            let arg = LunarSeries.latD[i] * d + LunarSeries.latM[i] * ms + LunarSeries.latMp[i] * ml + LunarSeries.latF[i] * f
            var term = LunarSeries.latCoeff[i] * sinDeg(arg)
            for _ in 0..<LunarSeries.latEPower[i] { term *= e }
            correction += term
        }
        correction /= 1_000_000.0

        let venus = 175.0 * (sinDeg(119.75 + c * 131.849 + f) + sinDeg(119.75 + c * 131.849 - f)) / 1_000_000.0
        let flatEarth = (-2235.0 * sinDeg(l) + 127.0 * sinDeg(l - ml) - 115.0 * sinDeg(l + ml)) / 1_000_000.0
        let extra = 382.0 * sinDeg(313.45 + c * 481266.484) / 1_000_000.0
        return correction + venus + flatEarth + extra
    }

    /// Distance from the centre of the Earth to the centre of the moon, in meters.
    public static func lunarDistance(_ moment: Moment) -> Double {
        let c = julianCenturies(moment)
        let d = lunarElongationArgument(c)
        let m = solarAnomaly(c)
        let mp = lunarAnomaly(c)
        let f = moonNode(c)
        let e = 1.0 - 0.002516 * c - 0.0000074 * c * c
        var correction = 0.0
        for i in 0..<LunarSeries.distCoeff.count {
            let arg = LunarSeries.distD[i] * d + LunarSeries.distM[i] * m + LunarSeries.distMp[i] * mp + LunarSeries.distF[i] * f
            correction += LunarSeries.distCoeff[i] * pow(e, abs(LunarSeries.distM[i])) * cosDeg(arg)
        }
        return 385_000_560.0 + correction
    }

    // MARK: - Sidereal time and lunar altitude

    /// Mean sidereal time at Greenwich, in degrees, for a moment in universal time.
    public static func siderealFromMoment(_ moment: Moment) -> Double {
        let c = (moment - .j2000) / 36525.0
        return mod360(poly(c, [280.46061837, 36525.0 * 360.98564736629, 0.000387933, -1.0 / 38710000.0]))
    }

    /// Geocentric altitude of the centre of the moon, in degrees, without refraction.
    public static func lunarAltitude(_ moment: Moment, location: Location) -> Double {
        let c = julianCenturies(moment)
        let lambda = lunarLongitude(c)
        let beta = lunarLatitude(c)
        let alpha = rightAscension(moment, beta: beta, lambda: lambda)
        let delta = declination(moment, beta: beta, lambda: lambda)
        let hourAngle = mod360(siderealFromMoment(moment) + location.longitude - alpha)
        let altitude = toDegrees(asin(sinDeg(location.latitude) * sinDeg(delta)
            + cosDeg(location.latitude) * cosDeg(delta) * cosDeg(hourAngle)))
        return mod360(altitude + 180.0) - 180.0
    }

    /// Parallax of the moon in altitude, in degrees, for a geocentric altitude.
    public static func lunarParallax(altitude: Double, moment: Moment) -> Double {
        mod360(toDegrees(asin(6_378_140.0 / lunarDistance(moment) * cosDeg(altitude))))
    }

    /// Altitude of the centre of the moon seen from the surface, in degrees, without refraction.
    public static func topocentricLunarAltitude(_ moment: Moment, location: Location) -> Double {
        let altitude = lunarAltitude(moment, location: location)
        return altitude - lunarParallax(altitude: altitude, moment: moment)
    }

    /// Calendrical Calculations' observed altitude of the upper limb: topocentric altitude plus horizon
    /// refraction for the location plus 16' semi-diameter. Meant for rise and set, not for altitudes above
    /// the horizon (the refraction term is the fixed horizon value).
    public static func observedLunarAltitude(_ moment: Moment, location: Location) -> Double {
        topocentricLunarAltitude(moment, location: location) + refraction(location) + 16.0 / 60.0
    }

    /// Standard time of moonset on the date of `date` at `location`, or nil if the moon does not set that day.
    public static func moonset(_ date: Moment, location: Location) -> Moment? {
        let moment = location.universalFromStandard(date)
        let waxing = lunarPhase(date, julianCenturies: julianCenturies(date)) < 180.0
        let alt = observedLunarAltitude(moment, location: location)
        let offset = alt / (4.0 * (90.0 - abs(location.latitude)))
        let approx: Moment
        if waxing {
            approx = offset > 0.0 ? moment + offset : moment + 1.0 + offset
        } else {
            approx = moment - offset + 0.5
        }
        let set = Moment(binarySearchMoment(lo: approx.inner - 6.0 / 24.0, hi: approx.inner + 6.0 / 24.0) { x in
            observedLunarAltitude(Moment(x), location: location) < 0.0
        })
        guard set < moment + 1.0 else { return nil }
        let standard = Moment(max(location.standardFromUniversal(set).inner, date.inner))
        return standard < date ? nil : standard
    }

    // MARK: - Additions for crescent rules (not in Calendrical Calculations)

    /// Horizontal position: altitude above the horizon and azimuth east of north, both in degrees.
    public struct Horizontal: Sendable {
        public let altitude: Double
        public let azimuth: Double
    }

    static func horizontal(rightAscension alpha: Double, declination delta: Double, moment: Moment, location: Location) -> Horizontal {
        let h = mod360(siderealFromMoment(moment) + location.longitude - alpha)
        let phi = location.latitude
        let altitude = toDegrees(asin(sinDeg(phi) * sinDeg(delta) + cosDeg(phi) * cosDeg(delta) * cosDeg(h)))
        // Meeus 13.5 measures azimuth from the south; add 180 to measure it from the north.
        let azimuthFromSouth = toDegrees(atan2(sinDeg(h), cosDeg(h) * sinDeg(phi) - tanDeg(delta) * cosDeg(phi)))
        return Horizontal(altitude: altitude, azimuth: mod360(azimuthFromSouth + 180.0))
    }

    /// Geocentric position of the centre of the moon, no refraction.
    public static func lunarHorizontal(_ moment: Moment, location: Location) -> Horizontal {
        let c = julianCenturies(moment)
        let lambda = lunarLongitude(c)
        let beta = lunarLatitude(c)
        return horizontal(rightAscension: rightAscension(moment, beta: beta, lambda: lambda),
                          declination: declination(moment, beta: beta, lambda: lambda),
                          moment: moment, location: location)
    }

    /// Position of the centre of the moon seen from the surface (parallax applied to the altitude), no refraction.
    public static func topocentricLunarHorizontal(_ moment: Moment, location: Location) -> Horizontal {
        let geo = lunarHorizontal(moment, location: location)
        return Horizontal(altitude: geo.altitude - lunarParallax(altitude: geo.altitude, moment: moment), azimuth: geo.azimuth)
    }

    /// Position of the centre of the sun, no refraction (solar parallax of 8.8" is ignored).
    public static func solarHorizontal(_ moment: Moment, location: Location) -> Horizontal {
        let lambda = solarLongitude(julianCenturies(moment))
        return horizontal(rightAscension: rightAscension(moment, beta: 0, lambda: lambda),
                          declination: declination(moment, beta: 0, lambda: lambda),
                          moment: moment, location: location)
    }

    /// Atmospheric refraction in degrees for an object whose airless altitude is `altitude` degrees
    /// (Saemundsson 1986, standard pressure and temperature). Near 34' at the horizon, about 10' at 5 degrees.
    public static func refraction(atTrueAltitude altitude: Double) -> Double {
        let h = max(altitude, -1.0)
        return 1.02 / tanDeg(h + 10.3 / (h + 5.11)) / 60.0
    }

    /// Geocentric elongation (angle between the centres of the moon and the sun) in degrees.
    public static func geocentricElongation(_ moment: Moment) -> Double {
        let c = julianCenturies(moment)
        let beta = lunarLatitude(c)
        let dLambda = lunarLongitude(c) - solarLongitude(c)
        return toDegrees(acos(min(1, max(-1, cosDeg(beta) * cosDeg(dLambda)))))
    }

    /// Elongation seen from the surface, from the topocentric horizontal positions of both bodies, in degrees.
    public static func topocentricElongation(_ moment: Moment, location: Location) -> Double {
        let moon = topocentricLunarHorizontal(moment, location: location)
        let sun = solarHorizontal(moment, location: location)
        let cosE = sinDeg(moon.altitude) * sinDeg(sun.altitude)
            + cosDeg(moon.altitude) * cosDeg(sun.altitude) * cosDeg(moon.azimuth - sun.azimuth)
        return toDegrees(acos(min(1, max(-1, cosE))))
    }

    /// Moment (universal time) in [lo, hi] at which `f` crosses `target` going in `rising` direction, or nil.
    /// Scans in 10-minute steps, then bisects to about one second.
    static func crossing(from lo: Moment, to hi: Moment, target: Double, rising: Bool, _ f: (Moment) -> Double) -> Moment? {
        let step = 10.0 / 1440.0
        var t = lo.inner
        var previous = f(lo) - target
        while t < hi.inner {
            let next = min(t + step, hi.inner)
            let value = f(Moment(next)) - target
            if (rising && previous < 0 && value >= 0) || (!rising && previous > 0 && value <= 0) {
                return Moment(binarySearchMoment(lo: t, hi: next) { x in
                    let v = f(Moment(x)) - target
                    return rising ? v >= 0 : v <= 0
                })
            }
            previous = value
            t = next
        }
        return nil
    }

    /// Universal time of sunset (upper limb at the standard -50' apparent horizon) during the UT day containing
    /// `noonish` +- 12h around local noon, or nil if the sun does not set (polar day or night).
    public static func sunsetUT(nearLocalNoonOf day: RataDie, location: Location) -> Moment? {
        // Iterate on the hour angle: at sunset the sun's hour angle equals H0, where the altitude is -50'.
        let h0 = -50.0 / 60.0
        let phi = location.latitude
        var t = Double(day.dayNumber) + 0.75 - location.longitude / 360.0
        for _ in 0..<6 {
            let moment = Moment(t)
            let lambda = solarLongitude(julianCenturies(moment))
            let alpha = rightAscension(moment, beta: 0, lambda: lambda)
            let delta = declination(moment, beta: 0, lambda: lambda)
            let cosH0 = (sinDeg(h0) - sinDeg(phi) * sinDeg(delta)) / (cosDeg(phi) * cosDeg(delta))
            guard cosH0 >= -1, cosH0 <= 1 else { return nil } // the sun does not set (polar day or night)
            var hourAngle = mod360(siderealFromMoment(moment) + location.longitude - alpha)
            if hourAngle > 180 { hourAngle -= 360 }
            let dt = (toDegrees(acos(cosH0)) - hourAngle) / 360.98564736629
            t += dt
            if abs(dt) < 1e-7 { break }
        }
        return Moment(t)
    }

    /// Universal time of moonset (upper limb at the standard -34' refraction, topocentric) after `start`, within 30 hours.
    public static func moonsetUT(after start: Moment, location: Location) -> Moment? {
        // Semi-diameter = 0.2725 * horizontal parallax (Meeus ch. 55); parallax itself is already in the topocentric altitude.
        let semiDiameter = 0.2725 * lunarParallaxHorizontal(start)
        return crossing(from: start, to: start + 1.25, target: -34.0 / 60.0 - semiDiameter, rising: false) {
            topocentricLunarHorizontal($0, location: location).altitude
        }
    }

    /// Horizontal parallax of the moon in degrees (the parallax at altitude 0).
    public static func lunarParallaxHorizontal(_ moment: Moment) -> Double {
        toDegrees(asin(6_378_140.0 / lunarDistance(moment)))
    }

    /// Universal time at which the sun is `depression` degrees below the horizon in the morning, searching the 24 hours
    /// after `start`. Used for dawn (fajr / imsak).
    public static func dawnUT(after start: Moment, location: Location, depression: Double) -> Moment? {
        crossing(from: start, to: start + 1.0, target: -depression, rising: true) {
            solarHorizontal($0, location: location).altitude
        }
    }
}
