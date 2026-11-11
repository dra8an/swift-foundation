# Proposal for the port: a region-aware `.islamic` calendar

Draft, 2026-11-09, for swift-foundation's divergence notes or an upstream issue. Measured and implemented in
icu4swift (`Docs/CRESCENT_RULES_RESULTS.md` Rounds 4–7, `Sources/CalendarAstronomical/HijriRegional.swift`,
`Tests/CalendarAstronomicalTests/HijriRegionalTests.swift`). Not yet delivered.

## 1. What `.islamic` computes today, and how wrong it is

Foundation's `.islamic` (CLDR `islamic`, "astronomical simulation") is ICU4C's algorithm, which the Swift port
reproduces exactly: the moon's phase angle from a Duffett-Smith series, evaluated at 00:00 UTC on successive days; the
month begins on the day after the first midnight at which the new moon has passed. No place, no sunset, no visibility.
ICU's forward and backward searches disagree by a day, which is why ICU reports a maximum month length of 31 days and
the port reproduces that too.

Against 510 announced month starts (Ramadan, Shawwal, Dhu al-Hijjah) of 52 national authorities, 2009–2026
(moonsighting.com's compilation, checked against first-hand data: Egypt 3/3, Türkiye 9/10):

| | Exact | Announced later by 1 day | Later by 2+ | Announced earlier |
|---|---|---|---|---|
| `.islamic` as implemented (ICU4C) | **103 (20%)** | 326 (64%) | 81 (16%) | 0 |

A conjunction clock is early almost everywhere and never late; no authority starts a month at the new moon.

## 2. What is proposed, in one piece

`.islamic` keeps its identifier and gains a region. Without a region it computes the Umm al-Qura table (ICU4X's choice
since 2.2.0; `components/calendar/src/cal/hijri.rs`). With a region it computes the method that region's authority
follows, from a region-to-method table:

| Regions | Method | Verified against |
|---|---|---|
| TR | Diyanet era rules + 4 named corrections | 707/707 published months, AH 1399–1457 |
| MY | MABIMS at the official reference point + 2 named corrections | 98/98 published months |
| ID | MABIMS at Banda Aceh, geocentric altitude | 25/25 published months |
| SA, KW, QA, BH, AE, YE, JO, PS, LB, SY, IQ, SD, DZ, TN, LY, EG, AF, SO, and any unlisted region | Umm al-Qura table (KACST, AH 1300–1600; rule + 1 correction beyond) | 131/131 published; 77% of the bloc's announcements (70–93% per country) |
| PK, MA, OM, IN, BD, IR, ZA, LK, MU, TZ, KE, AU, NZ, NG, BN, TT, GY, BB, CL, NA, ZW, ZM, MZ, SN, GH, NP, MV | predicted naked-eye visibility (Odeh's criterion at best time) at a national reference point, threshold as measured | 81% of announcements (Morocco 11/12, Pakistan 11/13, Australia 11/11, Guyana 10/10, South Africa 10/11, Sri Lanka 11/13, Mauritius 12/13, Tanzania 11/12, Kenya 10/11; weaker: India 6/13, Bangladesh 5/11) |

The reference implementation (`HijriRegional.method(forRegion:)`, `HijriRegional.monthLength(start:next:method:)`)
runs its whole test set in 10 seconds. One astronomy engine (the ICU4X-derived lunar and solar series), calibrated on
Diyanet's printed times to about a minute, serves every method.

What the mapping does not claim: sighting countries keep a 10–20% residual that no computation removes, and the
documentation must say so; India and Bangladesh have several committees and match poorly at any reference point.

## 3. Work items in the port (part of this proposal, not later stages)

1. **Routing.** `.islamic` without a region → the Umm al-Qura table already in the port (`ummAlQuraTable`). Divergence
   from ICU4C to be recorded as deliberate; removes the 31-day months.
2. **Region on `Calendar`.** A stored region (or location) that selects the method, in the way `timeZone` selects day
   boundaries: part of `==`, `hash` and `Codable`; a defined fallback (the default method) when a calendar is rebuilt
   from `Locale` or `Calendar.Identifier`, which cannot carry it. New public API: initializer and property, with Apple
   parity.
3. **Formatting.** `ICUDateFormatter.format(_:)` calls `udat_formatForFields(udateFormat, date.udate, …)`, so ICU
   computes every Hijri field from the absolute time with its own `islamic` calendar; the Swift calendar's month starts
   are not consulted. The formatter must take the fields from the Swift calendar for `.islamic` (and for any calendar
   whose dates differ from ICU's), or the region-aware dates would compute one day and print another.
4. **Rules and data.** Port `HijriRegional` and the four rule sets with their correction lists; carry the published
   dates (Diyanet 708, Umm al-Qura 132, Malaysia 99, Indonesia 26 first days) as test fixtures and the announced-date
   measurement as a non-asserting report.

## 4. Why not stages

Routing alone (item 1) is an improvement (20% → about 50% exact overall, 70–93% in the Saudi bloc) but leaves every
sighting country and the three computed authorities wrong by a day or two for part of the year, and would have to be
revisited. The region table is where the measured value is; items 2 and 3 are its cost, and they are the same
engineering whether done now or later.

## 5. API sketch (for discussion, not a decision)

```swift
extension Calendar {
    /// The region whose authority decides the month starts of the `.islamic` calendar. `nil` means the default
    /// method (the Umm al-Qura table). Ignored by every other calendar identifier.
    public var region: Locale.Region? { get set }

    /// `.islamic` as computed for `region`.
    public init(identifier: Calendar.Identifier, region: Locale.Region?)
}
```

- **Semantics.** `Calendar(identifier: .islamic)` ≡ `Calendar(identifier: .islamic, region: nil)` → Umm al-Qura table.
  With a region, `HijriRegional.method(forRegion:)` selects the method; unlisted regions behave as `nil`.
- **Equality, hashing, `Codable`.** `region` takes part exactly as `timeZone` does: two `.islamic` calendars with
  different regions are different values and may give different `DateComponents` for the same `Date`; `Codable` adds an
  optional `region` key, absent = `nil`, so archives from older versions decode unchanged.
- **Round trips that cannot carry a region.** `Calendar.Identifier`, `Locale`'s `calendar` keyword, `NSCalendar`
  bridging and `Calendar.current` carry no region; a calendar rebuilt through them has `region == nil`. Documented, not
  inferred from the locale's region: the user who wants Pakistan's calendar asks for it.
- **Formatting.** `Date.FormatStyle` and `DateFormatter` with a regional `.islamic` must obtain era, year, month, day and
  weekday from the Swift calendar, not from ICU's `udat`; the month and day names still come from ICU's locale data.
  Until that exists, a regional calendar must either be refused by the formatter or documented as printing ICU's dates.
- **Out of scope.** Observational announcements for Ramadan, Shawwal and Dhu al-Hijjah can override any computed
  method in the regions that sight; the documentation of `region` says so. No per-region `Calendar.Identifier` is
  proposed (CLDR has none, and a closed enum should not grow one case per country).
