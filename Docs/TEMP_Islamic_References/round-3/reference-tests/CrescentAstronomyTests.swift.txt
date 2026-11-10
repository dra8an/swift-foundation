// Reference values from Calendrical Calculations (sample data), as used by ICU4X's astronomy.rs tests.
// ICU4X uses 0.0 for "no moonset"; here that is nil.
// Altitude and parallax differ from ICU4X by about 1 arcsecond for modern dates and up to ~26 arcseconds for
// -586 CE: icu4swift's delta-T (Earth rotation) model differs slightly from ICU4X's, and the error grows with
// distance from the present, as delta-T uncertainty does. Latitude and distance, which do not depend on
// Earth rotation, match to 1e-6.
import Testing
import CalendarCore
@testable import AstronomicalEngine

@Suite("Crescent astronomy")
struct CrescentAstronomyTests {
    // ICU4X / Calendrical Calculations Mecca: 21°25'24" N, 39°49'24" E, 298 m, UTC+3.
    static let ccMecca = Location(latitude: 6427.0 / 300.0, longitude: 11947.0 / 300.0, elevation: 298.0, utcOffset: 1.0 / 8.0)
    static let rd: [Double] = [-214193, -61387, 25469, 49217, 171307, 210155, 253427, 369740, 400085, 434355, 452605, 470160, 473837, 507850, 524156, 544676, 567118, 569477, 601716, 613424, 626596, 645554, 664224, 671401, 694799, 704424, 708842, 709409, 709580, 727274, 728714, 744313, 764652]
    static let expectedLatitude: [Double] = [2.4527590208461576, -4.90223034654341, -2.9394693592610484, 5.001904508580623, -3.208909826304433, 0.894361559890105, -3.8633355687979827, -2.5224444701068927, 1.0320696124422062, 3.005689926794408, 1.613842956502888, 4.766740664556875, 4.899202930916035, 4.838473946607273, 2.301475724501815, -0.8905637199828537, 4.7657836433468495, -2.737358003826797, -4.035652608005429, -3.157214517184652, -1.8796147336498752, -3.379519408995276, -4.398341468078228, 2.099198567294447, 5.268746128633113, -1.6722994521634027, 4.6820126551666865, 3.705518210116447, 2.493964063649065, -4.167774638752936, -2.873757531859998, -4.667251128743298, 5.138562328560728]
    static let expectedAltitude: [Double] = [-13.163184128188277, -7.281425833096932, -77.1499009115812, -30.401178593900795, 71.84857827681589, -43.79857984753659, 40.65320421851649, -40.2787255279427, 29.611156512065406, -19.973178784428228, -23.740743779700097, 30.956688013173505, -18.88869091014726, -32.16116202243495, -45.68091943596022, -50.292110029959986, -54.3453056090807, -34.56600009726776, 44.13198955291821, -57.539862986917285, -62.08243959461623, -54.07209109276471, -16.120452006695814, 23.864594681196934, 32.95014668614863, 72.69165128891194, -29.849481790038908, 31.610644151367637, -42.21968940776054, 28.6478092363985, -38.95055354031621, 27.601977078963245, -54.85468160086816]
    static let expectedDistance: [Double] = [387624532.22874624, 393677431.9167689, 402232943.80299366, 392558548.8426357, 366799795.8707107, 365107305.3822873, 401995197.0122423, 404025417.6150537, 377671971.8515077, 403160628.6150732, 375160036.9057225, 369934038.34809774, 402543074.28064245, 374847147.6967837, 403469151.42100906, 386211365.4436033, 385336015.6086019, 400371744.7464432, 395970218.00750065, 383858113.5538787, 389634540.7722341, 390868707.6609328, 368015493.693663, 399800095.77937233, 404273360.3039046, 382777325.7053601, 378047375.3350678, 385774023.9948239, 371763698.0990588, 362461692.8996066, 394214466.3812425, 405787977.04490376, 404202826.42484397]
    static let expectedParallax: [Double] = [0.9180377088277034, 0.9208275970231943, 0.20205836298974478, 0.8029475944705559, 0.3103764190238057, 0.7224552232666479, 0.6896953754669151, 0.6900664438899986, 0.8412721901635796, 0.8519504336914271, 0.8916972264563727, 0.8471706468502866, 0.8589744596828851, 0.8253387743371953, 0.6328154405175959, 0.60452566100182, 0.5528114670829496, 0.7516491660573382, 0.6624140811593374, 0.5109678575066725, 0.4391324179474404, 0.5486027633624313, 0.9540023420545446, 0.835939538308717, 0.7585615249134946, 0.284040095327141, 0.8384425157447107, 0.8067682261382678, 0.7279971552035109, 0.8848306274359499, 0.720943806048675, 0.7980998225232075, 0.5204553405568378]
    static let expectedMoonset: [Double?] = [-214192.91577491348, -61386.372392431986, 25469.842646633304, 49217.03030766261, 171307.41988615665, 210155.96578468647, 253427.2528524993, nil, 400085.5281194299, 434355.0524936674, 452605.0379962325, 470160.4931771927, 473837.06032208423, 507850.8560177605, nil, 544676.908706548, 567118.8180096536, 569477.7141856537, 601716.4168627897, 613424.9325031227, 626596.9563783304, 645554.9526297608, 664224.070965863, 671401.2004198332, 694799.4892001058, 704424.4299627786, 708842.0314145002, 709409.2245215117, nil, 727274.2148254914, nil, 744313.2118589033, 764652.9631741203]

    static func close(_ a: Double, _ b: Double, relative: Double = 1e-6, absolute: Double = 1e-9) -> Bool {
        abs(a - b) <= max(absolute, relative * abs(b))
    }

    @Test func lunarLatitude() {
        for (i, rd) in Self.rd.enumerated() {
            let got = Astronomical.lunarLatitude(Astronomical.julianCenturies(Moment(rd)))
            #expect(Self.close(got, Self.expectedLatitude[i]), "RD \(rd): \(got) vs \(Self.expectedLatitude[i])")
        }
    }

    @Test func lunarDistance() {
        for (i, rd) in Self.rd.enumerated() {
            let got = Astronomical.lunarDistance(Moment(rd))
            #expect(Self.close(got, Self.expectedDistance[i]), "RD \(rd): \(got) vs \(Self.expectedDistance[i])")
        }
    }

    @Test func lunarAltitude() {
        for (i, rd) in Self.rd.enumerated() {
            let got = Astronomical.lunarAltitude(Moment(rd), location: Self.ccMecca)
            #expect(Self.close(got, Self.expectedAltitude[i], relative: 0, absolute: 0.01), "RD \(rd): \(got) vs \(Self.expectedAltitude[i])")
        }
    }

    @Test func lunarParallax() {
        for (i, rd) in Self.rd.enumerated() {
            let alt = Astronomical.lunarAltitude(Moment(rd), location: Self.ccMecca)
            let got = Astronomical.lunarParallax(altitude: alt, moment: Moment(rd))
            #expect(Self.close(got, Self.expectedParallax[i], relative: 1e-4), "RD \(rd): \(got) vs \(Self.expectedParallax[i])")
        }
    }

    @Test func moonset() {
        // ICU4X bisects to one minute, this port to about one second, so allow two minutes.
        for (i, rd) in Self.rd.enumerated() {
            let got = Astronomical.moonset(Moment(rd), location: Self.ccMecca)
            if let expected = Self.expectedMoonset[i] {
                #expect(got != nil && abs(got!.inner - expected) < 2.0 / 1440.0, "RD \(rd): \(String(describing: got?.inner)) vs \(expected)")
            } else {
                #expect(got == nil, "RD \(rd): expected no moonset, got \(String(describing: got?.inner))")
            }
        }
    }

    /// Meeus, Astronomical Algorithms, Example 47.a: 1992 April 12, 0h TD.
    @Test func meeusExample47a() {
        let td = 727300.0 // RD of 1992-04-12
        let ut = Moment(td - Astronomical.ephemerisCorrection(Moment(td)))
        let c = Astronomical.julianCenturies(ut)
        #expect(abs(Astronomical.lunarLatitude(c) - (-3.229126)) < 1e-4)
        #expect(abs(Astronomical.lunarDistance(ut) / 1000.0 - 368_409.7) < 1.0)
        // Calendrical Calculations' longitude includes nutation; Meeus' apparent longitude is 133.167265.
        #expect(abs(Astronomical.lunarLongitude(c) - 133.167265) < 1e-3)
    }

    /// Sanity checks for the additions: refraction shape.
    @Test func refractionShape() {
        // Saemundsson takes the true (airless) altitude: 29' at true 0 deg (the object then appears about half a degree up).
        #expect(abs(Astronomical.refraction(atTrueAltitude: 0) * 60 - 29.0) < 0.5)
        #expect(abs(Astronomical.refraction(atTrueAltitude: 5) * 60 - 9.7) < 0.5)
    }

    /// Cross-check the additions against the validated functions, at sea level (so the horizon definitions agree):
    /// sunset within 1 minute of icu4swift's Reingold sunset, moonset within 2 minutes of the CC moonset above.
    @Test func additionsAgreeWithValidatedFunctions() {
        let jeddah = Location(latitude: 21.5, longitude: 39.2, elevation: 0, utcOffset: 3.0 / 24.0)
        for rd in stride(from: 737000, to: 744000, by: 97) { // 2018-2037
            let day = RataDie(Int64(rd))
            if let mine = Astronomical.sunsetUT(nearLocalNoonOf: day, location: jeddah),
               let reference = Astronomical.sunset(at: Moment(Double(rd)), location: jeddah) {
                let referenceUT = jeddah.universalFromStandard(reference)
                #expect(abs(mine - referenceUT) < 1.0 / 1440.0, "sunset RD \(rd): \((mine - referenceUT) * 1440) min")
            }
            if let reference = Astronomical.moonset(Moment(Double(rd)), location: jeddah) {
                let referenceUT = jeddah.universalFromStandard(reference)
                if let mine = Astronomical.moonsetUT(after: referenceUT - 2.0 / 24.0, location: jeddah) {
                    #expect(abs(mine - referenceUT) < 2.0 / 1440.0, "moonset RD \(rd): \((mine - referenceUT) * 1440) min")
                } else {
                    Issue.record("moonset RD \(rd): no moonset found near the reference")
                }
            }
            // Topocentric elongation is close to geocentric (within about 1 degree, the lunar parallax).
            let t = Moment(Double(rd) + 0.7)
            #expect(abs(Astronomical.topocentricElongation(t, location: jeddah) - Astronomical.geocentricElongation(t)) < 1.05)
        }
    }
}
