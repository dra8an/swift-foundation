# Round 3: the Hijri calendars, ready to port

**Updated by round 5 (2026-11-11):** a separate rule for Diyanet's first days before 1980, and four Diyanet corrections
where there were five. The six files that changed are listed in `../round-5/README.md`. Where this file says five, read four.

Assembled 2026-11-09 from the icu4swift verification package (branch `islamic-crescent`). Everything here was computed
and tested on the research machine; nothing has been changed in this repository's sources. Read in this order:

1. `1_Diyanet_and_regional_spec.md` — the behaviour to implement: Diyanet step by step (§1–6), Umm al-Qura (§7), which
   calendars to ship and which not (§8), the region-aware calendar and its reference implementation (§9–10), validity
   of each method (§11).
2. `2_islamic_identifier_proposal.md` — what `.islamic` computes today (ICU's conjunction clock, 20% of announced
   dates), the one-piece proposal (default Umm al-Qura, region → method), the four work items, an API sketch.
3. `3_measurements_and_rejected_hypotheses.md` — the evidence: every round of measurement, every hypothesis tried and
   rejected (do not retry them), the five Diyanet dates no rule reproduces and why.

## What to port

| From | To | Notes |
|---|---|---|
| `reference-code/HijriRegional.swift.txt` | the region → method table and `monthLength(start:next:method:)` | ISO regions, reference points, Odeh thresholds, Malaysia's two corrections |
| `reference-code/CrescentRules.swift.txt` | Diyanet eras (`DiyanetEra`, `diyanetStartsTomorrow`, `diyanetCorrections`), Umm al-Qura rule + correction, MABIMS functions, the 2,517-row American west-coast table | the coast table is data (Natural Earth 1:10m, public domain); `data/american_west_coast_generator.py` regenerates it |
| `reference-code/CrescentAstronomy.swift.txt`, `LunarSeriesTables.swift.txt` | only if the port's own engine does not reproduce `data/crescent_astronomy_fixture.csv` | the spec's §3 lists the months decided by hundredths of a degree |
| `reference-tests/*.swift.txt` | the tests that define "done" | 707/707, 131/131, 98/98, 25/25; the announced-date rates as a non-asserting report |

The `.swift.txt` extension is only so that nothing under `Docs/` is picked up by tooling; rename when porting.

## Data

- `data/crescent_official_dates.csv` — published first days: Diyanet AH 1398-12 … 1457-11 (Diyanet's own tables and
  maps), Umm al-Qura AH 1440–1450 (official 1420–1450 table), Malaysia, Indonesia, Singapore, Egypt (Dar al-Ifta
  announcements; not to be shipped as a calendar, see spec §8). Dates are published facts; sources in the `source` column.
- `data/announced_dates_2009_2026.csv` — 1,766 announced first days of Ramadan, Shawwal and Dhu al-Hijjah by country,
  AH 1429–1448, from the moonsighting.com compilation (`page` and `basis` columns; `subgroup=yes` marks sub-community
  rows; Dhu al-Hijjah `first_day` is the listed Eid al-Adha date minus 9). Use for the measurement report, not as an
  assertion: the compilation has a few percent of errors (Türkiye 9/10 against Diyanet's list).
- `data/crescent_astronomy_fixture.csv` — our engine's values for every decision evening (conjunction, sunset, moonset,
  altitudes, elongations, Odeh value, Wellington dawn, best mainland point) and Diyanet's printed map times against
  ours. Match these before matching the dates.

## Work items in this repository (from the proposal, §3)

1. Route `.islamic` without a region to the Umm al-Qura table already in the port; record the divergence from ICU4C.
2. A `region` on `Calendar` (sketch in the proposal §5), part of equality, hashing and `Codable`, with a defined fallback.
3. Formatting: `ICUDateFormatter` must take the Hijri fields from the Swift calendar for `.islamic`; today
   `udat_formatForFields` has ICU compute them from the absolute time.
4. Port the rules, corrections, region table and fixtures; remove `VisibilityRule.egypt`.

## What is not here

The copyrighted sources (Diyanet's maps and lists, JAKIM's takwim PDFs, the moonsighting.com pages, the Keleş article)
stay on the research machine under `Research/crescent/`. Only dates and measurements travel.
