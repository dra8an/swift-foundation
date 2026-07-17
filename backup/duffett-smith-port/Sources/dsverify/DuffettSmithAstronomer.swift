// Faithful Swift port of the ICU4C CalendarAstronomer subset needed by the
// Chinese calendar (icu4c/source/i18n/astro.cpp, Duffett-Smith based).
// ⚠ CONTINGENCY ARTIFACT — not for the feature branch without explicit agreement.
//
// Fidelity: pure UT (no ΔT, matching ICU's unimplemented TODO), Kepler eps 1e-5,
// ceil() ms stepping + recursive restart in timeOfAngle, floor-based normalization,
// ICU epoch literals. Equatorial-coordinate code omitted (dead for this path).

import Foundation

struct DuffettSmithAstronomer {
    static let SYNODIC_MONTH = 29.530588853
    static let PI = 3.14159265358979323846
    static let PI2 = PI * 2.0
    static let TROPICAL_YEAR = 365.242191
    static let MINUTE_MS = 60_000.0
    static let DAY_MS = 86_400_000.0
    static let JULIAN_EPOCH_MS = -210866760000000.0
    static let JD_EPOCH = 2447891.5

    static let SUN_ETA_G = 279.403303 * PI / 180
    static let SUN_OMEGA_G = 282.768422 * PI / 180
    static let SUN_E = 0.016713

    static let moonL0 = 318.351648 * PI / 180
    static let moonP0 = 36.340410 * PI / 180
    static let moonN0 = 318.510107 * PI / 180
    static let moonI = 5.145366 * PI / 180

    static func WINTER_SOLSTICE() -> Double { (PI * 3) / 2 }
    static let NEW_MOON = 0.0

    private(set) var fTime: Double
    private var julianDay: Double = .nan
    private var sunLongitudeValue: Double = .nan
    private var meanAnomalySun: Double = .nan
    private var moonEclipLong: Double = .nan
    private var moonPositionSet = false

    init(_ time: Double) {
        fTime = time
    }

    mutating func setTime(_ aTime: Double) {
        fTime = aTime
        clearCache()
    }

    private mutating func clearCache() {
        julianDay = .nan
        sunLongitudeValue = .nan
        meanAnomalySun = .nan
        moonEclipLong = .nan
        moonPositionSet = false
    }

    static func normalize(_ value: Double, _ range: Double) -> Double {
        value - range * (value / range).rounded(.down)
    }

    static func norm2PI(_ angle: Double) -> Double {
        normalize(angle, PI * 2.0)
    }

    static func normPI(_ angle: Double) -> Double {
        normalize(angle + PI, PI * 2.0) - PI
    }

    mutating func getJulianDay() -> Double {
        if julianDay.isNaN {
            julianDay = (fTime - Self.JULIAN_EPOCH_MS) / Self.DAY_MS
        }
        return julianDay
    }

    // Kepler's equation, solved iteratively (Duffett-Smith p.90)
    static func trueAnomaly(_ meanAnomaly: Double, _ eccentricity: Double) -> Double {
        var delta: Double
        var E = meanAnomaly
        repeat {
            delta = E - eccentricity * sin(E) - meanAnomaly
            E = E - delta / (1 - eccentricity * cos(E))
        } while abs(delta) > 1e-5
        return 2.0 * atan(tan(E / 2) * ((1 + eccentricity) / (1 - eccentricity)).squareRoot())
    }

    mutating func getSunLongitude() -> Double {
        if sunLongitudeValue.isNaN {
            (sunLongitudeValue, meanAnomalySun) = Self.getSunLongitude(getJulianDay())
        }
        return sunLongitudeValue
    }

    // Duffett-Smith p.86
    static func getSunLongitude(_ jDay: Double) -> (longitude: Double, meanAnomaly: Double) {
        let day = jDay - JD_EPOCH
        let epochAngle = norm2PI(PI2 / TROPICAL_YEAR * day)
        let meanAnomaly = norm2PI(epochAngle + SUN_ETA_G - SUN_OMEGA_G)
        let longitude = norm2PI(trueAnomaly(meanAnomaly, SUN_E) + SUN_OMEGA_G)
        return (longitude, meanAnomaly)
    }

    // Duffett-Smith p.142, through ecliptic longitude only (equatorial branch
    // is dead code for the Chinese path).
    private mutating func computeMoonPosition() {
        if moonPositionSet { return }
        _ = getSunLongitude()
        let day = getJulianDay() - Self.JD_EPOCH

        let meanLongitude = Self.norm2PI(13.1763966 * Self.PI / 180 * day + Self.moonL0)
        var meanAnomalyMoon = Self.norm2PI(meanLongitude - 0.1114041 * Self.PI / 180 * day - Self.moonP0)

        let evection = 1.2739 * Self.PI / 180 * sin(2 * (meanLongitude - sunLongitudeValue) - meanAnomalyMoon)
        let annual = 0.1858 * Self.PI / 180 * sin(meanAnomalySun)
        let a3 = 0.3700 * Self.PI / 180 * sin(meanAnomalySun)

        meanAnomalyMoon += evection - annual - a3

        let center = 6.2886 * Self.PI / 180 * sin(meanAnomalyMoon)
        let a4 = 0.2140 * Self.PI / 180 * sin(2 * meanAnomalyMoon)

        var moonLongitude = meanLongitude + evection + center - annual + a4

        let variation = 0.6583 * Self.PI / 180 * sin(2 * (moonLongitude - sunLongitudeValue))
        moonLongitude += variation

        var nodeLongitude = Self.norm2PI(Self.moonN0 - 0.0529539 * Self.PI / 180 * day)
        nodeLongitude -= 0.16 * Self.PI / 180 * sin(meanAnomalySun)

        let y = sin(moonLongitude - nodeLongitude)
        let x = cos(moonLongitude - nodeLongitude)

        moonEclipLong = atan2(y * cos(Self.moonI), x) + nodeLongitude
        moonPositionSet = true
    }

    // Duffett-Smith p.147
    mutating func getMoonAge() -> Double {
        computeMoonPosition()
        return Self.norm2PI(moonEclipLong - sunLongitudeValue)
    }

    mutating func getSunTime(_ desired: Double, _ next: Bool) -> Double {
        timeOfAngle({ $0.getSunLongitude() }, desired, Self.TROPICAL_YEAR, Self.MINUTE_MS, next)
    }

    mutating func getMoonTime(_ desired: Double, _ next: Bool) -> Double {
        timeOfAngle({ $0.getMoonAge() }, desired, Self.SYNODIC_MONTH, Self.MINUTE_MS, next)
    }

    // astro.cpp:689-755, incl. the ceil-stepping and recursive anti-divergence HACK
    mutating func timeOfAngle(
        _ eval: (inout DuffettSmithAstronomer) -> Double,
        _ desired: Double, _ periodDays: Double, _ epsilon: Double, _ next: Bool
    ) -> Double {
        var lastAngle = eval(&self)
        let deltaAngle = Self.norm2PI(desired - lastAngle)
        var deltaT = (deltaAngle + (next ? 0.0 : -Self.PI2)) * (periodDays * Self.DAY_MS) / Self.PI2

        var lastDeltaT = deltaT
        let startTime = fTime

        setTime(fTime + ceil(deltaT))

        repeat {
            let angle = eval(&self)
            let factor = abs(deltaT / Self.normPI(angle - lastAngle))
            deltaT = Self.normPI(desired - angle) * factor

            if abs(deltaT) > abs(lastDeltaT) {
                let delta = ceil(periodDays * Self.DAY_MS / 8.0)
                setTime(startTime + (next ? delta : -delta))
                return timeOfAngle(eval, desired, periodDays, epsilon, next)
            }

            lastDeltaT = deltaT
            lastAngle = angle

            setTime(fTime + ceil(deltaT))
        } while abs(deltaT) > epsilon

        return fTime
    }
}
