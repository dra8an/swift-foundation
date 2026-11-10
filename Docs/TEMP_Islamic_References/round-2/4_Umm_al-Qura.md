# Umm al-Qura (KACST): how the table computes sunset and moonset (round 2)

Collected 2026-11-06. Every request identified itself honestly (default curl, WebFetch, web-fetch subagent) and respected robots.txt. I did not access astronomycenter.net. Round-1 findings are not repeated here.

## Summary

- **Q1, definitions: no official definition found.** No official source says whether sunset and moonset mean the upper limb with refraction, the centre at the horizon, or something else. None says how the 295 m elevation is used.
  - The official printed table gives only the conditions. Its condition 1, "the whole body of the moon above the horizon after sunset", is the only official wording about which part of the moon counts. The website and a 2005 paper by a KACST astronomer say only "moonset after sunset".
  - One secondary source names a convention: van Gent's conversion-table page, as summarised by a search engine, says upper limb, refraction, lunar parallax and an "ideal horizon" (so no dip). That page now returns 404, so this is **unverified**.
  - Another secondary source is an Elixir library (`calendrical`) that uses centre-of-disc sunset and moonset. It misses exactly the same month as the developer: 1446/6, "Moonset 7 s before sunset".
- **Q2, times for the evening of 2024-12-01: no official times found.**
  - The printed table has no times; its pages are date conversions only.
  - The site's prayer times come from `/api/`, which ummulqura.org.sa's robots.txt disallows.
  - I found no Supreme Court statement for Jumada al-Akhirah 1446.
  - One secondary statement exists. Egypt's National Research Institute of Astronomy and Geophysics (NRIAG), as reported in the press, said the moon sets in Makkah **together with** sunset on that day, with no minute value.
  - I found no documented ihtiyat (safety margin) for Maghrib in the Umm al-Qura prayer timetable.
- **Conflicting secondary date claim:** the al-Habib blog says the Umm al-Qura calendar marks **3 Dec 2024** as 1 Jumada al-Akhirah 1446. The official printed table says **Monday 2 Dec 2024** (PDF p.169, re-checked from the page image this session). I could not check whether the live KACST site now says 3 Dec, because its data is behind the disallowed `/api/`.

## 1. How sunset and moonset are defined; use of the 295 m elevation

**Answer:** Not found in any official source. What the official sources do say:

**(a) Official printed table, preface (MoF / KACST committee, scan hosted by van Gent, PDF p.9).** It lists three conditions and the coordinates, with no limb, refraction, dip or topocentric wording.
- Quote: "١- ان يكون كامل جرم القمر (الهلال) فوق الأفق بعد غروب الشمس. ٢- ان يكون غروب القمر بعد غروب الشمس (في مكة المكرمة) بحيث يكون بالإمكان رؤيته وقد تخلق فيه النور. ٣- ولادة الهلال فلكيا" … "الارتفاع : ٢٩٥ مترا عن سطح البحر"
- Gloss: (1) the whole body of the moon (crescent) is above the horizon after sunset; (2) moonset is after sunset (at Makkah), so that it could be seen with light formed in it; (3) astronomical birth of the crescent … elevation: 295 m above sea level.
- Read literally, condition 1 refers to the moon's lower limb at the moment of sunset, but no limb is named. The 295 m is listed only as a coordinate; nothing says how it is used.
- Link: https://webspace.science.uu.nl/~gent0113/islam/downloads/umm_al_qura_1420_1450.pdf (PDF p.9)
- Provenance: official. **Verified** (page image re-rendered and read this session).

**(b) ummulqura.org.sa (KACST site), about-calendar text.** It has no definitions.
- Quote: "يعتمد التقويم منذ عام 1420هـ على إحداثيات الكعبة المشرفة بمكة المكرمة أساسًا للحسابات الفلكية، ويتم تحديد بداية الشهر عند ولادة الهلال وغروب القمر بعد غروب الشمس في مكة المكرمة."
- Gloss: since 1420 AH the calendar uses the Kaaba's coordinates; the month starts at the crescent's birth and moonset after sunset in Makkah.
- I also searched the site's `pages.json` and i18n files for refraction / elevation / Maghrib-method / ihtiyat terms. There are no hits beyond UI labels.
- Link: https://www.ummulqura.org.sa/ar/about-calendar (text in https://www.ummulqura.org.sa/assets/data/pages.json)
- Provenance: official. **Verified** against the round-1 download of pages.json (2026-11-05), grepped this session.

**(c) Al-Mostafa, Z. A., "Lunar Calendars: The New Saudi Arabian Criterion", *The Observatory* 125 (2005) 25–30.** The author is at KACST's Astronomy and Geophysics Research Institute. Round 1 could not read this paper; I read the ADS scan this session. It describes the rule but defines neither limb, refraction nor elevation.
- Quotes (p.28):
  - "This model follows the conjunction and the moonset before sunset over the Holy Kaaba (the Black House at Mecca)". The text says "moonset before sunset" as printed.
  - "when making a calendar for any place that depends on the Moon setting after the Sun at the end of the lunar month in that place … starting in the lunar year 1420 H (1999–2000), this criterion was used to compute the new Umm Al-Qura Calendar, taking into account the coordinates of the Holy Kaaba."
  - "…the new Moon must have been born (conjunction) before sunset at the coordinates of the Holy Kaaba. This condition has been taken into account since calendar year 1423 H (2003)."
- Link: https://articles.adsabs.harvard.edu/pdf/2005Obs...125...25A
- Provenance: other (peer-reviewed paper by a KACST scientist; not an official KACST publication). **Verified** (page images read).

**(d) van Gent, conversion-table page (1420–1434 AH), via search snippet only.** The search engine's summary of this page says sunset and moonset times are "computed for the moment the upper limb disappears, with refraction and the monthly lunar parallax variation included", measured against "an ideal horizon at 90° from the zenith". That would mean no dip for elevation.
- This is van Gent's own computing convention for his visibility data. Nothing in the snippet says it is KACST's.
- Link: https://webspace.science.uu.nl/~gent0113/islam/ummalqura_table.htm (now **HTTP 404**; it is not linked from van Gent's current Umm al-Qura menu)
- Provenance: other. **Unverified**: the wording is a search-engine paraphrase, not a quote I could re-open.
- The live van Gent rules page says only "The geocentric conjunction occurs before sunset. The moon sets after the sun." (verified, https://webspace.science.uu.nl/~gent0113/islam/ummalqura_rules.htm).

**(e) `calendrical` (Elixir library) docs, `Calendrical.Islamic.UmmAlQura.Astronomical`.** This is the same single-miss situation as the developer's.
- Quote: "The astronomical computation uses centre-of-disk sunset and centre-of-disk moonset conventions (matching Skyfield/van Gent) and achieves 99.7 % agreement (934 of 937 months) with the van Gent reference dataset for Era 4 (1423–1500 AH)."
- Its table row: "| 1446/6 | 2024-12-02 | 2024-12-03 | Moonset 7 s before sunset |".
- Its explanation: "All three involve moonset-sunset gaps of less than 10 seconds — below the precision floor of any rise/set calculation given atmospheric refraction uncertainty (±2 arcmin ≈ ±10 s)."
- The claim "matching … van Gent" is the library's own. Van Gent's live rules page states no convention, and (d) above suggests van Gent used the upper limb.
- Link: https://calendrical.hexdocs.pm/Calendrical.Islamic.UmmAlQura.Astronomical.md
- Provenance: other. **Verified** (downloaded and read).

**Use of the 295 m elevation:** not found. Only the coordinate listing in (a) mentions it.

## 2. Published sunset and moonset times at Makkah, evening of 2024-12-01

**Hijri date check:** 1 Jumada al-Ula 1446 = Sunday 2024-11-03, and 1 Jumada al-Akhirah 1446 = Monday 2024-12-02. So the evening of 2024-12-01 is 29 Jumada al-Ula, and the official table started the new month the next day.
- Quote: "الاثنين | ١ | ٢ … جمادى الآخرة ١٤٤٦ / ديسمبر ٢٠٢٤" (Monday, 1 Jumada al-Akhirah = 2 December).
- Link: same printed-table PDF, p.169. Provenance: official. **Verified** (page image).
- The same page has **no sunset, moonset or conjunction times**; it is a date-conversion table only. **Verified.**

**Official times:** not found.

**Secondary statement (no times, just "together with"):** NRIAG (Egypt), via Egypt Telegraph, 2024-11-29.
- Quote: "سيولد مباشرة بعد حدوث الاقتران في تمام الساعة الثامنة و22 دقيقة صباحا يوم الأحد المقبل الموافق يوم 1 ديسمبر" … "وأوضح المعهد، في بيان له، أن القمر يغرب في مكة المكرمة مع غروب شمس ذلك اليوم، وهو يوم الرؤية."
- Gloss: conjunction at 08:22 Cairo time (06:22 UT) on Sunday 1 December; the moon sets in Makkah together with sunset that day. The same report gives Cairo moonset 6 min before sunset.
- Link: https://www.egypttelegraph.com/95458
- Provenance: other (Egyptian government institute as reported in the press; not Saudi). **Verified** (re-opened with curl).
- The same statement appears on filgamaa.com: "وأضاف المعهد أنه سيغرب القمرفي مكة المكرمة مع غروب شمس ذلك اليوم يوم الرؤية". That copy is **unverified**: the subagent read it once, and on re-open the site returned **blocked: filgamaa.com (HTTP 403 to curl)**.

**Conflicting secondary claim about the date:** al-Habib blog (Habib bin Hilal), December 2024.
- Quote: "The Ummul Qura Calendar of Saudi Arabia also marks Tuesday, 3rd Dec 2024 as the first day of Jumadal Akhirah 1446 AH."
- This contradicts the official printed table (2 Dec). I could not check it against the live KACST data (see Not found).
- Link: https://blog.al-habib.info/2024/12/jumadal-akhirah-1446-ah-a-new-month-begins/
- Provenance: other. **Verified** that the blog says this, not that it is true.

**Supreme Court statement for Jumada al-Akhirah 1446:** not found.

**Maghrib ihtiyat in the Umm al-Qura prayer timetable:** not found.

## Not found

- **Official definition of sunset/moonset (limb, refraction, centre), topocentric vs geocentric, and use of the 295 m elevation.** Looked:
  - the printed-table preface, PDF pp.7–10 (re-read);
  - ummulqura.org.sa `pages.json` and i18n (ar/en), grepped for انكسار/احتياط/ارتفاع/المغرب/refraction/elevation/Maghrib;
  - al-Mostafa 2005 (full text);
  - van Gent pages: rules, converter, principal, introduction and solar are live; the table page is 404;
  - KFUPM al-Shukri page Ram1426.htm (Makkah horizon, no definitions);
  - WebSearch, English and Arabic (e.g. "تقويم أم القرى حساب غروب الشمس الانكسار الجوي ارتفاع المكان", "Umm al-Qura calendar KACST algorithm moonset upper limb refraction topocentric", "مدينة الملك عبدالعزيز … الانكسار الارتفاع عن سطح البحر نصف قطر الشمس").
- **Official sunset/moonset/Maghrib times for Makkah on 2024-12-01.** Looked:
  - the printed table p.169 (no times);
  - ummulqura.org.sa: the prayer times and annual data load from `/api/`, which robots.txt disallows, so I did not access them;
  - WebSearch for Makkah Maghrib on that date (only third-party aggregator sites, not used);
  - WebSearch for Saudi press (Jeddah Astronomical Society, alyaum) on this crescent: nothing for Jumada al-Akhirah 1446.
- **Supreme Court statement for Jumada al-Akhirah 1446.** Looked: WebSearch "المحكمة العليا بيان شهر جمادى الآخرة 1446 تقويم أم القرى" and variants. I found statements for Muharram 1446 (184/H) and Dhu al-Qadah/Dhu al-Hijjah 1446, but none for this month. I did not crawl uqn.gov.sa, whose terms forbid automated copying (round 1).
- **Maghrib ihtiyat.** Looked: WebSearch "تقويم أم القرى وقت المغرب احتياط دقيقة", "Umm al-Qura prayer times Maghrib sunset 0.833 refraction precaution KACST". Only fatwas and generic guides came up, nothing official.
- **Live KACST date for 1 Jumada al-Akhirah 1446 (to test al-Habib's 3 Dec claim):** not checked, because `/api/` is disallowed.
- **NRIAG Astronomical Guide 1446 (nriag.sci.eg).** Possibly holds Makkah times. **blocked: nriag.sci.eg**: its robots.txt disallows ClaudeBot, anthropic-ai and Claude-Web. I had downloaded the PDF before reading the whole robots.txt; I deleted it unread.
- **Archived copy of van Gent's ummalqura_table.htm.** I tried the Internet Archive availability API. The session's permission system denied it, and I did not pursue it further.

## Terms of use

| Source | Terms found |
|---|---|
| ummulqura.org.sa (official) | Round 1: terms allow using the site's services "provided that the website is not misused or disrupted"; nothing on reuse of data; "All rights reserved". robots.txt allows `/` but disallows `/api/` and `/backend/` (re-checked this session). |
| Printed table PDF (MoF/KACST, hosted by van Gent) | No licence stated. Government publication. |
| ADS scan of al-Mostafa 2005 | Page footer: "© The Observatory • Provided by the NASA Astrophysics Data System". No reuse licence stated. |
| calendrical.hexdocs.pm | I did not read the library's licence. hexdocs robots.txt returns a 404 page. |
| van Gent pages | Round 1: "© R.H. van Gent (2007-2017)", no terms. |
| egypttelegraph.com | robots.txt `Allow: /`. I did not read the site's terms. |
| filgamaa.com | robots.txt allows. Re-access returned 403. |
| blog.al-habib.info | robots.txt disallows only `/dlm_uploads/`. I did not read the site's terms. |
| dar-alifta.org | Read by the subagent: no Makkah or minute content. I did not read the terms. |
| nriag.sci.eg | Blocked by robots.txt for Claude agents; Content-Signal "search=yes,ai-train=no,use=reference". |

Scratch files (not in any repository) are under /private/tmp/claude-501/-Users-draganbesevic-Projects-claude-swift-foundation/2d6e7985-46b0-4c93-9d48-36d48ffe15f2/scratchpad/r2uq/:
- ads/mostafa2005.pdf and its page images
- p-169.png and pre-009.png (rendered printed-table pages)
- cal/astro.md (the calendrical doc)
- v/et2.html and v/ah2.html (verification copies)
