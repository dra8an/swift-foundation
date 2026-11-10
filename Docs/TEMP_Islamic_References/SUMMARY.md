# Summary and suggested code changes

Research collected 2026-11-05 from sources the coding agent cannot reach. Details, quotes, links, provenance and all dates are in the per-rule files next to this one. Provenance: **official** = the authority itself, **other** = secondary, **none** = not found. Verification: 85 checks, 0 refuted.

## What to change

| Rule | Our value | Status | Suggested change |
|---|---|---|---|
| Diyanet | 5° altitude, 8° elongation | correct (official) | Keep. Framework is the 2016 Istanbul congress, thresholds from 1978. |
| Diyanet | 60°S–60°N, oceans included | **wrong limit** | Remove the ±60° limit. Official text: "anywhere on Earth", no latitude limit; oceans count. Skip only places with no sunset. |
| Diyanet | before 00:00 UTC | correct (other) | Keep; mark as secondary-sourced (congress working paper: "before 24:00 GMT"). |
| Diyanet | Wellington, dawn = Sun 18° below | partly | Keep Wellington (official). The month rule says "imsak" with no angle; 18° is Diyanet's general imsak angle (other). Keep 18°, document it. Americas condition is official: "mainland North and South America" (land only). |
| MABIMS | 3° altitude, 6.4° elongation, all 4 countries | partly | Values correct for Malaysia, Indonesia, Singapore. Make the start date per country: Malaysia from 1 Muharram 1443 (2021-08-10); Indonesia from 1 Ramadan 1443 (2022-04-03, decided 2021-12-08); Singapore from 2022. Before that: altitude 2°, elongation 3°, OR moon age 8 h (MABIMS 1992). Brunei decides Ramadan, Syawal, Zulhijjah by sighting only (not computable; other). |
| MABIMS | definitions | new detail | Indonesia (official, PMA 1/2026 Art. 4(4)): altitude **topocentric**, elongation **geocentric**. Malaysia (eKITAB): apparent altitude = h − parallax + refraction (r = 7′54″), **moon centre**; elongation from airless topocentric positions. |
| MABIMS | Banda Aceh for all four | **wrong** | Per country. Indonesia: anywhere in the national territory, in practice the far northwest (Banda Aceh is a fair approximation; Sabang is further west). Malaysia: Tanjung Chinchin 6°26′10″N 99°38′30″E up to 1443, Pulau Perak 5°41′05″N 98°56′14″E from 1 Muharram 1444 (change official, coordinates other); a sighting anywhere in Malaysia also counts. Singapore: Tuas 1.2949°N 103.6305°E (official), calculation only. Brunei: sighting, no computed place. |
| Egypt | conjunction before sunset, moonset ≥ 5 min after sunset | **wrong** | Official (Dar al-Ifta fatwa 3420, 2016): on the evening of the 29th the month can start only if the moon sets after the sun AND moonset is ≥ **15 h 40 min after conjunction**; then an actual sighting is required. Fixed lag rules (16 or 20 min) are explicitly rejected. Suggest: implement the 15 h 40 min filter as the computed rule and document that a failed sighting can still make the month 30 days. |
| Egypt | Cairo | **wrong** | Sighting committees across Egypt (7 in 2016; 2011 list: Helwan, Qatamiya, 6 October, Salloum, Qena, Aswan, al-Wahat, Toshka, Marsa Alam, St Catherine). No coordinates published. Suggest: test both "Cairo" and "any of these sites" against the 103 official dates in Egypt.md and keep the better match. |
| Egypt | — | note | Dhu al-Hijjah follows the Saudi Supreme Court decision (6 of 7 recorded deviations). The Egyptian Survey Authority publishes an official computed Hijri calendar (prayer-time tables); its algorithm was not found. It differed from the announcement once (Ramadan 1447). |
| Umm al-Qura | rule since AH 1423 | **wrong year** | Official texts say **AH 1420**. Only secondary sources (van Gent) say 1423 with moonset-only for 1420–1422. |
| Umm al-Qura | conjunction before sunset + moonset after sunset at Mecca | partly | The official printed table has three conditions: whole disc of the moon above the horizon after sunset, moonset after sunset at Makkah, astronomical birth of the crescent. Place (official): 39°49′32″E, 21°25′21″N, 295 m. "Geocentric conjunction" is secondary only. |
| Umm al-Qura | table vs rule after AH 1450 | explained | The official printed calendar covers AH 1420–1450 only. The 1300–1600 table in ICU came from KACST via IBM Egypt (2014); after 1450 it is not authority-published. Suggest: keep the table for ICU parity (Foundation's target) and document that post-1450 values are not official. |
| All | months longer than 30 days | answered | Never (official, all four). Test only on the evening of the 29th; if it fails the month has 30 days and the next day starts the new month, with **no test on the 30th**. Make sure the code never tests on day 30 or produces a 31-day month. |

## Dates available for tests

| File | Rows | Official coverage |
|---|---|---|
| Diyanet.md | 215 | Diyanet tables AH 1440 to 1457 |
| MABIMS.md | 154 | Malaysia JAKIM continuous 1440/1 to 1450/8; Indonesia and Singapore announcements |
| Egypt.md | 103 | complete Dar al-Ifta announcements 1440/1 to 1448/5 (50 sighted on the 29th, 53 completed to 30) |
| Umm_al-Qura.md | 132 | see file; official publication ends 1450 |

## Terms of use (before copying dates into the repo)

ICOP forbids republishing and its robots.txt blocks Claude agents; nothing from it is used. moonsighting.com has only a bare copyright line. Per-source terms for the official sites are in each file; most state no licence, so treat the dates as test references and check before committing them upstream.
