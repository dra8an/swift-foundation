# TEMPORARY: research request for the Islamic calendar rules

**Do not merge this file upstream. Delete it before any pull request.** It is a work note for a research agent.

## Round 4 (2026-11-11): the official Umm al-Qura months after AH 1450

Thank you for round 3. We ported its rules, and every official month of `crescent_official_dates.csv` now matches (Diyanet with your five corrections, Malaysia with your two). Same rules as before: do not guess, write "not found" and where you looked, and say for each statement whether the source is official, another source, or none.

**What we found, for your notes.**
* **Our Umm al-Qura rule needs no correction.** Round 3 gives 131 of 131 months of AH 1440 to 1450 with one correction. Ours gives all 336 months of the table from AH 1423 to 1450 with none. Our definitions, all at Mecca (21.4225° N, 39.8256° E, 295 m): the new moon (in ecliptic longitude) comes before the geometric sunset (the sun's centre at the horizon, no refraction). The test is made when the sun's centre is 34′ plus the dip below the horizon. At that moment, the moon's topocentric centre must be at or above that same line.
* **The table after AH 1450 follows another rule.** Our rule above gives only 1,179 of the 1,799 months of AH 1451 to 1600/11 in the table that ICU has, spread over every block of 10 years. This rule gives all of them, and also 1,438 of the 1,440 months of AH 1300 to 1419: a month has 29 days if the new moon came before 00:00 Mecca time (UTC+3) at the start of day 29, or if at the geometric sunset of day 29 the moon is more than 5.5 hours old and its centre sets more than 19.515 minutes after the sun's centre (topocentric, no refraction). We found this rule by tests against the table. We have no published source for it.
* **Line endings.** 633 lines of `round-3/data/crescent_official_dates.csv` end with `\r\n`, the others with `\n`. A program that splits only on `\n` loses those rows.

**1. KACST's own month starts after AH 1450.** The first day of each month for AH 1451 to 1600 (2029 to 2174), or as far as KACST publishes them. Round 3 had official data only up to AH 1450 (the printed table of AH 1420 to 1450). We must know which one KACST publishes today: the future part of ICU's table, or today's official rule.
* Where to look: the converter on ummulqura.org.sa, any newer printed table or PDF from KACST or the Ministry of Finance, and any KACST statement about how the future years are computed. `robots.txt` of ummulqura.org.sa disallows `/api/`, so use only what the public pages show.
* Check these months first. In each, the table in ICU and today's official rule differ by one day, with a clear margin (the moon 1.7° to 3.4° above the horizon at sunset, the new moon 4.5 to 18 hours before sunset):

| Month | ICU's table | Today's official rule |
|---|---|---|
| 1 Rabi al-Thani 1451 | 2029-08-12 | 2029-08-11 |
| 1 Rajab 1451 | 2029-11-08 | 2029-11-07 |
| 1 Dhu al-Qadah 1451 | 2030-03-06 | 2030-03-05 |
| 1 Ramadan 1453 | 2031-12-16 | 2031-12-15 |
| 1 Shawwal 1454 | 2033-01-03 | 2033-01-02 |

* For each month you find, give the Hijri month, the Gregorian first day, the source link, and whether the source is official.

**2. Your rule against the table after AH 1450.** Did you compare your Umm al-Qura rule with the table of AH 1451 to 1600? If yes, how many months matched, and with which definitions? If no, please run it and report the count.

**Format of the results of round 4.** Put them in `Docs/TEMP_Islamic_References/round-4/`, one Markdown file for each of the two items, with quotes, links and the provenance of each statement, as before.

## Round 2 (2026-11-06): the exact computation of each authority

The results of round 1 are in `Docs/TEMP_Islamic_References/`. With them, our rules now give the official first day in almost every month: Diyanet 211 of 215, Malaysia 124 of 127, Umm al-Qura 131 of 132, Indonesia and Singapore all. The remaining months all sit right at a threshold: hundredths of a degree, or seconds of time. So each authority computes some detail differently from us. Same rules as in round 1: do not guess, write "not found" and where you looked, and say for each statement whether the source is official, another source, or none.

**1. Diyanet: how the computation is done.**
* The booklet "Kameri Ay Başları Hesap ve Haritaları" (2014, for 1437 to 1444 AH) and any later edition, for example for the years through 2035. If a copy is online, the pages that describe the method.
* Which astronomical algorithms or ephemeris Diyanet uses.
* The moment of the test: sunset of the upper edge of the sun with refraction, or of the center of the sun at the horizon without refraction, or something else.
* The moon's altitude: from the surface or from the center of the Earth, to the center of the moon or to an edge, with or without refraction. The elongation: from the surface or from the center of the Earth.
* How "seen on the mainland of North or South America" is checked: a list of points, a grid, a map of land, or something else. And how the time limit of 00:00 UTC is applied.
* The sun angle for imsak at Wellington in this rule.
* Diyanet's visibility maps or computed values for these evenings, if published: 2021-06-10, 2023-05-19, 2026-02-17, 2030-05-02, 2032-03-11 and 2033-05-28.

**2. The western coast of the American mainland.** The westernmost point of the mainland of North America and of South America (not islands) for each whole degree of latitude, from 70° N to 55° S: latitude, longitude, the place name if any, and the source. A public domain source such as Natural Earth is best. Say which source, which version, and its license.

**3. Malaysia (JAKIM): how the takwim is computed.**
* The Almanak Falak Syarie: its table of refraction for the moon's altitude, and how it defines the moon's altitude and the elongation (from the surface or from the center of the Earth, with or without refraction, which edge of the moon).
* The moment of sunset that JAKIM uses, and the elevation used for Tanjung Chinchin and Pulau Perak.
* Any published values (altitude, elongation, sunset and moonset times) for these evenings: 2020-11-15 at Tanjung Chinchin, 2022-11-24 at Pulau Perak, 2027-12-28 at Pulau Perak.

**4. Umm al-Qura (KACST): how the table computes sunset and moonset.**
* Sunset and moonset of the upper edge with refraction, or of the centers at the horizon without refraction, or something else. How the elevation of 295 m is used.
* Any published sunset and moonset times at Mecca for the evening of 2024-12-01.

**Format of the results of round 2.** Put them in `Docs/TEMP_Islamic_References/round-2/`, one Markdown file for each of the four items above, with quotes, links and the provenance of each statement, in the same style as round 1.

## Why we need this

We are writing Swift implementations of Hijri calendars that start each month by an astronomical rule. To check them, we need the official rules and the official dates. Please collect the items below. Do not guess. If something is not known, write "not found" and say where you looked.

## What we know so far, to confirm or correct

| Rule | Used in | The criterion as we know it |
|---|---|---|
| Diyanet | Turkey, and some Balkan countries | The 1978 Istanbul criterion: somewhere on Earth, at sunset, the moon is at least 5 degrees high and at least 8 degrees from the sun |
| MABIMS | Brunei, Indonesia, Malaysia, Singapore | The criterion approved in 2019: at sunset, the moon is at least 3 degrees high and at least 6.4 degrees from the sun, judged in the region |
| Egypt | Egypt | The moon sets at least 5 minutes after the sun, judged at Cairo |
| Umm al-Qura | Saudi Arabia | Since AH 1423: the new moon comes before sunset, and the moon sets after the sun, both at Mecca |

## What to collect for each rule

1. **The official text of the criterion that is in use today,** with a link and a short quote. Say since when it is in use, and list earlier versions with their dates.
2. **The exact definitions,** because they change the margin cases:
   * Is the height of the moon measured from the center of the observer's place on the surface (topocentric) or from the center of the Earth (geocentric)?
   * Is it measured to the center of the moon or to its upper edge?
   * Does it include the bending of light by the air (refraction)?
   * Is the angle between the moon and the sun measured from the surface or from the center of the Earth?
   * At which moment is the test made: at sunset, at a fixed time, or at a best time after sunset?
   * At which place: the coordinates, or the area and the rule for "somewhere on Earth" (for example a time limit, or a condition about land)?
3. **The official first day of each month for AH 1440 to 1460,** from the authority itself, with links. Add later years if the authority publishes them.
4. **The months where the announced first day differed from the computed rule,** for example because of a sighting decision, with the reason if it is given.
5. **The terms of use of each source:** may the dates be used to test software, and may they be copied into an open source repository?

### Rule by rule

* **Diyanet:** is today's Turkish calendar based on the 1978 criterion or on the 2016 Istanbul conference (the "unified Hijri calendar")? Diyanet's published tables for AH 1440 to 1460.
* **MABIMS:** for each of the four countries, the criterion in use and the date it was adopted, the place where it is judged, and the official calendar (for example Malaysia's JAKIM takwim and Indonesia's Kemenag takwim).
* **Egypt:** the authority that computes the calendar, the criterion text, the place, the published dates, and the cases where Dar al-Ifta's decision differed.
* **Umm al-Qura:** the newest calendar that KACST or the Saudi government publishes, for AH 1446 and later. How the future years of the table are computed, and any corrections that were published. Our check shows that a table we have agrees with the AH 1423 rule in 99% of months from AH 1423 to 1450, but only in about 65% after AH 1450. We want to know which of the two the authority follows for future years.

### Archives of announced dates

* **ICOP** (astronomycenter.net) and **moonsighting.com** keep the announced first day of each month for each country. Please report only their terms of use and the structure of their pages. Do not copy their data yet.

## Format of the results

Put the results next to this file, in `Docs/TEMP_Islamic_References/`, one Markdown file for each rule:

* A section "Criterion", with the quotes and links from items 1 and 2.
* A table with the columns: Hijri year, Hijri month, first day (Gregorian, yyyy-mm-dd), source link, notes.
* A section "Terms of use".
* For each statement, say whether you found it in an official source, in another source, or not at all.
