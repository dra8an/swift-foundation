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

/// Static helpers shared by `_CalendarProtocol` conformers. Each helper takes
/// all the state it needs as parameters — no `self`, no protocol pollution.
/// Calendars keep their own private storage but forward to these helpers for
/// the duplicated logic (validation, locale-fallback resolution, etc.).
internal enum _CalendarUtility {

    // MARK: - firstWeekday

    /// Clamps and validates a new `firstWeekday` value.
    /// Used by `firstWeekday`'s setter in each calendar.
    static func validatedFirstWeekday(_ value: Int) -> Int {
        precondition(value >= 1 && value <= 7, "Weekday should be in the range of 1...7")
        return value
    }

    /// Resolves `firstWeekday`: returns the explicitly-stored value if set,
    /// else falls back to the locale's preference, else defaults to 1 (Sunday).
    /// Used by `firstWeekday`'s getter in each calendar.
    static func resolveFirstWeekday(stored: Int?, locale: Locale?) -> Int {
        if let stored {
            return stored
        } else if let locale {
            return locale.firstDayOfWeek.icuIndex
        } else {
            return 1
        }
    }

    // MARK: - minimumDaysInFirstWeek

    /// Clamps a new `minimumDaysInFirstWeek` value to the valid range 1...7.
    /// Used by `minimumDaysInFirstWeek`'s setter in each calendar.
    static func clampedMinimumDaysInFirstWeek(_ value: Int) -> Int {
        if value < 1 { return 1 }
        if value > 7 { return 7 }
        return value
    }

    /// Resolves `minimumDaysInFirstWeek`: returns the explicitly-stored value
    /// if set, else falls back to the locale's preference, else defaults to 1.
    /// Used by `minimumDaysInFirstWeek`'s getter in each calendar.
    static func resolveMinimumDaysInFirstWeek(stored: Int?, locale: Locale?) -> Int {
        if let stored {
            return stored
        } else if let locale {
            return locale.minimumDaysInFirstWeek
        } else {
            return 1
        }
    }

    // MARK: - copy()

    /// Resolves arguments for `copy(...)`: for each parameter, returns the
    /// override if supplied, otherwise the current stored value.
    /// Used by each calendar's `copy(...)` to avoid duplicating the
    /// "override or current" logic at every call site.
    static func resolvedCopyArgs(
        currentTimeZone: TimeZone, changingTimeZone: TimeZone?,
        currentLocale: Locale?, changingLocale: Locale?,
        currentFirstWeekday: Int?, changingFirstWeekday: Int?,
        currentMinimumDaysInFirstWeek: Int?, changingMinimumDaysInFirstWeek: Int?
    ) -> (timeZone: TimeZone, locale: Locale?, firstWeekday: Int?, minimumDaysInFirstWeek: Int?) {
        let newTimeZone = changingTimeZone ?? currentTimeZone
        let newLocale = changingLocale ?? currentLocale
        let newFirstWeekday: Int? = changingFirstWeekday ?? currentFirstWeekday
        let newMinDays: Int? = changingMinimumDaysInFirstWeek ?? currentMinimumDaysInFirstWeek
        return (newTimeZone, newLocale, newFirstWeekday, newMinDays)
    }
}
