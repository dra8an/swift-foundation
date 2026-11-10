# Diyanet: how the computation is done (round 2)

> Collected 2026-11-06. Pages were read with WebFetch's default identification, and plain curl was used where sites allowed it. No headers were changed, robots.txt was respected and astronomycenter.net was not accessed. Provenance: **official** = Diyanet's own site or document; **other** = secondary source; **none** = not found, or my own reading. Every quote below was re-opened at least once and is marked verified or unverified.

## Summary

- **The booklet's method text is online.** It is not a PDF: it is the "KAMERİ AY BAŞLARI HESAP VE HARİTALARININ AÇIKLANMASI" section of `vakithesaplama.diyanet.gov.tr/haritalar.php`. That page also has one official visibility map per month for 1430–1457 AH, including all six evenings asked about (official). The booklet itself was not found.
- **The method, in Diyanet's words:**
  - From the moment of conjunction, Diyanet checks the Moon's and Sun's coordinates until the moment the 8° and 5° criteria are first met.
  - That moment gives the place, date and time where the crescent can first be seen "by the human eye".
  - Coordinates are then computed at 6-hour intervals and given in five columns.
  - The plotted points are joined into the red line on the map (official).
- **A new official statement settles the land question.** The Din İşleri Yüksek Kurulu statement on Ramadan 1447 (kurul.diyanet.gov.tr, 18 Feb 2026) says a visibility line that lies over the ocean, not over land, is not enough to start the month. It also says the calculations are done relative to the Greenwich meridian (UTC) (official).
- **Topocentric vs geocentric is not stated by Diyanet.** A peer-reviewed comparison of KHGT (the unified global Hijri calendar of Muhammadiyah, an Indonesian organisation) with Diyanet reads Diyanet as **topocentric** (other). It finds exactly two different month starts in 1447–1457: Ramadan 1447 and Rabi I 1455. The second is the developer's 2033-05-28 evening.
- **Imsak angle:** 18° below the horizon for latitudes under 45°, per a Din İşleri Yüksek Kurulu expert citing 2009 Kurul decisions (other). Wellington, at 41.3°S, falls in that band.
- **Not found:** the ephemeris used, the sunset definition (upper limb or centre, with or without refraction), the Moon centre or limb, and refraction.

---

## 1. The booklet "Kameri Ay Başları Hesap ve Haritaları"

**Answer.** No PDF of the 2014 booklet (1437–1444) or of any later edition was found. The booklet's explanatory text is published on Diyanet's maps page, under the heading **"KAMERİ AY BAŞLARI HESAP VE HARİTALARININ AÇIKLANMASI"**. The same page has a "Kameri Yıl Seçiniz" selector covering 1430–1457 AH, with one "Hilali Görülebilirlik Haritası" per month, which is the content of the 2016–2035 editions.

**Method text, verbatim** (WebFetch returned it in consecutive fragments; gloss after each):
- "Bu bilgiler çizelgelerde Conjunction satırı ile verilmektedir."
- "İçtima anından itibaren ayın koordinatları ile güneşin koordinatları kontrol edilerek ilk defa yukarıda belirtilen kriterleri yakaladığı an belirlenmektedir." (Gloss: starting at conjunction, the Moon's and Sun's coordinates are checked, and the moment they first meet the criteria above is found.)
- "Bu belirlenen an ise, yeryüzünde hilalin ilk defa insan gözü ile görülebileceği yer, tarih ve zaman bilgilerini vermektedir." (Gloss: that moment gives the place, date and time on Earth where the crescent can first be seen by the human eye.)
- "Yukarıda bahsedilen kriterler esas alınarak yapılan hesaplamalarla İçtima anının tarihi ve saati çok hassas olarak Greenwich saatine göre belirlenmektedir." (Gloss: the date and time of conjunction are fixed very precisely in Greenwich time.)
- "Bu ilk görülme anından sonraki değişimleri bulabilmek için 6'şar saat arayla Ay ve Güneşin koordinatlarından yararlanılarak yeryüzünün nerelerinden görülebileceğini belirleyecek koordinatlar hesaplanmış ve beş sütunda verilmiştir." (Gloss: to follow the changes after the first-visibility moment, coordinates showing where on Earth the crescent can be seen were computed at 6-hour intervals and given in five columns.)
- "İşaretlenen noktalar birleştirilerek haritada kırmızı çizgi ile gösterilen hat oluşturulmaktadır." (Gloss: the marked points are joined to form the red line on the map.)
- "Haritanın içerisinde bulunan Güneş ve Hilal sembolleri; hilalin ilk göründüğü anda Güneş ve Ayın dünya üzerindeki konumlarını göstermektedir." (Gloss: the Sun and crescent symbols show the Sun's and Moon's positions over the Earth at the first-visibility moment.)
  - My reading (none): the symbols sit at the sub-solar and sub-lunar points, not at the observing site. On every map I checked, the symbol's longitude equals (12 h − first-visibility UTC) × 15°.
- The page also says: "sarı ile belirtilen yerlerde hava şartları müsait ise" (in the yellow areas the crescent can be seen if the weather allows). Places outside the line see it only on the 2nd day.

**Link:** https://vakithesaplama.diyanet.gov.tr/haritalar.php · **Provenance:** official · **Verified** (fetched four times).

The thesis by Ilman et al. (2026) cites the same page under the title "Kamerî Ay Başları Hesap ve Haritalarının Açıklaması" (other, verified).

## 2. Algorithms or ephemeris

**Answer: not found.** No source names VSOP87, ELP, JPL DE, Meeus or a program. A Diyanet astronomer says the team writes its own algorithms:
- "algoritmaların yazılmasından web yayınlarına kadar tüm süreç ekibimiz tarafından yürütülüyor" (Gloss: our team runs the whole process, from writing the algorithms to web publishing.)
- The team is "3 astronom ve bir vakit hesaplama uzmanından oluşan ekip" (three astronomers and one prayer-time calculation specialist).
- "Astronomik hesaplar hilalin çıplak gözle görülebilirliğini esas alan kriterlere dayanıyor." (Gloss: the calculations rest on criteria based on naked-eye visibility.)

**Link:** https://www.hurriyet.com.tr/gundem/dunyanin-namaz-vakitlerini-turk-astronomlar-hesapliyor-43113821 (Hümeyra Nur İşlek, 22 Feb 2026) · **Provenance:** other · **Verified.**

## 3. The moment of the test (definition of sunset)

**Answer: not found (official definition).**
- Diyanet says only "Güneş battığı anda" (at sunset).
- The glossary entry "Gurup" reads: "Güneşin batması, gün batımı." (the setting of the Sun, sunset). It gives no limb and no refraction. https://vakithesaplama.diyanet.gov.tr/sozluk.php (official, verified).
- temkin.php: "güneş doğuş-batışta 7 dakika temkin uygulanmakta" (a 7-minute safety margin is applied at sunrise and sunset). This is for prayer times; nothing links it to the crescent test (official, verified in round 1 and again here).

**Official test values you can use to tell the definitions apart.** Diyanet's Ramadan 1447 "gözlem şeması" images:
- Source page: https://vakithesaplama.diyanet.gov.tr/icerik.php?icerik=104
- Image files: `https://diykapi.diyanet.gov.tr/api/Files/ReadFile/019c711f-e48e-776c-8c5c-2dda7c871583` and the five other `019c71…` / `019c939c…` IDs.
- Legend from https://vakithesaplama.diyanet.gov.tr/sema.php:
  - "A = Guneşin battığı anda; guneş ile hilal arasındaki açıyı vermektedir." (A is the angle between Sun and crescent at the moment of sunset.)
  - "Açının işaretinin negatif (-) veya pozitif (+) olusu hilalin ufkun altında veya üstünde olma durumunu belirlemektedir." (The sign of A says whether the crescent is below or above the horizon.)
  - "T = Ay ile gunesin batisi arasindaki zaman farkini verir." (T is the time between sunset and moonset.)
- In the drawings, the angle runs from the "UFUK DÜZLEMİ" (horizon plane) to the Moon, so A behaves as the Moon's altitude at sunset.

| Date (sunset) | Ankara A / T | Mecca A / T |
|---|---|---|
| 2026-02-17 | 00°02′ / 03 dakika | 00°18′ / 03 dakika |
| 2026-02-18 | 11°38′ / 1 saat 10 dakika | 12°17′ / 59 dakika |
| 2026-02-19 | 23°51′ / 2 saat 17 dakika | 24°52′ / 1 saat 55 dakika |

- Provenance: official. Verified: I read all six images directly; the sema.php legend was re-opened.
- Caveat: the observer coordinates Diyanet uses for "Ankara" and "Mekke" are not given.

## 4. Moon altitude and elongation: topocentric or geocentric, centre or limb, refraction

**Official: not stated.** haritalar.php contains none of "topo", "yüzey", "merkez", "kırılma", "refrak", "paralaks", "üst kenar" or "yarıçap" (checked, verified). The kurul statement does not mention them either (verified).
- Only one official hint: glossary "Bu'd" = "Uzanım. Gezegen-Yer-Güneş üçlüsünün oluşturduğu açı." (elongation = the angle formed by planet, Earth and Sun, i.e. measured at the Earth). This is a generic glossary entry, not the crescent rule. Official, verified.
- The method text speaks of the place where the crescent can be seen "insan gözü ile" (with the human eye).

**Secondary (other): topocentric.** Source: Ilman, Mariyam & Panjalu, "Disparities in Global Hijri Calendars: A comparative study of Muhammadiyah's KHGT and Diyanet Türkiye 1447–1457 AH", Al-Afaq 8(2), Dec 2026, DOI 10.20414/afaq.v8i2.15981. Copy read: https://repository.um-surabaya.ac.id/id/eprint/14943/1/Rayhan%20Ilman_20221551041_Tugas%20Akhir_Jurnal.pdf
- Counts: "Of the 131 first-of-the-month dates … 129 cases (98.5%) yielded identical dates, while differences occurred in 2 cases … Ramadan 1447 AH and Rabi' al-Awwal 1455 AH."
- The authors say this is their interpretation: "this study interprets the operational application of the Diyanet criteria as being consistent with a topocentric perspective. This interpretation is made by the author … and should not be understood as an explicit statement contained in the official Diyanet documents."
- For 2033 they report Stellarium values at Rivas, Nicaragua: "topocentric elongation 7°13′8″ < 8°; topocentric altitude +4°59′21″ < 5°".
- Verified (local text extract).

**My own observation (none; not computed).** The same paper's Table 3 gives KHGT's geocentric first-fulfilment time for Ramadan 1447 as 03:42 UTC, identical to Diyanet's 03:42. For 1455-3 it gives KHGT 00:02 against Diyanet 00:03. Near-identical first-visibility times sit awkwardly with a full topocentric altitude correction (about 0.9° of parallax). Test both variants against these times before adopting the paper's conclusion.

## 5. "Seen on the mainland of the Americas" and the 00:00 UTC limit

**Official:**
- "Yapılan hesaplamalara göre hilal, 17 Şubat 2026 tarihinde Büyük Okyanus üzerinde görülebilir hale gelecek olmakla birlikte, görülme hattının karalarda olmayıp okyanus üzerinde olması, yeni ayın başlangıcı için yeterli kabul edilmemektedir. Yeni ayın başlangıcına esas teşkil edecek şartlar, 18 Şubat 2026 tarihinde oluşacağından Ramazan'ın başlangıcı 19 Şubat olarak belirlenmiştir." (Gloss: the crescent becomes visible over the Pacific on 17 February, but because the visibility line lies over the ocean and not over land, that is not enough; the conditions are met on 18 February, so Ramadan starts on 19 February.)
  - Note that the 03:42 UTC visibility on 18 Feb is called "17 Şubat", the local evening date.
- "Yeni kameri ayın başlaması için ru'yetin Güney ve Kuzey Amerika Kıtası ana karalarında gerçekleşmesi gerekir." (Gloss: for the new month to begin, sighting must occur on the mainland of South and North America.)
- "Hicrî aybaşlarının tespitine ilişkin astronomik hesaplamalar Greenwich başlangıç meridyenine göre (UTC) yapılmaktadır." (Gloss: the calculations are done relative to the Greenwich meridian, UTC.)
- The page does **not** mention 00:00, 24:00 or "gece yarısı" (midnight).
- **Link:** https://kurul.diyanet.gov.tr/tr/duyuru/2026-ramazan/019c7121-78c4-775c-964e-e581a8efa2c8 ("1447 (2026) Yılı Ramazan Ayı Başlangıcına İlişkin Açıklama", 18 Şubat 2026) · official · **verified.**
- So the official wording judges the *visibility line* ("görülme hattı") against land. The line is built from points at 6-hour intervals (Q1). No list of points, grid or land map is described.

**Other:** in correspondence with Muhammadiyah, Diyanet placed the first fulfilment for Ramadan 1447 over "the Aleutian and Fox Islands", and treated "islands separated from the mainland" as not counting. The paper says: "visibility in oceanic regions and on islands separated from the mainland is not taken into account"; "The statement also cites the low population density in the disputed area." Its sources are a letter from Abdulhamid Eşmeli of the Turkish Embassy in Jakarta (19 May 2025) and Muhammadiyah Announcement No. 01/MLM/I.1/B/2025. Same paper as Q4; verified.

## 6. Sun depression angle for imsak at Wellington

**Official: not found.** The kurul statement says only "imsaktan önce" (before imsak) and gives no angle (verified). temkin.php: "İmsak ve yatsı vakitlerinde ise herhangi bir temkin uygulaması yoktur." (no safety margin at imsak or yatsı; official, verified).

**Other:** "Tablodaki hesaplamalar Din İşleri Yüksek Kurulunun 2009 yılında aldığı kararlara göre yapılmıştır. … 45° enlem öncesinde imsak vakti için 18 derece yatsı vakti için ise 17 derece esas alınmıştır." (Gloss: under the 2009 Kurul decisions, 18° is used for imsak and 17° for yatsı below 45° latitude.)
- Source: M. Bülent Dadaş (Dr., DİB Din İşleri Yüksek Kurulu Uzmanı), "Tarihi ve Güncel Boyutlarıyla Yukarı Enlemlerde Oruç Problemi", https://dergipark.org.tr/en/download/article-file/410300 · verified (local extract).
- Context only: the KHGT paper gives Wellington dawn on 2033-05-28 as 17:56 UTC.

## 7. Diyanet's maps for the six evenings

All maps are under https://vakithesaplama.diyanet.gov.tr/upload_image/uploads/haritalar/. They are official, and I read all six images directly (verified). Copies are saved in `/private/tmp/claude-501/-Users-draganbesevic-Projects-claude-swift-foundation/2d6e7985-46b0-4c93-9d48-36d48ffe15f2/scratchpad/maps/`; my enlarged crops of the Americas are in `/private/tmp/claude-501/-Users-draganbesevic-Projects-claude-swift-foundation/2d6e7985-46b0-4c93-9d48-36d48ffe15f2/scratchpad/crops/`.

| Evening | File | Month | Conjunction (UTC) | First visibility (UTC) | Day 1 | Western red line vs the Americas (my reading of the map: none) |
|---|---|---|---|---|---|---|
| 2021-06-10 | 1442Zilkade.JPG | 1442 Zilkade | 10 Jun 2021 10:53 | 11 Jun 04:00 | 11 Jun 2021 (Cuma) | Reaches mainland California and Mexico (to about 105°W near 20°N) |
| 2023-05-19 | 51444Zilkade.JPG | 1444 Zilkade | 19 May 2023 15:53 | 20 May 06:54 | 21 May 2023 (Pazar) | Pacific; the line just grazes the Alaska Peninsula / Cook Inlet near 60°N 150°W (a plotted point sits there) |
| 2026-02-17 | 21447Ramazan.JPG | 1447 Ramazan | 17 Feb 2026 12:01 | 18 Feb 03:42 | 19 Feb 2026 (Perşembe) | Pacific only; no mainland (confirmed by the kurul text) |
| 2030-05-02 | Muharrem1452.jpg | 1452 Muharrem | 2 May 2030 14:12 | 3 May 07:08 | 3 May 2030 (Cuma) | Covers south-west mainland Alaska (Alaska Peninsula / Bristol Bay shaded) |
| 2032-03-11 | Zilhicce1453.jpg | 1453 Zilhicce | 11 Mar 2032 16:25 | 12 Mar 05:00 | 13 Mar 2032 (Cumartesi) | Covers much of western mainland Alaska, yet the month starts on the 13th |
| 2033-05-28 | Rebilevvel1455.jpg | 1455 Rebiülevvel | 28 May 2033 11:37 | 29 May 00:03 | 30 May 2033 (Pazartesi) | Runs just offshore of the Pacific coast of Central America and Ecuador (about 85°W); not on land |

Observations (none; mine):
- **2030 vs 2032 and 2023:** mainland Alaska seems to be enough in 2030 but not in 2032 or 2023. Something other than the land test may decide those two.
- **2032:** by my rough, unverified estimate, Wellington dawn at −18° on 2032-03-12 is about 16:40 UTC. That is only about 15 minutes after the 16:25 conjunction, so the Wellington-imsak test is a near-threshold candidate there.
- **2033:** first visibility is 3 minutes after 00:00 UTC, so the main test misses the cut-off by minutes.
- **Rounded times:** two first-visibility times are exactly on the hour (04:00, 05:00), which may point to a coarse time step in Diyanet's search.

## Not found

- **Booklet PDF (2014, any later edition).** Looked: vakithesaplama kitaplar.php and makaleler.php (73 articles; none Diyanet-method); searches for "Kameri Ay Başları" "Hesap ve Haritaları", "Kameri Aybaşları" 2016-2022 / 2023-2035 pdf.
- **Ephemeris or algorithm name.** Looked: haritalar.php, sema.php, icerik=84/104, sozluk.php, the kurul statement, Hürriyet, Habertürk, memurlar.net (2026); searches for Meeus/VSOP87/ELP/JPL with Diyanet.
- **Official sunset definition, centre/limb, refraction, topocentric/geocentric.** Looked: haritalar.php keyword check, sozluk.php, temkin.php, sema.php, the kurul statement.
- **Official imsak angle for the Wellington test, and Wellington coordinates.** Looked: kurul statement, temkin.php, sabah_ezani.php.
- **Official grid, point list or land mask for the Americas check.** Looked: haritalar.php, kurul statement.
- **Arabic congress book.** "ULUSLARARASI HİCRİ TAKVİM BİRLİĞİ KİTABI (Arapça)" is linked from kitaplar.php at fetva.diyanet.gov.tr/DosyaGoster.aspx?…; **not fetched: fetva.diyanet.gov.tr's robots.txt disallows `/*.aspx`.**
- **blocked: vakithesaplama.diyanet.gov.tr to plain curl** (HTTP 403, including robots.txt). It was read with WebFetch, as in round 1.
- **dergipark article-file/410422** returned HTTP 429; not retried.

## Terms of use

| Source | Statement |
|---|---|
| vakithesaplama.diyanet.gov.tr (haritalar, sema, sozluk, temkin, icerik=104; maps and diykapi images) | "© 2021 T.C. Diyanet İşleri Başkanlığı. Her hakkı saklıdır." (All rights reserved.) No licence. The map images were saved only to the scratchpad; do not copy them into the repository. |
| kurul.diyanet.gov.tr statement | "© 2026 Din İşleri Yüksek Kurulu - Tüm hakları saklıdır." (All rights reserved.) |
| Ilman et al., Al-Afaq 2026 (UM Surabaya copy) | "This is an open access article under the CC BY-SA license." / "Copyright: © 2026 by authors." |
| Dadaş (DergiPark 410300) | Licence not checked. |
| Hürriyet, Habertürk, memurlar.net | Not checked; used for statements only. |
