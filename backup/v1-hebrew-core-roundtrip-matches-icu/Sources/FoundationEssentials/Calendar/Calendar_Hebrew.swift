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

#if canImport(os)
internal import os
#elseif canImport(Bionic)
@preconcurrency import Bionic
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(CRT)
import CRT
#elseif os(WASI)
@preconcurrency import WASILibc
#endif

/// Pure-Swift implementation of the Hebrew calendar, derived from the
/// Reingold & Dershowitz algorithms (`Calendrical Calculations`) via
/// `icu4swift/Sources/CalendarComplex/HebrewArithmetic.swift`.
///
/// This replaces the ICU4C-backed Hebrew path in `_CalendarICU`. It works on
/// all supported platforms (including Linux, which cannot compile ICU without
/// significant effort) and is substantially faster than the ICU path because
/// Foundation's `_CalendarProtocol` contract does not require the ICU
/// `ucal_set` / `add` / `roll` eager-recalculation semantics.
internal final class _CalendarHebrew: _CalendarProtocol, @unchecked Sendable {

#if canImport(os)
    internal static let logger: Logger = {
        Logger(subsystem: "com.apple.foundation", category: "hebrew_calendar")
    }()
#endif

    let kSecondsInWeek = 604_800
    let kSecondsInDay = 86400
    let kSecondsInHour = 3600
    let kSecondsInMinute = 60

    let inf_ti: TimeInterval = 4398046511104.0

    init(identifier: Calendar.Identifier, timeZone: TimeZone?, locale: Locale?, firstWeekday: Int?, minimumDaysInFirstWeek: Int?, gregorianStartDate: Date?) {
        // .hebrew is the only identifier this class handles. `gregorianStartDate`
        // is ignored (only the Gregorian/Julian cutover calendar uses it).
        assert(identifier == .hebrew, "_CalendarHebrew only handles .hebrew")

        self.identifier = identifier
        self.timeZone = timeZone ?? .default
        self.locale = locale

        if let firstWeekday, (firstWeekday >= 1 && firstWeekday <= 7) {
            _firstWeekday = firstWeekday
        }

        if var minimumDaysInFirstWeek {
            if minimumDaysInFirstWeek < 1 {
                minimumDaysInFirstWeek = 1
            } else if minimumDaysInFirstWeek > 7 {
                minimumDaysInFirstWeek = 7
            }
            _minimumDaysInFirstWeek = minimumDaysInFirstWeek
        }
    }

    let identifier: Calendar.Identifier

    var locale: Locale?

    var timeZone: TimeZone

    var _firstWeekday: Int?
    var firstWeekday: Int {
        set {
            precondition(newValue >= 1 && newValue <= 7, "Weekday should be in the range of 1...7")
            _firstWeekday = newValue
        }
        get {
            if let _firstWeekday {
                return _firstWeekday
            } else if let locale {
                return locale.firstDayOfWeek.icuIndex
            } else {
                return 1
            }
        }
    }

    var _minimumDaysInFirstWeek: Int?
    var minimumDaysInFirstWeek: Int {
        set {
            if newValue < 1 {
                _minimumDaysInFirstWeek = 1
            } else if newValue > 7 {
                _minimumDaysInFirstWeek = 7
            } else {
                _minimumDaysInFirstWeek = newValue
            }
        }
        get {
            if let _minimumDaysInFirstWeek {
                return _minimumDaysInFirstWeek
            } else if let locale {
                return locale.minimumDaysInFirstWeek
            } else {
                return 1
            }
        }
    }

    func copy(changingLocale: Locale?, changingTimeZone: TimeZone?, changingFirstWeekday: Int?, changingMinimumDaysInFirstWeek: Int?) -> _CalendarProtocol {
        let newTimeZone = changingTimeZone ?? self.timeZone
        let newLocale = changingLocale ?? self.locale

        let newFirstWeekday: Int?
        if let changingFirstWeekday {
            newFirstWeekday = changingFirstWeekday
        } else if let _firstWeekday {
            newFirstWeekday = _firstWeekday
        } else {
            newFirstWeekday = nil
        }

        let newMinDays: Int?
        if let changingMinimumDaysInFirstWeek {
            newMinDays = changingMinimumDaysInFirstWeek
        } else if let _minimumDaysInFirstWeek {
            newMinDays = _minimumDaysInFirstWeek
        } else {
            newMinDays = nil
        }

        return _CalendarHebrew(identifier: identifier, timeZone: newTimeZone, locale: newLocale, firstWeekday: newFirstWeekday, minimumDaysInFirstWeek: newMinDays, gregorianStartDate: nil)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(timeZone)
        hasher.combine(firstWeekday)
        hasher.combine(minimumDaysInFirstWeek)
        hasher.combine(localeIdentifier)
        hasher.combine(preferredFirstWeekday)
        hasher.combine(preferredMinimumDaysInFirstweek)
    }

    // MARK: - Range

    func minimumRange(of component: Calendar.Component) -> Range<Int>? {
        fatalError("TODO: minimumRange")
    }

    func maximumRange(of component: Calendar.Component) -> Range<Int>? {
        fatalError("TODO: maximumRange")
    }

    func range(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Range<Int>? {
        fatalError("TODO: range(of:in:for:)")
    }

    // MARK: - Ordinality

    func ordinality(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Int? {
        fatalError("TODO: ordinality(of:in:for:)")
    }

    // MARK: - Date intervals

    func dateInterval(of component: Calendar.Component, for date: Date) -> DateInterval? {
        fatalError("TODO: dateInterval(of:for:)")
    }

    // MARK: - Weekend queries

    func isDateInWeekend(_ date: Date) -> Bool {
        fatalError("TODO: isDateInWeekend")
    }

    // MARK: - Date ↔ DateComponents

    /// Rata Die day number of Date's reference instant (midnight UTC, Jan 1 2001).
    private static let rataDieAtDateReference: Int64 = 730_486

    /// Convert a local-seconds-since-reference value to (RD, seconds-in-day).
    private static func rataDieAndSecondsInDay(localSeconds: Double) -> (rd: Int64, secondsInDay: Double) {
        let totalDays = (localSeconds / 86400).rounded(.down)
        let rd = Int64(totalDays) &+ rataDieAtDateReference
        let secondsInDay = localSeconds - totalDays * 86400
        return (rd, secondsInDay)
    }

    /// Given a fixed-day RD + local-seconds-within-day, build a UTC Date after
    /// subtracting the TimeZone offset at that local instant.
    private func utcDate(fromRataDie rd: Int64, secondsInDay: Double, in timeZone: TimeZone,
                        repeatedTimePolicy: TimeZone.DaylightSavingTimePolicy,
                        skippedTimePolicy: TimeZone.DaylightSavingTimePolicy) -> Date {
        let daysSinceRef = rd &- Self.rataDieAtDateReference
        let secondsAsIfUTC = Double(daysSinceRef) * 86400 + secondsInDay
        let tmpDate = Date(timeIntervalSinceReferenceDate: secondsAsIfUTC)
        let (tzOffset, dstOffset) = timeZone.rawAndDaylightSavingTimeOffset(
            for: tmpDate, repeatedTimePolicy: repeatedTimePolicy, skippedTimePolicy: skippedTimePolicy)
        return tmpDate - Double(tzOffset) - dstOffset
    }

    func date(from components: DateComponents) -> Date? {
        // If the components specify era = 0 (BAH — before AM), refuse: Hebrew
        // calendar's AM era starts at year 1 and is by construction positive.
        // Most callers pass era = 1 or no era (we treat no-era as AM = 1).
        if let era = components.era, era != 1 {
            return nil
        }

        guard let yearValue = components.year else { return nil }
        guard yearValue >= Int(Int32.min) && yearValue <= Int(Int32.max) else { return nil }
        let year = Int32(yearValue)

        let civilMonth = components.month ?? 1
        let day = components.day ?? 1

        // Validate civil month is in 1..13 AND corresponds to a real month in this
        // year (civil month 6 is "Adar I" which only exists in leap years).
        guard civilMonth >= 1 && civilMonth <= 13,
              let biblical = HebrewArithmetic.civilToBiblical(year: year, civilMonth: UInt8(civilMonth)) else {
            return nil
        }
        let daysInMonth = Int(HebrewArithmetic.lastDayOfMonth(year, month: biblical))
        guard day >= 1 && day <= daysInMonth else { return nil }

        let rd = HebrewArithmetic.fixedFromHebrew(year: year, month: biblical, day: UInt8(day))

        // Time-of-day in local seconds (defaults to midnight).
        var secondsInDay: Double = 0
        if let hour = components.hour { secondsInDay += Double(hour) * 3600 }
        if let minute = components.minute { secondsInDay += Double(minute) * 60 }
        if let second = components.second { secondsInDay += Double(second) }
        if let nanosecond = components.nanosecond { secondsInDay += Double(nanosecond) / 1e9 }

        let tz = components.timeZone ?? timeZone
        // Matches _CalendarGregorian's DST policy: skipped and repeated both resolve to .former.
        return utcDate(fromRataDie: rd, secondsInDay: secondsInDay, in: tz,
                      repeatedTimePolicy: .former, skippedTimePolicy: .former)
    }

    func dateComponents(_ components: Calendar.ComponentSet, from date: Date, in timeZone: TimeZone) -> DateComponents {
        // Shift to local time by adding the TZ offset, then floor to a day number.
        let (tzOffset, dstOffset) = timeZone.rawAndDaylightSavingTimeOffset(
            for: date, repeatedTimePolicy: .former, skippedTimePolicy: .former)
        let localSeconds = date.timeIntervalSinceReferenceDate + Double(tzOffset) + dstOffset
        let (rd, secondsInDay) = Self.rataDieAndSecondsInDay(localSeconds: localSeconds)

        let (year, biblicalMonth, day) = HebrewArithmetic.hebrewFromFixed(rd)
        let civilMonth = HebrewArithmetic.biblicalToCivil(year: year, biblicalMonth: biblicalMonth)

        var result = DateComponents()

        if components.contains(.era) { result.era = 1 } // AM
        if components.contains(.year) { result.year = Int(year) }
        if components.contains(.month) { result.month = Int(civilMonth) }
        if components.contains(.day) { result.day = Int(day) }
        if components.contains(.isLeapMonth) {
            // Foundation's `.hebrew` (ICU-backed) always reports `isLeapMonth = false`
            // for Hebrew — the leap-month distinction is encoded in the stable month
            // numbering (Adar I = civil 6, only in leap years) rather than a flag.
            // Match that behavior.
            result.isLeapMonth = false
        }

        // Time-of-day components.
        if components.contains(.hour) || components.contains(.minute)
            || components.contains(.second) || components.contains(.nanosecond) {
            let h = Int(secondsInDay / 3600)
            let remAfterH = secondsInDay - Double(h) * 3600
            let m = Int(remAfterH / 60)
            let remAfterM = remAfterH - Double(m) * 60
            let s = Int(remAfterM)
            let fractional = remAfterM - Double(s)
            let ns = Int((fractional * 1e9).rounded())
            if components.contains(.hour) { result.hour = h }
            if components.contains(.minute) { result.minute = m }
            if components.contains(.second) { result.second = s }
            if components.contains(.nanosecond) { result.nanosecond = ns }
        }

        if components.contains(.weekday) {
            // RD 1 = Monday (Jan 1, year 1 ISO). Civil weekday: Sunday=1..Saturday=7.
            // Mapping: (RD mod 7) → weekday
            //   RD mod 7 == 0 → Sunday (1)
            //   RD mod 7 == 1 → Monday (2)
            //   RD mod 7 == 2 → Tuesday (3)  ... etc.
            var r = rd % 7
            if r < 0 { r += 7 }
            result.weekday = Int(r) + 1
        }

        if components.contains(.dayOfYear) {
            // Days preceding this civil month in this year, + day.
            let preceding = Int(HebrewArithmetic.daysPrecedingCivilMonth(
                year: year, civilMonth: UInt8(civilMonth)))
            result.dayOfYear = preceding + Int(day)
        }

        if components.contains(.timeZone) {
            result.timeZone = timeZone
        }

        // Components not yet implemented: .weekdayOrdinal, .quarter, .weekOfMonth,
        // .weekOfYear, .yearForWeekOfYear, .calendar, .isRepeatedDay.
        // These are filled in by later work.

        return result
    }

    func dateComponents(_ components: Calendar.ComponentSet, from date: Date) -> DateComponents {
        dateComponents(components, from: date, in: self.timeZone)
    }

    func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool) -> Date? {
        fatalError("TODO: date(byAdding:to:wrappingComponents:)")
    }

    func dateComponents(_ components: Calendar.ComponentSet, from start: Date, to end: Date) -> DateComponents {
        fatalError("TODO: dateComponents(_:from:to:)")
    }

#if FOUNDATION_FRAMEWORK
    func bridgeToNSCalendar() -> NSCalendar {
        fatalError("TODO: bridgeToNSCalendar")
    }
#endif
}

// MARK: - Hebrew calendrical arithmetic (Reingold & Dershowitz)

/// Low-level arithmetic for the Hebrew calendar.
///
/// Algorithms from "Calendrical Calculations" by Reingold & Dershowitz (4th ed., 2018),
/// ported from `icu4swift/Sources/CalendarComplex/HebrewArithmetic.swift`.
///
/// All algorithms work in biblical month numbering (Nisan = 1, Tishri = 7).
/// `_CalendarHebrew`'s public API exposes civil ordering (Tishri = 1), so
/// we convert at the boundary via `biblicalToCivil` / `civilToBiblical`.
///
/// Fixed-day numbers use the Rata Die convention: R.D. 1 = midnight at the
/// start of proleptic Gregorian January 1, year 1. All arithmetic is `Int64`
/// to avoid overflow at extreme years (year ≈ ±5.88 M in Int32 terms).
///
/// Three floor-division fixes (2026-04-22, from icu4swift's ±10,000-year
/// round-trip stability test) are preserved:
///   1. `hebrewFromFixed` year approximation: uses `floorDiv` (else one year high at extreme negatives).
///   2. `calendarElapsedDays` returns `Int64` (else Int32 overflow at year ≈ ±5.88 M).
///   3. `calendarElapsedDays` internal divisions use `floorDiv` (else ~29-day skew at very negative years).
internal enum HebrewArithmetic {

    /// Hebrew epoch: Tishri 1 of year 1 AM = R.D. -1,373,427
    /// (= proleptic Julian year -3760, October 7).
    static let epoch: Int64 = -1_373_427

    // Biblical month ordinals.
    static let NISAN: UInt8 = 1
    static let IYYAR: UInt8 = 2
    static let SIVAN: UInt8 = 3
    static let TAMMUZ: UInt8 = 4
    static let AV: UInt8 = 5
    static let ELUL: UInt8 = 6
    static let TISHRI: UInt8 = 7
    static let MARHESHVAN: UInt8 = 8
    static let KISLEV: UInt8 = 9
    static let TEVET: UInt8 = 10
    static let SHEVAT: UInt8 = 11
    static let ADAR: UInt8 = 12
    static let ADARII: UInt8 = 13

    // MARK: Leap Year (Metonic 19-year cycle)

    /// Whether a Hebrew year is a leap year (13 months).
    /// Leap positions in the 19-year cycle: 3, 6, 8, 11, 14, 17, 19.
    static func isLeapYear(_ year: Int32) -> Bool {
        var r = (7 &* Int64(year) &+ 1) % 19
        if r < 0 { r += 19 }
        return r < 7
    }

    static func monthsInYear(_ year: Int32) -> UInt8 {
        isLeapYear(year) ? 13 : 12
    }

    // MARK: Floor Division

    /// Floor division — always rounds toward negative infinity.
    /// Swift's `/` truncates toward zero, which disagrees with R&D's algorithms
    /// for negative numerators (silently produces wrong results for very
    /// negative years).
    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        if (a >= 0) == (b > 0) {
            return a / b
        } else {
            return (a &- b &+ 1) / b
        }
    }

    // MARK: Elapsed Days (Molad Arithmetic)

    /// Days elapsed from the Sunday noon before the epoch to the molad of Tishri.
    ///
    /// Returns `Int64`: at year ≈ ±5.88 M this value crosses ±2.15 × 10^9, which
    /// would overflow Int32. Uses `floorDiv` on both internal divisions.
    static func calendarElapsedDays(_ year: Int32) -> Int64 {
        let monthsElapsed = floorDiv(235 &* Int64(year) &- 234, 19)
        let partsElapsed = 12084 &+ 13753 &* monthsElapsed
        let days = 29 &* monthsElapsed &+ floorDiv(partsElapsed, 25920)

        var r = (3 &* (days &+ 1)) % 7
        if r < 0 { r += 7 }
        if r < 3 {
            return days &+ 1
        } else {
            return days
        }
    }

    /// Dehiyyot correction keeping year lengths in {353,354,355,383,384,385}.
    static func yearLengthCorrection(_ year: Int32) -> UInt8 {
        let ny0 = calendarElapsedDays(year - 1)
        let ny1 = calendarElapsedDays(year)
        let ny2 = calendarElapsedDays(year + 1)
        if (ny2 - ny1) == 356 { return 2 }
        else if (ny1 - ny0) == 382 { return 1 }
        else { return 0 }
    }

    /// Fixed date of Tishri 1 (Hebrew New Year) for the given year.
    static func newYear(_ year: Int32) -> Int64 {
        return epoch &+ calendarElapsedDays(year) &+ Int64(yearLengthCorrection(year))
    }

    // MARK: YearData (cached per conversion)

    /// Year-level precomputed metadata. Computing this once per `fromRataDie` /
    /// `toRataDie` call avoids the redundant `newYear` / `calendarElapsedDays`
    /// invocations that a naive implementation would incur inside month-walk loops.
    /// (This was the 2026-04-19 optimization in icu4swift: 2.9 µs → 96 ns.)
    struct YearData {
        let year: Int32
        let newYear: Int64
        let yearLen: Int32          // 353..385
        let isLeap: Bool
        let longMarheshvan: Bool    // Marheshvan 30d
        let shortKislev: Bool       // Kislev 29d

        init(year: Int32) {
            self.year = year
            let ny0 = HebrewArithmetic.calendarElapsedDays(year - 1)
            let ny1 = HebrewArithmetic.calendarElapsedDays(year)
            let ny2 = HebrewArithmetic.calendarElapsedDays(year + 1)
            let corr0: UInt8
            if (ny2 - ny1) == 356 { corr0 = 2 }
            else if (ny1 - ny0) == 382 { corr0 = 1 }
            else { corr0 = 0 }
            let nyThis = HebrewArithmetic.epoch &+ ny1 &+ Int64(corr0)
            self.newYear = nyThis

            // Compute next year's length directly to get this year's length.
            let ny3 = HebrewArithmetic.calendarElapsedDays(year + 2)
            let corr1: UInt8
            if (ny3 - ny2) == 356 { corr1 = 2 }
            else if (ny2 - ny1) == 382 { corr1 = 1 }
            else { corr1 = 0 }
            let nyNext = HebrewArithmetic.epoch &+ ny2 &+ Int64(corr1)
            self.yearLen = Int32(nyNext &- nyThis)

            self.isLeap = HebrewArithmetic.isLeapYear(year)
            self.longMarheshvan = self.yearLen == 355 || self.yearLen == 385
            self.shortKislev = self.yearLen == 353 || self.yearLen == 383
        }

        /// Days in a biblical-month within this year.
        func lastDayOfMonth(_ month: UInt8) -> UInt8 {
            switch month {
            case HebrewArithmetic.IYYAR, HebrewArithmetic.TAMMUZ,
                 HebrewArithmetic.ELUL, HebrewArithmetic.TEVET,
                 HebrewArithmetic.ADARII:
                return 29
            case HebrewArithmetic.ADAR:
                return isLeap ? 30 : 29
            case HebrewArithmetic.MARHESHVAN:
                return longMarheshvan ? 30 : 29
            case HebrewArithmetic.KISLEV:
                return shortKislev ? 29 : 30
            default:
                // NISAN, SIVAN, AV, TISHRI, SHEVAT
                return 30
            }
        }

        var lastMonthOfYear: UInt8 {
            isLeap ? HebrewArithmetic.ADARII : HebrewArithmetic.ADAR
        }
    }

    // MARK: Year / Month Queries

    static func daysInYear(_ year: Int32) -> UInt16 {
        UInt16(YearData(year: year).yearLen)
    }

    static func isLongMarheshvan(_ year: Int32) -> Bool {
        YearData(year: year).longMarheshvan
    }

    static func isShortKislev(_ year: Int32) -> Bool {
        YearData(year: year).shortKislev
    }

    static func lastDayOfMonth(_ year: Int32, month: UInt8) -> UInt8 {
        YearData(year: year).lastDayOfMonth(month)
    }

    // MARK: Fixed ↔ Hebrew Conversion (biblical month ordering)

    static func fixedFromHebrew(year: Int32, month: UInt8, day: UInt8) -> Int64 {
        let yd = YearData(year: year)
        return fixedFromHebrew(yearData: yd, month: month, day: day)
    }

    static func fixedFromHebrew(yearData yd: YearData, month: UInt8, day: UInt8) -> Int64 {
        var totalDays: Int64 = yd.newYear &+ Int64(day) &- 1
        if month < TISHRI {
            // Add Tishri..lastMonth, then Nisan..(month-1)
            let last = yd.lastMonthOfYear
            var m: UInt8 = TISHRI
            while m <= last {
                totalDays &+= Int64(yd.lastDayOfMonth(m))
                m &+= 1
            }
            m = NISAN
            while m < month {
                totalDays &+= Int64(yd.lastDayOfMonth(m))
                m &+= 1
            }
        } else {
            var m: UInt8 = TISHRI
            while m < month {
                totalDays &+= Int64(yd.lastDayOfMonth(m))
                m &+= 1
            }
        }
        return totalDays
    }

    static func hebrewFromFixed(_ date: Int64) -> (year: Int32, month: UInt8, day: UInt8) {
        // Approximate year using average Hebrew year length ≈ 365.2468.
        //
        // Uses floor division: the approximation must err LOW, never high.
        // The forward-only `while newYear(year+1) <= date` loop can't backtrack,
        // so a high-skewed `approx` at extreme negative RDs would leave `year`
        // pinned past the true value and produce a negative day-of-year remainder.
        let dayDelta = date &- epoch
        let approx = Int32(1 &+ floorDiv(dayDelta &* 98496, 35975351))

        var year = approx - 1
        while newYear(year + 1) <= date {
            year += 1
        }

        let yd = YearData(year: year)
        var rem = Int(date &- yd.newYear)

        // Civil month order for biblical months:
        //   common year: Tishri (7), Marheshvan (8) ... Adar (12), Nisan (1) ... Elul (6)
        //   leap year:   Tishri (7), ... Adar (12), AdarII (13), Nisan (1), ... Elul (6)
        var m: UInt8 = TISHRI
        let last = yd.lastMonthOfYear
        while m <= last {
            let len = Int(yd.lastDayOfMonth(m))
            if rem < len {
                return (year, m, UInt8(rem + 1))
            }
            rem -= len
            m &+= 1
        }

        m = NISAN
        while m < TISHRI {
            let len = Int(yd.lastDayOfMonth(m))
            if rem < len {
                return (year, m, UInt8(rem + 1))
            }
            rem -= len
            m &+= 1
        }

        // Unreachable for a valid in-range date.
        return (year, ELUL, UInt8(rem + 1))
    }

    // MARK: Civil ↔ Biblical Month Conversion
    //
    // Foundation's public `.hebrew` calendar uses **stable** (ICU-style) month
    // numbering, not the dense ordering. Month numbers are:
    //
    //   1 = Tishrei     8 = Nisan
    //   2 = Cheshvan    9 = Iyyar
    //   3 = Kislev     10 = Sivan
    //   4 = Tevet      11 = Tammuz
    //   5 = Shevat     12 = Av
    //   6 = Adar I  ←  only exists in leap years; INVALID in common years.
    //   7 = Adar (common) / Adar II (leap)
    //  13 = Elul
    //
    // So common years have 12 months numbered {1,2,3,4,5,7,8,9,10,11,12,13}
    // (month 6 skipped), and leap years have 13 months {1..13}. This keeps
    // Nisan = 8, Elul = 13 constant across common and leap years, which is
    // what ICU does and what `DateComponents.month` returns.

    /// Convert biblical month → civil month (stable / ICU numbering).
    static func biblicalToCivil(year: Int32, biblicalMonth: UInt8) -> UInt8 {
        let leap = isLeapYear(year)
        switch biblicalMonth {
        case TISHRI: return 1
        case MARHESHVAN: return 2
        case KISLEV: return 3
        case TEVET: return 4
        case SHEVAT: return 5
        case ADAR: return leap ? 6 : 7   // Adar I in leap; plain Adar in common.
        case ADARII: return 7            // leap year only
        case NISAN: return 8
        case IYYAR: return 9
        case SIVAN: return 10
        case TAMMUZ: return 11
        case AV: return 12
        case ELUL: return 13
        default: return 0
        }
    }

    /// Convert civil month (stable / ICU numbering) → biblical month.
    /// Returns `nil` if the civil month doesn't exist in this year
    /// (i.e., civil month 6 / "Adar I" in a common year).
    static func civilToBiblical(year: Int32, civilMonth: UInt8) -> UInt8? {
        let leap = isLeapYear(year)
        switch civilMonth {
        case 1: return TISHRI
        case 2: return MARHESHVAN
        case 3: return KISLEV
        case 4: return TEVET
        case 5: return SHEVAT
        case 6: return leap ? ADAR : nil      // Adar I (leap only)
        case 7: return leap ? ADARII : ADAR
        case 8: return NISAN
        case 9: return IYYAR
        case 10: return SIVAN
        case 11: return TAMMUZ
        case 12: return AV
        case 13: return ELUL
        default: return nil
        }
    }

    /// Days in a civil-ordered month. Returns 0 for the invalid civil-6 slot in common years.
    static func daysInCivilMonth(year: Int32, civilMonth: UInt8) -> UInt8 {
        guard let biblical = civilToBiblical(year: year, civilMonth: civilMonth) else {
            return 0
        }
        return lastDayOfMonth(year, month: biblical)
    }

    /// Days preceding a civil-ordered month in its year (for day-of-year).
    /// Skips civil-6 in common years (where it doesn't exist).
    static func daysPrecedingCivilMonth(year: Int32, civilMonth: UInt8) -> UInt16 {
        let yd = YearData(year: year)
        var total: UInt16 = 0
        for m: UInt8 in 1..<civilMonth {
            if let biblical = civilToBiblical(year: year, civilMonth: m) {
                total += UInt16(yd.lastDayOfMonth(biblical))
            }
            // else: no-such-month slot — contribute 0 days.
        }
        return total
    }
}
