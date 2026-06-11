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

/// Pure-Swift Japanese imperial calendar. Same arithmetic as Gregorian; year
/// is reckoned within the current era (Meiji, Taishō, Shōwa, Heisei, Reiwa).
internal final class _CalendarJapanese: _CalendarProtocol, @unchecked Sendable {

    private struct EraEntry {
        let index: Int
        let startGregorianYear: Int
        let startMonth: Int
        let startDay: Int
    }

    /// All 237 Japanese eras (Taika 645 → Reiwa 2019), sorted descending by start date.
    /// Sourced from ICU4C `supplementalData.txt`. Index values match ICU's era numbering.
    /// TODO: Meiji (232) — Apple's runtime ICU treats Meiji start as 1868-09-08 not the
    /// CLDR-canonical 1868-10-23. Using 1868-09-08 here for runtime parity; revisit when
    /// we have time to investigate the data source discrepancy.
    private static let eras: [EraEntry] = [
        EraEntry(index: 236, startGregorianYear: 2019, startMonth: 5, startDay: 1),
        EraEntry(index: 235, startGregorianYear: 1989, startMonth: 1, startDay: 8),
        EraEntry(index: 234, startGregorianYear: 1926, startMonth: 12, startDay: 25),
        EraEntry(index: 233, startGregorianYear: 1912, startMonth: 7, startDay: 30),
        EraEntry(index: 232, startGregorianYear: 1868, startMonth: 9, startDay: 8),
        EraEntry(index: 231, startGregorianYear: 1865, startMonth: 4, startDay: 7),
        EraEntry(index: 230, startGregorianYear: 1864, startMonth: 2, startDay: 20),
        EraEntry(index: 229, startGregorianYear: 1861, startMonth: 2, startDay: 19),
        EraEntry(index: 228, startGregorianYear: 1860, startMonth: 3, startDay: 18),
        EraEntry(index: 227, startGregorianYear: 1854, startMonth: 11, startDay: 27),
        EraEntry(index: 226, startGregorianYear: 1848, startMonth: 2, startDay: 28),
        EraEntry(index: 225, startGregorianYear: 1844, startMonth: 12, startDay: 2),
        EraEntry(index: 224, startGregorianYear: 1830, startMonth: 12, startDay: 10),
        EraEntry(index: 223, startGregorianYear: 1818, startMonth: 4, startDay: 22),
        EraEntry(index: 222, startGregorianYear: 1804, startMonth: 2, startDay: 11),
        EraEntry(index: 221, startGregorianYear: 1801, startMonth: 2, startDay: 5),
        EraEntry(index: 220, startGregorianYear: 1789, startMonth: 1, startDay: 25),
        EraEntry(index: 219, startGregorianYear: 1781, startMonth: 4, startDay: 2),
        EraEntry(index: 218, startGregorianYear: 1772, startMonth: 11, startDay: 16),
        EraEntry(index: 217, startGregorianYear: 1764, startMonth: 6, startDay: 2),
        EraEntry(index: 216, startGregorianYear: 1751, startMonth: 10, startDay: 27),
        EraEntry(index: 215, startGregorianYear: 1748, startMonth: 7, startDay: 12),
        EraEntry(index: 214, startGregorianYear: 1744, startMonth: 2, startDay: 21),
        EraEntry(index: 213, startGregorianYear: 1741, startMonth: 2, startDay: 27),
        EraEntry(index: 212, startGregorianYear: 1736, startMonth: 4, startDay: 28),
        EraEntry(index: 211, startGregorianYear: 1716, startMonth: 6, startDay: 22),
        EraEntry(index: 210, startGregorianYear: 1711, startMonth: 4, startDay: 25),
        EraEntry(index: 209, startGregorianYear: 1704, startMonth: 3, startDay: 13),
        EraEntry(index: 208, startGregorianYear: 1688, startMonth: 9, startDay: 30),
        EraEntry(index: 207, startGregorianYear: 1684, startMonth: 2, startDay: 21),
        EraEntry(index: 206, startGregorianYear: 1681, startMonth: 9, startDay: 29),
        EraEntry(index: 205, startGregorianYear: 1673, startMonth: 9, startDay: 21),
        EraEntry(index: 204, startGregorianYear: 1661, startMonth: 4, startDay: 25),
        EraEntry(index: 203, startGregorianYear: 1658, startMonth: 7, startDay: 23),
        EraEntry(index: 202, startGregorianYear: 1655, startMonth: 4, startDay: 13),
        EraEntry(index: 201, startGregorianYear: 1652, startMonth: 9, startDay: 18),
        EraEntry(index: 200, startGregorianYear: 1648, startMonth: 2, startDay: 15),
        EraEntry(index: 199, startGregorianYear: 1644, startMonth: 12, startDay: 16),
        EraEntry(index: 198, startGregorianYear: 1624, startMonth: 2, startDay: 30),
        EraEntry(index: 197, startGregorianYear: 1615, startMonth: 7, startDay: 13),
        EraEntry(index: 196, startGregorianYear: 1596, startMonth: 10, startDay: 27),
        EraEntry(index: 195, startGregorianYear: 1592, startMonth: 12, startDay: 8),
        EraEntry(index: 194, startGregorianYear: 1573, startMonth: 7, startDay: 28),
        EraEntry(index: 193, startGregorianYear: 1570, startMonth: 4, startDay: 23),
        EraEntry(index: 192, startGregorianYear: 1558, startMonth: 2, startDay: 28),
        EraEntry(index: 191, startGregorianYear: 1555, startMonth: 10, startDay: 23),
        EraEntry(index: 190, startGregorianYear: 1532, startMonth: 7, startDay: 29),
        EraEntry(index: 189, startGregorianYear: 1528, startMonth: 8, startDay: 20),
        EraEntry(index: 188, startGregorianYear: 1521, startMonth: 8, startDay: 23),
        EraEntry(index: 187, startGregorianYear: 1504, startMonth: 2, startDay: 30),
        EraEntry(index: 186, startGregorianYear: 1501, startMonth: 2, startDay: 29),
        EraEntry(index: 185, startGregorianYear: 1492, startMonth: 7, startDay: 19),
        EraEntry(index: 184, startGregorianYear: 1489, startMonth: 8, startDay: 21),
        EraEntry(index: 183, startGregorianYear: 1487, startMonth: 7, startDay: 29),
        EraEntry(index: 182, startGregorianYear: 1469, startMonth: 4, startDay: 28),
        EraEntry(index: 181, startGregorianYear: 1467, startMonth: 3, startDay: 3),
        EraEntry(index: 180, startGregorianYear: 1466, startMonth: 2, startDay: 28),
        EraEntry(index: 179, startGregorianYear: 1460, startMonth: 12, startDay: 21),
        EraEntry(index: 178, startGregorianYear: 1457, startMonth: 9, startDay: 28),
        EraEntry(index: 177, startGregorianYear: 1455, startMonth: 7, startDay: 25),
        EraEntry(index: 176, startGregorianYear: 1452, startMonth: 7, startDay: 25),
        EraEntry(index: 175, startGregorianYear: 1449, startMonth: 7, startDay: 28),
        EraEntry(index: 174, startGregorianYear: 1444, startMonth: 2, startDay: 5),
        EraEntry(index: 173, startGregorianYear: 1441, startMonth: 2, startDay: 17),
        EraEntry(index: 172, startGregorianYear: 1429, startMonth: 9, startDay: 5),
        EraEntry(index: 171, startGregorianYear: 1428, startMonth: 4, startDay: 27),
        EraEntry(index: 170, startGregorianYear: 1394, startMonth: 7, startDay: 5),
        EraEntry(index: 169, startGregorianYear: 1390, startMonth: 3, startDay: 26),
        EraEntry(index: 168, startGregorianYear: 1389, startMonth: 2, startDay: 9),
        EraEntry(index: 167, startGregorianYear: 1387, startMonth: 8, startDay: 23),
        EraEntry(index: 166, startGregorianYear: 1387, startMonth: 8, startDay: 22),
        EraEntry(index: 165, startGregorianYear: 1384, startMonth: 4, startDay: 28),
        EraEntry(index: 164, startGregorianYear: 1381, startMonth: 2, startDay: 10),
        EraEntry(index: 163, startGregorianYear: 1379, startMonth: 3, startDay: 22),
        EraEntry(index: 162, startGregorianYear: 1375, startMonth: 5, startDay: 27),
        EraEntry(index: 161, startGregorianYear: 1372, startMonth: 4, startDay: 1),
        EraEntry(index: 160, startGregorianYear: 1370, startMonth: 7, startDay: 24),
        EraEntry(index: 159, startGregorianYear: 1346, startMonth: 12, startDay: 8),
        EraEntry(index: 158, startGregorianYear: 1340, startMonth: 4, startDay: 28),
        EraEntry(index: 157, startGregorianYear: 1336, startMonth: 2, startDay: 29),
        EraEntry(index: 156, startGregorianYear: 1334, startMonth: 1, startDay: 29),
        EraEntry(index: 155, startGregorianYear: 1331, startMonth: 8, startDay: 9),
        EraEntry(index: 154, startGregorianYear: 1329, startMonth: 8, startDay: 29),
        EraEntry(index: 153, startGregorianYear: 1326, startMonth: 4, startDay: 26),
        EraEntry(index: 152, startGregorianYear: 1324, startMonth: 12, startDay: 9),
        EraEntry(index: 151, startGregorianYear: 1321, startMonth: 2, startDay: 23),
        EraEntry(index: 150, startGregorianYear: 1319, startMonth: 4, startDay: 28),
        EraEntry(index: 149, startGregorianYear: 1317, startMonth: 2, startDay: 3),
        EraEntry(index: 148, startGregorianYear: 1312, startMonth: 3, startDay: 20),
        EraEntry(index: 147, startGregorianYear: 1311, startMonth: 4, startDay: 28),
        EraEntry(index: 146, startGregorianYear: 1308, startMonth: 10, startDay: 9),
        EraEntry(index: 145, startGregorianYear: 1306, startMonth: 12, startDay: 14),
        EraEntry(index: 144, startGregorianYear: 1303, startMonth: 8, startDay: 5),
        EraEntry(index: 143, startGregorianYear: 1302, startMonth: 11, startDay: 21),
        EraEntry(index: 142, startGregorianYear: 1299, startMonth: 4, startDay: 25),
        EraEntry(index: 141, startGregorianYear: 1293, startMonth: 8, startDay: 5),
        EraEntry(index: 140, startGregorianYear: 1288, startMonth: 4, startDay: 28),
        EraEntry(index: 139, startGregorianYear: 1278, startMonth: 2, startDay: 29),
        EraEntry(index: 138, startGregorianYear: 1275, startMonth: 4, startDay: 25),
        EraEntry(index: 137, startGregorianYear: 1264, startMonth: 2, startDay: 28),
        EraEntry(index: 136, startGregorianYear: 1261, startMonth: 2, startDay: 20),
        EraEntry(index: 135, startGregorianYear: 1260, startMonth: 4, startDay: 13),
        EraEntry(index: 134, startGregorianYear: 1259, startMonth: 3, startDay: 26),
        EraEntry(index: 133, startGregorianYear: 1257, startMonth: 3, startDay: 14),
        EraEntry(index: 132, startGregorianYear: 1256, startMonth: 10, startDay: 5),
        EraEntry(index: 131, startGregorianYear: 1249, startMonth: 3, startDay: 18),
        EraEntry(index: 130, startGregorianYear: 1247, startMonth: 2, startDay: 28),
        EraEntry(index: 129, startGregorianYear: 1243, startMonth: 2, startDay: 26),
        EraEntry(index: 128, startGregorianYear: 1240, startMonth: 7, startDay: 16),
        EraEntry(index: 127, startGregorianYear: 1239, startMonth: 2, startDay: 7),
        EraEntry(index: 126, startGregorianYear: 1238, startMonth: 11, startDay: 23),
        EraEntry(index: 125, startGregorianYear: 1235, startMonth: 9, startDay: 19),
        EraEntry(index: 124, startGregorianYear: 1234, startMonth: 11, startDay: 5),
        EraEntry(index: 123, startGregorianYear: 1233, startMonth: 4, startDay: 15),
        EraEntry(index: 122, startGregorianYear: 1232, startMonth: 4, startDay: 2),
        EraEntry(index: 121, startGregorianYear: 1229, startMonth: 3, startDay: 5),
        EraEntry(index: 120, startGregorianYear: 1227, startMonth: 12, startDay: 10),
        EraEntry(index: 119, startGregorianYear: 1225, startMonth: 4, startDay: 20),
        EraEntry(index: 118, startGregorianYear: 1224, startMonth: 11, startDay: 20),
        EraEntry(index: 117, startGregorianYear: 1222, startMonth: 4, startDay: 13),
        EraEntry(index: 116, startGregorianYear: 1219, startMonth: 4, startDay: 12),
        EraEntry(index: 115, startGregorianYear: 1213, startMonth: 12, startDay: 6),
        EraEntry(index: 114, startGregorianYear: 1211, startMonth: 3, startDay: 9),
        EraEntry(index: 113, startGregorianYear: 1207, startMonth: 10, startDay: 25),
        EraEntry(index: 112, startGregorianYear: 1206, startMonth: 4, startDay: 27),
        EraEntry(index: 111, startGregorianYear: 1204, startMonth: 2, startDay: 20),
        EraEntry(index: 110, startGregorianYear: 1201, startMonth: 2, startDay: 13),
        EraEntry(index: 109, startGregorianYear: 1199, startMonth: 4, startDay: 27),
        EraEntry(index: 108, startGregorianYear: 1190, startMonth: 4, startDay: 11),
        EraEntry(index: 107, startGregorianYear: 1185, startMonth: 8, startDay: 14),
        EraEntry(index: 106, startGregorianYear: 1184, startMonth: 4, startDay: 16),
        EraEntry(index: 105, startGregorianYear: 1182, startMonth: 5, startDay: 27),
        EraEntry(index: 104, startGregorianYear: 1181, startMonth: 7, startDay: 14),
        EraEntry(index: 103, startGregorianYear: 1177, startMonth: 8, startDay: 4),
        EraEntry(index: 102, startGregorianYear: 1175, startMonth: 7, startDay: 28),
        EraEntry(index: 101, startGregorianYear: 1171, startMonth: 4, startDay: 21),
        EraEntry(index: 100, startGregorianYear: 1169, startMonth: 4, startDay: 8),
        EraEntry(index: 99, startGregorianYear: 1166, startMonth: 8, startDay: 27),
        EraEntry(index: 98, startGregorianYear: 1165, startMonth: 6, startDay: 5),
        EraEntry(index: 97, startGregorianYear: 1163, startMonth: 3, startDay: 29),
        EraEntry(index: 96, startGregorianYear: 1161, startMonth: 9, startDay: 4),
        EraEntry(index: 95, startGregorianYear: 1160, startMonth: 1, startDay: 10),
        EraEntry(index: 94, startGregorianYear: 1159, startMonth: 4, startDay: 20),
        EraEntry(index: 93, startGregorianYear: 1156, startMonth: 4, startDay: 27),
        EraEntry(index: 92, startGregorianYear: 1154, startMonth: 10, startDay: 28),
        EraEntry(index: 91, startGregorianYear: 1151, startMonth: 1, startDay: 26),
        EraEntry(index: 90, startGregorianYear: 1145, startMonth: 7, startDay: 22),
        EraEntry(index: 89, startGregorianYear: 1144, startMonth: 2, startDay: 23),
        EraEntry(index: 88, startGregorianYear: 1142, startMonth: 4, startDay: 28),
        EraEntry(index: 87, startGregorianYear: 1141, startMonth: 7, startDay: 10),
        EraEntry(index: 86, startGregorianYear: 1135, startMonth: 4, startDay: 27),
        EraEntry(index: 85, startGregorianYear: 1132, startMonth: 8, startDay: 11),
        EraEntry(index: 84, startGregorianYear: 1131, startMonth: 1, startDay: 29),
        EraEntry(index: 83, startGregorianYear: 1126, startMonth: 1, startDay: 22),
        EraEntry(index: 82, startGregorianYear: 1124, startMonth: 4, startDay: 3),
        EraEntry(index: 81, startGregorianYear: 1120, startMonth: 4, startDay: 10),
        EraEntry(index: 80, startGregorianYear: 1118, startMonth: 4, startDay: 3),
        EraEntry(index: 79, startGregorianYear: 1113, startMonth: 7, startDay: 13),
        EraEntry(index: 78, startGregorianYear: 1110, startMonth: 7, startDay: 13),
        EraEntry(index: 77, startGregorianYear: 1108, startMonth: 8, startDay: 3),
        EraEntry(index: 76, startGregorianYear: 1106, startMonth: 4, startDay: 9),
        EraEntry(index: 75, startGregorianYear: 1104, startMonth: 2, startDay: 10),
        EraEntry(index: 74, startGregorianYear: 1099, startMonth: 8, startDay: 28),
        EraEntry(index: 73, startGregorianYear: 1097, startMonth: 11, startDay: 21),
        EraEntry(index: 72, startGregorianYear: 1096, startMonth: 12, startDay: 17),
        EraEntry(index: 71, startGregorianYear: 1094, startMonth: 12, startDay: 15),
        EraEntry(index: 70, startGregorianYear: 1087, startMonth: 4, startDay: 7),
        EraEntry(index: 69, startGregorianYear: 1084, startMonth: 2, startDay: 7),
        EraEntry(index: 68, startGregorianYear: 1081, startMonth: 2, startDay: 10),
        EraEntry(index: 67, startGregorianYear: 1077, startMonth: 11, startDay: 17),
        EraEntry(index: 66, startGregorianYear: 1074, startMonth: 8, startDay: 23),
        EraEntry(index: 65, startGregorianYear: 1069, startMonth: 4, startDay: 13),
        EraEntry(index: 64, startGregorianYear: 1065, startMonth: 8, startDay: 2),
        EraEntry(index: 63, startGregorianYear: 1058, startMonth: 8, startDay: 29),
        EraEntry(index: 62, startGregorianYear: 1053, startMonth: 1, startDay: 11),
        EraEntry(index: 61, startGregorianYear: 1046, startMonth: 4, startDay: 14),
        EraEntry(index: 60, startGregorianYear: 1044, startMonth: 11, startDay: 24),
        EraEntry(index: 59, startGregorianYear: 1040, startMonth: 11, startDay: 10),
        EraEntry(index: 58, startGregorianYear: 1037, startMonth: 4, startDay: 21),
        EraEntry(index: 57, startGregorianYear: 1028, startMonth: 7, startDay: 25),
        EraEntry(index: 56, startGregorianYear: 1024, startMonth: 7, startDay: 13),
        EraEntry(index: 55, startGregorianYear: 1021, startMonth: 2, startDay: 2),
        EraEntry(index: 54, startGregorianYear: 1017, startMonth: 4, startDay: 23),
        EraEntry(index: 53, startGregorianYear: 1012, startMonth: 12, startDay: 25),
        EraEntry(index: 52, startGregorianYear: 1004, startMonth: 7, startDay: 20),
        EraEntry(index: 51, startGregorianYear: 999, startMonth: 1, startDay: 13),
        EraEntry(index: 50, startGregorianYear: 995, startMonth: 2, startDay: 22),
        EraEntry(index: 49, startGregorianYear: 990, startMonth: 11, startDay: 7),
        EraEntry(index: 48, startGregorianYear: 989, startMonth: 8, startDay: 8),
        EraEntry(index: 47, startGregorianYear: 987, startMonth: 4, startDay: 5),
        EraEntry(index: 46, startGregorianYear: 985, startMonth: 4, startDay: 27),
        EraEntry(index: 45, startGregorianYear: 983, startMonth: 4, startDay: 15),
        EraEntry(index: 44, startGregorianYear: 978, startMonth: 11, startDay: 29),
        EraEntry(index: 43, startGregorianYear: 976, startMonth: 7, startDay: 13),
        EraEntry(index: 42, startGregorianYear: 973, startMonth: 12, startDay: 20),
        EraEntry(index: 41, startGregorianYear: 970, startMonth: 3, startDay: 25),
        EraEntry(index: 40, startGregorianYear: 968, startMonth: 8, startDay: 13),
        EraEntry(index: 39, startGregorianYear: 964, startMonth: 7, startDay: 10),
        EraEntry(index: 38, startGregorianYear: 961, startMonth: 2, startDay: 16),
        EraEntry(index: 37, startGregorianYear: 957, startMonth: 10, startDay: 27),
        EraEntry(index: 36, startGregorianYear: 947, startMonth: 4, startDay: 22),
        EraEntry(index: 35, startGregorianYear: 938, startMonth: 5, startDay: 22),
        EraEntry(index: 34, startGregorianYear: 931, startMonth: 4, startDay: 26),
        EraEntry(index: 33, startGregorianYear: 923, startMonth: 4, startDay: 11),
        EraEntry(index: 32, startGregorianYear: 901, startMonth: 7, startDay: 15),
        EraEntry(index: 31, startGregorianYear: 898, startMonth: 4, startDay: 26),
        EraEntry(index: 30, startGregorianYear: 889, startMonth: 4, startDay: 27),
        EraEntry(index: 29, startGregorianYear: 885, startMonth: 2, startDay: 21),
        EraEntry(index: 28, startGregorianYear: 877, startMonth: 4, startDay: 16),
        EraEntry(index: 27, startGregorianYear: 859, startMonth: 4, startDay: 15),
        EraEntry(index: 26, startGregorianYear: 857, startMonth: 2, startDay: 21),
        EraEntry(index: 25, startGregorianYear: 854, startMonth: 11, startDay: 30),
        EraEntry(index: 24, startGregorianYear: 851, startMonth: 4, startDay: 28),
        EraEntry(index: 23, startGregorianYear: 848, startMonth: 6, startDay: 13),
        EraEntry(index: 22, startGregorianYear: 834, startMonth: 1, startDay: 3),
        EraEntry(index: 21, startGregorianYear: 824, startMonth: 1, startDay: 5),
        EraEntry(index: 20, startGregorianYear: 810, startMonth: 9, startDay: 19),
        EraEntry(index: 19, startGregorianYear: 806, startMonth: 5, startDay: 18),
        EraEntry(index: 18, startGregorianYear: 782, startMonth: 8, startDay: 19),
        EraEntry(index: 17, startGregorianYear: 781, startMonth: 1, startDay: 1),
        EraEntry(index: 16, startGregorianYear: 770, startMonth: 10, startDay: 1),
        EraEntry(index: 15, startGregorianYear: 767, startMonth: 8, startDay: 16),
        EraEntry(index: 14, startGregorianYear: 765, startMonth: 1, startDay: 7),
        EraEntry(index: 13, startGregorianYear: 757, startMonth: 8, startDay: 18),
        EraEntry(index: 12, startGregorianYear: 749, startMonth: 7, startDay: 2),
        EraEntry(index: 11, startGregorianYear: 749, startMonth: 4, startDay: 14),
        EraEntry(index: 10, startGregorianYear: 729, startMonth: 8, startDay: 5),
        EraEntry(index: 9, startGregorianYear: 724, startMonth: 2, startDay: 4),
        EraEntry(index: 8, startGregorianYear: 717, startMonth: 11, startDay: 17),
        EraEntry(index: 7, startGregorianYear: 715, startMonth: 9, startDay: 2),
        EraEntry(index: 6, startGregorianYear: 708, startMonth: 1, startDay: 11),
        EraEntry(index: 5, startGregorianYear: 704, startMonth: 5, startDay: 10),
        EraEntry(index: 4, startGregorianYear: 701, startMonth: 3, startDay: 21),
        EraEntry(index: 3, startGregorianYear: 686, startMonth: 7, startDay: 20),
        EraEntry(index: 2, startGregorianYear: 672, startMonth: 1, startDay: 1),
        EraEntry(index: 1, startGregorianYear: 650, startMonth: 2, startDay: 15),
        EraEntry(index: 0, startGregorianYear: 645, startMonth: 6, startDay: 19),
    ]

    private let gregorian: _CalendarGregorian

    init(identifier: Calendar.Identifier, timeZone: TimeZone?, locale: Locale?, firstWeekday: Int?, minimumDaysInFirstWeek: Int?, gregorianStartDate: Date?) {
        assert(identifier == .japanese, "_CalendarJapanese only handles .japanese")
        self.gregorian = _CalendarGregorian(identifier: .gregorian, timeZone: timeZone, locale: locale, firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek, gregorianStartDate: gregorianStartDate)
    }

    let identifier: Calendar.Identifier = .japanese

    var locale: Locale? {
        get { gregorian.locale }
        set { gregorian.locale = newValue }
    }

    var timeZone: TimeZone {
        get { gregorian.timeZone }
        set { gregorian.timeZone = newValue }
    }

    var firstWeekday: Int {
        get { gregorian.firstWeekday }
        set { gregorian.firstWeekday = newValue }
    }

    var minimumDaysInFirstWeek: Int {
        get { gregorian.minimumDaysInFirstWeek }
        set { gregorian.minimumDaysInFirstWeek = newValue }
    }

    func copy(changingLocale: Locale?, changingTimeZone: TimeZone?, changingFirstWeekday: Int?, changingMinimumDaysInFirstWeek: Int?) -> any _CalendarProtocol {
        let args = _CalendarUtility.resolvedCopyArgs(
            currentTimeZone: gregorian.timeZone, changingTimeZone: changingTimeZone,
            currentLocale: gregorian.locale, changingLocale: changingLocale,
            currentFirstWeekday: gregorian._firstWeekday, changingFirstWeekday: changingFirstWeekday,
            currentMinimumDaysInFirstWeek: gregorian._minimumDaysInFirstWeek, changingMinimumDaysInFirstWeek: changingMinimumDaysInFirstWeek
        )
        return _CalendarJapanese(identifier: identifier, timeZone: args.timeZone, locale: args.locale, firstWeekday: args.firstWeekday, minimumDaysInFirstWeek: args.minimumDaysInFirstWeek, gregorianStartDate: nil)
    }

    var supportsNextDateFastPath: Bool { gregorian.supportsNextDateFastPath }

    // MARK: - Range

    func minimumRange(of component: Calendar.Component) -> Range<Int>? {
        if component == .era { return 0..<(Self.eras.last!.index + Self.eras.count) }
        if component == .year { return 1..<2 }
        return gregorian.minimumRange(of: component)
    }

    func maximumRange(of component: Calendar.Component) -> Range<Int>? {
        if component == .era { return 0..<(Self.eras.first!.index + 1) }
        return gregorian.maximumRange(of: component)
    }

    func range(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Range<Int>? {
        gregorian.range(of: smaller, in: larger, for: date)
    }

    func ordinality(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Int? {
        gregorian.ordinality(of: smaller, in: larger, for: date)
    }

    func dateInterval(of component: Calendar.Component, for date: Date) -> DateInterval? {
        if component == .era {
            return eraInterval(containing: date)
        }
        return gregorian.dateInterval(of: component, for: date)
    }

    func isDateInWeekend(_ date: Date) -> Bool {
        gregorian.isDateInWeekend(date)
    }

    // MARK: - Date / DateComponents conversion

    func date(from components: DateComponents) -> Date? {
        gregorian.date(from: convertedToGregorian(components))
    }

    func dateComponents(_ components: Calendar.ComponentSet, from date: Date, in timeZone: TimeZone) -> DateComponents {
        var dc = gregorian.dateComponents(components, from: date, in: timeZone)
        adjustToJapanese(&dc, date: date, requested: components)
        return dc
    }

    func dateComponents(_ components: Calendar.ComponentSet, from date: Date) -> DateComponents {
        var dc = gregorian.dateComponents(components, from: date)
        adjustToJapanese(&dc, date: date, requested: components)
        return dc
    }

    func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool) -> Date? {
        gregorian.date(byAdding: components, to: date, wrappingComponents: wrappingComponents)
    }

    func dateComponents(_ components: Calendar.ComponentSet, from start: Date, to end: Date) -> DateComponents {
        var dc = gregorian.dateComponents(components, from: start, to: end)
        if components.contains(.year) {
            dc.year = japaneseYearDifference(from: start, to: end)
        }
        return dc
    }

    func nextDate(after date: Date, matching components: DateComponents, direction: Calendar.SearchDirection) -> Date? {
        gregorian.nextDate(after: date, matching: convertedToGregorian(components), direction: direction)
    }

    // MARK: - Era helpers

    private func eraEntry(forGregorianYear y: Int, month m: Int, day d: Int) -> EraEntry? {
        for era in Self.eras {
            if (y, m, d) >= (era.startGregorianYear, era.startMonth, era.startDay) {
                return era
            }
        }
        return nil
    }

    private func eraEntry(byIndex index: Int) -> EraEntry? {
        Self.eras.first(where: { $0.index == index })
    }

    private func eraInterval(containing date: Date) -> DateInterval? {
        let comps = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
        guard let era = eraEntry(forGregorianYear: y, month: m, day: d) else {
            return gregorian.dateInterval(of: .era, for: date)
        }
        var startDC = DateComponents()
        startDC.year = era.startGregorianYear
        startDC.month = era.startMonth
        startDC.day = era.startDay
        startDC.hour = 0; startDC.minute = 0; startDC.second = 0
        guard let start = gregorian.date(from: startDC) else { return nil }
        let endDate: Date
        if let next = Self.eras.lastIndex(where: { $0.index == era.index }).flatMap({ idx in idx > 0 ? Self.eras[idx - 1] : nil }) {
            var endDC = DateComponents()
            endDC.year = next.startGregorianYear
            endDC.month = next.startMonth
            endDC.day = next.startDay
            endDC.hour = 0; endDC.minute = 0; endDC.second = 0
            guard let e = gregorian.date(from: endDC) else { return nil }
            endDate = e
        } else {
            endDate = start.addingTimeInterval(Calendar._inf_ti)
        }
        return DateInterval(start: start, end: endDate)
    }

    private func japaneseYearDifference(from start: Date, to end: Date) -> Int {
        let s = gregorian.dateComponents([.year], from: start).year ?? 0
        let e = gregorian.dateComponents([.year], from: end).year ?? 0
        return e - s
    }

    // MARK: - Components conversion

    private func convertedToGregorian(_ components: DateComponents) -> DateComponents {
        var dc = components
        if let era = dc.era, let year = dc.year, let eraEntry = eraEntry(byIndex: era) {
            dc.year = year + eraEntry.startGregorianYear - 1
        }
        dc.era = nil
        return dc
    }

    private func adjustToJapanese(_ dc: inout DateComponents, date: Date, requested: Calendar.ComponentSet) {
        guard requested.contains(.era) || requested.contains(.year) else { return }
        let probe = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let y = probe.year, let m = probe.month, let d = probe.day else { return }
        if let era = eraEntry(forGregorianYear: y, month: m, day: d) {
            if requested.contains(.era) { dc.era = era.index }
            if requested.contains(.year) { dc.year = y - era.startGregorianYear + 1 }
        }
        // For pre-Meiji dates, leave gregorian's era + year as-is.
    }
}
