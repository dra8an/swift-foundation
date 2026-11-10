# Crescent rules checked against official dates

Measured 2026-11-06 on branch `islamic-crescent`. Official dates come from the research in swift-foundation
`Docs/TEMP_Islamic_References/` (branch `port/islamic-family`), copied to
`Tests/CalendarAstronomicalTests/crescent_official_dates.csv`.

## Method

For every pair of consecutive official month starts P and S, the rule looks at the evening of day 29
(P + 28) and predicts a 29-day month (new month tomorrow) or a 30-day month. The prediction is compared with
S − P. Each decision is scored on its own, so one wrong call cannot shift the months after it.

Code: `Sources/AstronomicalEngine/CrescentAstronomy.swift` (moon latitude, distance, altitude, parallax,
moonset, elongation; ported from ICU4X / Calendrical Calculations and checked against their reference values and
Meeus Example 47.a), `Sources/CalendarAstronomical/CrescentRules.swift` (the rules),
`Tests/CalendarAstronomicalTests/CrescentRulesComparison.swift` (this measurement; run with
`swift test --filter CrescentRulesComparison`).

## Results

| Rule | Best reading | Match | Remaining misses |
|---|---|---|---|
| Umm al-Qura | conjunction before sunset + moon sets after the sun, at the Kaaba (2 or 3 conditions give the same result) | **130/131 (99.2%)** | AH 1446-6: moon and sun set within the same minute (lag ≈ 0), a razor-edge case |
| Diyanet | **no latitude limit** (moon must be past conjunction), **topocentric altitude with refraction (apparent; any scale 0.75–1.0)**, **geocentric elongation**, no search grid (sunset line at 00 UTC; exact American west coast), Americas + Wellington exception on (round 3) | **212/214 (99.1%)** | evenings **2023-05-19** and **2032-03-11**: Diyanet's own maps show mainland Alaska inside the visibility zone on both, yet the month did not start, so its stated rule does not decide them (round 3). On the 3° grid the misses were 2021-06-10 and 2023-05-19 instead |
| Malaysia (MABIMS) | official reference points (Tanjung Chinchin to AH 1443, Pulau Perak from 1444); 1992 criterion until the end of 2021 (JAKIM's 2021 takwim still used it), 2021 criterion from the 2022 edition; apparent altitude, elongation between the refracted positions (round 2) | **96/98 (98.0%)** | AH 1443-10: documented sighting override (Labuan); AH 1449-8 (evening 2027-12-28): razor-edge, 0.015° from AH 1444-5 in the opposite direction. Round 1 reading (airless elongation, switch at 1443) gave 95/98 |
| Indonesia (MABIMS) | Banda Aceh, **geocentric** altitude, geocentric elongation | **25/25** | with the regulation's topocentric altitude: 23/25, both misses are 2027 calendar entries where only geocentric altitude reaches 3° |
| Egypt | conjunction before sunset + moonset ≥ 5 min after sunset, at **Cairo** | **83/92 (90.2%)**; Dhu al-Hijjah 8/8 | all 9 misses go one way: the rule allows the month, Egypt waited a day (young moons, 4.5–12.6 h, presumably not sighted). Egypt never started a month the rule forbids |
| Singapore | Tuas | not measured | the 9 official dates are not consecutive months |

## Answers for the code (values the other agent asked about)

| Question | Research said | Measurement says |
|---|---|---|
| Diyanet ±60° latitude limit | not in any official text | **not needed** (round 3): the two months it fixed (AH 1441-2, 1442-3) passed on the grid only through the *old, waning* moon at polar sunsets before the conjunction. With a past-conjunction check the limit changes nothing |
| Diyanet altitude geocentric or topocentric | not stated officially | **topocentric**: Diyanet's Ramadan 1447 diagrams match our topocentric altitude (23°51′ / 24°52′ exactly on Feb 19), geocentric is 53′ too high. Near the horizon its values sit ~26′ above airless topocentric, i.e. with refraction (~0.8× Saemundsson). Apparent altitude is what fixes 2021 (round 3) |
| Diyanet elongation geocentric or topocentric | not stated officially | **geocentric**: reproduces Diyanet's first-visibility time on all six mapped evenings (0–47 s before its printed minute); topocentric would be 1–1.5 h later (round 3) |
| Diyanet Americas + Wellington exception | official | **needed**: +14 months; without it ≈ 91% |
| MABIMS Banda Aceh for all four | wrong for Malaysia, Singapore, Brunei | Malaysia at Banda Aceh: 85–89%; at its own reference points: 94–97%. Use per-country places |
| MABIMS definitions, Malaysia | eKITAB: apparent altitude, topocentric airless elongation | apparent altitude confirmed; for elongation the refracted positions fit better (96/98 vs 95/98, round 2) |
| MABIMS definitions, Indonesia | PMA 1/2026: topocentric altitude, geocentric elongation | the published 2027 calendar fits **geocentric** altitude (25/25 vs 23/25) |
| Egypt 15 h 40 min filter (fatwa 3420) | official text | does **not** describe the announced dates: 67% match, 29 months started with the moon 3–15 h past conjunction |
| Egypt: conjunction before sunset + moonset ≥ 5 min | was the code's guess | **best fit**: 90%, and never wrong in the impossible direction |
| Egypt place: Cairo or the 10 sites | committees across Egypt | Cairo fits slightly better (83 vs 82) |
| Umm al-Qura 2 vs 3 conditions | printed table has 3 | no difference in AH 1440–1450 |

## Caveats

- These are fits to the announced dates, not to the authorities' code. Months decided by sighting (Egypt, Brunei,
  some Malaysia and Indonesia months) cannot be predicted by any rule.
- Razor-edge cases (values within about 0.05° of a threshold, or a moonset lag near 0) depend on small definition
  differences: refraction model, elevation, the 1-arcsecond ΔT difference from ICU4X.
- The American mainland for the Diyanet exception is the western coastline from Natural Earth 1:10m land v5.1.2 (public
  domain), one value per whole degree of latitude, interpolated; a point east of the coast counts as mainland.
- The astronomy here is Calendrical Calculations / Meeus (arc-second level for these dates), not the code in
  swift-foundation; marginal months can come out differently there.
- Egypt sighting-site coordinates are approximate town coordinates; no official coordinates exist.

## Round 2 experiments (2026-11-06, after the round-2 research)

| Hypothesis | Result |
|---|---|
| Diyanet: American mainland from Natural Earth's coastline instead of latitude/longitude boxes | **adopted**: 210 → 212/214 |
| Diyanet: the ±60° limit also applies to the America exception | rejected: fixes nothing, breaks AH 1452-1 (2030, where Diyanet's map counts Bristol Bay) |
| Diyanet: finer search grid (1° instead of 3°) | no effect (212/214 either way) |
| Diyanet: apparent altitude (with refraction) | ties topocentric; geocentric is worse (it fixes 2021 but breaks 2026, which Diyanet officially rejected as ocean-only, and 2033) |
| Malaysia: JAKIM's 2021 takwim was computed with the 1992 criterion; the 2021 criterion applies from the 2022 edition | **adopted** (data provenance, not a fit) |
| Malaysia: elongation between the refracted (apparent) positions of moon and sun | **adopted**: with the line above, 95 → 96/98 |
| Malaysia: values at the whole minute of sunset (JUPEM lists hh:mm) | rejected: worse (93-95/98) |
| Malaysia: Almanak Falak Syarie refraction (0.945 × Saemundsson on the geocentric altitude) | no effect on the score |
| Malaysia: JUPEM's printed elongations (KL 2020-11-15, PICC 2022-11-24) | match neither standard definition: about 30% of the way from refracted to airless. A blend fitted to them scores the same 96/98; not recommended (two calibration points) |

Remaining misses after round 2: Diyanet 2 (2021-06-10 and 2023-05-19: Diyanet is more lenient than us at the margin in
2021 and stricter in 2023, so no single parameter explains both; likely how its visibility line is drawn from 6-hourly
points), Malaysia 2 (AH 1443-10, a documented sighting override; AH 1449-8, evening 2027-12-28, 0.015° from AH 1444-5
in the opposite direction), Umm al-Qura 1 (a 7-second tie), Egypt 9 (sighting decisions).

## Round 3: Diyanet calibration (2026-11-06)

Temporary probe: `Tests/CalendarAstronomicalTests/CrescentDiyanetProbe.swift`
(`COAST_CSV=Research/crescent/naturalearth/coast_fine.csv swift test --filter CrescentDiyanetProbe`; the
`firstVisibility` sub-test takes ~5.5 min, the rest seconds).

**Diyanet's own numbers reproduced.**

| Check (official source: Diyanet's maps and Ramadan 1447 diagrams) | Result |
|---|---|
| Conjunction, six mapped evenings | ours within one minute on all six (2033: 11:36:23 vs 11:37) |
| First visibility (earliest sunset anywhere with altitude ≥ 5°, elongation ≥ 8°) | with **geocentric elongation**: 03:59:26 / 06:53:36 / 03:42:04 / 07:07:41 / 04:59:13 / 00:02:27 against Diyanet's 04:00 / 06:54 / 03:42 / 07:08 / 05:00 / 00:03. The time is set by the elongation alone, so altitude and sunset definition do not move it. Topocentric elongation: 1–1.5 h later on every evening |
| Moonset lag T at Ankara and Mecca, Feb 17–19 2026 | matches our sunset (upper limb at −50′) and moonset (topocentric upper limb at −34′) to the minute: 70/70, 59/59, 137/137.5, 115/114.9 |
| Moon angle A at sunset, same diagrams | topocentric: exact on Feb 19 (23°51′, 24°52′), 3′ low on Feb 18, 26–27′ low on Feb 17 near the horizon, so Diyanet includes refraction somewhat weaker than Saemundsson (≈0.8×). Geocentric is 53′ too high |

So Diyanet = **topocentric altitude (with refraction) + geocentric elongation**, at a standard sunset. This also
explains the KHGT paper's finding that Diyanet's 03:42 equals a "geocentric" computation: first visibility depends
only on elongation.

**The land test.** The America mask is now the Natural Earth mainland polygon (land intervals per whole degree of
latitude, embedded in `CrescentRules.swift`) instead of "east of the west coast". It changes nothing, and that was
predictable: along a latitude the westernmost mainland point has the latest sunset and the best moon, so inlets such
as Cook Inlet (east of it) never decide. The handoff's expectation that it would flip 2023 was wrong.

**Exact coast instead of the 3° grid.** Evaluating the America exception at the westernmost mainland point every
0.05° of latitude (margin = min(altitude − 5°, elongation − 8°)):

| Evening | Diyanet | Topocentric | Apparent |
|---|---|---|---|
| 2021-06-10 | started | −0.023 (miss) | **+0.012** (Oregon 44.6° N) — refraction factor ≥ 0.71 suffices |
| 2023-05-19 | no | +0.098 (miss) | +0.222 (miss; Kuskokwim Bay 58.7° N) |
| 2026-02-17 | no | −0.208 | −0.042 |
| 2030-05-02 | started | +0.057 | +0.083 |
| 2032-03-11 | no | +0.030 (**miss**, Cape Prince of Wales 65.7° N; the 3° grid never hit it) | +0.030 (miss) |
| 2033-05-28 | no | −0.164 | −0.012 |

Confirmed by a full scored run after the rule code was changed (below): 212/214, misses 2023-05-19 and 2032-03-11.

**Why 2023 and 2032 are not ours to fix.** Diyanet's maps (local copies) shade mainland Alaska inside the visibility
zone on both evenings, and the 2023 and 2030 maps look alike (Alaska Peninsula and Bristol Bay shaded), yet 2030
started and 2023 did not. The Wellington-dawn condition does not separate them either: 2023 has 117 min between
conjunction and −18° dawn; 2032 has 16 min and did not start, while 2031-01-24 has 24 min and did. Separating
2031 from 2032 would need a dawn angle of about 21°, which nobody uses, and still leaves 2023. So on these two
evenings Diyanet's decision follows something outside its published rule (not found in the round-1/2 research).

| Round 3 hypothesis | Result |
|---|---|
| Land test with the real mainland polygon | no effect (reason above); kept as the more correct definition |
| Elongation geocentric vs topocentric (Diyanet's first-visibility times) | **geocentric**, confirmed to the minute |
| Altitude geocentric / topocentric / apparent (Diyanet's diagrams) | **topocentric with refraction** |
| Exact coast instead of grid | turns 2021 into a hit with apparent altitude, exposes 2032 |
| A different Wellington dawn angle | rejected: 2031 vs 2032 would need ~21°, and 2023 stays unexplained |

### Round 3, continued: rule code without a grid

`CrescentRules.diyanet(_:refractionScale:)` no longer uses a search grid:
- **Main test**: along a latitude the moon at sunset is better the later the sunset, so the best place is where the sun
  sets at exactly 00:00 UTC. The test evaluates the moon at 00:00 UTC along that sunset line (every 0.1° of latitude;
  the longitude comes from the sun's hour angle at −50′).
- **America exception**: the westernmost mainland point every 0.05° of latitude (table in the code, from
  `coast_fine.py`). The whole-degree polygon table from earlier in round 3 was removed.
- **Past-conjunction check**: the moment must be after this lunation's conjunction (and less than 3 days after).

| Diyanet reading (full run, 214 months) | Score | Misses |
|---|---|---|
| apparent altitude, no latitude limit | **212/214** | 2023-05-19 (AH 1444-11), 2032-03-11 (AH 1453-12) |
| same, ±60° on the main test | 212/214 | same |
| same, ±60° on both tests | 212/214 | 2023-05-19, 2030-05-02 |
| topocentric (no refraction) | 211/214 | + 2021-06-10 |
| geocentric | 209/214 | + 2022-07-28, 2026-02-17, 2033-05-28 |
| apparent, refraction × 0.5 / 0.6 / 0.7 | 211/214 | + 2021-06-10 (needs ≥ 0.71) |
| apparent, refraction × 0.75 … 1.0 | **212/214** | 2023, 2032 |
| apparent, refraction × 1.1 / 1.2 | 211/214 | + 2033-05-28 |

Runtime of the Diyanet measurement: 32 s (was ~80 s on the 3° grid).

### The two remaining misses (2023-05-19, 2032-03-11)

| Hypothesis | Result |
|---|---|
| A different New Zealand place for the dawn test (Wellington, Auckland, Gisborne, East Cape, Chatham Is, Cape Reinga; −18°) | rejected: at every mainland place 2031-02-21 (started) and 2032-03-11 (not) are both positive, 2032 only 8–16 min less; the Chatham Islands make both negative. 2023 has 85–118 min everywhere |
| Diyanet's maps print anything else | no: the full 2023 and 2032 maps give only conjunction, first visibility and day 1 (all matching ours to the minute) |
| Hajj months follow Saudi (Umm al-Qura) | Diyanet and Umm al-Qura official dates agree on all 22 Zilkade/Zilhicce starts in AH 1440–1450 (they differ in 8 of 132 months overall). Scored with our Umm al-Qura rule for those months: **Zilhicce only → 213/214** (fixes 2032; 2023 remains); Zilkade + Zilhicce → 213/214 but breaks AH 1452-11 (2031-02-22, where Diyanet followed its own rule against Saudi). Only three Hajj-month decisions in 1440–1457 differ between the two rules; Diyanet sided with Saudi twice (2023, 2032) and with its own rule once (2031). Not a consistent rule, and 2032 is a single point |

Conclusion: the astronomy is settled (every convention pinned to Diyanet's own numbers, no unofficial parameters left).
2023 and 2032 are decisions that Diyanet's published rule does not reproduce under any reading we can find, and the
local data cannot tell why. Settling them needs Diyanet's own statements (web research).

The temporary probe `CrescentDiyanetProbe.swift` holds the round-3 calibration (first visibility, diagrams, exact coast,
exception months, high-latitude check, New Zealand places). `CrescentRulesComparison` gained `diyanetRefractionScale`
and `diyanetHajjMonths`.

### All Diyanet maps against our times (233 local maps, AH 1438–1457)

Header text read by OCR (two independent OCR passes × Turkish and English halves, majority of the four readings;
`Research/crescent/round3-raw/maps/`), compared with our conjunction and our exact first visibility (earliest moment
the sunset line has geocentric elongation ≥ 8° and altitude ≥ 5°, past conjunction; probe `CrescentDiyanetMaps`).

| Check | Result |
|---|---|
| Conjunction | 218 read; every difference beyond a minute was checked: OCR misreads (exact 2-hour or wrong-day offsets; Diyanet's font prints 9 like "?") except one. **All others agree within a minute**, spread evenly over about −45 s … +15 s (ours minus printed): Diyanet's times are ours **+ ~15 s, rounded to the nearest minute** |
| The one real outlier | Şaban 1449: printed 27 Dec 2027 **20:16**, ours 20:12:18, Moshier 20:12:21. Diyanet's own first visibility for that month (12:59) matches ours (12:58:54), so the printed conjunction is a slip on that map |
| First visibility | 217 read; same picture (all within a minute after OCR misreads are set aside; same ~15 s offset). In every month it is set by the elongation reaching 8°, never by the altitude, so it cannot test refraction further |
| First day of the month | the 200 printed first days inside our data's range all equal the official dates in `crescent_official_dates.csv` (3 apparent mismatches were "29" read as "2") |

So Diyanet's conjunction, first visibility and elongation definition are confirmed for every month on its maps, not
just the six from round 2.

### Web research on the two remaining misses (2026-11-06)

Question: why did Diyanet not start Zilkade 1444 on 20 May 2023 and Zilhicce 1453 on 12 March 2032, when its published
rule (and its own maps) say it should? Provenance: official = Diyanet / Din İşleri Yüksek Kurulu; other = everything else.

| Finding | Source | Provenance |
|---|---|---|
| 2023 was not a live decision: Diyanet's 2023 list, published 2 Jan 2023, already gives "01 ZİLKADE 1444 21 MAYIS-2023 PAZAR". Diyanet's own pre-computation said "no month" on 19 May | vakithesaplama.diyanet.gov.tr/icerik.php?icerik=150; Hürriyet 2 Jan 2023 (hurriyet.com.tr/bilgi/…-42197342) | official; other (copy) |
| 1978 decisions: 8° elongation after conjunction, 5° altitude at sunset, anywhere on Earth ("belli bir yer şart değildir"); decision 7 only says maps for Ramazan, Şevval and Zilhicce will be prepared. No 00:00 UTC, America or New Zealand clause (those come from 2016), no Zilhicce/Arafat/Mecca rule (decision 4 only wants the announcement made by a future Mecca observatory) | vakithesaplama.diyanet.gov.tr/hilal_toplantisi.php | official |
| 2016 criteria, word for word as we implement them (00:00 UT/GMT; after it: 1978 criterion met somewhere + conjunction before fajr in New Zealand + visibility on the American mainland) | S. Anwar, "Tindak lanjut Kalender Hijriah Global Turki 2016", tarjih.or.id PDF, p. 16, citing the congress scientific committee's working paper p. 9 | other |
| Wellington is the official New Zealand place ("Yeni Zelanda/Wellington'daki imsak") | kurul.diyanet.gov.tr Ramazan 1447 statement (also diyanetamerica.org English PDF) | official |
| Diyanet's method pages (Tanımlar, Hicri Takvim Farkı, Yeni Ay Tanım Farkı, Şemalar) give 5°/8° and "visible anywhere"; no mention of Saudi Arabia, Umm al-Qura, Arafat, or any exception | vakithesaplama.diyanet.gov.tr tanim.php, hicri_farki.php, ay_tanim.php, icerik.php?icerik=84 | official |
| Zilhicce is now confirmed by sighting: 2025 "Yurtiçinde 41, yurtdışında 54 şehirde … ilk hilal Ankara ilimizde gözlemlendi", "28 Mayıs 2025 … Zilhicce ayının 1. günü olduğu teyit edilmiştir"; 2026: seen in 41 Turkish cities, 18 May accepted, Saudi Arabia mentioned only as "also seen there". Neither says Zilhicce follows Saudi Arabia | kurul.diyanet.gov.tr/tr/duyuru/zilhicce-hilali-goruldu/019716e6-…; diyanethaber.com.tr (18 May 2026) | official |
| The 2016 congress decision text (Sabah's copy) has no Zilhicce/Arafat/Hajj rule; Arafat appears only as the reason a single calendar is needed | sabah.com.tr 30 May 2016 | other |
| False lead: "Ramadan, Shawwal and Dhu al-Hijjah still need sighting" refers to an OIC foreign-ministers' decision (1999), not the 2016 congress; the Keleş article's Ramazan/Şevval/Zilhicce sentence describes Saudi Umm al-Qura practice | tarjih.or.id PDF p. 17; Keleş, İslam Hukuku Araştırmaları Dergisi 28 (2016) | other |

Not found: any Diyanet statement on Zilkade 1444 or on Zilhicce 1453; any Diyanet rule tying Zilhicce or Arafat to
Saudi Arabia; Diyanet's land test for the Americas (which American land counts). Looked: the pages above, searches
(Turkish and English) for Zilkade 1444 hilal açıklama, Kurul Zilhicce announcements, "Hicri Takvim Farkı", the 2016
criteria text. Unavailable: muftisays.com blog (404), aa.com.tr (DNS failure), the Arabic congress book (fetva .aspx,
robots.txt), dini_gunler.php (needs a form).

**Conclusion.** Under the published rule, with every convention pinned to Diyanet's own numbers, Diyanet's own
calculation and maps show the month should have started on both evenings, and its pre-published calendars say it did
not. No published Diyanet text explains this. The two months stay as documented exceptions (2 of 214); there is no
basis in the sources for a rule that would reproduce them.

### Diyanet's whole published list, AH 1318–1444 (1900–2022)

Source (official): Diyanet's Hijri-to-Gregorian tables, vakithesaplama.diyanet.gov.tr/icerik.php?icerik=73, 74, 75, 76, 77,
78, 117, 123, 105, 124, 125, 126, 127, 128 (linked from hicriden_miladiye.php). 1,518 month starts transcribed
(local: `Research/crescent/diyanet-history/diyanet_1318_1444.txt`). Checks: every gap 29 or 30 days, no month missing;
the 54 months overlapping `crescent_official_dates.csv` are identical; two printed weekdays in AH 1418 are wrong (the
dates are consistent). Note: the list we used before started at AH 1440, but `icerik=128` already covered AH 1437–1439.

Scored with `CrescentRulesComparison/diyanetHistory` (`DIYANET_HISTORY=…`, ~7 min). Readings of the rule: **2016**
(as above); **1978-A** any sunset of the evening anywhere, ocean included; **1978-B** only sunsets before 00:00 UTC;
**1978-C** before 00:00 UTC or the American mainland, no New Zealand clause. All with apparent altitude, geocentric
elongation, no grid.

| Period | 2016 | 1978-A | 1978-B | 1978-C |
|---|---|---|---|---|
| AH 1318–1398 (1900–1978) | 617/971 | 523/971 | 687/971 (71%) | 617/971 |
| AH 1399–1437 (1978–2016) | 433/468 | 354/468 | **453/468 (96.8%)** | 428/468 |
| AH 1438–1444 (2016–2022) | **77/78** | 64/78 | 73/78 | 77/78 |

What Diyanet did, period by period (from the per-decade counts and the per-month detail, probes
`CrescentDiyanetTransition` and `CrescentDiyanetCutoff`):

| Period | Practice that reproduces the list | Fit | Exceptions |
|---|---|---|---|
| before AH 1399 (to Nov 1978) | none of these readings (best 71%); a different method before the 1978 conference | — | not modelled |
| AH 1399–1429 (Dec 1978–Dec 2008) | 1978 criterion **only at sunsets before 00:00 UTC**, no exception after midnight | 369/372 | AH 1399-9, 1401-8, 1411-5: the rule allows the month, Diyanet waited a day |
| AH 1430–1435 (Jan 2009–2014) | before 00:00 UTC, **or first visibility anywhere (ocean included) by about 05:15 UTC** (started: first visibility 0.2–5.2 h after 00:00 UTC; not started: 5.5 h or later) | 44/46 of the decisions that hinge on after-midnight visibility | AH 1433-10 (Şevval 1433, +3.8 h) and AH 1434-11 (Zilkade 1434, +1.9 h) not started |
| AH 1436–1437 (Oct 2014–Sep 2016) | **no exception**: only before 00:00 UTC (AH 1436-4 not started although the moon passes +1.28° on the Alaska coast) | all | — |
| AH 1438–1457 (Oct 2016–2035) | **2016 rule** (00:00 UTC + America mainland + Wellington) | 77/78 (2016–2022) and 212/214 (2018–2035) | AH 1438-3 (2016-11-29, Alaska +0.153°, not started), 2023-05-19, 2032-03-11 |

So the 2016 rule matches Diyanet from its introduction onwards; earlier, Diyanet used a stricter (1978–2008, 2014–2016)
or a different (2009–2014) treatment of after-midnight visibility. Combined over AH 1399–1457 with the right rule
per period, 698 of 706 decisions are reproduced (summed from the period results above, not one combined run); the
8 exceptions are listed in the table.

### Chasing the last 8 misses, AH 1399–1457 (2026-11-06, scope agreed with the user: 1978 onwards only)

Before AH 1399 is out of scope: Ottoman / early-Republic practice, method undocumented. The data shows the 1978
criterion taking effect exactly at AH 1399 (1 Dec 1978, the day after the conference): 1–4 misses every year before,
0–1 after.

Status: **699/707** decisions reproduced with the period rules (probe `CrescentDiyanetLand`, one run). All 8 misses are
"our rule says start, Diyanet waited a day"; there is no case since 1978 of Diyanet starting a month the rule forbids.

| Miss | Best margin | Notes |
|---|---|---|
| AH 1399-9 (Ramazan 1979) | +2.5° (main test) | not a margin case; first Ramazan after the conference; probably a discretionary decision |
| AH 1401-8 (1981) | +0.118° | |
| AH 1411-5 (1990) | +0.006° | razor-edge |
| AH 1433-10 (Şevval 2012), 1434-11 (2013) | first visibility +3.8 h / +1.9 h | indistinguishable from months that started (e.g. AH 1435-01) on every quantity tried; "lived" months, probably discretionary |
| AH 1438-3 (2016-11-29) | +0.153° Alaska coast | |
| AH 1444-11 (2023-05-19), 1453-12 (2032-03-11) | +0.10° / +0.03° Alaska | 2032 is the only month with conjunction under 24 min before Wellington dawn (16 min; smallest started 24 min, 2031-02) |

Hypotheses tested and rejected (do not retry):
- Land required for the main test (Natural Earth, islands included): fixes none, breaks AH 1414-2, 1417-4, 1437-10, which
  start only via ocean points at 60–71° S. The main test counts ocean everywhere, no latitude limit.
- Diyanet evaluating on a grid (0.5°, 1°, 2°, 2.5°, 3°, 5°, 10°; aligned and half-offset): best 700/707 but only by
  trading misses (breaks 1439-3, 1442-11, 1452-1); none fixes 1399-9, 1401-8, 1433-10, 1434-11.
- A single extra condition (13 tried: conjunction time, first-visibility time, moon age, Wellington margin, apparent
  altitude / elongation / moonset lag at Ankara, Mecca, Istanbul): best rejects 3 of 8 while keeping all 332 starts.
- AH 1430–1435: no condition on the Americas (altitude, elongation, lag, margin) separates the two misses from starts.

Open lead: **Diyanet's own Wellington imsak.** If its published imsak for Wellington runs 16–24 min earlier than our
−18° dawn, 2032 is explained and nothing else breaks. namazvakitleri.diyanet.gov.tr lists "Yeni Zelanda" but its city
picker is JavaScript; the fetch tool could not reach the Wellington page (needs a browser or the user).

Local data: `Research/crescent/naturalearth/land_rows.py` → `land_rows.txt` (all land, 0.25° rows). Probes:
`CrescentDiyanetLand`, `CrescentDiyanetGrid`, `CrescentDiyanetFeatures`, `CrescentDiyanetEraB` (env vars in each).

### Round 4 (2026-11-06, later session): calendar-year batches, the maps themselves, and what is left

**Period boundaries are calendar years, not dates.** Diyanet computes a Gregorian year at a time. Assigning each
decision to the year of the month's first day (A ≤ 2008, B 2009–2013 with the ~05:15 UTC cut-off, C 2014–2016 no
exception, D 2017+ the 2016 rule) gives **700/707** (probe `CrescentDiyanetBatches`), and explains AH 1438-3
(1 Dec 2016): the 2016 calendar was computed before the May 2016 congress. Documented: Keleş (İslam Hukuku
Araştırmaları Dergisi 28, pp. 371–372) reads the Rebiülevvel 1439 map from Diyanet's *2014* publication ("Kameri Ay
Başları Hesap ve Haritaları 2016–2022, Türkiye 2014"): first visibility 19 Nov 2017 01:31 UTC in western America,
"since it passes 24:00 Greenwich it is counted as the next day", month "unified on 20 November". The current official
table says 19 November: Diyanet recomputed 2017 onward after the congress and left 2016 as printed. The same logic
applies to AH 1399-9 (Ramazan 1979): the 1979 calendar was printed before the 27–30 Nov 1978 conference.

**The remaining seven** (all "rule says start, Diyanet waited"):

| Miss | Status |
|---|---|
| AH 1399-9 (Jul 1979), +2.5° | 1979 calendar printed before the conference: pre-conference method (undocumented) |
| AH 1401-8 (Jun 1981), 1411-5 (Nov 1990) | elongation reaches 8° at 23:46 and 23:59 UTC: 14 min and 1 min from the cut-off, 1980s ephemerides |
| AH 1433-10 (Aug 2012), 1434-11 (Sep 2013) | lived months; the B rule is inferred from 12 starts; no quantity separates these two |
| AH 1444-11 (2023-05-19), 1453-12 (2032-03-11) | precomputed; not separable from 2030-05-02 (started) by anything below |

**Hypotheses tested and rejected for 2023/2032 (do not retry):**
- A list of places (city list, 70 American cities incl. 28 in Alaska; probe `CrescentDiyanetCities`): in Nov 2017
  (started) the only mainland place that passes is Cold Bay (+0.04°); Cold Bay also passes in May 2023 (+0.06°).
  No static set of places, polygon or latitude limit can start 2030 (best +0.08° at 61–63° N) and refuse 2023
  (+0.22° at 58.65° N, +0.06° at 55.2° N): at the same places 2023 has the better numbers.
- The exception measured with the ecliptic-longitude difference instead of the true elongation
  (`CrescentDiyanetDeltaLambda`): 44/52 against 50/52; fixes 2032, breaks six starts.
- Diyanet's Wellington imsak: by reasoning, not measurement. 2032 needs an imsak ≥ 17 min *earlier* than the −18°
  dawn; Diyanet's imsak is the later one (18°, no temkin), and every DST-confusion variant also passes 2032.
- The drawn maps. Registered six of Diyanet's maps to lat/lon (Mercator; 94–98 % land agreement; `round3-raw/zones/`)
  and overlaid our zone. Findings: (1) where the boundary is altitude-bound (southern edge of the Asia–Africa zone)
  Diyanet's curve and ours coincide; (2) Diyanet's first-visibility markers (stars/dots) lie exactly on our
  elongation-bound boundary; (3) Diyanet's *Pacific/America* zone is a lenient drawing convention: its eastern edge
  runs up to 20° of longitude (over an hour of sunset) east of ours, in Nov 2017 and Jun 2021 over the whole US west
  coast and Mexico, in Feb 2026 touching only the tip of the Alaska Peninsula ("line over the ocean"); (4) in May 2023
  Diyanet's own zone contains *more* mainland Alaska (Alaska Peninsula, Bristol Bay, Kuskokwim, up to Cook Inlet)
  than in May 2030. So no rule of the form "zone (theirs or ours) touches the mainland" can give 2030 yes and 2023 no.

**The mechanism behind the seven (not "thin air").** Diyanet computes in batches; its map files come in three
series: 2017–2022, 2023–2027 (named by month within the Gregorian year), 2028–2035. Keleş proves the batch mechanism
for 2016/2017 (see above). Under the one strict criterion, the decisions that depend on Alaska alone are:

| Batch | Alaska-only decisions | Outcome |
|---|---|---|
| 2017–2022 | Nov 2017 (peninsula tip +0.09°), May 2022 (Bristol Bay) | started |
| 2023–2027 | May 2023 (peninsula, Bristol Bay, Kuskokwim, Hooper Bay: +0.05 … +0.22°) | refused |
| 2028–2035 | Feb 2028, Feb 2029, May 2030 (Bering coast 61–63° N, +0.08°), Feb 2031, Feb 2035 | started |
| 2028–2035 | Mar 2032 (Seward Peninsula tip only, +0.03° = 3.6 min of sunset) | refused |

June 2021 started on the Oregon coast at +0.012°, so Diyanet's effective threshold is within ~0.01° of ours; no
uniform threshold can refuse May 2023. Reading: **the 2023–2027 run had no Alaska in its American-mainland
definition** (one data point: May 2023 is that batch's only Alaska-only decision). March 2032 is a 3.6-minute case at
one extreme point (the tip in or out of the 2028–2035 run's list, or a few minutes in its sunset), the same class as
Jun 1981 (14 min) and Nov 1990 (1 min). Ramazan 1979 is the pre-conference 1979 calendar. Aug 2012 and Sep 2013 remain
unexplained: the 2009–2013 practice is inferred from 12 starts and those two lived months sit inside their range on
every quantity tried (first-visibility time, Wellington, America margins, conjunction time, first-visibility place).
What would settle the batch readings: Diyanet's "Kameri Ay Başları Hesap ve Haritaları" publication for each series
(computation date, place list); not found online.

**Conclusion.** The astronomy and the published rule are implemented correctly for every period since Dec 1978 and
reproduce 700 of 707 decisions. The seven remaining dates cannot be derived from any reading of Diyanet's rule or from
Diyanet's own maps; two of them (2023, 2032) contradict Diyanet's own drawings. For the port they are a small override
table, not a formula. Sources that could still settle 2023/2032: Diyanet's computation itself (not published) or a
Diyanet statement for those months (not found).

### Round 5 (2026-11-06, late): the 2009–2013 rule from Diyanet's own maps

Diyanet's visibility maps exist from AH 1430 Rebiülevvel (Feb 2009) on; all 93 for 1430–1437 were fetched and read.
Measured on them and on our strict zone: in 2009–2013 an after-midnight crescent was accepted iff the day-29 zone west of
30° W reached the northern hemisphere's tropics (strict-zone northern limit ≥ 16.5° N for every start; ≤ 2.5° N or
no zone for every refusal; threshold 10° N). No land test is involved; the 2016 congress replaced this with the
American-mainland rule (the latitude rule would wrongly start Mar 2018, Oct 2022, Apr 2025 and others). 2014–2016: no
exception, confirmed by the Sep 2015 and Sep 2016 maps (zone over South America, refused). With this, 702/707; the five
left are 1979-07, 1981-06, 1990-11, 2023-05, 2032-03 (status in Round 4). Data: `round3-raw/pre2016/`,
`round3-raw/north_limits.txt`.

### Round 6 (2026-11-09): the five remaining dates, closed by measurement

**One scored run** (probe `CrescentDiyanetFinalScore`, `round6-raw/final_score.txt`) with the period rules: A (first day
in calendar year ≤ 2008) criterion met at a sunset before 00:00 UTC anywhere; B (2009–2013) also a start if, after
00:00 UTC, the criterion is met at the sunset just east of the date line at some latitude ≥ 10° N (the Round 5
latitude rule); C (2014–2016) no exception; D (2017+) the 2016 rule. **702/707: A 370/373, B 61/61, C 38/38,
D 233/235.** Misses: AH 1399-9 (26 Jul 1979), 1401-8 (4 Jun 1981), 1411-5 (19 Nov 1990), 1444-11 (21 May 2023),
1453-12 (13 Mar 2032); all five "rule says 29 days, Diyanet printed 30".

**Tested today and rejected (do not retry):**

1. *Period A, elongation definition* (`CrescentDiyanetElongationA`, `ela_periodA.txt`): at the 00:00 UTC sunset line, with
   the altitude part shared, true geocentric elongation 370/373; ecliptic-longitude difference 337; right-ascension
   difference 341; topocentric 343. Period A has starts at +0.068° (AH 1410-5, Dec 1989), +0.069° (1402-12, Oct 1982)
   and +0.114° (1414-2, Jul 1993) against refusals at +0.118° (1401-8) and +0.006° (1411-5): no threshold on the
   elongation, no latitude band (1401-8 passes at 47.8° S … 14.8° N; 1402-12 at 19.9° S … 49.2° N; 1410-5 at
   65.5° S … 8.1° S) and no altitude (best apparent altitude +1.41° against +1.41 … +1.46° for starts) separates them
   (`CrescentDiyanetElongationBand`, `band_profile.txt`).
2. *Coastline resolution for the 2016 exception* (`CrescentDiyanetCoastResolution`, `coast_resolution.txt`): rows every
   0.05° (the rule), 0.25°, 0.5° or 1°, longitudes exact or snapped east / to the nearest step: all ten variants 233/235.
   A 1° coastline refuses Mar 2032 (Seward Peninsula tip, −0.014 … −0.036°) but also refuses Jun 2021 (Oregon coast,
   −0.005 … −0.009°), which started. 2032 (+0.030°) and 2021 (+0.012°) are both 3.6-minute-of-sunset cases, in opposite
   directions: the precision floor of any reimplementation.
3. *First-visibility place and a time-sampled mainland test* (`CrescentDiyanetTimeProfile`, `band_profile.txt`), after
   Diyanet's method text ("coordinates at 6-hour intervals, five columns"): May 2023's first visibility is at 30.8° N
   179.3° E and May 2030's at 32.5° N 173.7° E, both west of the date line. Sampling the sunset line at FV + 0 … 6 h in
   30-minute steps, 2023 crosses mainland Alaska at FV, FV + 0.5 h and FV + 1 h, while May 2030 and Nov 2017 (started)
   cross it at no sampled moment (their passes are narrow in latitude). Any sampled test refuses started months.
4. *Diyanet's imsak, measured.* Diyanet's prayer-time site for Ankara, 9 Nov 2026: İmsak 05:54, Güneş 07:19. Ours:
   sun 18° below at 05:53:43, sunrise 07:26:26 (`CrescentDiyanetAnkaraDawn`; their sunrise carries the 7-minute temkin
   their site documents). So Diyanet's imsak is the −18° dawn with no margin, to the minute; Wellington (41.3° S) is in
   the same latitude band (Dadaş: 18° below 45°; temkin.php: no temkin at imsak). The Wellington clause refuses 2032
   only with an imsak 17 … 24 minutes earlier than ours (started Feb 2031 has +24 min): excluded. The Wellington page
   itself could not be read: namazvakitleri.diyanet.gov.tr answers even robots.txt with a security block (no retry).
   The clause is operational: AH 1446-11, 1447-12 and 1449-1 pass the America test and are refused with the
   conjunction 100 … 133 minutes after Wellington dawn.
5. *Umm al-Qura.* All five misses coincide with the Umm al-Qura first day of the month (ICU table), but "the later of the
   rule and Umm al-Qura" scores 594/707 (`CrescentDiyanetUmmAlQuraBound`, `uq_bound.txt`): Diyanet starts before
   Umm al-Qura in 113 months and equals it in 569 of 707, so five coincidences are the base rate.
6. *1979.* R. H. van Gent (Utrecht University, "The Islamic Calendar of Turkey", webspace.science.uu.nl/~gent0113/islam/
   diyanetcalendar_rules.htm; other): "1344 AH … to 1399 AH … different rules were adopted, the details of which are as
   yet unclear"; the 5°/8° rule applies from 1400 AH (began 21 November 1979). Our list agrees: AH 1393–1398 have 2–3
   misses a year under the rule, 1399 one (Ramazan), 1400 none. Diyanet's own implementation date was not found
   (searched; Bulut's 2013 Diyanet İlmi Dergi article is about the 1925 parliamentary debate). Reading: Ramazan 1979 is
   in the last pre-rule year.

**Why the five cannot be derived from any reading of the rule (each has a started month with equal or worse numbers):**

| Miss | Its numbers | Started months |
|---|---|---|
| 1981-06 (A) | elongation at 00:00 UTC +0.118°, best altitude +1.41° | Jul 1993 +0.114° / +1.43°; Oct 1982 +0.069°; Dec 1989 +0.068° |
| 1990-11 (A) | +0.006° = 43 seconds | below the precision floor (ΔT alone is 57 s in 1990) |
| 2023-05 (D) | America +0.222° at 59.1° N, Wellington +117 min | May 2030 +0.083° at 63.2° N with +204 min; Feb 2031 +0.466° with +24 min: no rule monotone in (America, Wellington) refuses 2023 and starts both |
| 2032-03 (D) | America +0.030° at 65.65° N (3.6 min), Wellington +16 min | Jun 2021 +0.012° (3.6 min); Feb 2031 +24 min; imsak offset excluded (item 4) |
| 1979-07 (A) | main test +2.5° | pre-rule year (item 6) |

**Conclusion.** The astronomy and the rule are right for every period since AH 1400 and reproduce 702 of 707 published
decisions. The five are: one month before the rule was in force (1979), two cases below the precision floor of any
independent implementation (1990: 43 s; 2032: 3.6 min of sunset, with Jun 2021 the same size the other way), one
14-minute case from a 1980s program whose ephemeris is unknown (1981), and one batch-definition case (2023: the only
Alaska-only decision of the 2023–2027 computation run; its numbers beat a started month in the next run). No further
computation can settle them; only Diyanet's own run outputs could. For the port, Diyanet's published dates are the
authority: a table of published month starts (AH 1318–1457 is public, 1900–2035) with the rule beyond it reproduces
the published calendar exactly, the way ICU carries Umm al-Qura as a table for 1300–1600 AH; the alternative is the
rule plus a five-entry override table. That choice is the user's.

**Addendum (2026-11-09, later): the full Keleş article.** The user supplied the complete text of Y. Keleş, "Hicri Aylar İçin
Takvim Sistemleri ve Takvim Birliği", İslam Hukuku Araştırmaları Dergisi 28 (2016) 351–390 (`Research/crescent/
sources-local-only/`). It is not Diyanet's computation booklet; it cites that booklet as **"Diyanet İşleri Başkanlığı,
Kameri Ay Başları Hesap ve Haritaları, Miladi 2016–2022 / Hicri 1437–1444, Türkiye 2014"** (footnotes 34, 35, 49, 50,
63, 74), a print publication not found online. What the article settles (provenance: official statements quoted by a
Din İşleri Yüksek Kurulu expert):
- p. 367: Diyanet's practice before 2016 in its own words: the Greenwich meridian and international time zones are the
  measure; if visibility occurs before 24:00 Greenwich time, the morning after that night is the first day; after it,
  the following day. This is the period-A/C rule exactly.
- p. 375 (citing İ. Yücel, TDV İslam Ansiklopedisi 18, "Hilal", p. 8): until 1974 Türkiye used Fatin Gökmen's system: the
  visibility of the crescent for a hypothetical observer on a 4,300 m peak in Morocco, the westernmost Islamic
  country, so that the month never began before the whole Islamic world could see it. Thresholds not given; 1975–1979
  not described. This is the computed method behind the pre-AH-1400 list (354 misses under the 1978 rule for 1900–1978).
- p. 383: Diyanet's astronomers analysed 87 months (presentation of 4 Nov 2015): under the 24:00 rule, 30% of months had
  an American first visibility delayed by a day and 29% had the far east begin before visibility; the stated motivation
  for the 2016 America exception.
- pp. 371–372 and 372–373: the Nov 2017 and Jul 2020 examples as computed in the 2014 booklet (pre-2016 rule): 20 Nov 2017
  and 22 Jul 2020. The official table now has 19 Nov 2017 (recomputed under the 2016 rule) and 22 Jul 2020 (AH 1441-12:
  the strict America test fails, best +0.07° at 41° N over the Pacific; the official date and our rule agree).
Nothing in the article bears on the five open dates; the inputs they depend on are in the booklet or in Diyanet's
program, not in this literature.

### Option B implemented (2026-11-09, late morning): 707/707 with named corrections

The user accepts only 707/707 and rejects a runtime table of dates. So `CrescentRules.swift` now computes Diyanet's
calendar from the era rules (`DiyanetEra`: ≤2008, 2009–2013, 2014–2016, 2017+, by the Gregorian year of the candidate
first day) and carries the five published months as `diyanetCorrections`. `CrescentDiyanetPublishedTests` computes every
month AH 1399–1457 against the 708 published first days now in `crescent_official_dates.csv` and asserts: era rules
alone 702/707 with exactly the five named misses; with corrections 707/707. One run, 7 seconds:
`DIYANET|published decisions 707|era rules 702|with corrections 707|rule misses: AH 1399-9 AH 1401-8 AH 1411-5 AH 1444-11 AH 1453-12`.
The spec for the port is `Docs/CRESCENT_DIYANET_SPEC.md`.

### Umm al-Qura, same pattern (2026-11-09)

`CrescentRules.ummAlQuraMonthLength` (conjunction before sunset and moonset after sunset at the Kaaba) with
`ummAlQuraCorrections` = [AH 1446-6: Jumada I 1446 has 29 days]. `CrescentUmmAlQuraPublishedTests` over the 131
published decisions AH 1440–1450: rule alone 130 with exactly that miss, with the correction 131/131
(`UMMALQURA|published decisions 131|rule 130|with corrections 131|rule misses: AH 1446-6`). The case: evening of
1 Dec 2024, moonset 7 seconds before sunset at the Kaaba in our computation, the published table starts Jumada II on
2 Dec; a precision-floor case of the same kind as Diyanet's AH 1411-5. Not yet checked on AH 1420–1439 (table not local).

### Round 7 (2026-11-09, afternoon): announced dates of observational authorities vs predicted visibility

**Data.** moonsighting.com (Khalid Shaukat's compilation of official announcements) carries per-country lists of the
announced first day of Ramadan, Shawwal and Dhu al-Hijjah (the last as Eid al-Adha, the 10th) for AH 1429–1448; pages
fetched with plain curl (robots.txt has no disallow), parsed by `Research/crescent/announcements-local-only/
parse_moonsighting.py` → 1,766 dated entries, 158 labels, 1,073 country-months after normalisation, 23 with
conflicting dates (sub-communities; skipped). Quality check against first-hand data: Egypt rows = Dar al-Ifta 3/3,
Turkey rows = Diyanet 9/10 (Ramadan 2008 listed a day early). So: good for match rates, not for exact rule fitting.
Dar al-Ifta's own archive starts in 2017 (sitemap lastmod; older IDs 404), so at most ~20 more Egyptian months exist.

**Measurement** (probe `CrescentAnnouncementsProbe`, `round6-raw/announcements_measure.txt`): for 510 national
decisions in 52 countries, the first day predicted at the capital (or main city) under six rules, against the
announced day. "Exact / announced later / announced earlier / off by 2+":

| Rule at the reference point | Exact | Later by 1 | Earlier by 1 | 2+ |
|---|---|---|---|---|
| MABIMS 2021 (3°, 6.4°) | 262 (51%) | 100 | 127 | 21 |
| Diyanet 5°/8° | 263 (52%) | 58 | 149 | 40 |
| moonset after sunset (Umm al-Qura style) | 252 (49%) | 194 | 61 | 3 |
| Odeh zone B (naked eye, perfect conditions) | 269 (53%) | 29 | 176 | 36 |
| Odeh zone A (easily visible) | 213 (42%) | 5 | 235 | 57 |
| **ICU's `islamic` conjunction clock** | **103 (20%)** | 326 | 0 | 81 |

The 50% ceiling of any single rule is a mixture of three populations:
- **Genuine sighting countries** are matched by a *strict* visibility criterion: Odeh B/A at the capital gives
  Morocco 11/12, Pakistan 11/13 (zone A), Oman 8/10, South Africa 10/11, Sri Lanka 11/13, Mauritius 12/13, Tanzania
  11/12, Kenya 10/11, Australia 11/11, Guyana 10/10, Namibia 10/11, Zimbabwe 8/8, Chile 7/7, Trinidad 8/9; weaker:
  Iran 7/11, Bangladesh 7/11 (5°/8°), Nigeria 7/12, Brunei 6/10, India 6/13 (several committees mixed in the source).
- **The Saudi-following bloc** is matched by Umm al-Qura's own rule, i.e. by the Umm al-Qura calendar: Saudi
  Arabia 13/14, Kuwait 12/15, Qatar 12/15, Lebanon 12/15, Syria 11/14, Sudan 11/15, Jordan 10/13, Palestine 10/13,
  Bahrain 10/13, Algeria 10/11, Tunisia 10/13, Libya 8/10, Egypt 8/12.
- **Computed authorities** are not local and a capital proxy fails them by construction (Turkey 0/10 under every
  local rule; its own rule is global and gives 707/707); Malaysia and Indonesia are verified separately (98/98, 25/25).

ICU's clock is the baseline: 20% exact, a day early in 64% and two or more days early in 16%, never late.

**Caveats.** Compilation errors of a few percent; the capital as reference point (committees accept reports from
anywhere in the country; a western or southern point would fit some countries better); three months a year;
2009–2026 only; small per-country samples (7–15).

**Formatting path in the port** (checked the same afternoon): `ICUDateFormatter.format(_:)` calls
`udat_formatForFields(udateFormat, date.udate, …)`, so ICU computes every calendar field from the absolute time with
its own `islamic` calendar; the Swift calendar's month starts are not consulted when formatting. A location-aware
`.islamic` would therefore compute one date and print another unless formatting is changed to take the fields from the
Swift calendar. That is the first engineering question for any such proposal.
