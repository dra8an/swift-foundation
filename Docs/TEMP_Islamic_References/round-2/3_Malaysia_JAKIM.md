# Malaysia (JAKIM): how the takwim is computed (round 2)

Collected 2026-11-06. I used plain curl with its default identification, WebFetch and WebSearch. I set no browser headers, used no mirrors or proxies, did not access astronomycenter.net, and checked robots.txt where a site had one. Provenance labels: **official** (JAKIM, JUPEM, state mufti offices), **other** (university, journal or news), **none** (nothing found).

## Summary

- **No source gives JAKIM's exact definitions.** I found no official text that says whether the moon's altitude is topocentric, includes refraction, or is measured to the centre or a limb, nor whether the elongation is topocentric. I also could not get the Almanak Falak Syarie (AFS) refraction table itself.
- **The best method source is a university teaching sheet.** UTM's eKITAB, which works from the AFS tables, gives worked cases at Tanjung Chinchin and Pulau Perak:
  - Moon centre, refraction r taken from the AFS refraction table using the computed geocentric altitude hB, parallax subtracted.
  - Elongation is topocentric, centre to centre, without refraction.
  - The sun at sunset is at −(SD + 34').
  - Sunset and moonset times come from AFS tables, rounded to the minute.
- **The figures JAKIM actually uses come from JUPEM.** JUPEM's Bahagian Ukur Geodetik produces them with its own software: "Perisian SPPFv1.3" in 2020, "Perisian AIMS" in 2022-2023, and "Perisian AIMS JUPEM" in 2026. The 2026 sheets are labelled "Terbias" (refracted), list Delta T, and give the station height ("40 m"). The 2020 and 2022 sheets give no height. The Federal Territories mufti office (muftiwp.gov.my) republishes these sheets, but only for three sighting sites (Menara KL, PICC Putrajaya, Menara UMS Labuan). It has none for Tanjung Chinchin or Pulau Perak.
- **None of the three evenings has published reference-point values.** The nearest official data is the JUPEM sheet for 2020-11-15 at Menara KL and for 2022-11-24 at PICC. Nothing is published for 2027-12-28.
- **Two published reference-point values can serve as calibration points:**
  - Tanjung Chinchin, 2022-05-01 (official, Perak mufti): altitude 5°27', elongation 5°57'.
  - Pulau Perak, 2023-04-20 (other, Utusan quoting a JAKIM panel member): altitude 2°02', elongation 2°15', sunset 7.31 pm, moonset 7.43 pm.
- **Rounding matters near the thresholds.** Both JUPEM and eKITAB list sunset to the whole minute and quote altitude and elongation at that rounded minute. Near sunset the moon's altitude changes by about 11-13' per minute (read from the JUPEM tables). That alone could explain misses of a few hundredths of a degree. This is my inference; no source states it.

## Q1. Almanak Falak Syarie: refraction table, altitude and elongation definitions

**Refraction table.** The table itself was not found. The eKITAB sheets cite it and give two values read from it:

| Station, evening | Computed (geocentric) altitude hB | Refraction r from the AFS table |
|---|---|---|
| Tanjung Chinchin, 29 Ramadan 1443 (2022-05-01) | 06°01'43" | 7'54" |
| Pulau Perak, 29 Syaaban 1444 (2023-03-22) | 09°21'30" | 5'26" |

- **Quote:** "Pembetulan kesan biasan atmosfera boleh di dapati dari jadual biasan atmosfera di dalam almanak falak syarie. Jadual tersebut menetapkan kesan biasan yang berubah-ubah mengikut ... suhu, kelembapan dan tekanan udarakasa pada altitud tertentu." (The refraction correction comes from the AFS refraction table, which varies with temperature, humidity and air pressure at a given altitude.) Also "Bagi altitud hilal, hB = 09° 21' 30" / Biasan, r = 5' 26''".
- **Links:** <https://people.utm.my/shahabuddin/wp-content/uploads/sites/890/2023/03/Kiraan-Awal-Ramadan-1444H_Pulau-Perak.pdf> and <https://people.utm.my/shahabuddin/wp-content/uploads/sites/890/2022/04/02-Kiraan-Awal-Syawal-1443H.pdf>
- **Provenance:** other (UTM teaching material, eKITAB by Dato' Sr Dr Azhari Mohamed and Wan Kamel Wan Hussain). **Verified** (read from the PDF text).
- **My own arithmetic (no source):** both values equal 0.945 × Saemundsson's standard refraction (10 °C, 1010 hPa) at hB. That is what a temperature of about 26-27 °C would give. The table is looked up with the geocentric altitude hB, not the topocentric one.

**Moon altitude (eKITAB method):** moon centre, topocentric, with refraction.
- **Quote:** "di mana h adalah altitud pusat bulan" (h is the altitude of the moon's centre). "Altitud ketara adalah altitud bulan selepas mengambil kira kesan paralaks dan biasan atmosfera ... hK = hB - p + r" (apparent altitude is after parallax and refraction), with "p = po kos(hB)".
- **Link:** the same Pulau Perak PDF.
- **Provenance:** other. **Verified.**

**Moon altitude (JUPEM sheets, which JAKIM uses):** these print the moon's altitude per minute and are labelled "Terbias" (refracted) in 2026, so the altitude is apparent. Whether it refers to the centre or a limb is not stated.
- **Quote:** "DATA RUKYAH MATAHARI DAN BULAN ... [ 5°16'43" U, 115°10'25" T, 40 m ] / Terbias / Delta T 75.4 saat ... Sumber : Perisian AIMS JUPEM".
- **Link:** <https://muftiwp.gov.my/images/falak/rukyah/data_rukyah/mums/2026/31.9Nov2026.pdf>
- **Provenance:** official (JUPEM sheet hosted by the Federal Territories mufti office). **Verified.**
- **My inference:** the sun-altitude column in the 2020 and 2022 sheets changes by about 13'50"/min high in the sky but by about 11'40"/min near 0°. That slowdown is refraction, so those altitudes are apparent too.

**Elongation (eKITAB):** topocentric, centre to centre, without refraction.
- **Quote:** "Bagi tujuan menghitung jarak lengkung pusat bulan ke pusat matahari, altitud relatif bulan dan matahari toposentrik tanpa biasan digunakan" (for the centre-to-centre elongation, topocentric altitudes without refraction are used). Also "Parameter jarak lengkung yang dirujuk adalah dari pusat bulan ke pusat matahari." Formula: "kos s = kos (hB - hM) x kos (AzB - AzM)" with hB − p for the moon.
- **Link:** the same Pulau Perak PDF.
- **Provenance:** other. **Verified.**

**Elongation (JUPEM "Jarak Lengkung" column):** the definition is not stated. Kosmo, citing JAKIM and JUPEM data, calls it "jarak lengkung pusat bulan" (arc from the moon's centre) (other, verified via fetch excerpt, <https://www.kosmo.com.my/?p=422700>).
- **My own arithmetic (no source):** I recomputed the elongation from the sheets' own altitudes and azimuths.

| Sheet | Printed elongation | From apparent altitudes | From airless altitudes |
|---|---|---|---|
| KL, 2020-11-15 18:57 | 2.811° | 2.706° | 3.028° |
| PICC, 2022-11-24 18:59 | 6.108° | 6.016° | 6.355° |
| Labuan, 2026-11-09 18:01 | 5.316° | 5.309° | 5.388° |

  Only the 2026 sheet roughly reproduces from apparent altitudes. In the 2022 sheet the column grows smoothly at about 27'/h, which looks like a geocentric quantity, but this is unproven.

**Ephemeris behind the AFS:** one paper says the AFS uses the J1950 epoch with Newcomb's sun and Brown's moon. I saw this only in a search-result summary; core.ac.uk blocked the PDF. **Unverified.**

## Q2. Sunset definition and station elevation

**eKITAB:** sunset is read from AFS tables tabulated for latitudes 5° and 6°, corrected for longitude, and given to the whole minute ("WPM matahari terbenam di stesen 19 35"). For the elongation, the sun's altitude at sunset is −(SD + 34').
- **Quote:** "Biasan Ufuk ketika matahari terbenam ditakrifkan sebagai 0° 34ʹ 00ʺ ... hM = - (SDmh + Biasan Ufuk) ... = - 0° 50ʹ 03ʺ" (horizontal refraction at sunset is defined as 34'; the sun's altitude at sunset is −(SD + 34') = −0°50'03").
- **Link:** the Pulau Perak PDF.
- **Provenance:** other. **Verified.** No observer elevation appears anywhere in eKITAB.

**Selangor mufti staff (prayer-time context):** "matahari terbenam berlaku ketika ... jarak zenit matahari yang dihitung adalah, z = 90˚ 50’ ... Nilai 50’ didapati berdasarkan nilai ½ semidimeter matahari (SD=16’) dan nilai pembiasan atmosfera (R=34’)" (sunset is when the sun's computed zenith distance is 90°50': SD 16' plus refraction 34'). Dip is given as "Dip = 1.76 √h (dalam minit)".
- **Link:** <https://juffas.muftiselangor.gov.my/index.php/jurnal/article/download/35/20/319> (JUFFAS vol. 1 no. 2, Dec 2024, Surtahman and Sadali, Jabatan Mufti Selangor)
- **Provenance:** other (a journal article, though published by an official body). **Verified.**

**JUPEM sheets:** sunset is a whole minute ("Matahari Terbenam : 18:59:00"). My inference from the tables:
- 2020 (KL) and 2022 (PICC): the listed minute is when the sun's apparent centre crosses about −16', i.e. the upper limb at a sea-level horizon. Example: at PICC on 2022-11-24 the sun is at −11'16" at 18:59 and −22'55" at 19:00.
- 2026 (Labuan, "40 m"): the listed 18:01 fits −16' minus about 11' of dip for 40 m. So the newer software appears to include elevation.
- The 2023 summary sheets print the sun's altitude at the listed sunset minute, for example "Altitud Matahari -00° 16' 43"" at KL with sunset 7:24 PM (<https://MUFTIWP.GOV.MY/images/falak/rukyah/laporan_cerapan_hilal/ANALISIS_DATA_HILAL_2023.pdf>, "Sumber: JUPEM & JAKIM", official, verified).

**Elevation of Tanjung Chinchin and Pulau Perak:** not found.
- A data.gov.my dataset, "Jadual Terbit dan Terbenam Bulan Tg Chinchin, Langkawi bagi Tahun 2019" (JUPEM), reportedly has coordinate and height ("ketinggian") columns, but the host was unreachable (blocked: archive.data.gov.my, ECONNREFUSED).
- The station coordinates differ between sources:

| Station | Source | Latitude | Longitude | Provenance |
|---|---|---|---|---|
| Pulau Perak | eKITAB | 5°41'03"N | 98°56'20"E | other, verified |
| Pulau Perak | Kosmo, quoting the minister | 5°41'05"N | (98°56'14"E per round 1) | other, verified |
| Tanjung Chinchin | eKITAB | 6°26'10"N | 99°38'30"E | other, verified |

## Q3. Published values for the three evenings

**2020-11-15, Tanjung Chinchin:** not found. The nearest official data is the JUPEM sheet for Menara KL (3°09'10"N, 101°42'13"E; "sumber: perisian SPPFv1.3"; "SEKSYEN GEODESI ... JABATAN UKUR DAN PEMETAAN MALAYSIA"):
- Header: "Bulan terbenam: 19 : 10 ... Matahari terbenam: 18 : 57 ... Umur hilal: 06 j 02 m ... Ijtimak: 13:07 (15-11-2020)" (moonset 19:10, sunset 18:57, moon age 6 h 02 m, conjunction 13:07).
- Row at 18:57: moon altitude 02 20 32, moon azimuth 252 17 30, sun altitude −00 11 53, sun azimuth 251 21 33, elongation 02 48 41.
- Link: <https://www.muftiwp.gov.my/images/falak/rukyah/data_rukyah/mkl/15-17_NOV2020MKL-min.pdf> (PICC and Labuan versions sit under /picc/ and /mums/ with the same file pattern).
- Provenance: official. **Verified.**

**2022-11-24, Pulau Perak:** not found. The nearest official data is the JUPEM sheet for PICC Putrajaya (2°53'40"N, 101°40'36"E; "Sumber : Perisian AIMS"):
- Header: "Bulan Terbenam : 19:22:00 ... Matahari Terbenam : 18:59:00 ... Umur Hilal : 12j 25m ... Ijtimak : 06:57:00 (2022-11-24)" (moonset 19:22, sunset 18:59, moon age 12 h 25 m, conjunction 06:57).
- Row at 18:59: moon altitude 04° 24' 29", moon azimuth 245° 32' 22", sun altitude −00° 11' 16", sun azimuth 249° 25' 32", elongation 06° 06' 28".
- Link: <https://MUFTIWP.GOV.MY/images/falak/rukyah/data_rukyah/picc/2022/29_24Nov22-min.pdf>
- Provenance: official. **Verified.**

**2027-12-28, Pulau Perak:** not found. The muftiwp data page covers only 2020-2026.

**Reference-point calibration values (other evenings):**
- **Tanjung Chinchin, 29 Ramadan 1443 (2022-05-01):** "data hisab pada 29 Ramadhan di Tanjung Chinchin ( titik rujuk paling barat di Malaysia) ... Ketinggian hilal : 5 darjah 27 minit ... Elongasi hilal : 5 darjah 57 minit" (altitude 5°27', elongation 5°57').
  - Link: <https://mufti.perak.gov.my/images/artikel%20isu%20semasa/Isu1Syawal.pdf>. Official. **Verified.**
  - For comparison, eKITAB for the same evening (other, verified) gives apparent altitude 05°14'53", topocentric elongation 06°01'31", sunset 19:29 and moonset 19:53. So JAKIM's figures differ from eKITAB's.
- **Pulau Perak, 2023-04-20 (Syawal 1444):** "berdasarkan hisab di Pulau Perak, altitud atau ketinggian bulan daripada matahari ialah dua darjah dua minit dan elongasi atau jarak lengkung dua darjah 15 minit"; "bulan dijangka terbenam pukul 7.43 petang ... daripada waktu matahari terbenam pukul 7.31 petang" (altitude 2°02', elongation 2°15', moonset 7.43 pm, sunset 7.31 pm). Utusan, 5 Apr 2023, quoting Hanafiah Abdul Razak of JAKIM's falak panel.
  - Link: <https://www.utusan.com.my/nasional/2023/04/sambut-aidilfitri-terkejut-dijangka-tidak-berulang/>. Other. **Verified** (via fetch-tool excerpt).

## Not found

| Item | Where I looked |
|---|---|
| The AFS refraction table and the AFS definitions | Searches "Almanak Falak Syarie" + biasan / jadual biasan / pembiasan / altitud ketara; "jupem.gov.my Almanak Falak Syarie"; JUPEM AIMS/SPPF + toposentrik/biasan. **blocked: core.ac.uk** (Cloudflare "Just a moment" page). **blocked: anyflip.com** (403, JUFAS Syawal 1443 monograph with a JUPEM section). |
| An official limb or centre statement, and whether JAKIM's elongation is topocentric or geocentric | The sources above; JAKIM takwim footers (round 1); the muftiwp data-rukyah page (no methodology text); the Perak mufti PDF; Utusan and Kosmo. **USIM SALAM Digest** paper unreachable (ECONNREFUSED). |
| Elevation of Tanjung Chinchin and Pulau Perak | Kosmo and Utusan July 2022 articles (no height); **archive.data.gov.my** Tanjung Chinchin moon and sun tables unreachable (ECONNREFUSED, also via WebFetch). |
| Values at the reference points for 2020-11-15, 2022-11-24 and 2027-12-28 | <https://www.muftiwp.gov.my/ms/perkhidmatan/data-falak/data-rukyah> (only KL, PICC and Labuan, 2020-2026); ANALISIS_DATA_HILAL_2023 (Rejab 1444 to Jamadilakhir 1445, those three sites only); searches "Tanjung Chinchin" + hilal/altitud/2020/Rabiulakhir 1442, "data hilal Pulau Perak", "24 November 2022" hilal, "15 November 2020" anak bulan, "titik paling barat" "Pulau Perak" Jamadilawal 1444H, JAKIM "data hisab"/"maklumat hilal". **Pusat Falak Sheikh Tahir dataset** on archive.data.gov.my unreachable. |

## Terms of use

| Site | robots.txt | Terms of use |
|---|---|---|
| muftiwp.gov.my | Returns 404 (no robots.txt) | Not seen; government site, publicly posted PDFs. |
| people.utm.my | Allows everything except /wp-admin/ | Not checked; academic material. |
| juffas.muftiselangor.gov.my | Not checked | Journal PDF, open access. |
| mufti.perak.gov.my | Not checked | Read in round 1. |
| utusan.com.my, kosmo.com.my | Not checked | Copyrighted news; only short quotes used. |

All files I downloaded are in /private/tmp/claude-501/-Users-draganbesevic-Projects-claude-swift-foundation/2d6e7985-46b0-4c93-9d48-36d48ffe15f2/scratchpad/dl (utm_r1444.pdf, utm_s1443.pdf, wp_24nov22.pdf, wp_nov2020mkl.pdf, wp_9nov26.pdf, wp_analisis2023.pdf).
