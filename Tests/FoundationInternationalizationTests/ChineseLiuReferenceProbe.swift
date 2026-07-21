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

// External validation of the fallback zone 2101-2200 against Yuk Tung Liu's
// Chinese calendar data (https://ytliu0.github.io/ChineseCalendar/, GPL-3.0):
// JPL DE441 ephemeris + Stephenson/Morrison ΔT + GB/T 33661-2017 modern rules,
// UTC+8, the same rule system our fallback implements, computed from the
// best available ephemeris by an independent source. Extracted 2026-07-19 from
// src/calendarData.js (github.com/ytliu0/ChineseCalendar); decode validated
// against six known years (2020, 2023, 2024, 2033, 1984, 2000).
// This is the strongest external authority for 2101-2200: HKO stops at 2100,
// and beyond 2200 no published modern-rules source exists.

import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

@Suite("Chinese Liu Reference Probe")
private struct ChineseLiuReferenceProbe {

    // (relatedISOYear, CNY RataDie, leap display number (0 = none),
    //  month-length bits: bit i set = ordinal month i+1 has 30 days)
    private static let liu: [(iso: Int, cnyRD: Int, leap: Int, bits: UInt16)] = [
        (2101, 767038, 7, 0x095B),
        (2102, 767422, 0, 0x05AD),
        (2103, 767777, 0, 0x0BAA),
        (2104, 768132, 5, 0x1B52),
        (2105, 768516, 0, 0x0D92),
        (2106, 768870, 0, 0x0D25),
        (2107, 769224, 4, 0x1A4B),
        (2108, 769608, 0, 0x0A55),
        (2109, 769962, 9, 0x14AD),
        (2110, 770346, 0, 0x04B6),
        (2111, 770700, 0, 0x06B5),
        (2112, 771055, 6, 0x0DAA),
        (2113, 771439, 0, 0x0EC9),
        (2114, 771794, 0, 0x0E92),
        (2115, 772148, 4, 0x1D26),
        (2116, 772532, 0, 0x0D2A),
        (2117, 772886, 0, 0x0A56),
        (2118, 773240, 3, 0x14B6),
        (2119, 773624, 0, 0x0556),
        (2120, 773978, 7, 0x0AD5),
        (2121, 774362, 0, 0x0B55),
        (2122, 774717, 0, 0x074A),
        (2123, 775071, 5, 0x0E93),
        (2124, 775455, 0, 0x0695),
        (2125, 775809, 0, 0x052B),
        (2126, 776163, 4, 0x0A57),
        (2127, 776547, 0, 0x0A9B),
        (2128, 776902, 11, 0x155A),
        (2129, 777286, 0, 0x056A),
        (2130, 777640, 0, 0x0B65),
        (2131, 777995, 6, 0x174A),
        (2132, 778379, 0, 0x0B4A),
        (2133, 778733, 0, 0x0A95),
        (2134, 779087, 5, 0x152B),
        (2135, 779471, 0, 0x054D),
        (2136, 779825, 0, 0x0AAD),
        (2137, 780180, 2, 0x156A),
        (2138, 780564, 0, 0x05AA),
        (2139, 780918, 7, 0x0BA5),
        (2140, 781302, 0, 0x0DA5),
        (2141, 781657, 0, 0x0D4A),
        (2142, 782011, 5, 0x1D15),
        (2143, 782395, 0, 0x0D16),
        (2144, 782749, 0, 0x094E),
        (2145, 783103, 4, 0x0AAD),
        (2146, 783487, 0, 0x0AD6),
        (2147, 783842, 11, 0x15B4),
        (2148, 784226, 0, 0x06D2),
        (2149, 784580, 0, 0x0EA5),
        (2150, 784935, 6, 0x0E8A),
        (2151, 785318, 0, 0x068B),
        (2152, 785672, 0, 0x0D17),
        (2153, 786027, 5, 0x0956),
        (2154, 786410, 0, 0x095B),
        (2155, 786765, 0, 0x0ADA),
        (2156, 787120, 3, 0x16D4),
        (2157, 787504, 0, 0x0754),
        (2158, 787858, 7, 0x1745),
        (2159, 788242, 0, 0x0B45),
        (2160, 788596, 0, 0x0A8B),
        (2161, 788950, 6, 0x152B),
        (2162, 789334, 0, 0x04AD),
        (2163, 789688, 0, 0x096B),
        (2164, 790043, 4, 0x0B5A),
        (2165, 790427, 0, 0x0BAA),
        (2166, 790782, 10, 0x1B54),
        (2167, 791166, 0, 0x0DA2),
        (2168, 791520, 0, 0x0D45),
        (2169, 791874, 6, 0x1A95),
        (2170, 792258, 0, 0x0A95),
        (2171, 792612, 0, 0x052D),
        (2172, 792966, 5, 0x09AD),
        (2173, 793350, 0, 0x0AB5),
        (2174, 793705, 0, 0x0DAA),
        (2175, 794060, 3, 0x1DA4),
        (2176, 794444, 0, 0x0EA2),
        (2177, 794798, 7, 0x1D46),
        (2178, 795182, 0, 0x0D4A),
        (2179, 795536, 0, 0x0A96),
        (2180, 795890, 6, 0x1536),
        (2181, 796274, 0, 0x055A),
        (2182, 796628, 0, 0x0AD5),
        (2183, 796983, 4, 0x16CA),
        (2184, 797367, 0, 0x0752),
        (2185, 797721, 0, 0x0EA5),
        (2186, 798076, 2, 0x0D4A),
        (2187, 798459, 0, 0x054B),
        (2188, 798813, 6, 0x0A97),
        (2189, 799197, 0, 0x0AAB),
        (2190, 799552, 0, 0x055A),
        (2191, 799906, 5, 0x0AD5),
        (2192, 800290, 0, 0x0B65),
        (2193, 800645, 0, 0x0752),
        (2194, 800999, 3, 0x1AA5),
        (2195, 801383, 0, 0x0B25),
        (2196, 801737, 7, 0x1A4B),
        (2197, 802121, 0, 0x094D),
        (2198, 802475, 0, 0x0AAD),
        (2199, 802830, 6, 0x156A),
        (2200, 803214, 0, 0x05B4),
    ]

    /// Liu flags these years' boundaries as day-level uncertain in principle
    /// (ΔT/leap-second extrapolation; a conjunction or zhongqi within minutes
    /// of midnight UTC+8). Divergence there is unadjudicable, not an error,
    /// but we still compare and report, and currently match Liu everywhere.
    private static let uncertainYears: Set<Int> = [2114, 2115, 2116, 2133, 2142, 2155, 2157, 2165, 2172, 2183, 2186, 2192]

    @Test func chineseLiu_fallbackZone2101_2200() {
        var failures: [String] = []
        var uncertainDiffs: [String] = []
        for (iso, cnyRD, leap, bits) in Self.liu {
            let y = _ChineseCalendarEngine.year(relatedISOYear: iso)
            var diffs: [String] = []
            if y.newYearRataDie != cnyRD { diffs.append("CNY rd \(y.newYearRataDie) vs Liu \(cnyRD)") }
            if Int(y.leapDisplay) != leap { diffs.append("leap \(y.leapDisplay) vs Liu \(leap)") }
            if y.monthLengthBits != bits { diffs.append("bits \(String(y.monthLengthBits, radix: 16)) vs Liu \(String(bits, radix: 16))") }
            if !diffs.isEmpty {
                let msg = "\(iso): \(diffs.joined(separator: "; "))"
                if Self.uncertainYears.contains(iso) || Self.uncertainYears.contains(iso - 1) {
                    uncertainDiffs.append(msg + " [Liu-flagged uncertain]")
                } else {
                    failures.append(msg)
                }
            }
        }
        print("[chineseLiu_fallbackZone2101_2200] years=\(Self.liu.count) failures=\(failures.count) uncertain-diffs=\(uncertainDiffs.count)")
        for f in failures.prefix(20) { print("    \(f)") }
        for u in uncertainDiffs { print("    \(u)") }
        #expect(failures.isEmpty, "\(failures.count) failures: \(failures.prefix(10))")
    }
}
