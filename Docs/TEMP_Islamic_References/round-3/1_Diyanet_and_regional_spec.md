# Diyanet (Türkiye) Hijri calendar: computation spec for the port

Status 2026-11-11: reproduces all 707 published month starts AH 1399–1457 (1 Dec 1978 to about Feb 2036), 703 by the
era rules alone and 4 by named corrections; verified by
`Tests/CalendarAstronomicalTests/CrescentDiyanetPublishedTests.swift` in icu4swift (9 s). Reference implementation:
`Sources/CalendarAstronomical/CrescentRules.swift` (`DiyanetEra`, `diyanetCorrections`, `diyanetMonthLength`,
`diyanetStartsTomorrow`), astronomy in `Sources/AstronomicalEngine/CrescentAstronomy.swift` and `LunarSeriesTables.swift`.
Background and every rejected hypothesis: `Docs/CRESCENT_RULES_RESULTS.md`. Delivered to the port as round 3
(2026-11-09). Changed on 2026-11-11 (results doc, Round 10; round 5 for the port): a separate rule for first days
before 1980, and four corrections where there were five.

## 1. The decision, month by month

A month that begins on day `start` has 29 days if the new month begins "tomorrow" as seen from the evening of
`start + 28` (its 29th day), else 30. Let `midnight` be 00:00 UTC at the end of that evening's UTC date.

0. **First days before 1 January 1980** (`before1980`, by the Gregorian date of the candidate first day `start + 29`):
   the older test decides alone, and steps 1–4 are not used. At Mecca (21°25′21″ N, 39°49′32″ E; the elevation is not
   used) take the sunset of that evening (sun's upper limb at the −50′ horizon) and the first moonset after
   `sunset − 8 h` (moon's centre, seen from the surface, at −(34′ + 0.2725 × horizontal parallax), searched within
   30 hours). If `moonset − sunset ≥ 18.5 minutes`: 29 days, else 30 (also 30 if the moon does not set in that time).
   Any limit from 18.1 to 18.7 minutes gives the same published dates.

1. **Conjunction.** `conjunction = newMoonBefore(midnight + 12 h)`. If `midnight + 12 h − conjunction ≥ 3 days`, the
   crescent is not new: 30 days.
2. **Criterion at a place and moment** (`meets`): the moment is after the conjunction and less than 3 days after it;
   the moon's geocentric altitude ≥ 4° (pre-filter); apparent altitude = geocentric altitude − parallax in altitude +
   refraction ≥ **5°**; geocentric (true) elongation between the centres of moon and sun ≥ **8°**.
3. **The 1978 rule (all eras from 1980).** Geocentric elongation at `midnight` ≥ 8°, and at `midnight` some point on the sunset
   line (sun's upper limb at the −50′ horizon) satisfies `meets`. Scan latitudes −88° … +88° in 0.1° steps; for each
   latitude the longitude where the sun sets at exactly `midnight` (`sunsetLongitude`). Any hit: 29 days.
4. **Era extension**, by the Gregorian calendar year of the candidate first day `start + 29`:
   - **1980–2008** (`years1980to2008`) and **2014–2016** (`years2014to2016`): none. 30 days.
   - **2009–2013** (`years2009to2013`): geocentric elongation at `midnight + 12 h` ≥ 8°, and at some latitude 10° N …
     88° N (0.25° steps) the sunset at longitude −179.999° on this evening is ≥ `midnight`, has elongation ≥ 8° and
     satisfies `meets`. Hit: 29 days, else 30.
   - **2017 onward** (`from2017`): the conjunction (`newMoonBefore(midnight)`) is before dawn (sun 18° below the horizon,
     geometric centre, no margin) at Wellington (41.2865° S, 174.7762° E) on the local morning that follows the evening
     (the first dawn after `midnight − 18 h`), with `dawn − conjunction < 2 days`; and at some row of the American
     west-coast table the sunset on this evening is ≥ `midnight`, has elongation ≥ 8° and satisfies `meets`. Hit: 29.
5. **Corrections.** If the *following* month is one of AH 1401-8, 1411-5, 1444-11, 1453-12, the month has 30
   days regardless of steps 1–4.

Era boundaries as rata die (RD 1 = 1 Jan 1 CE proleptic Gregorian): 1980-01-01 = 722815, 2009-01-01 = 733408,
2014-01-01 = 735234, 2017-01-01 = 736330.

## 2. Conventions that matter (calibrated on Diyanet's own printed numbers)

| Quantity | Convention | Calibration |
|---|---|---|
| Lunar and solar positions | the ICU4X-derived series in `CrescentAstronomy.swift` / `LunarSeriesTables.swift` (ELP/VSOP-class), ΔT as in the engine | Diyanet's printed conjunction and first-visibility times on 233 maps (2017–2035) agree within about a minute |
| Elongation | geocentric, between centres: acos(cos β · cos Δλ) | ecliptic-longitude difference, RA difference and topocentric elongation all fail (Round 6) |
| Altitude | topocentric (parallax removed) plus Sæmundsson refraction 1.02/tan(h + 10.3/(h + 5.11)) arcmin, at the moon's centre | Diyanet's Ramadan 1447 diagrams and the altitude-bound map edges |
| Sunset | sun's upper limb at the standard −50′ horizon (centre at −0.8333°), no temkin | the same maps |
| Dawn at Wellington | sun's centre 18° below the horizon, no margin | Diyanet's Ankara imsak 05:54 on 9 Nov 2026 = our −18° dawn 05:53:43 |
| American mainland | the single Natural Earth 1:10m land polygon containing both Americas; westernmost mainland longitude per 0.05° latitude row, 71.95° N … 53.85° S (2517 rows, `americanWestCoast`); islands excluded (Vancouver Island, Kodiak, Aleutians, Tierra del Fuego) | Diyanet's 2026 statement: islands do not count; the 2017–2035 decisions |

## 3. Why the astronomy must be this precise

Several published starts are decided by margins that a different ephemeris or coastline would flip:

| Month | Decided by | Margin |
|---|---|---|
| AH 1442-11 (Jun 2021) | Oregon coast, 44.6° N | apparent altitude +0.012° |
| AH 1452-1 (May 2030) | Bering coast, 63.2° N | +0.083° |
| AH 1439-3 (Nov 2017) | Alaska Peninsula tip, 54.85° N | +0.088° |
| AH 1402-12 (Oct 1982), 1410-5 (Dec 1989), 1414-2 (Jul 1993) | elongation at 00:00 UTC | +0.069°, +0.068°, +0.114° |
| AH 1455-3 (May 2033) | first visibility 3 min after 00:00 UTC | refused, −0.012° on the mainland |

An implementation that reproduces the 707 published dates with these conventions is correct; one that uses another
library must be re-validated against the same 707 dates (`crescent_official_dates.csv`, rows `diyanet,diyanet`).

## 4. The four corrections, and why they are data

All four are "rule says 29 days, Diyanet printed 30". Each was re-examined on 2026-11-11 (results doc, Round 10):

| Month given 30 days before | First day (published) | Reason |
|---|---|---|
| **1 Şaban 1401** | 4 Jun 1981 | the elongation reached 8° 14.1 minutes before the cut-off (13.9 with our series), yet July 1993 started with 13.8: the published list contradicts itself, and no clock offset or threshold gives both |
| **1 Cemaziyelevvel 1411** | 19 Nov 1990 | 46 seconds before the cut-off in universal time (54 with our series), 12 seconds after it in dynamical time, the scale of the almanacs of the time. A program that used dynamical time before 2009 would refuse this month and change no other; one decision supports that, so it stays a correction |
| **1 Zilkade 1444** | 21 May 2023 | mainland Alaska passes with +0.222°; May 2030 started with +0.083° on the same coast. No shift of the altitude and elongation thresholds refuses this month and keeps the others |
| **1 Zilhicce 1453** | 13 Mar 2032 | +0.030° at the tip of the Seward Peninsula, about two minutes of sunset on the wrong side of June 2021 (started with +0.012°); the new moon is 16 minutes before dawn at Wellington, where the smallest margin of any start is 24 |

Ramazan 1399 (26 Jul 1979) was the fifth correction until 2026-11-11. It is not an exception: the 1978 rule took effect
with the 1980 calendar, and the older test of step 0 gives the published date (moonset 13.2 minutes after sunset at
Mecca).

## 5. Range of validity

- **First days from 1 January 1980:** the 1978 rule and its later forms, as above. Diyanet publishes to AH 1457
  (2035); later years follow from the `from2017` rule until Diyanet publishes otherwise; any new deviation is one more
  entry in the correction list.
- **First days from 1 December 1978 to 20 December 1979** (AH 1399-1 … 1400-2, 14 decisions): the older test of step 0.
  All 14 are reproduced. The 1978 rule gives 13 of them; the one it misses is Ramazan 1399.
- **Before AH 1399:** the older test is an approximation, not Diyanet's documented method (Fatin Gökmen's
  Morocco-observer system until 1974, the 1975–1979 practice undocumented; Keleş 2016 p. 375, van Gent). Against
  Diyanet's published list it gives 13 of 13 for first days in 1978, 234 of 247 for 1960–1979, about 93% for 1925–1959
  with a limit near 22.5 minutes, and under 75% before 1925. The 1978 rule gives 617 of 971 for 1900–1978. The port
  should either state that the Diyanet calendar begins at AH 1399 or document the earlier output as an approximation.

## 6. Test data

`Tests/CalendarAstronomicalTests/crescent_official_dates.csv`, rows `diyanet,diyanet,<AH year>,<month>,<first day>`:
AH 1398-12 … 1439-12 from Diyanet's Hicri–Miladi tables (vakithesaplama.diyanet.gov.tr, icerik pages), AH 1440-1 …
1457-11 from Diyanet's official table and visibility maps. 708 first days, 707 decisions. The dates are published facts;
the Research folder's copies of Diyanet's pages and maps stay local.

## 7. Umm al-Qura, the same pattern

Rule (in force since AH 1420): the month beginning on `start` has 29 days if, at the Kaaba (21° 25′ 21″ N, 39° 49′ 32″ E,
295 m) on the evening of `start + 28`, the conjunction is before sunset and the moon sets after the sun (sun's upper
limb at −50′; moonset of the moon's upper limb at −34′ refraction, with parallax); else 30. One correction:
**AH 1446-6** (1 Jumada II 1446 = 2 Dec 2024), Jumada I has 29 days although our moonset is 7 s before sunset.
Verified on the 131 published decisions AH 1440–1450 (`ummalqura` rows of the CSV): 131/131 with the correction, 130
without. Reference: `CrescentRules.ummAlQuraMonthLength`, `ummAlQuraCorrections`;
test `CrescentUmmAlQuraPublishedTests`. Foundation and ICU ship this calendar as a table for AH 1300–1600; the rule and
correction are the cross-check and the fallback beyond the table.

## 8. Scope position: which calendars to ship as computed

| Calendar | Verified | Position |
|---|---|---|
| Diyanet | 707/707 (era rules 703 + 4 corrections) | ship; §1–6 |
| Umm al-Qura | 131/131 (rule + 1 correction) | ship as ICU does (KACST table AH 1300–1600); rule as cross-check and fallback; §7 |
| Malaysia (JAKIM) | 96/98 by rule; 98/98 with 2 corrections (AH 1443-10 Labuan sighting override; AH 1449-8, 0.015°) | ship with the two corrections; document that Ramadan, Syawal and Zulhijjah announcements may override the computed takwim |
| Indonesia (Kemenag) | 25/25 | ship; same documentation as Malaysia (sidang isbat) |
| Singapore (MUIS) | not verifiable (9 non-consecutive official dates) | include only once MUIS's calendar is confirmed computed and consecutive dates exist |
| Egypt (Dar al-Ifta) | 83/92 by the best rule; announcements follow no threshold | **do not ship.** Observational by procedure; future announcements are not predictable, so no computed calendar can be correct. Egypt's computed civil calendar (Egyptian Survey Authority) is a different calendar (Ramadan 1447: ESA 18 Feb 2026, announced 19 Feb) and would need its own multi-year data, which the ESA site's terms forbid copying. |

The port currently has Egypt only as the internal `Astronomy.VisibilityRule.egypt` (Cairo, moonset ≥ 5 min after sunset)
with a few test dates and no public calendar identifier; removing it is a small change.

## 9. A location-aware predicted-visibility calendar: measured value and blockers

Proposal under discussion: `.islamic` unchanged (ICU parity), plus a variant that takes a location and computes month
starts from a visibility criterion there. Measured against 510 announced month starts of 52 national authorities
(results doc § Round 7):

| Who | Best computed predictor | Match |
|---|---|---|
| Sighting countries (Morocco, Pakistan, Oman, South Africa, Sri Lanka, Mauritius, East Africa, Australia, Caribbean…) | Odeh's visibility criterion (zone B, naked eye) at the national reference point | 80–92% per country |
| Saudi-following bloc (Gulf, Levant, Maghreb except Morocco, Egypt, Sudan) | the Umm al-Qura calendar itself | 70–93% |
| Computed authorities (Türkiye, Malaysia, Indonesia, Brunei) | their own rules (§1–7) | 100% / 100% with corrections |
| ICU's current `islamic` (conjunction at 00:00 UTC) | — | 20% exact, early by a day or two in 80% |

So a region-to-method mapping is what the data supports: computed authorities by their rules, the Saudi bloc by the
Umm al-Qura table, sighting countries by Odeh-B at a national point with a documented 10–20% residual that no
computation removes. A single location-aware criterion applied everywhere would stay near 50%.

Blockers before any API: (1) formatting goes through ICU (`udat_formatForFields` on the absolute time), so the
Swift calendar's dates would not be what is printed; (2) new public API on `Calendar` (initializer + stored location)
and Apple parity; (3) a location cannot travel through `Locale` or `Calendar.Identifier`, so the fallback must be
defined. The computation itself exists and is verified.

## 10. Reference implementation of the regional calendar (2026-11-09)

`Sources/CalendarAstronomical/HijriRegional.swift`: `HijriRegional.method(forRegion:)` maps an ISO region to a method
(`ummAlQuraTable`, `diyanet`, `malaysia`, `indonesia`, `visibility(Location, minimumOdehValue:)`), and
`HijriRegional.monthLength(start:next:method:)` computes the month. `defaultMethod` (no region) is the Umm al-Qura
table. Malaysia carries two corrections (AH 1443-10 Labuan sighting, AH 1449-8 razor edge), Indonesia none.
`HijriRegionalTests` (10 s): Umm al-Qura table 131/131, Diyanet 707/707, Malaysia 98/98, Indonesia 25/25; against
the 510 announced dates (env `ANNOUNCED_CSV`), sighting countries 206/255 (81%), Saudi-following bloc 159/207 (77%),
computed authorities 26/29 (90%; the misses are compilation errors and Indonesia's pre-2016 practice).

## 11. Validity of each method

| Method | Verified range | Before the range | After the range |
|---|---|---|---|
| Diyanet era rules + corrections | AH 1399–1457 (Dec 1978 – ~Feb 2036), 707/707 | other methods were in use (Gökmen's Morocco observer to 1974; 1975–1979 undocumented); the older test of §1 step 0 matches 234 of 247 months of 1960–1979 and less before; the 1978 rule matches 617 of 971 months 1900–1978 | the 2017+ rule continues; each new Diyanet publication is checked and, if needed, one correction added |
| Umm al-Qura table | AH 1300–1600 (the KACST table as ICU ships it); rule + correction verified AH 1440–1450, 131/131 | nothing published | rule (conjunction before sunset, moonset after sunset at the Kaaba) |
| Malaysia | AH 1440–1460 published takwim, 98/98 with 2 corrections; the 1992 criterion is applied before the 2022 edition but is verified only inside this range | unverified | MABIMS 2021 at Pulau Perak continues |
| Indonesia | AH 1440–1460, 25/25 | unverified (pre-2022 criterion applied) | MABIMS 2021 at Banda Aceh continues |
| Visibility (sighting countries) | announcements 2009–2026, 81% overall, per-country rates in results doc Round 7 | a prediction at any date; no data to check | the same |
| ICU's `.islamic` (for reference) | — | — | 20% of announcements |
