# Round 4, item 1: the month starts KACST publishes after AH 1450

Written 2026-11-11. Every statement says whether its source is **official** (the authority's own site or document),
**other** (a secondary source) or **none** (not found, or not checked). Measurements are ours, made with the icu4swift
engine; they are marked **measured**.

## Answer

1. **KACST's site shows the dates of ICU's table, not the dates of today's official rule.** Nine months after AH 1450
   were looked up, all five of your list among them, each one a month where the two differ by a day. The site showed
   ICU's date in all nine (official; table below). One month before AH 1420 was looked up too, and there the site also
   shows ICU's date.
2. **No official list of the months after AH 1450 was found.** The site answers one date or one year at a time, and
   only up to AH 1500. Nothing official was found for AH 1501 to 1600.
3. **A second table with an official pedigree disagrees with ICU's after AH 1450.** The table inside Microsoft's .NET,
   which Microsoft says is licensed from the Saudi government, covers AH 1318 to 1500. For AH 1451 to 1500 it is one
   day earlier than ICU's table in 211 of 600 months, and it equals today's official rule in 600 of 600 months
   (measured, with your definitions of that rule).
4. **Our recommendation: keep ICU's table for `.islamicUmmAlQura`, AH 1300 to 1600, unchanged.** It is what KACST's own
   site shows today for the months checked, and it is what ICU, Java and Apple's Foundation ship. Record the
   disagreement with .NET as a known open point. We do not propose replacing any part of the table by the rule.

## The months looked up on KACST's site

Looked up by hand, in a browser, on <https://www.ummulqura.org.sa> on 2026-11-11 by the owner of this project. The
research agent did not see the pages: the site's `robots.txt` disallows `/api/` and `/backend/`, where its dates come
from, so no program read them. The owner did not say which public page was used (the site has a converter and a
yearly calendar).

| First day of | Shown by KACST's site (official) | ICU's table | Today's official rule (measured) | .NET's table (other) |
|---|---|---|---|---|
| 1 Rabi al-Thani 1451 | 2029-08-12 | 2029-08-12 | 2029-08-11 | 2029-08-11 |
| 1 Rajab 1451 | 2029-11-08 | 2029-11-08 | 2029-11-07 | 2029-11-07 |
| 1 Dhu al-Qadah 1451 | 2030-03-06 | 2030-03-06 | 2030-03-05 | 2030-03-05 |
| 1 Ramadan 1453 | 2031-12-16 | 2031-12-16 | 2031-12-15 | 2031-12-15 |
| 1 Shawwal 1454 | 2033-01-03 | 2033-01-03 | 2033-01-02 | 2033-01-02 |
| 1 Muharram 1458 | 2036-02-29 | 2036-02-29 | 2036-02-28 | 2036-02-28 |
| 1 Rajab 1470 | 2048-04-15 | 2048-04-15 | 2048-04-14 | 2048-04-14 |
| 1 Shawwal 1483 | 2061-02-22 | 2061-02-22 | 2061-02-21 | 2061-02-21 |
| 1 Jumada al-Ula 1496 | 2073-05-09 | 2073-05-09 | 2073-05-08 | 2073-05-08 |

The first five rows are your list. The other four were chosen by us before your request arrived, by the same test:
a clear margin for the rule (the moon sets 9 to 20 minutes after the sun, the new moon 9.5 to 14 hours before sunset).

One month before AH 1420, where ICU's table and .NET's differ (see below), was looked up the same way:

| First day of | Shown by KACST's site (official) | ICU's table | .NET's table (other) |
|---|---|---|---|
| 1 Muharram 1400 | 1979-11-21 | 1979-11-21 | 1979-11-20 |

## Where we looked for a full official list, and what was not found

* **The site's public pages** (official). The site is a single-page application; its static files hold only text, and
  every date comes from the backend that `robots.txt` disallows. Its yearly-calendar page offers AH 1318 to 1500
  (round 1 read this from the page's code on 2026-11-05; not read again today). So the site covers AH 1451 to 1500
  one year at a time, and nothing after AH 1500. **A full list for AH 1451 to 1600: not found.**
* **A newer printed table or PDF: not found.** The only printed table we know is the Ministry of Finance and KACST
  table of AH 1420 to 1450 (official; `../Umm_al-Qura.md`). Looked: the round 1 searches in Arabic and English
  (`تقويم أم القرى بعد عام 1450هـ`, `Umm al-Qura KACST data 1451 1500`), and van Gent's bibliography (other), which
  lists printed tables for AH 1300 to 1429 and for AH 1420 to 1450 only.
* **A KACST statement on how the future years are computed: not found.** The site states the rule in general terms
  (official, read in round 1): "ويتم تحديد بداية الشهر عند ولادة الهلال وغروب القمر بعد غروب الشمس في مكة المكرمة"
  (the start of the month is set at the birth of the crescent and the setting of the moon after the sun in Makkah).
  That text describes today's rule. It does not describe the dates the site shows after AH 1450.

## The two tables and where each comes from

**ICU's table, AH 1300 to 1600** (other). The record is ICU ticket ICU-10695,
<https://unicode-org.atlassian.net/browse/ICU-10695>, read today through the tracker's public interface (its
`robots.txt` allows it):

* 2014-04-21: "Unable to use the http://www.ummulqura.org.sa/ site to validate the days-in-month table I reached out
  to KACST in hopes to get an authoritative source."
* 2014-06-17: "received word from our team in Egypt: We have successfully contacted KASCT team and got the official
  data from year 1300 to 1600. It seems the website was not updated with all the data correctly".
* 2014-06-17: "I tested with the data supplied by our Egypt team and it matches the Java v8 JDK results now from years
  1300-1600."
* 2014-09-09: "Rolled in the attached data, much better."

The ticket's attachment `HIJRA.TXT` holds the month lengths of AH 1300 to 1600. We compared it with ICU's table: the
same first day (1882-11-12) and the same length for all 3,611 months from 1300/01 to 1600/11 (measured). The file is
written in the format of Java's Hijrah calendar properties file (`iso-start=1882-11-12`, then `1300=30 29 30 …`).
KACST itself is not quoted anywhere in the ticket, so the claim that the data is KACST's rests on the comment above.

**The table in Microsoft's .NET, AH 1318 to 1500** (other). Source file, MIT licence:
<https://github.com/dotnet/runtime/blob/60685192899cbd2f47534e17dc2861bfd7cb77b9/src/libraries/System.Private.CoreLib/src/System/Globalization/UmAlQuraCalendar.cs>.
Its comment says "These data are taken from Tables/Excel/UmAlQura.xls". Microsoft's documentation says the calendar
"uses a table-based algorithm licensed from the Saudi government" and "can express dates to the year 1500 A.H."
(<https://learn.microsoft.com/en-us/dotnet/api/system.globalization.umalquracalendar>, read in round 1). The Saudi
document behind it is not public. The month starts we computed from that file are in
`data/dotnet_umalqura_first_days.csv`.

## The two tables compared (measured)

Each month is judged alone: from the table's own first day, the rule is evaluated on the evening of day 29 and its
answer (29 or 30 days) is compared with the table's.

| Years (AH) | Month starts equal in both tables | What ICU's table follows | What .NET's table follows |
|---|---|---|---|
| 1318–1355 | 85 of 456 | your fitted rule (see item 2) | the day after the UTC date of the new moon: 456 of 456 |
| 1356–1391 | 80 of 432 | your fitted rule | the same: 432 of 432 |
| 1392–1419 | 61 of 336 | your fitted rule | the same: 336 of 336 |
| 1420–1450 | 372 of 372 | the printed official table | the printed official table |
| 1451–1500 | 389 of 600 | your fitted rule: 600 of 600 | today's official rule, your definitions: 600 of 600 |
| 1501–1600 | not in .NET | your fitted rule: 1,199 of 1,199 | not covered |

Where the two differ, .NET's month starts one day earlier than ICU's (two days earlier in 17 months before AH 1420).

Two things follow.

* **After AH 1450** the two tables are two different computations: .NET's is today's official rule carried forward,
  ICU's is a stricter rule that no published text describes. KACST's site sides with ICU's in the nine months checked.
* **Before AH 1420** .NET's table is exactly the rule that van Gent (other) documents for AH 1392 to 1419: the month
  starts at the sunset before "When the astronomical new moon occurs less than 3 hours after Saudi midnight (equivalent
  with 0h UTC or Greenwich midnight)", and "otherwise at the sunset following that"
  (<https://webspace.science.uu.nl/~gent0113/islam/ummalqura_rules.htm>, as quoted in our round 1 notes). In civil
  days that is the day after the UTC date of the new moon. ICU's table differs from
  it in 275 of the 336 month starts of AH 1392 to 1419. So for 1972 to 1999, the years when that rule was in force,
  ICU's table is not the calendar as that rule gives it. Example: 1 Muharram 1400 is 1979-11-21 in ICU's table and
  1979-11-20 in .NET's. KACST's site shows 1979-11-21 (official, looked up as above), so for this month the site has
  the same date as ICU's table. Which of the two days the Saudi calendar printed in 1979: **not checked against a
  source of that time** (none).

This does not change the recommendation: the port matches ICU, and ICU's table is what KACST's site shows for the
future months checked. It is recorded here because it is a measured difference between two tables that both claim a
Saudi source, and because a user who compares the port with Windows will see it.

## What is settled, and what is not

Settled by the lookups: KACST's site shows ICU's dates for every month checked, nine after AH 1450 and one before
AH 1420. For the one month before AH 1420 it does not show the date of the rule that was in force then. So the site
appears to serve the same AH 1300 to 1600 data that ICU has, at least for the years it covers (AH 1318 to 1500). Ten
months are a sample, not the whole table.

Not settled, and nothing on the web can settle it today: which dates Saudi Arabia will print for AH 1451. The printed
official table ends at AH 1450 (May 2029). Also not found: any published text for the rule behind the table outside
AH 1420 to 1450, and any official list for AH 1501 to 1600.
