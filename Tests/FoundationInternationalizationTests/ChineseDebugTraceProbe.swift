//===----------------------------------------------------------------------===//
// Temporary debug utility: traces every _CalendarProtocol call the generic
// framework makes. Not part of any suite; delete before handoff.
//===----------------------------------------------------------------------===//

import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#else
@testable import FoundationInternationalization
@testable import FoundationEssentials
#endif

private final class TracingCalendar: _CalendarProtocol, @unchecked Sendable {
    let inner: any _CalendarProtocol
    init(_ inner: any _CalendarProtocol) { self.inner = inner }
    init(identifier: Calendar.Identifier, timeZone: TimeZone?, locale: Locale?, firstWeekday: Int?, minimumDaysInFirstWeek: Int?, gregorianStartDate: Date?) {
        fatalError("use init(_:)")
    }
    var identifier: Calendar.Identifier { inner.identifier }
    var locale: Locale? { get { inner.locale } set { } }
    var timeZone: TimeZone { get { inner.timeZone } set { } }
    var firstWeekday: Int { get { inner.firstWeekday } set { } }
    var minimumDaysInFirstWeek: Int { get { inner.minimumDaysInFirstWeek } set { } }
    var preferredFirstWeekday: Int? { inner.preferredFirstWeekday }
    var preferredMinimumDaysInFirstweek: Int? { inner.preferredMinimumDaysInFirstweek }
    var gregorianStartDate: Date? { inner.gregorianStartDate }
    var isAutoupdating: Bool { inner.isAutoupdating }
    var isBridged: Bool { inner.isBridged }
    var debugDescription: String { inner.debugDescription }
    var localeIdentifier: String { inner.localeIdentifier }
    func copy(changingLocale: Locale?, changingTimeZone: TimeZone?, changingFirstWeekday: Int?, changingMinimumDaysInFirstWeek: Int?) -> any _CalendarProtocol { self }
    func hash(into hasher: inout Hasher) { inner.hash(into: &hasher) }
    func minimumRange(of component: Calendar.Component) -> Range<Int>? { inner.minimumRange(of: component) }
    func maximumRange(of component: Calendar.Component) -> Range<Int>? { inner.maximumRange(of: component) }
    func range(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Range<Int>? {
        let r = inner.range(of: smaller, in: larger, for: date)
        print("TRACE range(\(smaller),\(larger),\(date)) -> \(String(describing: r))")
        return r
    }
    func ordinality(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Int? {
        inner.ordinality(of: smaller, in: larger, for: date)
    }
    func dateInterval(of component: Calendar.Component, for date: Date) -> DateInterval? {
        let r = inner.dateInterval(of: component, for: date)
        print("TRACE dateInterval(\(component), \(date)) -> \(String(describing: r))")
        return r
    }
    func isDateInWeekend(_ date: Date) -> Bool { inner.isDateInWeekend(date) }
    func date(from components: DateComponents) -> Date? {
        let r = inner.date(from: components)
        print("TRACE date(from: \(components)) -> \(String(describing: r))")
        return r
    }
    func dateComponents(_ components: Calendar.ComponentSet, from date: Date, in timeZone: TimeZone) -> DateComponents {
        let r = inner.dateComponents(components, from: date, in: timeZone)
        print("TRACE dateComponents(\(date)) -> \(r)")
        return r
    }
    func dateComponents(_ components: Calendar.ComponentSet, from date: Date) -> DateComponents {
        dateComponents(components, from: date, in: timeZone)
    }
    func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool) -> Date? {
        let r = inner.date(byAdding: components, to: date, wrappingComponents: wrappingComponents)
        print("TRACE byAdding(\(components), to \(date), wrap \(wrappingComponents)) -> \(String(describing: r))")
        return r
    }
    func dateComponents(_ components: Calendar.ComponentSet, from start: Date, to end: Date) -> DateComponents {
        inner.dateComponents(components, from: start, to: end)
    }
    func nextDate(after date: Date, matching components: DateComponents, direction: Calendar.SearchDirection) -> Date? {
        let r = inner.nextDate(after: date, matching: components, direction: direction)
        print("TRACE nextDate(after \(date), matching \(components)) -> \(String(describing: r))")
        return r
    }
    var supportsNextDateFastPath: Bool { inner.supportsNextDateFastPath }
#if FOUNDATION_FRAMEWORK
    func bridgeToNSCalendar() -> NSCalendar { inner.bridgeToNSCalendar() }
#endif
}

@Suite("Chinese Debug Trace")
private struct ChineseDebugTraceProbe {
    @Test func chineseTraceBySettingMinute() {
        let ours = _CalendarChinese(identifier: .chinese, timeZone: .gmt, locale: nil,
                                    firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        let cal = Calendar(inner: TracingCalendar(ours))
        var gc = Calendar(identifier: .gregorian); gc.timeZone = .gmt
        var dc = DateComponents(); dc.year = 2020; dc.month = 5; dc.day = 23; dc.hour = 12; dc.timeZone = .gmt
        let d = gc.date(from: dc)!
        print("TRACE ==== bySetting minute 30 of \(d)")
        let r = cal.date(bySetting: .minute, value: 30, of: d)
        print("TRACE ==== result: \(String(describing: r))")
        #expect(Bool(true))
    }
}

@Suite("Chinese ICU LeapFlag Semantics")
private struct ChineseICULeapFlagProbe {
    @Test func chineseIcuLeapFlagPerSet() {
        let icu = _CalendarICU(identifier: .chinese, timeZone: .gmt, locale: nil,
                               firstWeekday: nil, minimumDaysInFirstWeek: nil, gregorianStartDate: nil)
        var gc = Calendar(identifier: .gregorian); gc.timeZone = .gmt
        var dc = DateComponents(); dc.year = 2020; dc.month = 5; dc.day = 23; dc.hour = 12; dc.timeZone = .gmt
        let leapDate = gc.date(from: dc)!
        dc.month = 3
        let normalDate = gc.date(from: dc)!
        let sets: [(String, Calendar.ComponentSet)] = [
            ("[.minute]", [.minute]), ("[.hour]", [.hour]), ("[.day]", [.day]),
            ("[.month]", [.month]), ("[.month,.day]", [.month, .day]),
            ("[.era,.year,.month,.day]", [.era, .year, .month, .day]),
            ("[.isLeapMonth]", [.isLeapMonth]), ("[.weekday]", [.weekday]),
        ]
        for (label, set) in sets {
            let l = icu.dateComponents(set, from: leapDate, in: .gmt)
            let n = icu.dateComponents(set, from: normalDate, in: .gmt)
            print("ICULEAP \(label): leapDate.isLeapMonth=\(String(describing: l.isLeapMonth)) normalDate.isLeapMonth=\(String(describing: n.isLeapMonth))")
        }
        #expect(Bool(true))
    }
}
