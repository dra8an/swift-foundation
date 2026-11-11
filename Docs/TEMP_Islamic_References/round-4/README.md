# Round 4: the Umm al-Qura months after AH 1450

**TEMPORARY. Do not merge upstream.** Written 2026-11-11 in answer to "Round 4" of
`Docs/TEMP_Islamic_References_Request.md`. Nothing in this repository's sources was changed.

1. `1_KACST_month_starts_after_1450.md` — which dates KACST publishes after AH 1450.
2. `2_our_rule_against_the_table.md` — our rule against the table, and your two rules checked in our engine.

## The short answers

* **KACST's site shows ICU's dates.** Nine months after AH 1450 where ICU's table and today's official rule differ
  were looked up by hand on ummulqura.org.sa, all five of your list among them; all nine showed ICU's date. So did
  one month before AH 1420 (1 Muharram 1400).
* **Keep ICU's table for `.islamicUmmAlQura` as it is.** We do not propose to replace any part of it by the rule.
* **Both of your rules hold in our engine.** Your current rule gives 336 of 336 months of AH 1423 to 1450. Your fitted
  rule gives 1,799 of 1,799 months of AH 1451 to 1600/11 and 1,438 of 1,440 of AH 1300 to 1419; the two it misses are
  Muharram 1364 and Shawwal 1365. Our windows for its limits equal yours to the second.
* **A second table with a Saudi source disagrees with ICU's.** The table in Microsoft's .NET (AH 1318 to 1500) is one
  day earlier than ICU's in 211 of the 600 months of AH 1451 to 1500. There it equals today's official rule, with your
  definitions, in 600 of 600 months. Before AH 1420 it also differs from ICU's, in about four months of five.
* **No published text was found** for the rule behind the table after AH 1450, and no official list of those months.

## Changed outside this folder

Only line endings: `round-3/data/crescent_official_dates.csv` and `round-3/data/announced_dates_2009_2026.csv` now end
every line with `\n`. Their content is otherwise the same.

## Data

`data/ummalqura_rule_check.csv`, `data/ummalqura_table_sweep.txt` and `data/dotnet_umalqura_first_days.csv` are
described at the end of the second file. The .NET month starts were computed from Microsoft's MIT-licensed source
file, linked in the first file.
