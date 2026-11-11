# Round 5: Diyanet before 1980, and four corrections where there were five

**TEMPORARY. Do not merge upstream.** Written 2026-11-11. Nothing in this repository's sources was changed. This round
was not requested: the owner of the project asked us to re-examine the five Diyanet corrections of round 3, and two
things changed as a result. Every statement says whether its source is **official**, **other** or **none**; counts are
**measured** with the icu4swift engine.

## What changed

1. **A separate rule for first days before 1 January 1980.** The 1978 rule (altitude 5°, elongation 8°, before 24:00
   UTC) took effect with the 1980 calendar, not in December 1978. Before that, Diyanet's published months follow an
   older test.
2. **1 Ramazan 1399 (26 July 1979) is no longer a correction.** The older test gives the published date. Four
   corrections remain: 1 Şaban 1401, 1 Cemaziyelevvel 1411, 1 Zilkade 1444, 1 Zilhicce 1453.

With this, the rules alone reproduce 703 of the 707 published decisions of AH 1399 to 1457, and all 707 with the four
corrections (measured; before: 702 and five).

## The older test

For a candidate first day before 1 January 1980 (rata die 722815), the month before it has 29 days if, on the evening
of its day 29, **the moon sets at least 18.5 minutes after the sun at Mecca**. Nothing else is tested.

* Place: 21°25′21″ N, 39°49′32″ E. The elevation is not used and there is no dip of the horizon.
* Sunset: the sun's upper limb at the horizon with 34′ of refraction and a radius of 16′ (centre 50′ below).
* Moonset: the first one after 8 hours before that sunset. The moon's centre, seen from the surface, is 34′ plus
  0.2725 times the horizontal parallax below the horizon (the upper limb with refraction).
* The limit: any value from 18.1 to 18.7 minutes gives the same published dates for first days in 1978 and 1979. Inside
  the range that the tests cover (AH 1399 on), the limit can be anywhere from 13.2 to 18.7 minutes: the closest months
  are 1 Ramazan 1399 (waits, 13.19 minutes) and 1 Safer 1400 (starts, 18.73 minutes). Your sunset includes the dip
  for 295 m, so your minutes can differ from ours by some seconds; check these two months.

This test describes Diyanet's published list. It is not Diyanet's documented method (none). Keleş (other) says that
until 1974 Türkiye computed the visibility for an observer on a 4,300 m peak in Morocco, and van Gent (other) puts the
start of the 5° and 8° rule at AH 1400.

## The evidence

Diyanet's published first days (official, the Hicri to Miladi tables on vakithesaplama.diyanet.gov.tr) against both
tests, by the calendar year of the first day (measured; one row for each decision in
`data/diyanet_older_test_1960_1995.csv`):

| First day in | Months | 1978 rule | Older test |
|---|---|---|---|
| 1960–1977 | 222 | 175 | 209 |
| 1978 | 13 | 10 | **13** |
| 1979 | 12 | 11 | **12** |
| 1980 | 12 | **12** | 9 |
| 1981 | 13 | 12 | 11 |
| 1982–1995 | 173 | 172 | 132 |

Where the two tests give different answers, Diyanet follows the older test in 39 of 44 months of 1960 to 1977 and in
4 of 4 months of 1978 and 1979. It follows the 1978 rule in 46 of 48 months of 1980 to 1995. The switch is at the 1980
calendar. The same happened in 2016: the calendar of that year was computed before the congress of May 2016, and the
new rule shows from 2017.

Two limits of this evidence:

* In 1979 itself, Ramazan is the only month in which the two tests differ. The case rests on 1978, on the exact
  switch in 1980, and on Diyanet computing one calendar year at a time.
* The older test is not exact before 1978. It gives 234 of 247 months for 1960 to 1979. Its misses suggest a second
  condition that we did not find (five refusals with an elongation under 5.6°).

## What to change in the port

1. For a first day before 1 January 1980, decide by the older test and skip the 1978 rule.
2. Remove 25 July 1979 from the corrections. That is the day the 1978 rule gave for 1 Ramazan 1399; the published day
   is 26 July 1979.
3. Expect 703 of 707 by the rules alone, and these four misses: 1 Şaban 1401 (rule 3 June 1981, published 4 June),
   1 Cemaziyelevvel 1411 (18 and 19 November 1990), 1 Zilkade 1444 (20 and 21 May 2023), 1 Zilhicce 1453 (12 and
   13 March 2032).

If the port states that the Diyanet calendar begins at AH 1399, these 14 months (1 December 1978 to 20 December 1979)
are the only ones the older test decides.

## The four corrections that remain

All four are months the rule starts one day before the published day. Each was tested again (measured):

| First day (published) | What we found |
|---|---|
| 1 Şaban 1401, 4 Jun 1981 | The elongation reaches 8° 14.1 minutes before 24:00 UTC, and Diyanet waited. In July 1993 it reaches 8° 13.8 minutes before, and Diyanet started. No clock offset and no threshold gives both. |
| 1 Cemaziyelevvel 1411, 19 Nov 1990 | 46 seconds before 24:00 in universal time, 12 seconds after it in dynamical time. A program that used dynamical time before 2009 would refuse this month and change no other. One decision supports that, so it stays a correction. |
| 1 Zilkade 1444, 21 May 2023 | Mainland Alaska passes with +0.222°. May 2030 started with +0.083° on the same coast. No shift of the altitude and elongation thresholds refuses this month and keeps the others. |
| 1 Zilhicce 1453, 13 Mar 2032 | +0.030° at the tip of the Seward Peninsula, about two minutes of sunset on the wrong side of June 2021, which started with +0.012°. The new moon is 16 minutes before dawn at Wellington; the smallest margin of any start is 24. |

The altitude part of the rule is fixed from both sides by four months in three of Diyanet's computation runs: started
with +0.087° (November 2017) and +0.013° (June 2021), refused with −0.012° (May 2033) and −0.042° (February 2026).

## Files

Changed in `round-3/`, so that the package there still matches our code:

| File | Change |
|---|---|
| `1_Diyanet_and_regional_spec.md` | new step 0 (the older test), §4 (four corrections and their reasons), §5 (range of validity) |
| `2_islamic_identifier_proposal.md` | one cell: four corrections |
| `reference-code/CrescentRules.swift.txt` | `DiyanetEra.before1980`, `years1980to2008` (was `before2009`), `diyanetOlderTestMinimumLagMinutes`, `diyanetCorrections` |
| `reference-code/HijriRegional.swift.txt` | one comment |
| `reference-tests/CrescentDiyanetPublishedTests.swift.txt` | the era boundary of 1980; 703 and four misses |
| `data/crescent_astronomy_fixture.csv` | Diyanet rows: the era label; for the 14 rows before 1980 the sunset and moonset at Mecca and the minutes between them; `rule_days` of AH 1399-9 is now 30 |

New here: `data/diyanet_older_test_1960_1995.csv`, one row for each decision with a first day from 1960 to 1995. Its
columns: the month that starts and its published first day; the evening of day 29; the published length of the month
before; the minutes from sunset to moonset at Mecca and the answer of the older test; the minutes from 24:00 UTC to
the moment the elongation reaches 8° (negative means before) and the answer of the 1978 rule.

## Also on this branch

`Docs/Islamic_Crescent_Calendars.md` is a guide in plain words that the owner asked for, in the style of the other
calendar guides. It is not temporary. Change it as the code requires.
