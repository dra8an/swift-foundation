# Round 4, item 2: our rule against the table after AH 1450, and your two rules in our engine

Written 2026-11-11. All counts here are **measured** with the icu4swift engine (its own code for the sun, the moon,
the new moon and the horizon; the series are the published ones of Meeus and of Calendrical Calculations, as yours
are). The table is ICU's Umm al-Qura table, AH 1300 to 1600. Each month is judged alone: from the table's own first
day, a rule is evaluated on the evening of day 29, and its answer (29 or 30 days) is compared with the table's.

## Answer

**Yes, we compared, and we get what you get.**

| Months (AH) | Count | Our rule | Your current rule, in our engine | Your fitted table rule, in our engine |
|---|---|---|---|---|
| 1300/01 – 1419/12 | 1,440 | 943 | 942 | **1,438** |
| 1420/01 – 1422/12 | 36 | 34 | 33 | 24 |
| 1423/01 – 1450/12 | 336 | 334 | **336** | 227 |
| 1451/01 – 1600/11 | 1,799 | 1,175 | 1,176 | **1,799** |

* Your current rule gives all 336 months of AH 1423 to 1450 in our engine too, with no correction.
* Your fitted rule gives all 1,799 months after AH 1450 and 1,438 of 1,440 before AH 1420 in our engine too.
* After AH 1450, today's official rule matches about 65% of the table whichever definitions are used: ours 1,175,
  yours 1,176 in our engine, yours 1,179 in your engine. Every one of the 623 misses of your rule goes the same way:
  the table gives 30 days where the rule gives 29. In each, the moon's centre sets less than 20.4 minutes after the
  sun's.

## Our rule and its definitions

A month has 29 days if, on the evening of day 29 at the Kaaba (21°25′21″ N, 39°49′32″ E), the new moon comes before
sunset and the moon sets after the sun.

* Sunset: the sun's centre 50′ below the horizon (the upper limb with 34′ of refraction and a radius of 16′). No dip
  for the 295 m.
* Moonset: the moon's centre, seen from the surface, 34′ plus the moon's own radius below the horizon (the radius is
  0.2725 times the horizontal parallax, 14.7′ to 16.7′). No dip.
* New moon: the series of Calendrical Calculations (`nth-new-moon`), compared with that sunset.

It misses two months of AH 1423 to 1450 that your definitions give:

| Month | Evening of day 29 | Table | Our rule | Why |
|---|---|---|---|---|
| Jumada al-Ula 1427 | 2006-06-25 | 30 days | 29 | The new moon comes 65 seconds before our sunset and 2.9 minutes after your geometric sunset. |
| Jumada al-Ula 1446 | 2024-12-01 | 29 days | 30 | Our moon sets 4 seconds before our sun. With one line for both bodies, as in your rule, the moon is 0.034° above it. |

The second is the one correction that round 3 named (it wrote it as the start of the next month, 1 Jumada al-Thaniya
1446). **Your definitions are the better ones:** they need no correction, and item 1 shows that they also give all 600
months of AH 1451 to 1500 in the table of Microsoft's .NET. That is 936 of 936 months in two tables with a Saudi
source. We intend to take your definitions into our reference rule; that is not done yet.

## Your current rule, in our engine

Definitions as in your code (`VisibilityRule.ummAlQura`, commit `5396bd74`): Mecca 21.4225° N, 39.8256° E, 295 m; the
new moon before the geometric sunset; at the moment the sun's centre is 34′ plus the dip below the horizon (1.2087°),
the moon's centre, seen from the surface, at or above that same line.

* AH 1423 to 1450: 336 of 336.
* The closest months in our engine. Against the line: Rajab 1446, the moon 0.027° below it (about 7 seconds), table
  30 days; Jumada al-Ula 1446, 0.034° above it (about 9 seconds), table 29 days. Against the geometric sunset:
  Jumada al-Ula 1427, the new moon 2.9 minutes after it, table 30 days.
* The table does not fix the new-moon limit at exactly the geometric sunset. Any depression of the sun's centre from
  0 up to about 36′ gives the same 336 months. The standard sunset (50′) does not: it loses Jumada al-Ula 1427.
* AH 1420 to 1422: 33 of 36. Two misses are Jumada al-Thaniya 1421 and Rajab 1422, where the table gives 29 days
  although the new moon comes more than 4 hours after sunset. They end in the early starts of Rajab 1421 and Shaban
  1422 that van Gent (other) reports for these years, when the rule had no new-moon condition. The third is Shawwal 1420, where the moon is 0.007° above the line (about 2
  seconds) and the table gives 30 days.
* After AH 1450 our engine gives 1,176 where yours gives 1,179. The column `rule_a_days` of
  `data/ummalqura_rule_check.csv` has our answer for every month, so you can find the three.

## Your fitted table rule, in our engine

Definitions as in your code (`VisibilityRule.ummAlQuraTable`): at the geometric sunset in Mecca, a month has 29 days
if the new moon came before 00:00 Mecca time of that day, or if the moon is at least 5.5 hours old and its centre,
seen from the surface and without refraction, is still at or above the horizon 19.515 minutes later.

* AH 1451/01 to 1600/11: 1,799 of 1,799. AH 1300 to 1419: 1,438 of 1,440.
* **The two months before AH 1420 that it misses** (your note did not name them; these are ours):

| Month | Evening of day 29 | Table | Rule | Moon's age at sunset | Centre sets after the sun's by |
|---|---|---|---|---|---|
| Muharram 1364 | 1945-01-14 | 29 days | 30 | 9.80 hours | 19.385 minutes (8 seconds under the limit) |
| Shawwal 1365 | 1946-09-25 | 30 days | 29 | 6.43 hours | 20.511 minutes (a minute over the limit) |

* **The windows of the three limits** (the values for which every month still matches; both ranges together, without
  the two months above):

| Limit | Your window | Our window | The two months that set it, in our engine |
|---|---|---|---|
| Minutes after sunset | 19.50 to 19.53 | 19.4997 to 19.5277 | Dhu al-Hijjah 1539 (30 days) and Jumada al-Thaniya 1587 (29 days) |
| Moon's age in hours | 5.35 to 5.64 | 5.344 to 5.641 | Dhu al-Qadah 1538 (30 days) and Rajab 1466 (29 days) |
| Start of the day | 00:00 Mecca time | from 3.4 minutes before to 1.2 minutes after 00:00 Mecca time | Jumada al-Ula 1454 (29 days) and Muharram 1337 (30 days) |

* How much each part decides, AH 1451 to 1600: of the 844 months of 29 days, 510 pass only the test of age and
  minutes, 22 pass only the test of the start of the day, and 312 pass both.

**What this agreement shows, and what it does not.** The two engines were written apart, and they give the same
windows to the second. So the fit is not an accident of one program. But both use the same published series, so this
is not a test against a different theory of the moon. The window for the minutes is 1.7 seconds wide among about
1,650 months that it decides, which is about the gap that chance leaves between neighbours; any value inside it is as
good as 19.515. We found no published text for this rule either.

## Our question of 2026-11-09, withdrawn

We asked what your table was compared against, because we took the table outside AH 1420 to 1450 for something other
than KACST's calendar. Item 1 shows that KACST's site publishes the table's dates after AH 1450 for the months
checked. We withdraw that reading, and we do not propose to replace any part of the table by the rule.

## Data

* `data/ummalqura_rule_check.csv` — one row for each month from AH 1300/01 to 1600/11, labelled by the month whose
  length is decided. Columns: the table's first day and the evening of day 29; the table's length; the new moon and
  the geometric sunset (UTC, our engine); the moon's age in hours at that sunset (negative if the new moon comes
  later); the hours by which the new moon came before 00:00 Mecca time of that day; the minutes between the settings
  of the two centres; the moon's height in degrees above your line at your moment; then the answer of your current
  rule (`rule_a_days`), of your fitted rule (`rule_b_days`) and of our rule, and our rule's own two margins.
* `data/ummalqura_table_sweep.txt` — the first run of our rule against the table, of 2026-11-09. **Its rows are
  labelled by the month that starts**, one month later than in the file above (its `AH 1446-06` is the row
  `1446,5` there). It counts 1,544 of 2,172 for AH 1420 to 1600 where the table above has 1,543 of 2,171, because it
  also includes the start of 1 Muharram 1420 (the length of Dhu al-Hijjah 1419).
* `data/dotnet_umalqura_first_days.csv` — the month starts of AH 1318 to 1500 computed from the table in Microsoft's
  .NET (item 1).

## Line endings

You were right. Two files of `round-3/data` had Windows line endings: 633 lines of `crescent_official_dates.csv` and
all 1,767 lines of `announced_dates_2009_2026.csv`. Both now end every line with `\n`; nothing else in them changed.
Our own tests split on any line ending, which is why we did not see it.
