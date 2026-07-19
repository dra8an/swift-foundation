# Chinese calendar port — master plan

> **Cold-start document.** Written 2026-07-17 to survive a context clear.
> Assume the reader knows nothing beyond what's written here and in the
> linked docs. This is the starting point for the Chinese port work.

---

## 1. Where the project stands (context)

Three-calendar arc so far, all following the same pattern — pure-Swift
`_CalendarProtocol` implementations behind feature flags, parity-verified
against `_CalendarICU` with zero divergences before any router flip
(`backup/PARITY_PROTOCOL.md` — non-negotiable):

| Effort | Status |
|---|---|
| Hebrew (#1953 + #2028) | **MERGED** upstream. Live behind feature flag. Fast paths + `_CalendarConstants`/`_CalendarUtility` shipped in #2028 (merge `91d1fb6d`, 2026-07-09). |
| Buddhist + Japanese (#2105) | **PR OPEN** since 2026-07-12 from `port/buddhist-japanese-main` (head `08b6e889`). Awaiting first review. |
| **Chinese (this plan)** | Starting. Research here on the 6.3 iMac; PR later from the 6.4 machine. |

**Workflow (proven twice):** research branch on this machine (stacked:
`port/hebrew` → `port/buddhist` → **`port/chinese`** off `port/buddhist`
tip `ae2bc97`), full parity suites against `_CalendarICU` constructed
directly (bypasses feature flags), then the 6.4 machine cuts a clean
`port/chinese-main` off `upstream/main` — code only, never `backup/` —
and opens the PR. Chinese has **no dependency on #2105 merging**; the only
shared file is `Calendar_Cache.swift` (one flag + routing line, trivially
reconciled at cherry-pick regardless of PR order).

**Drift risk:** if #2105 review changes shared shapes (as #2028's review
did — `supportsNextDateFastPath` changed twice), adapt at cherry-pick.
Track via the protocol baseline in agent memory
(`reference_calendar_protocol_baseline.md`) and
`gh api ".../contents/...Calendar_Protocol.swift?ref=main"` diffs.

## 2. Environment (this machine — critical)

- **`export TOOLCHAINS=swift SWIFTCI_USE_LOCAL_DEPS=1` before EVERY build/
  test/bench.** Xcode's default 6.2.3 FAILS to compile `Calendar_Hebrew.swift`
  (type-check timeout). The working toolchain is Swift 6.3.1-RELEASE in
  `~/Library/Developer/Toolchains/`. If an unexpected full rebuild starts or
  unchanged code stops compiling, check `swift --version` FIRST.
- Stale-artifact protocol: `./scripts/clean-test.sh` (see
  `backup/BUILD_CACHE_PROTOCOL.md`). Expected durations:
  `backup/EXPECTED_TIMES.md` (stop at +10% over).
- `swift test --filter` matches **test function names**, not suite display
  names. Multi-name alternation `a|b|c` works for tests; for the bench
  package only `^exact$` single filters work (see `backup/BENCHMARKS_PACKAGE.md`).
- Test discipline: collect divergences into an array, ONE `#expect` at the
  end; cap failure accumulation (~200) to avoid flooding.
- Comments in source: terse, one line max (upstream reviewers trim more).
- Repo: `/Users/draganbesevic/Projects/claude/swift-foundation`
  (`origin` = dra8an fork, `upstream` = swiftlang). The separate clone at
  `Projects/claude/collation/swift-foundation` is unrelated — never touch.
  The Bash cwd resets to the FROZEN icu4swift project — always `cd` first.
- Never commit/push without explicit user instruction. Announce every
  long-running launch before starting it. Use `gh` for PR inspection.

## 3. Scope

- **Phase 1 (this plan): `.chinese` only.** `_CalendarChinese` in
  `Sources/FoundationEssentials/Calendar/Calendar_Chinese.swift`.
- **Phase 2 (optional, decide later): `.dangi`** — Korean lunisolar sibling.
  Same engine, different epoch/meridian (ICU `dangical.cpp`; icu4swift has a
  working Dangi). Foundation's `Calendar.Identifier` HAS `.dangi` (verified,
  `Calendar.swift:93`). If Phase 1's architecture is parameterized the way
  `IslamicTabularArithmetic` was in icu4swift, Dangi is a small facade.
- **Out of scope:** the other six `hasRepeatingMonths` identifiers
  (gujarati/kannada/marathi/telugu/vietnamese/vikram, `Calendar.swift:733`)
  — verify what `_CalendarICU` even does for them before ever considering.
- Foundation-side framework awareness: `Calendar.hasRepeatingMonths`
  includes `.chinese`/`.dangi` — framework code (enumeration, recurrence)
  branches on it and on `DateComponents.isLeapMonth`, which is plumbed
  through `Calendar_Enumerate.swift`, `Calendar_Recurrence.swift`,
  `DateComponents.swift`. Hebrew's `{month, isLeapMonth}` handling is prior
  art (`Calendar_Hebrew.swift`).

## 4. The Chinese calendar, structurally

- Lunisolar: months are true lunations (29/30 days), years have 12 or 13
  months. A leap month repeats the preceding month's number with
  `isLeapMonth = true`.
- Which month leaps: determined astronomically — the month containing no
  major solar term (zhōngqì) following the winter-solstice month rules.
  Month 11 contains the winter solstice; New Year = second (sometimes
  third) new moon after solstice.
- **ICU's field conventions** (VERIFIED 2026-07-17 — the authoritative
  version is § 11.1; the sketch below was the pre-verification guess):
  - `era` = 60-year cycle number since the 2637 BCE epoch (Huangdi era);
    recent dates are in cycle ~78–79.
  - `year` = 1…60 within the cycle.
  - `month` = 1…12 (leap month repeats the number; `isLeapMonth`
    distinguishes).
  - `day` = 1…30; `dayOfYear` up to ~384.
  - Day boundaries follow the **calendar's own TimeZone** (normal Calendar
    behavior); the China meridian enters only the astronomical month/solstice
    computation (ICU: UTC+8 after 1928; **before 1929 ICU uses Beijing local
    mean time 7:45:40** — a fidelity detail that matters for Strategy A and
    for pre-1929 table generation in Strategy B).
  - Expect ICU quirks like the Buddhist/Japanese finds (`quarter = 0` at
    year-wrap; odd `dateInterval(.era)`) — discover, document, exclude.

## 5. THE STRATEGY DECISION (make this first)

The parity bar is zero divergences vs `_CalendarICU(.chinese)`. Note
carefully: **icu4swift's Chinese was validated against Hong Kong
Observatory data, not ICU** — ICU computes its own astronomy and disagrees
with HKO occasionally (icu4swift saw a 1906 cluster). HKO-derived data is
NOT automatically ICU-parity data.

### Strategy A — port ICU's own astronomy
Port `chnsecal.cpp` + the needed parts of `astro.cpp` (ICU's
CalendarAstronomer, Duffett-Smith-based) to Swift.
- **Pros:** parity by algorithm fidelity for ALL dates; no baked data; no
  range policy needed.
- **Cons:** ~1,000+ lines of delicate float astronomy; parity requires
  matching ICU's floating-point behavior (same IEEE doubles and same libm
  on-platform — likely fine on macOS, watch trig-boundary flips on other
  platforms); slow (ICU-class performance unless we add caching); biggest
  review surface upstream.

### Strategy B — bake a table FROM ICU (recommended)
Generate year data by sweeping `_CalendarICU(.chinese)` day-by-day right
here (we have ICU in-process), pack it like icu4swift's
`PackedChineseYearData` (UInt32/year: 13-bit month lengths + 4-bit leap
month index + new-year offset bits), and implement all field math as bit
ops over the packed year.
- **Pros:** parity **by construction** in range; icu4swift's proven
  architecture (its packed accessors ran at ~5 ns); tiny data (~4 KB for
  1,000 years); ICU4X itself ships precomputed Chinese data — strong
  precedent to cite in the PR; generation and verification are the same
  sweep probe.
- **Cons:** bounded range → needs an out-of-range policy (below); the
  generator must interpret ICU's edge conventions correctly (the sweep
  probes make errors visible immediately).
- **Range suggestion:** 1600–2600 (~4 KB), covering any plausible use with
  huge margin.
- **⚠ SIZE IS THE TOP UPSTREAM CONCERN (user, 2026-07-17).** Binary size
  is the swift-foundation reviewers' biggest sensitivity — every byte of
  baked data and every line of fallback code must be justified in the PR,
  never dismissed as negligible. Argue size comparatively and offer
  tiers; let the reviewers pick.
- **Size tiers (UInt32/year = 4 B/yr; ICU4X-style 3 B packing = ×0.75):**

  | Range | Years | UInt32 | 3-byte |
  |---|---|---|---|
  | 1901–2099 (icu4swift-equivalent) | 199 | 796 B | 597 B |
  | 1900–2100 (Apple-table range) | 201 | 804 B | 603 B |
  | 1800–2200 | 401 | 1.6 KiB | 1.2 KiB |
  | 1700–2300 | 601 | 2.3 KiB | 1.8 KiB |
  | 1600–2600 | 1,001 | 3.9 KiB | 2.9 KiB |

  **How to use the Apple ICU comparison (user, 2026-07-17):** it is fine
  to cite it as an EFFICIENCY point — "our day-packed table is ~15×
  denser per year than the ~11.8 KB of tables ICU carries internally for
  1900–2100" — but NEVER as an offset/replacement argument. The
  pure-Swift ports are ADDITIVE: `swift-foundation-icu` stays linked and
  its tables stay in the binary; every byte we add is on top. "Ours is
  smaller than what ICU ships" justifies nothing; "our packing is
  15× denser than ICU's approach" shows the addition is as small as the
  problem allows.
  Legitimate size arguments only: (a) exact absolute cost per tier, with
  the minimal viable range as default; (b) densest packing (3 B/yr);
  (c) table-vs-code: for the covered years a table may be a SMALLER
  binary addition than the compiled astronomy fallback code that would
  otherwise serve them — measure both and present the numbers; (d) this
  would be the first substantial baked table in the pure-Swift calendars
  (Hebrew/Buddhist/Japanese are algorithmic + a small era list), so
  expect maximum scrutiny.
- **Fallback code size counts too** under size-first review. Measured
  back-of-hand (2026-07-17, from icu4swift sources / the verified DS
  port / merged upstream ports):

  | Component | Source LOC | Const data | Rough binary* |
  |---|---|---|---|
  | Calendar_ChineseTraditional class (anchor: Calendar_Hebrew = 1,840 LOC) | ~1,800–2,200 | — | ~60–80 KB |
  | Packed year table + bit accessors | ~120 | 0.8–3.9 KiB | ~5 KB + data |
  | **Reingold (Meeus) fallback, Chinese subset** | ~400 | ~3 KB (≈395 coefficients) | **~15–20 KB** |
  | **Duffett-Smith fallback** (verified port) | ~340 | ~0.3 KB | **~12–14 KB** |
  | **Moshier (IF ever added)** — solar 728 + lunar 661 + engine 80 LOC (+154 sunrise for Hindu) | ~1,470 (~1,650 w/ sunrise) | **~15 KB** (~1,800 VSOP87/DE404 series terms) | **~40–45 KB** |
  | Clamp (no fallback) | ~0 | — | ~0 |

  \* rule-of-thumb 30–50 B machine code per numeric-Swift LOC; treat as
  order-of-magnitude only, measure the real delta at M-final.
  Notes: DS is actually the SMALLEST astronomy option (its truncated
  series are exactly why it's inaccurate); Reingold costs ~+60 LOC and
  ~3 KB more for the measured accuracy win; **Moshier is ~3× the entire
  Reingold engine and stays OUT of the Chinese PR** — it becomes its own
  justified addition when Hindu calendars land (they genuinely need it),
  and the engine-seam design makes adding it later drop-in. Omitting
  Moshier loses NOTHING for Chinese (measured: 0/3,119 month starts
  differ from Reingold on the 1700–1900/2100–2150 shoulders; the one
  divergent year in ~900, 1571, is outside Moshier's validity window).
  A smaller baked range shifts more years onto the fallback engine —
  under a size-capped review the sweet spot may be a narrower table +
  fallback rather than the widest table.
- **Packing bounds verified over 1600–2600** (2026-07-17): new-year
  offset from Jan 19 spans 2–61, so the 6-bit field (0–63) holds, with 9
  spare bits in the UInt32 if a swept value ever exceeds it; the 60–61
  cases are rare leap-M11/M12 years (1681, 1776, 1871, 2501, 2558, 2596 —
  some engine-sensitive, e.g. 1681), so the generator MUST assert offset
  bounds during the `_CalendarICU` sweep.
- **Out-of-range policy options** (decide with strategy):
  1. Fall back to `_CalendarICU`-matching *arithmetic approximation* —
     hard to make parity-clean; probably wrong choice.
  2. Port the astronomy ONLY as fallback (Strategy A shrunk to a
     correctness-nonessential path) — originally assumed "most work";
     § 5b research (2026-07-17) shows the needed subset is only
     ~300–340 Swift LOC.
  3. Clamp/saturate at range edges and document — simplest; ICU itself is
     astronomically dubious far out; probes then cover in-range only, with
     the boundary behavior explicitly tested and documented.
- **What ICU4X actually does out of range** (verified in source
  2026-07-17: `components/calendar/src/cal/east_asian_traditional.rs`
  `Rules::year` for `China`, + `east_asian_traditional/simple.rs`):
  baked table 1912–2099 (GB/T 33661-2017 rules) → second baked table
  1900–1911 (Qing, KASI/HKO-confirmed) → outside both, a *píngqì*-style
  **mean-value arithmetic** fallback (`EastAsianTraditionalYear::simple`):
  mean Gregorian year length for solar terms, mean synodic month anchored
  to one real new moon (2000-01-06 18:14 UTC) and one real solstice
  (1999-12-22 07:44 UTC), pure integer-millisecond math, valid ±292M
  years. **No astronomy at runtime** — the astronomical path survives only
  as the data-generation helper `China::gb_t_33661_2017()`. So ICU4X
  already diverges from ICU4C outside 1900–2099: precedent that upstream
  considers out-of-range fidelity negotiable, but its fallback (a variant
  of option 1) matches neither ICU4C nor clamping.
- **DECISION LEANING (2026-07-17, revised after § 5b research):
  ReingoldEngine-style (Meeus) fallback** — ship the more-accurate
  astronomy out of range, accepting the documented ~1% month-start
  divergence from today's Foundation there (§ 5b Q2; the divergences are
  cases where ICU is astronomically wrong — Moshier referee 45–0). A
  faithful Duffett-Smith port exists as a **dormant contingency** in
  `<swift-foundation>/backup/duffett-smith-port/` (see § 5b Q3/Q4), so
  switching later is a drop-in if upstream review demands ICU-exact
  out-of-range behavior.
  **⚠ NOTE FOR THE MACHINE CREATING THE REAL FEATURE BRANCH (6.4
  machine): the Duffett-Smith port must NOT be included in the feature
  branch / PR unless the user explicitly agrees. It is a contingency
  artifact only. Copy this warning into `CHINESE_6.4_HANDOFF.md`.**

**Recommendation: B.** It's the icu4swift architecture with ICU replacing
HKO as the data source, it matches ICU4X's own approach, and it converts
the parity problem into a generation+verification problem we can brute-force
with in-process ICU.

### 5b. Out-of-range engine research (2026-07-17)

Empirical adjudication of ReingoldEngine (Meeus polynomials, icu4swift's
out-of-range fallback) vs ICU4C's Duffett-Smith `CalendarAstronomer`, plus
a sizing of a faithful Duffett-Smith Swift port. Method: a scratch harness
(faithful copy of icu4swift `ChineseYearData.compute`, parameterized by
engine + meridian) compared year structures against ICU via the macOS
system `Calendar(identifier: .chinese)` (Apple ICU ≈ upstream
chnsecal/astro), with the HKO CSV as authority in 1901–2099. Sweeps:
1500–1699 and 2151–2350. Harness preserved at
`backup/chncmp-harness/` (validated by reproducing the known
1906 Apr 23/24 Moshier-vs-HKO divergence exactly).

**Q2 — actual discrepancy measurements:**

- **Skill vs HKO, 1901–2099 (2,461 month starts):** Reingold misses **1**
  (the same 1906 M04 case Moshier misses — both engines, same day).
  ICU misses **3** (1914 M10, 1916 M01, 1920 M10, all +1 day) — including
  **Chinese New Year 1916: ICU says Feb 4, HKO and the historical record
  say Feb 3**. In the authoritative range, our fallback engine is
  measurably MORE accurate than ICU's.
- **Past 1500–1699 vs ICU:** shipping config (Reingold + pre-1929 Beijing
  LMT): 31/2,450 month starts differ (all ±1 day), 10 years with
  leap-placement/numbering label differences, and 2 structural years —
  incl. **1681 where Chinese New Year differs by a full month** (leap
  placement flips which new moon is M01). With the meridian equalized to
  UTC+8, 21/2,437 differ — i.e. ~⅓ of the shipping divergence is the
  meridian convention, ⅔ is the ephemeris.
- **Future 2151–2350 vs ICU:** 25/2,423 month starts differ (±1 day),
  5 label-mismatch years, and CNY-by-a-month cases at 2243 and 2319.
- **Reingold vs Moshier agree almost perfectly with each other:** future
  200/200 years identical; past 199/200 (one leap-detection flip at 1571).
- **Referee (Moshier = closest-to-modern-ephemeris proxy): on all 45
  Reingold-vs-ICU disagreements across both sweeps, Moshier sides with
  Reingold 45–0.** ICU's Duffett-Smith (pure UT, no ΔT, truncated lunar
  series) is the outlier, not our fallback.
- Rates: ~1% of month starts shift ±1 day vs ICU out of range; ~15% of
  years show SOME visible difference; ~1% of years shift Chinese New Year
  by a whole month.
- **Who actually runs where (don't misread the in-range numbers):** the
  1901–2099 skill-vs-HKO figures are FORCED-ENGINE benchmarks — a way to
  score each engine's astronomy against authority where authority exists.
  No shipping config runs Reingold or Duffett-Smith there: icu4swift ships
  the baked HKO table in 1901–2099, Moshier (via HybridEngine) in
  1700–1901 and 2099–2150, Reingold only outside 1700–2150; Foundation
  ships Apple's baked tables in 1900–2100 (see MAJOR DISCOVERY below).
  For the swift-foundation port with a 1600–2600 baked range, the
  fallback domain (<1600, >2600) lies ENTIRELY outside Moshier's validity
  window (~1700–2150) — which is exactly why the fallback fight is
  Reingold-vs-Duffett-Smith only, and porting Moshier (thousands of LOC of
  VSOP87/DE404) buys nothing: its whole usable window sits inside the
  baked range.
- **Moshier vs Reingold, measured (2026-07-17):** on the shoulders where
  icu4swift's Hybrid actually runs Moshier (1700–1900, 2100–2150) the two
  engines are **day-for-day identical** — 0 differing month starts /
  3,119, no label or new-year differences across 252 years. Across ALL
  ~900 years compared today, they differ in exactly one year (1571 — a
  leap-detection flip, outside Moshier's 1700–2150 fit range, where
  Reingold is the appropriate engine anyway) and share the same single
  1906 HKO miss. Moshier IS more precise at the instant level (VSOP87 /
  DE404, validated to 0.00001° against Swiss Ephemeris/JPL DE431, vs
  Meeus polynomials at ~minute level), but a minute-class error only
  matters when an event falls within ~a minute of local midnight —
  empirically ~never at day level in these ranges. Consequence: a
  Reingold-only fallback loses nothing measurable vs a Moshier port.

**Q3 — Duffett-Smith port size (from astro.cpp dependency analysis):**
far smaller than § Strategy A's "~1,000+ lines" assumption, because the
Chinese path needs only a subset and the equatorial-coordinate machinery
is dead code for it. Needed: `getSunLongitude`/`trueAnomaly` (2-body
Kepler sun), `getMoonPosition` through ecliptic longitude only,
`getMoonAge`, `timeOfAngle` root-finder, `getSunTime`/`getMoonTime`,
norm helpers ≈ 160 executable C++ LOC → **~170 Swift LOC**; chnsecal
astronomy glue (`winterSolstice`, `newMoonNear`, `majorSolarTerm`,
`hasNoMajorSolarTerm`, `isLeapMonthBetween`, `computeMonthInfo`,
`newYear`) ≈ 155 executable C++ LOC → **~135 Swift LOC**. **Total ≈
300–340 Swift LOC.** Day-for-day parity hazards to port verbatim: Kepler
eps `1e-5` + exact Newton update; `timeOfAngle`'s `ceil()` millisecond
stepping, `MINUTE_MS` termination, and its recursive anti-divergence
restart; **NO ΔT anywhere (ICU works in pure UT — do not "fix" this)**;
flat UTC+8 (`CHINA_OFFSET`) for ALL dates; `floorDivide` (toward −∞) in
day↔millis; `floor`-based angle normalization (not `fmod`);
truncation-toward-zero int casts; epoch literals (`JD_EPOCH = 2447891.5`,
`JULIAN_EPOCH_MS = -210866760000000.0`, `SYNODIC_MONTH = 29.530588853`).
Bit-for-bit is unattainable cross-platform (libm last-ULP), but all
outputs truncate to integer days, so day-parity is achievable.

**Q4 — cost of shipping Reingold first, switching to Duffett-Smith
later:** integration is trivial either way if the fallback sits behind an
engine boundary (icu4swift's `AstronomicalEngineProtocol` pattern, <50
LOC of glue). The switch cost = the ~340-LOC port (Q3) + regenerating
out-of-range expectations + **a second upstream review round, because the
switch changes observable out-of-range dates** — the dominant cost is
process, not code. Corollary: with a Duffett-Smith fallback the parity
probe can extend BEYOND the baked range (full-range zero divergence vs
`_CalendarICU`); with a Reingold fallback, out-of-range diverges from
current Foundation at the ~1% rate above but is demonstrably more
accurate astronomy.

**Q1 — reference sources outside 1700–2150 (who is REALLY right):**

| Source | Range | Basis | Type | Access |
|---|---|---|---|---|
| Yuk Tung Liu, ChineseCalendar | 722 BCE–2200 CE | JPL **DE441** + Stephenson/Morrison ΔT | BOTH: modern-rules times published for all years "for reference"; calendar dates corrected to promulgated history pre-1912 | GPL-3.0, re-runnable (github.com/ytliu0/ChineseCalendar, /ChineseCalendar-python) |
| Liu, Shixian pages | 1645–1911 | Historical Shixian method reconstruction | as-promulgated | web only (bot-blocked) |
| Academia Sinica converter | 1 CE–2101 | Xue/Ouyang 1940 tables | as-promulgated | web form, no bulk |
| Zhang Peiyu 三千五百年历日天象 | 722 BCE–2050 | academic recomputation | as-promulgated | paper only |
| Aslaksen | 1645–2644 | Meeus-class Mathematica | modern-rules proleptic | paper + notebook |
| sxwnl 寿星天文历 | −3000–+3000 | DE-fit + table corrections | hybrid | open source |

- **Best engine-adjudication ground truth: Liu (DE441)** — uniquely
  publishes modern-method new-moon/solar-term instants even for pre-1912
  years, and the code is re-runnable. Our referee finding (Moshier 45–0
  for Reingold over ICU) can be independently confirmed against DE441
  instants if ever challenged.
- **Do NOT use pre-1912 calendar DATES as engine ground truth** — the
  promulgated calendar was computed at the Beijing meridian in apparent
  solar time with historically imperfect methods (Liu counts **>200
  Qing-era month-start mismatches** vs modern computation), and pre-1645
  the rule system itself differed (mean-qi 平氣 solar terms). NO engine
  running modern rules matches pre-1912 history; "correct" out-of-range
  means "closer to DE441", nothing more.
- **ΔT uncertainty bounds what's knowable**: σ ≈ 20 s at 1500 CE, ~55 s
  at 1000 CE, ~140 s at 500 CE, and ~2.4 min at 2200 / ~4.5 min at 2300
  (extrapolation). Liu flags 8 lunar conjunctions + ~10 solar terms in
  2051–2200 as day-level uncertain in principle — engine disagreements on
  those dates are unadjudicable, and a flipped solar term near a boundary
  can relocate an entire leap month.
- Note: ICU's `CalendarAstronomer` applies **no ΔT at all** (pure UT), so
  its event instants drift from DE441 by roughly ΔT itself going back —
  ~3 min at 1600, ~26 min at 1000, ~95 min at 500 CE. Its out-of-range
  disadvantage GROWS with distance; the 45–0 referee result is not a
  statistical fluke but structural. (Inference from the no-ΔT finding +
  NASA ΔT tables.)

**MAJOR DISCOVERY (2026-07-17, while verifying the Duffett-Smith port):
Apple ICU is NOT pure Duffett-Smith in 1900–2100.** `swift-foundation-icu`
(what `_CalendarICU` links) carries `APPLE_ICU_CHANGES` that replace the
astronomy in Gregorian 1900–2100 with baked tables: `astro.cpp` embeds
~2,500 new-moon instants (`newMoonDates[]`) and piecewise sun-longitude
corrections (`sunLongitudeAdjustmts[][4]`) — rdar://15539491&16688723,
Apple's comment: *"faster and much more accurate (e.g. accurate to one
minute of time instead of 25, 60, or worse)"* — plus chnsecal-level
`newYearAdj[201]`/`winterSolsticeAdj` day tables (rdar://17888673).
Outside 1900–2100 Apple falls back to pure upstream Duffett-Smith.
Upstream OSICU has none of this. Note rdar://136543653: the newYear
adjustment table applies to chinese but NOT dangi.

Consequences:
- The § 5b Q2 "ICU" measurements split in two: **ICU-as-shipped**
  (Apple tables) misses 3 month starts vs HKO in-range; **pure
  Duffett-Smith** (upstream algorithm, what runs outside 1900–2100)
  misses **15** — measured via the contingency port. Reingold misses 1,
  Moshier 1. The correctness ranking out of range is therefore even more
  lopsided than the 45–0 referee suggested.
- **Strategy B is vindicated again**: sweeping the baked table from
  in-process `_CalendarICU` captures Apple's table behavior in 1900–2100
  by construction. A port of upstream ICU code (or upstream ICU4X data)
  would NOT match Foundation there.
- With the suggested 1600–2600 baked range, `_CalendarICU` outside the
  baked range is pure Duffett-Smith — exactly what the contingency port
  reproduces.

**Contingency port status: BUILT and VERIFIED** (2026-07-17,
`backup/duffett-smith-port/`, ~340 Swift LOC + harness): **0 divergent
days / 146,827** vs system ICU across 1500–1700 + 2150–2350 (the
out-of-range domain it would serve). The 1900–2100 differences vs system
ICU (538 days / 16 month-runs) are exactly Apple's baked tables, by
design out of the port's scope. ⚠ NOT for the feature branch — see § 5.

**Consequence for the M0 decision:** both options got cheaper/sharper.
The Duffett-Smith port is small (~340 LOC), so "option 2" is no longer
"most work"; and Reingold is now *proven* more accurate (45–0 referee,
fewer HKO misses in-range). The fork is purely **compat-with-today's-
Foundation vs astronomical correctness**, and the in-range version of the
same fork is now concrete too: bake-from-ICU ships ICU's 3 named HKO
misses (incl. CNY 1916 Feb 4 vs Feb 3); bake-from-HKO fixes them but
breaks the zero-divergence bar on those dates.

### 5c. M0 DECISIONS (2026-07-17) + remaining gaps

**DECIDED by user:**
1. Implement the Chinese calendar core file (Calendar_ChineseTraditional).
2. Fallback engine: **Reingold (Meeus), Chinese subset** (~400 LOC, ~3 KB consts).
3. **Duffett-Smith verified port stays on the research branch ONLY** —
   never enters the main PR branch without explicit user agreement (§ 5 ⚠).
4. **No Moshier** (zero measured loss for Chinese — § 5b; it arrives later
   with Hindu, where it's genuinely needed).
5. Baked table: **RANGE DECIDED 2026-07-17 (late): Chinese years
   1901–2100** — aligned to the HKO-attested range ("choose a year (1901
   to 2100)" per HKO's own site), 200 × UInt32 = 800 B, trivially
   expandable later. Table values swept from `_CalendarICU` (parity);
   HKO = day-level cross-check over the same span. Note (user's call,
   4-byte cost): Apple's ICU adjustment tables start at GREGORIAN 1900,
   so Chinese year 1900 (Jan 31 1900 – Feb 18 1901) falls to our
   fallback while `_CalendarICU` still uses Apple table data there — the
   parity probe will show whether that single year diverges; adding a
   1900 row (+4 B) would eliminate the only fallback year inside Apple's
   table zone. The earlier 1700–2150-vs-1900–2100 debate is CLOSED in
   favor of the HKO-aligned range; § 5c adjudication evidence defends
   the out-of-range divergences.
6. Exhaustive tests: port icu4swift Chinese tests where possible; update
   Foundation benchmark tests; measure ICU-vs-ours via feature-flag flip
   (Hebrew flag-flip methodology, see `backup/` bench docs).

**⚠ CRITICAL DESIGN FINDING (experiment, 2026-07-17 late): the fallback
must be chnsecal RULES + Reingold INSTANTS — never a port of icu4swift's
`ChineseYearData.compute`/`findNewYear` heuristic.** The CNY-by-a-month
pathologies below (1776 Mar 20 etc.) were reproduced by BOTH Reingold and
Moshier under icu4swift's heuristic — and then eliminated by running
ICU's chnsecal rules layer (computeMonthInfo/isLeapMonthBetween/newYear,
ported verbatim in `backup/duffett-smith-port/ReingoldChineseAstro.swift`)
over Reingold instants with flat UTC+8: CNY 1776 = Feb 19 ✓ (matches ICU
and the historical record), CNY 1871 = Feb 19 ✓, 1775/1870 keep their
historical leap-10th months ✓, adjacent years tile (icu4swift's heuristic
produced NON-TILING adjacent years — a real bug in the frozen library,
e.g. the month starting 1776-02-19 belonged to no year). Also: the
fallback meridian must be **flat UTC+8** (ICU convention), not icu4swift's
pre-1929 LMT. Residual rules+Reingold vs ICU divergence: 1700–1899 =
173/200 years clean, 10 label-diff years, 18/2,346 ±1-day starts;
2101–2150 = 44/50 clean, 2 label-diff years, 4/594. The surviving
label diffs are adjacent-leap-placement disputes (1727 m2L/m3L, 1800
m4L/m5L, 1805 m6L/m7L, 1827 m5L/m6L) and year-end leap-M12/M1 disputes
that still move CNY (1795, 1814, 1890, 2148) — where ICU asserts
historically near-impossible leap 12th/1st months (m12L 1794/1813/1889,
m1L 2148).

**REFERENCE ADJUDICATION (2026-07-17, triangulated: Liu's promulgated
Qing tables + sxtwl + independent PyEphem recomputation, zero mutual
divergences):** on every contested CNY case, **the port's fallback design
(chnsecal rules + Reingold + UTC8) matches the authoritative record and
ICU is wrong**:

| CNY | Reference (promulgated + modern rules) | Fallback design | ICU / Foundation today | icu4swift heuristic |
|---|---|---|---|---|
| 1776 | Feb 19 (N1775 = 闰十月) | **Feb 19 ✓** | Feb 19 ✓ | Mar 20 ✗ |
| 1795 | **Jan 21** (N1795 闰二月 Mar 21) | **Jan 21 ✓** | Feb 19 ✗ (fake m12L 1794) | Jan 21 ✓ |
| 1814 | **Jan 21** (N1814 闰二月; the revoked-闰八月 year, Veritable Records Vol 242) | **Jan 21 ✓** | Feb 20 ✗ (fake m11L 1813) | Jan 21 ✓ |
| 1871 | Feb 19 (N1870 = 闰十月) | **Feb 19 ✓** | Feb 19 ✓ | Mar 21 ✗ |
| 1890 | **Jan 21** (N1890 闰二月) | **Jan 21 ✓** | Feb 19 ✗ (fake m12L 1889) | Jan 21 ✓ |
| 2148 | **Feb 20** (N2147 = 闰冬月/leap 11th, Dec 23 2147) | **Feb 20 ✓** | Jan 21 ✗ (fake m1L 2148) | Feb 20 ✓ |

Scorecard vs the record: fallback design **6/6**, icu4swift heuristic
4/6, **ICU 2/6**. ICU's misses are exactly its 25–60-minute astronomy
class: e.g. Chunfen 1795 fell 23:03 UTC+8 (57 min from midnight) — inside
ICU's error bar, outside Reingold's.

**Adjacent-leap years ADJUDICATED (2026-07-17 late; Liu promulgated data
+ Academia Sinica converter + huaxia recomputed table):** all four hinge
on a zhōngqì just past midnight UTC+8 (Reingold & Moshier agree within
1 min): Guyu 1727 00:39, Xiazhi 1800 01:51, Chushu 1805 00:06, Dashu
1827 01:15 — our design puts the term in the later month (leap earlier),
ICU's cruder astronomy flips it.

| Leap of | Promulgated (Shixian) | Modern recomputation (huaxia) | Fallback design | ICU |
|---|---|---|---|---|
| 1727 | 闰三月 Apr 21 | 闰二月 Mar 23 | 闰二月 ✗prom/✓modern | 闰三月 ✓prom/✗modern |
| 1800 | 闰四月 May 24 | 闰四月 (same) | **闰四月 ✓✓** | 闰五月 ✗✗ |
| 1805 | 闰六月 Jul 26 | 闰七月 Aug 24 | **闰六月 ✓prom**/✗huaxia | 闰七月 ✗prom/✓huaxia |
| 1827 | 闰五月 Jun 24 | 闰五月 (same) | **闰五月 ✓✓** | 闰六月 ✗✗ |

1727 and 1805 are genuine promulgated-vs-modern divergence years (the
Imperial Bureau computed in Beijing APPARENT time with pre-modern
tables; Liu documents 200+ such mismatches over 1645–1911 and corrects
his tables to the promulgated record) — no modern-rules engine can match
1727-promulgated except by accident; ICU matches it by accident of its
error. At 1800/1827 ICU disagrees with BOTH conventions — flat wrong.

**GRAND TOTAL over all 10 adjudicated label disputes: fallback design
9/10 vs the promulgated record (sole miss = 1727, a convention case,
where it instead matches modern rules), ICU 3/10.** Remaining
unadjudicated: only the ±1-day starts (18+4 per 250 yrs), where Moshier
and PyEphem spot-checks consistently side with Reingold.

**Adjudication sources & reliability (for PR defense):**

Four INDEPENDENT verification chains agreed with zero mutual divergences
on every checked date (~20 boundary dates, ~150 month starts across the
16 focus years):

1. **Yuk Tung Liu, ChineseCalendar** (backbone) — DE441 + Stephenson/
   Morrison ΔT + GB/T 33661-2017; for 1645–1911 corrected to the
   promulgated Shixian calendar against PMO's 新编万年历, preserved
   Shixian calendars from 1840, and Zhang Peiyu, with the 200+
   corrections documented; cites primary sources (1813: Veritable
   Records of Renzong Vol 242); found errors in ALL four standard
   references for 11 Ming dates — i.e., he checks against surviving
   original calendars. GPL, re-runnable, data decoded directly from
   `src/calendarData.js` (decode validated on known years 2023/2020/
   2017/1984). Reliability: HIGH, but single-maintainer scholarship.
   https://ytliu0.github.io/ChineseCalendar/ (computation.html,
   rules.html, table.html?period=qing, leap_month_1_12.html;
   github.com/ytliu0/ChineseCalendar)
2. **Academia Sinica sinocal** — institutional (Taiwan national academy);
   independent lineage (Xue Zhongsan & Ouyang Yi 1940 對照表, the
   standard sinological reference). Confirmed all eight 1727/1800/1805/
   1827 boundary dates against Liu. Known to contain rare errors (the 11
   Ming dates), none in our range. Reliability: HIGH, independent of
   Liu. https://sinocal.sinica.edu.tw/
3. **sxtwl / 寿星万年历** — independent open-source codebase, checked
   against Zhang Peiyu/Chen Yuan/Fang Shiming for −721..1960; agreed on
   all 12 focus lunar years. Reliability: GOOD. github.com/sxwnl/sxwnl
4. **PyEphem recomputation** (agent's own, methodologically independent)
   — modern ephemeris; matched all ~150 promulgated month starts;
   astronomy-only cross-check, not a record source.

**HKO provenance for the MAIN (baked) range — fully documented and
locally archived** (verified 2026-07-17): icu4swift
`Docs/Chinese_reference.md` records the complete chain — official HKO
per-year files `https://www.hko.gov.hk/en/gts/time/calendar/text/files/
T{YEAR}e.txt` (1901–2100, 404 outside), the exact curl loop used, **all
200 raw files preserved verbatim** at icu4swift `Data/hko_raw/` (5.7 MB,
re-verifiable without refetching), the parser `Data/build_hko_csv.py`,
the leap-encoding convention (same month number twice in a row), and the
derived CSV schema (2,461 rows, Chinese years 1901–2099).

**Exact HKO coverage (live-reverified 2026-07-17: T1900e/T2101e → 404,
T1901e/T2100e → 200): every Gregorian DAY from 1901-01-01 through
2100-12-31 (73,049 days) carries an attested lunar date.** That is more
than the month-rows CSV exposes: T1901e opens with 1901-01-01 = day 11
of month 11 of CHINESE year 1900 (so Chinese 1900's m11 start Dec 22
1900 is recoverable by back-counting, and its m12 is fully attested),
and T2100e closes with 2100-12-31 = **day 1 of month 12 of Chinese year
2100** — all of Chinese 2100's month starts are attested; only m12's
length (needs CNY 2101) is not. The CSV drops Chinese 1900 and 2100 only
because its month-row schema needs a closing boundary.

**Action for the port — extract at DAY level, not month level:** build
the HKO cross-check expectation directly from the 200 raw files (already
archived at icu4swift `Data/hko_raw/`, 5.7 MB) as a day→(month, day,
isLeap) mapping. That uses all 73,049 attested days with zero waste,
naturally covers the Chinese-1900 tail and Chinese-2100 head that the
month-row CSV drops, and matches the shape of the port's daily parity
sweeps. Keep the CSV too for month-structure tests. Copy both + a
provenance citation into swift-foundation test resources. Remaining true
gaps for a 1900–2100 table: Chinese 1900 months 1–10 (cover via ICU4X
qing_data (KASI+HKO-confirmed), PMO 1900–2025, or Liu) and Chinese
2100's m12 length (Liu to 2200).

Supporting/context sources, correctly weighted: **huaxia 1645–2644
leap table** is a modern RECOMPUTATION, not the promulgated record
(proven: contradicts promulgated 1645/1727/1805) — used only as the
modern-rules column; **Baidu Baike / 老黄历** tertiary spot-checks only,
no load-bearing weight; **HKO** official for 1901–2100 (already our
regression source); **Zhang Peiyu 3500 Years** reaches us via Liu/sxtwl
(Liu maintains an errata page for it).

Weakest link, stated honestly: the promulgated-record verdicts trace to
Liu's and Xue/Ouyang's scholarship rather than our own archival reading
of Qing documents — mitigated by the four-chain agreement, the primary
citation for 1813, and contemporary-usage corroboration for 1727
(雍正五年闰三月 in Veritable-Records-era inscriptions).

**Range-tier framing REVISED by the adjudication:** the earlier
"1776 looks damning → widen to 1700–2150" reasoning is DEAD — that
pathology belonged to icu4swift's heuristic, and in the genuinely
contested years our fallback is RIGHT where Foundation today is WRONG.
The choice is now: **1900–2100 (correctness-first)** — fallback fixes
ICU's three wrong Qing CNYs + 2148, divergence defensible with citations
(Liu/sxtwl/PyEphem); vs **1700–2150 (parity-first)** — bakes ICU's wrong
1795/1814/1890 as bug-for-bug parity data. Both protocol-compliant
(zero-divergence gate is scoped to the baked range). User's original
1900–2100 choice is now well-armed; final call at M1.

**⚠ MEASURED CONSEQUENCE of the 1900–2100 range (probe G, 2026-07-17):**
the live fallback zone becomes 1700–1899 + 2101–2150, and Reingold-vs-ICU
there is NOT quiet: 1700–1899 has 41/2,374 month starts ±1 day, and **7
years where Chinese New Year itself moves — several by a full month
(1776, 1795, 1814, 1871, 1890)**; 2101–2150 has 4/594 + CNY-2148 by a
month. The CNY-month cases are leap-placement flips — NOT adjudicated by
the 45–0 referee (that covered same-label months only), and at least 1776
(historical CNY = Feb 19, matching ICU) looks bad against every published
table. Mitigation options: (a) widen table to **1700–2150 (~1.8 KiB)** —
kills every measured bad-look case for +1 KiB, fallback then serves only
<1700/>2150; (b) widen to 1600–2600 (3.9 KiB); (c) keep 1900–2100 and
document. **Recommendation: (a).** Decide before M1.

**Remaining gaps / landmines to plan for:**
- **Parity-probe scoping:** zero-divergence gate applies INSIDE the baked
  range only; outside, divergence from ICU is intentional (documented
  rates above) — probes must report, not gate, there.
- **Apple d0 artifact (IN table range):** system ICU emits impossible
  day=0 fields around 2057-09 and 2097-07 (its pinned tables clash with
  live moon astronomy). Verify whether `_CalendarICU` reproduces this;
  our packed table cannot represent d0 — expect a few days of irreducible
  divergence there; investigate + document (or special-case) at M2.
- **HKO regression conflict:** the ported HKO regression WILL fail at
  1914 M10, 1916 M01, and 1920 M10 by construction — the table is
  ICU-parity, and ICU differs from HKO at exactly those 3 month starts.
  Encode them as expected divergences in the ported test.
- **Era/cycle semantics:** match `swift-foundation-icu` (_CalendarICU),
  NOT the local upstream ICU 79 checkout — upstream changed the Chinese
  epoch to 1 CE (ICU-23167) and Apple's fork may not have it. Let probes
  decide every field convention.
- **Dangi: OUT OF SCOPE for this effort (user, 2026-07-17).** Not in the
  PR, not on the branch. Probes stay parameterized so a future Dangi
  effort is cheap; note for then: Apple's newYearAdj is NOT applied to
  dangi (rdar://136543653) while winterSolsticeAdj appears unconditional —
  Dangi's parity target differs from Chinese.
- **Standalone PR vs bundle (§ 10 Q3) unconfirmed** — standalone still
  recommended.
- Mechanical checklist: CMakeLists registration for every new file;
  feature-flag/router wiring; `hasRepeatingMonths`/`isLeapMonth`
  plumbing verification (Hebrew prior art); sub-day/timezone semantics
  follow the Hebrew pattern; EXPECTED_TIMES.md entries for new benches;
  `clean-test.sh` after class-layout changes (new calendar class!);
  CHINESE_6.4_HANDOFF.md must carry the § 5 DS-exclusion warning.

## 6. Source materials (the quarry)

- **icu4swift** (FROZEN — read, never edit):
  `/Users/draganbesevic/Projects/claude/CalendarAPI/icu4swift`
  - `Sources/CalendarAstronomical/` — Chinese + Dangi: `ChineseYearTable`
    (199 baked years 1901–2099, HKO-sourced), `PackedChineseYearData`
    (UInt32 packing — reuse the bit layout), `ChineseYearCache` (LRU-8),
    `ChineseYearData.compute` (findNewYear × 2, iterate 12 months, "13th
    month is leap if no leap detected" fallback — mirrors ICU4X
    `month_structure_for_year`).
  - `Docs/Chinese_reference.md`, `Docs/Chinese.md` — validation
    methodology and the 1906 HKO-divergence cluster writeup.
  - Packing-in-`DateInner` trick: store the packed year word inside the
    date's inner representation so accessors never re-look-up.
- **ICU4C**: `../icu/icu4c/source/i18n/chnsecal.{h,cpp}` (ChineseCalendar
  — epoch, cycle math, leap rules, CHINA zone constants),
  `astro.{h,cpp}` (CalendarAstronomer), `dangical.cpp` (Dangi deltas).
- **ICU4X**: `../icu4x/components/calendar/src/cal/chinese.rs` +
  `chinese_based` internals — the precomputed-data precedent.
- **Apple ICU**: `../swift-foundation-icu/icuSources/i18n/chnsecal.cpp` —
  check `APPLE_ICU_CHANGES` blocks for Apple-specific deltas (the Meiji
  lesson: Apple's runtime can differ from upstream data).
- **swift-foundation prior art**: `Calendar_Hebrew.swift` (RD-based
  arithmetic implementation shape, isLeapMonth handling, YearData cache),
  `Calendar_Buddhist/Japanese.swift` (flag wiring, probe patterns),
  `_CalendarUtility`/`_CalendarConstants` (shared helpers — USE them).

## 7. Implementation sketch

Files (remember **CMakeLists.txt registration** — `Sources/FoundationEssentials/Calendar/CMakeLists.txt`; the 6.4 machine caught this for B/J):
- `Sources/FoundationEssentials/Calendar/Calendar_Chinese.swift` —
  `_CalendarChinese: _CalendarProtocol`. NOT Gregorian composition; a full
  implementation like Hebrew: RD ↔ (cycle, year, month, isLeap, day) via
  packed year data; week fields via shared utilities matching ICU.
- Baked table: either in-file (Hebrew keeps everything in one file) or
  `Calendar_ChineseData.swift` — 200 packed UInt32s (1901–2100, § 5c) —
  in-file should be fine at this size.
- **Fallback (out of 1901–2100), per § 5c decisions:** chnsecal RULES
  layer + Reingold (Meeus) instants + flat UTC+8. Two pieces: (a) the
  Reingold Chinese subset (~400 LOC: solar longitude, nth-new-moon,
  estimatePriorSolarLongitude — port from icu4swift
  ReingoldSolar/ReingoldLunar, sunrise NOT needed); (b) the rules layer —
  port from the PROTOTYPE `backup/duffett-smith-port/Sources/dsverify/
  ReingoldChineseAstro.swift` (verbatim chnsecal computeMonthInfo/
  newYear/isLeapMonthBetween over engine primitives), NOT from
  icu4swift's ChineseYearData.compute (known non-tiling bug, § 5c).
  Keep terse comments (upstream reviewer preference).
- `Calendar_Cache.swift`: `foundation_swift_chinese_calendar_feature_enabled()`
  (both `#if` branches, hard-`false` on SPM) + `_calendarClass` routing —
  mirror the B/J shape exactly.
- `supportsNextDateFastPath(for: Calendar.ComponentSet) -> Bool` — return
  false / default (no fast paths in phase 1; leap months complicate the
  patterns; explicit follow-up like B/J).
- `bridgeToNSCalendar()` — `_NSSwiftCalendar(calendar: Calendar(inner: self))`
  (`#if FOUNDATION_FRAMEWORK`).
- Generator: a `@Test` (local-only, like the probes) that sweeps
  `_CalendarICU(.chinese)` daily over the chosen range, derives per-year
  (new-year RD, 12/13 month lengths, leap index), packs, and EMITS the
  Swift table source to stdout/scratchpad. Regeneration = rerun the test.

## 8. Test plan (all vs `_CalendarICU(.chinese)` constructed directly)

Discovery first, suites after — Chinese conventions must be OBSERVED, not
assumed:
1. **Discovery probes** (print-only): era/cycle/year values at known dates;
   leap-month representation in `dateComponents` (month number + isLeapMonth);
   `date(from:)` behavior with/without isLeapMonth and with ambiguous
   components; week-field behavior; `quarter`; `dateInterval(.era/.year/.month)`;
   TZ sensitivity (GMT vs Asia/Shanghai vs LA); pre-1929 dates (LMT epoch
   quirk); range extremes.
2. **Suite A** — protocol-level field parity, sampled densely + all
   discovery-flagged edges. Snapshot label `c1`.
3. **Suite B** — full public-API surface (mirror
   `JapanesePublicAPIComparisonProbe`: components, intervals, ordinality,
   ranges, adds incl. wrapping, bySetting, compare/isDate, weekends,
   enumerateDates with Chinese New Year `{month:1, day:1}` and leap-month
   patterns, from:to diffs). `c2`.
4. **Suite C** — RecurrenceRule parity (yearly CNY, monthly first-of-month
   across leap months, weekly, `.nth` weekday shapes, daily-with-times).
   `c3`.
5. **Daily sweep** — every day of the baked range vs ICU (for Strategy B
   this doubles as generator verification: table → fields must reproduce
   ICU exactly); plus boundary bands at range edges. Extend
   `CalendarDailySweepParityProbe.swift`.
6. **Strict-policy** — ADD `.chinese` to the parameterized
   `CalendarStrictPolicyParityProbe.swift` calendars list (it was built for
   this) + leap-month-specific strict patterns (`{month, isLeapMonth, day}`
   that exists only some years — the Chinese analogue of Feb-29).
7. **Benches** — mirror the per-calendar 5-shape block in
   `BenchmarkCalendar.swift` (`ChineseCalendar-nextThousandNewYears`, …);
   ICU-vs-ours via the flag-flip methodology in `backup/BENCHMARKS_PACKAGE.md`.
8. Full-suite regression + release-mode runs deferred to the 6.4 machine
   (Intel SIGBUS blocks release here).

Zero divergences before anything ships — divergences found are either our
bugs (fix) or documented ICU quirks (exclude + record, like `quarter=0`,
Japanese `dateInterval(.era)`, Meiji data).

## 9. Milestones

- M0: strategy decision (user) → discovery probes → conventions doc section.
- M1: generator + baked table + `_CalendarChinese` core (dateComponents /
  date(from:) round-trip green on sampled dates). Snapshot `c1`.
- M2: full Suite A green. `c2`.
- M3: Suites B + C green; daily sweep green; strict green. `c3`.
- **M3.5 (NEXT — verification hardening, added 2026-07-17 after the
  "anything unnoticed?" audit):** close the three verification gaps before
  benches; see § 11.7.
- M4: benches + docs (`BENCHMARKS_PACKAGE.md` results section) + session log.
- M5: handoff doc for the 6.4 machine (`CHINESE_6.4_HANDOFF.md`, mirroring
  `BUDDHIST_JAPANESE_6.4_HANDOFF.md`) + draft PR description. **Must carry
  the § 5 ⚠ warning: Duffett-Smith contingency port stays OUT of the
  feature branch unless the user explicitly agrees.**
- ~~(M6: Dangi)~~ — **dropped from this effort** (user, 2026-07-17);
  probes remain parameterized for a possible future effort.

## 10. Open questions for the user (answer at M0)

1. Strategy A vs **B (recommended)**; if B: range (default 1600–2600) and
   out-of-range policy. User leaning as of 2026-07-17 (revised after
   § 5b research): **ReingoldEngine-style (Meeus) fallback** — more
   accurate than ICU out of range; Duffett-Smith port kept as dormant
   contingency, ⚠ NOT for the feature branch without explicit agreement.
   See § 5.
2. ~~Dangi in Phase 1, Phase 2, or defer indefinitely?~~ **ANSWERED
   2026-07-17: out of scope for this effort entirely.**
3. Same single-branch/single-PR bundling as B/J, or Chinese standalone PR?
   (Standalone recommended — it's a big review on its own.)

## 11. Implementation log — verified conventions & divergence registry

> Everything in this section is OBSERVED/SOURCE-DERIVED during M1/M2
> (2026-07-17), not assumed. It is the raw material for the PR description
> and the 6.4 handoff. Snapshots: `c1` = `40be0f6` (M1), `c2` = `a316747` (M2).

### 11.1 Verified ICU field model (supersedes the § 4 sketch)

- extended year `ext` = related Gregorian year + 2637 (CNY 2000 → ext 4637).
- `era` = 60-year cycle = `(ext−1) fdiv 60 + 1` (2000 → era 78).
- `year` = `(ext−1) fmod 60 + 1` (1..60; 2000 → 17).
- `yearForWeekOfYear` = **ext**, not year-in-cycle.
- `dayOfYear` = CNY-relative (1..384).
- `month` = display number 1..12 (leap repeats it, `isLeapMonth` set);
  ICU populates `isLeapMonth` in EVERY dateComponents result whether or
  not requested (Hebrew precedent: always set it).
- `quarter` ≡ 0 for chinese (ICU bug; we return the same sentinel).
- LIMITS (chnsecal.cpp:174): era 1..83333, year 1..60, woy 1..50/55,
  day 1..29/30, doy 1..353/385, weekdayOrdinal −1..5, YEAR_WOY ±5,000,000.
- `date(from:)` era default when unset = era of the CURRENT date (ICU
  fields default from "now"), verified: `{year: 41}` alone → CNY 2024.
- Rejected-day behavior: day out of 1..monthLength → nil (Hebrew-shaped;
  strict probes in M3 will confirm against _CalendarICU's wrapper).

### 11.2 Verified ICU behavioral conventions (ported in M2)

1. `dateInterval(.yearForWeekOfYear)` → **nil** for chinese.
2. `date(byAdding: .yearForWeekOfYear)` → **no-op** for chinese.
3. `ordinality(.month, .year)` → **display month number**, NOT ordinal
   position (leap-4 day → 4, and the month after it → 5).
4. `dateInterval(.era)` = the 60-year cycle span (matched ICU on first try).
5. **Year-add pin dance** (THE nontrivial one; sources:
   `calendar.cpp` `Calendar::add` UCAL_YEAR → `set(year+N)` +
   `pinField(DOM)`; `Calendar::getActualMaximum(UCAL_DATE)` clones,
   `prepareGetActual` sets DOM=1, clone `complete()` resolves, but
   `handleGetMonthLength` is then called **on the original object** —
   reading the original's IS_LEAP_MONTH — with the CLONE's resolved
   month number; `chnsecal.cpp` `handleComputeMonthStart` resolves month
   as estimate `CNY + month0×29 days` → `newMoonNear` → **bump exactly
   once** if display OR leap mismatches — never twice):
   - S1 = single-bump resolution of (source display M, source leap L) in
     the target year.
   - pin length = month length at S2 = single-bump resolution of
     (S1's display number, ORIGINAL leap L).
   - result = S1 + min(day, len(S2)) − 1, **spilling leniently** into
     following months when unpinned.
   - Reproduces BOTH: 1906 m4L d30 + 1y → 1907-07-10 (spill into m6) and
     m12 d30 + 1y → Feb 7 (clamp), plus the 2023-leap-2 single-bump-
     consumed case (leap flag silently dropped when the bump was used for
     the display correction).
   Implemented in `_CalendarChinese.date(byAdding:)` year path +
   `resolvedMonthStart(ext:display:leap:)`.
6. Month-add = pure lunation stepping with day pinned
   (`ChineseCalendar::add` UCAL_MONTH → `offsetMonth`); our ordinal-walk +
   clamp matches on all sampled cases incl. day-30→29.

### 11.3 Known divergences & exclusions registry (the PR's "known issues")

| # | What | Scope | Cause | Status |
|---|---|---|---|---|
| 1 | ICU emits `day=0` and off-by-one doms | Chinese months starting 2057-09-28 and 2097-08-07 (30 days each) | Apple ICU internal clash: baked newYearAdj/winterSolsticeAdj + newMoonDates tables vs live code (§ 5c) | Excluded + documented. ICU is self-inconsistent (a valid calendar never emits day 0) |
| 2 | ICU year-level queries corrupted in those years | whole Chinese years 2057 & 2097 (e.g. `range(.day,.year)` = 1..<325 for a ~354-day year) | same artifact propagating into actualMaximum(DOY) | Excluded whole years in probes |
| 3 | fallback m6-2101 starts Jun 27 (ours) vs Jun 26 (ICU) | 30 days in Chinese 2101 (first fallback year) | documented Reingold-vs-Duffett-Smith conjunction class (§ 5b); our instant is astronomically right | Intentional; documented |
| 4 | out-of-range divergence profile | <1901 / >2100 | § 5b measurements + adjudication (9/10 vs promulgated record) | Intentional; PR-defensible with citations |

### 11.4 Bugs found & fixed via probes (process log)

- `toLocalDay` off-by-one in the fallback port (+1 that didn't belong):
  every fallback month start one day late; caught by the 74,510-day
  engine sweep (1,421 divergent days → 30 after fix). Lesson: the sweep
  gates real bugs, run it after any engine change.
- Probe hardcoded artifact-window literal for 2097 miscomputed by 35 days
  (manual RD arithmetic); replaced ALL probe literals with computed
  `gregorianRD(...)` expressions.
- My first four year-add models (clamp; bump+clamp; no-pin spill;
  pin-vs-spilled-month) each matched a subset of cases — only the
  source-derived pin dance (11.2 #5) matched all. Lesson recorded: for
  add/roll semantics, read Calendar::add + getActualMaximum verbatim
  FIRST; observed behavior alone underdetermines the algorithm.

### 11.5 Verification inventory (as of c2)

- Generator: 200 years swept from `_CalendarICU`; HKO cross-validation =
  exactly the 3 known ICU-vs-HKO month starts (1914 M10, 1916 M01/CNY,
  1920 M10) — 2,455/2,461 rows identical, nothing else.
- Engine daily sweep 1899-01-01..2102-12-31 (74,510 days): in-table
  divergence ONLY within registry #1 windows; out-of-table only registry
  #3; seams tile exactly; 1899+1900 fully clean (incl. 1900 leap-8).
- M1 probe: 5,723 sampled days, 13 fields, 0 diffs; round-trip 0 fails.
- Suite A (9 topics, ~900 dates): 0 divergences.

### 11.6 M3 findings (Suites B/C, daily sweep, strict — snapshot c3)

- **isLeapMonth population rule (THE M3 discovery):** ICU populates
  `isLeapMonth` in dateComponents results **iff the requested set contains
  `.month` or `.isLeapMonth`** — nil otherwise (verified per-set:
  [.minute]/[.hour]/[.day]/[.weekday] → nil; [.month]/[.month,.day]/
  [.era,.year,.month,.day]/[.isLeapMonth] → true/false). Our initial
  always-populate (copied from Hebrew's "ICU always populates" precedent)
  poisoned the GENERIC enumerate framework on leap-month dates: the match
  verifier saw an unsolicited isLeapMonth=true against patterns with the
  flag unset and never matched — breaking date(bySetting:), weekend
  queries, and enumerateDates for any leap-month input. Hebrew never hit
  this because its flag is always FALSE (nil-vs-false compares equal) and
  it has a nextDate fast path. One-line fix in
  `_CalendarChinese.dateComponents`.
- Routing fact: `_CalendarICU` has NO nextDate fast path (protocol default
  false) — ICU and our calendar both go through the generic enumerate
  framework, so Suite B/C parity genuinely exercises the same code path
  over both backends.
- Debug utility: `ChineseDebugTraceProbe.swift` contains `TracingCalendar`
  (a forwarding `_CalendarProtocol` wrapper printing every framework call)
  + the ICU leap-flag semantics probe. Research-branch only — ⚠ do NOT
  carry to the PR branch (it's how the M3 bug was found in minutes;
  keep for future framework debugging).
- Suite B (`ChinesePublicAPIComparisonProbe`, 8 topics, ~60 dates × ~140
  public-API surfaces each): zero divergences, including bySetting,
  bySettingHour, weekend queries, enumerateDates (CNY + Mid-Autumn),
  compare/isDate granularities, wrapping adds, from:to diffs — with
  leap-month dates as first-class topic.
- Suite C (`ChineseRecurrenceRuleParityProbe`, 6 rules: yearly CNY,
  yearly Mid-Autumn, monthly-1st across leap months, weekly Mondays,
  yearly nth-weekday, daily-with-times; anchors straddle leap-2/4/6
  years): zero divergences.
- Daily sweep 1899-01-01..2102-12-31 (8 fields/day, registry exclusions):
  zero failures. Strict-policy matrix (.chinese added) + Chinese-specific
  strict patterns ({m4,leap,d1} biennial-skip, CNY yearly, {m6,d30}
  short-month skip): zero failures. B/J tests in the shared probe files:
  unaffected, still green.

### 11.7 M3.5 — verification gaps from the end-of-day audit (✅ CLOSED 2026-07-19, snapshot c3.5)

Audit question: "any icu4swift-year-start-shaped bugs lurking?" Three gaps
were found; all closed 2026-07-19. Results per item:

1. **Deep-fallback never executed by tests** (<1899 / >2102) — exactly the
   icu4swift bug shape (its non-tiling 1776 lived in untested fallback).
   Add `ChineseInvariantProbe.swift`:
   - Tiling + structure invariant sweep over relatedIso ≈ −2000..5000:
     `year(Y).endRD == year(Y+1).newYearRD`, monthCount ∈ {12,13}, leap
     present iff 13 months, and **sum-of-length-bits == nyNext − ny** (this
     catches the silent-corruption case: fallback encodes month lengths as
     29/30 BITS — a 28/31-day solver gap would silently mis-encode; the
     sum check exposes it).
   - Historical pins from § 5c adjudication as PERMANENT expectations:
     CNY 1776-02-19, 1795-01-21, 1814-01-21, 1871-02-19, 1890-01-21,
     2148-02-20; leap months 1775=m10L, 1900=m8L, 2147=m11L.
   - Far-date round-trips + dateInterval(.year) adjacency at −1000, 1,
     1500, 3000, 4600 CE (internal consistency, NOT vs ICU — divergence
     out there is intentional/documented).
   - Add debug-only `assert(len == 29 || len == 30)` in the engine's
     fallback year builder (active under swift test, free in release).
2. **min/maximumRange never compared vs ICU** — the LIMITS-derived values
   (era 1..<83334 etc.) are unverified guesses. Add a probe comparing all
   components' minimumRange/maximumRange vs `_CalendarICU(.chinese)`.
3. **Hebrew isLeapMonth follow-up (upstream, NOT this branch):** the M3
   discovery (ICU populates isLeapMonth iff .month/.isLeapMonth requested)
   implies MERGED Hebrew may have a latent shape deviation: it ALWAYS
   populates isLeapMonth=false, ICU likely returns nil for sets like
   [.minute]. Verify with the per-set probe pointed at .hebrew (and check
   B/J too). Functionally benign (false ≡ nil under the framework's
   `?? false` coercions — which is why every Hebrew parity suite passed),
   but observable via DateComponents equality / `.isLeapMonth != nil`, so
   it violates strict parity. If confirmed: one-line guard like Chinese's;
   needs USER DECISION on how/when to upstream (Hebrew is merged; B/J PR
   #2105 still open — could fold into a review round).

### 11.8 M3.5 results (2026-07-19)

All three § 11.7 items closed; **zero engine bugs found** — the gaps were in
verification coverage, not the code:

1. **`ChineseInvariantProbe.swift`** (4 tests, all green first run):
   - Tiling + structure sweep, relatedIso −2000...5000 (7,001 years,
     ~11 s debug): 0 failures — every year tiles, 12/13 months with leap
     iff 13, length-bits sum == span, year length ∈ [353, 385]. The
     debug `assert(len ∈ {29,30})` now in the fallback year builder was
     active throughout: no non-lunation gap anywhere in ±3,500 years.
   - Historical pins (11): CNY 1776/1795/1814/1871/1890/2148 + leaps
     1775=m10L, 1776/2148=none, 1900=m8L, 2147=m11L — all exact. The
     § 5c adjudication is now a permanent regression gate.
   - Far-date round-trips + year-interval adjacency at −1000, 1, 1500,
     1681 (engine-sensitive), 3000, 4600 CE: 0 failures.
   - min/maximumRange vs ICU, all 16 components: **0 diffs** — the
     LIMITS-derived values are now verified, not guessed.
2. **Hebrew isLeapMonth shape deviation: CONFIRMED** (report-only probe
   `hebrewBJLeapFlagShape` in ChineseDebugTraceProbe.swift): merged
   Hebrew populates `isLeapMonth=false` for ALL requested sets; ICU
   returns nil unless the set contains .month/.isLeapMonth — 3/6 probe
   sets deviate ([.minute], [.day], [.weekday]). ICU's per-set rule is
   calendar-generic (same as Chinese). Functionally benign (false ≡ nil
   under `?? false` coercion — why every Hebrew suite passed), observable
   only via DateComponents equality / nil-checks. Fix would be the same
   one-line guard as Chinese's. **⚠ USER DECISION pending on upstreaming;
   Hebrew is merged, so this is a follow-up-PR question — do NOT patch
   Calendar_Hebrew.swift on this branch without instruction.**
3. **Buddhist + Japanese: CLEAN** (0/6 sets deviate) — no action needed,
   PR #2105 unaffected.

### 11.9 Liu external validation of the fallback zone (2026-07-19)

`ChineseLiuReferenceProbe.swift`: our fallback (chnsecal rules + Reingold +
UTC+8) vs Yuk Tung Liu's DE441 + Stephenson/Morrison ΔT + GB/T 33661-2017
data for **2101–2200** — the strongest external authority for that century
(HKO stops at 2100; nothing published exists past 2200). Data extracted from
his `calendarData.js` (GPL-3.0), decode validated on six known years, baked
into the probe as 100 packed rows (CNY RD + leap display + length bits).

**Result: 97/100 years match EXACTLY (CNY, leap placement, all month
lengths). The 3 diffs — 2133, 2165, 2172 — are a strict subset of Liu's own
day-level-uncertain conjunction list**, each a single month-boundary ±1 day
(adjacent length-bit pair swap, total days preserved), i.e. a new moon within
ΔT-extrapolation error of midnight UTC+8: unadjudicable in principle, per the
reference source itself. Same CNY and leap structure even in those 3 years.
Probe gates on zero divergence OUTSIDE Liu-flagged-uncertain years; flagged
diffs are reported, not failed.

Upgrade to the § 5b claim ladder: the fallback's future century is now
**externally validated**, not merely "better astronomy than ICU". (ICU, for
comparison, diverges from Liu in this zone at the documented § 5b rates,
including CNY 2148 by a full month.) For the PR: this + § 5c adjudication +
HKO in-range = every era of the calendar covered by an independent authority.

## 12. Two-tier test strategy (research-exhaustive vs PR-curated)

**Principle (user, 2026-07-19):** the research branch carries EXTREMELY
detailed probes against both ICU and reference sources — absolute certainty
of correctness. The PR branch carries a curated subset — zero upstream bloat.
Precedent verified via `gh pr view 2105 --json files`: B/J shipped only 7
files (2 impls, Calendar_Cache, CMakeLists, BenchmarkCalendar, 2
RecurrenceRule probes); ALL other probes stayed on the research branch.
Hebrew additionally shipped small SELF-CONTAINED tests (HebrewCalendarTests,
HebrewRegressionTests — no ICU pairing, no external data).

### 12.1 PR feature branch (`port/chinese-main`, cut by 6.4 machine)

| File | Rationale |
|---|---|
| `Calendar_Chinese.swift` | the implementation (chnsecal rules, year structure, table, _CalendarChinese) |
| `Calendar_Astronomy.swift` | shared `_CalendarAstronomy` (solar/lunar/ephemeris + Gregorian day math), split for Islamic/Hindu reuse |
| `Calendar_Cache.swift` (flag + routing) | B/J shape |
| `Calendar/CMakeLists.txt` (+Calendar_Chinese.swift) | required |
| `BenchmarkCalendar.swift` (5-shape Chinese block, M4) | B/J shape |
| `ChineseRecurrenceRuleParityProbe.swift` | exact B/J precedent |
| **NEW `ChineseCalendarTests.swift`** (write at M4/M5) | Hebrew precedent: self-contained, no ICU pairing, no external data. Distill: ~20 known-date spot checks across 1901–2100 (from the baked table, incl. leap months + CNYs); round-trips; § 5c historical pins (with the do-not-fix-to-match-ICU note); tiling+bits-sum invariant over a TRIMMED span (e.g. 1800–2300, seconds not 11 s); range-limit literals (now ICU-verified); the 2057/2097 d0-artifact windows as documented expectations |

### 12.2 Research branch ONLY (never cherry-picked; ⚠ list for the 6.4 handoff)

| Asset | Why it stays |
|---|---|
| `ChineseICUComparisonProbe.swift` (Suite A) | exhaustive ICU pairing; B/J kept theirs back |
| `ChinesePublicAPIComparisonProbe.swift` (Suite B) | same |
| Chinese additions in `CalendarDailySweepParityProbe.swift` + `CalendarStrictPolicyParityProbe.swift` | shared files not in #2105 at all |
| `ChineseTableGeneratorProbe.swift` | generator + discovery; regeneration is a research activity (plan § 7) |
| `ChineseInvariantProbe.swift` (full −2000..5000) | 11 s sweep; distilled subset goes into ChineseCalendarTests |
| `ChineseLiuReferenceProbe.swift` | **licensing caution: data extracted from Liu's GPL-3.0 repo.** Calendar dates are facts, but do not put GPL-derived tables into Apache-2.0 upstream; PR DESCRIPTION cites the validation result (97/100 exact, 3 within Liu's own uncertainty flags) instead |
| `ChineseDebugTraceProbe.swift` (TracingCalendar, ICU leap-flag semantics, Hebrew shape check) | debug tooling + pending user decision on Hebrew |
| HKO CSV / raw files | stay in icu4swift + § 5c provenance; PR description cites results (supersedes the earlier § 5c "copy CSV into swift-foundation test resources" action — do NOT copy; 54 KB of data upstream is exactly the bloat this section exists to prevent) |
| `backup/` (plan, harnesses, DS port) | never ships, per standing rule |

### 12.3 Evidence flow to the PR

The PR description (M5) carries the verification NARRATIVE with numbers —
ICU parity counts, HKO cross-check (2,455/2,461 + 3 named), § 5c adjudication
scorecard, Liu 97/100 — with § 11 as the citable archive. Upstream gets the
claims + curated executable checks; the exhaustive machinery stays here,
rerunnable on demand.

### 11.10 M4 IN PROGRESS (2026-07-19) — state + open anomaly

DONE: `Calendar_Cache.swift` wired (`foundation_swift_chinese_calendar_feature_enabled()`,
both #if branches hard-false + routing line, B/J shape exactly);
`BenchmarkCalendar.swift` Chinese 5-shape block added (nextThousandNewYears,
allocationsForFixedCalendar, copyOnWritePerformance,
dateComponents-yearMonthDay, roundTripDateComponents); main package builds,
probes green. ICU-baseline bench run captured (flags off, debug, prefix
filter `^ChineseCalendar-.*$` WORKS): dateComponents 211 ns/iter,
roundTrip 530 ns/iter, allocations 25130 ns, CoW 20495 ns (1-sample benches,
known-benign), raw at job-tmp bench_icu.txt (EPHEMERAL — regenerate via the
§ command if gone).

**⚠ OPEN ANOMALY (investigate FIRST next session, per
feedback_anomaly_investigation): `ChineseCalendar-nextThousandNewYears`
ICU-baseline median ~111 μs TOTAL** — implies ~111 ns per CNY match through
ICU's generic enumerate framework: implausible by orders of magnitude.
Suspect: enumeration terminates early (nil result stops the framework while
`count` never reaches 0 — the closure shape only decrements on callbacks).
Checks: (1) run the SAME shape against Hebrew/Buddhist siblings in the same
run and compare; (2) count actual callbacks in a scratch test with
Calendar(identifier:.chinese) in the bench package context (flags off);
(3) if ICU's enumerate genuinely bails for {month:1,day:1}, document as an
ICU limitation and adjust the bench shape (e.g. count via non-nil results
only) BEFORE the flag-flip comparison. Do NOT publish ICU-vs-ours numbers
until resolved.

**ANOMALY RESOLVED (2026-07-19, empirical):** both backends yield exactly
**145 non-nil matches, identical last date CNY 2163-02-03, then the GENERIC
FRAMEWORK stops on its own** (its internal search cap; the closure's
count=1000 never reaches 0). Scratch timing ~108 ms/run; the bench's
"111 μs" is that ~111 ms divided by the harness's default kilo
scalingFactor — numbers are internally consistent. NOT a Chinese or ICU
bug: identical behavior both sides, so the A/B comparison is fair (same
145-match workload). Sibling note: Buddhist/Japanese "nextThousand"
benches cap the same way (generic framework); only Hebrew truly does 1000
(fast path bypasses the cap). Keep the inherited name for consistency.
Verification probe: `chineseEnumerateCNYCallbackCount` in the debug-trace
file (research-only).

REMAINING for M4 next session: → flag-flip run (flip SPM-branch chinese
flag to true, rerun, RESTORE false before committing) → side-by-side table
in BENCHMARKS_PACKAGE.md + EXPECTED_TIMES.md entries → write the § 12.1
self-contained `ChineseCalendarTests.swift` → commit as c4.

### 11.11 M4 flag-flip results (2026-07-19, debug, SPM, this iMac)

| Bench (p50) | ICU | Pure Swift | Speedup |
|---|---|---|---|
| dateComponents-yearMonthDay | 211 ns | 65 ns | 3.2× |
| roundTripDateComponents | 530 ns | 136 ns | 3.9× |
| allocationsForFixedCalendar | 25,130 ns | 1,352 ns | 18.6× |
| copyOnWritePerformance | 20,495 ns | 554 ns | 37× |
| nextThousandNewYears | 111 μs | 113 μs | ~1× (framework-bound: both sides run the generic enumerate's 145-match cap; time is framework overhead, not calendar math — same profile as B/J) |

Flag restored to false after the run (verified). The user's why-parity
question on the enumerate bench is answered: the shared generic framework
dominates that shape; every calendar-math-bound shape shows the expected
3–37× win. Raw outputs: job-tmp bench_icu.txt / bench_ours.txt (ephemeral).
Remaining M4: BENCHMARKS_PACKAGE.md results section + EXPECTED_TIMES rows +
§ 12.1 ChineseCalendarTests.swift → snapshot c4.

### 11.12 Why enumerate is ~1× while Hebrew's Hanukkah bench was a blowout

Hebrew ships `supportsNextDateFastPath = true` + a hand-written `nextDate`
(#2028 deliverable): `Calendar.enumerateDates` BYPASSES the generic
framework — near-zero overhead AND no 145-match cap (truly 1000 matches).
Chinese phase 1 ships `false` deliberately (§ 7: leap months complicate
match patterns — {month:4} vs m4L ambiguity; B/J precedent: port first,
fast-path follow-up). So Chinese enumerate runs the SAME framework-bound,
145-capped path on both backends → ~1× by construction, NOT an engine
ceiling: dateComponents underneath is already 65 ns. **Follow-up-PR story
for upstream: a Chinese `nextDate` fast path (CNY {month:1,day:1} + the
B/J-proven shapes, leap semantics matched to ICU) should lift this bench
into Hebrew-class territory — mirror of the Hebrew two-PR arc.** Keep the
inherited "nextThousand" name; the 145-cap note (§ 11.10) covers the
misnomer for framework-path calendars.

### 11.13 Pre-PR review-tightening pass (2026-07-19)

Mined parkera+itingliu comments from #1953/#2028 via gh (#2105 still has
none). Their patterns: verbose comments; wrapped comments (guideline: don't
wrap); DateComponents-in-hot-paths ("pretty expensive struct" — parkera);
duplicated blocks; intermediary structures; force unwraps in tests; stale
comments. Audit of the six § 12.1 files:
- FIXED: 3× duplicated time-of-day extraction in date(byAdding:) (each a
  DateComponents round trip) → one `localSecondsInDay(of:in:)` helper doing
  plain arithmetic. Both parkera-pattern hits (expense + duplication) gone.
- FIXED: pin-dance, resolvedMonthStart, and test-pin comments compressed to
  unwrapped 1-liners (deep detail lives in § 11.2, not the code).
- CLEAN: no deep nesting (the 28-space grep hits are poly coefficient
  wraps); no force unwraps in shipped tests; source `ordinalAndDay!` (2×)
  is invariant-backed, matching merged-Hebrew idiom; bench block mirrors
  the shipped sibling shapes; RecurrenceRule probe is the shipped B/J
  template verbatim.
All 47 tests green after the pass.

### 11.14 CONTRIBUTION_GUIDELINE compliance pass (2026-07-19)

Upstream `CONTRIBUTION_GUIDELINE.md` located (not in our old fork base;
mirrored to `backup/CONTRIBUTION_GUIDELINE_upstream.md`; permanent memory
created). New fixes on PR-bound files: 3 force unwraps → guard+fatalError
w/ diagnostic (2× invariant) / guard-return-nil (year-add); 6 prints
stripped from ChineseRecurrenceRuleParityProbe ("no print in tests" — note:
shipped B/J probes in #2105 print too and may get flagged there);
@unchecked Sendable why-safe comment added. 47 tests green.
Accepted deviations, defensible: loop-style probe (matches shipped B/J
template; parameterization noted as review-response); weekNumber/utcDate
helpers duplicated from Hebrew (cross-calendar _CalendarUtility refactor =
prepared follow-up answer, wrong to smuggle into this PR).

### 11.15 Final CONTRIBUTION_GUIDELINE compliance verdict (2026-07-19, head `e38e88c`)

Point-by-point grep-verified on all six § 12.1 PR-bound files, ALL PASS:
no wrapped comments/DocC (last two unwrapped in `e38e88c`); why-only
comments; no PR refs; no force unwrap/cast anywhere (guard+fatalError w/
diagnostic for invariants); no unsafe APIs; @unchecked Sendable justified;
tests: zero prints, zero force unwraps, changed-path-relevant; benches:
sibling shapes, setup outside measured scope; no new platform flags.
Prepared review responses: (1) exit tests — fatalErrors guard internally
unreachable invariants, not caller contracts; (2) probe parameterization —
matches shipped B/J template, happy to convert; (3) shared-helper
consolidation (weekNumber/utcDate/rataDie ↔ Hebrew) — cross-calendar
_CalendarUtility refactor as follow-up, out of scope here.
Tightening history: § 11.13 (reviewer-pattern pass), § 11.14 (guideline
pass), this section (final verdict). Guideline mirror:
`backup/CONTRIBUTION_GUIDELINE_upstream.md`; permanent memory created.

### 11.16 Platform-import ladder fix (2026-07-19, user catch)

Our libm import block was Darwin/Glibc-only — would fail on Bionic/Musl/
CRT/WASI (the exact itingliu Hebrew-review trap, 'cannot find floor in
scope' on Linux-class CI). Replaced with the canonical 6-way ladder used
verbatim by merged Calendar_Hebrew AND Calendar_Gregorian. Chinese uses
libm heavily (sin/cos/tan/atan2/pow) so all five non-Darwin branches are
load-bearing. 6.4 machine: watch CI on all platforms anyway.

### 11.17 User tightening round 2 (2026-07-19)

1. "Pure-Swift"/"native" purged everywhere PR-facing (parkera dislikes the
   term; permanent rule added to the contribution-guideline memory): class
   DocC, Sendable comment, PR-draft title now say just "Swift".
2. Empty `///` separator lines: verified UPSTREAM-COMMON (Calendar.swift
   has 55, merged Hebrew 2) — standard DocC summary/discussion separator;
   kept.
3. Astronomy split: `_CalendarAstronomy` (calendar-agnostic: ephemeris
   correction, solar longitude, Meeus new-moon series, Gregorian RD math)
   now lives in `Calendar_Astronomy.swift` for future Islamic/Hindu reuse;
   Chinese-family-specific code (chnsecal rules `_ChineseRules`, solar-term
   indices, UTC+8, year packing, `_CalendarChinese`) stays in
   Calendar_Chinese.swift. All references renamed; § 12.1 now a 7-file
   pick list; CMakeLists carries Calendar_Astronomy on the research branch.

### 11.18 Table-packing trade space (2026-07-19, user-driven design)

Per-year information content: 13 month-length bits + 4-bit leap display +
6-bit NY offset = 23 bits (offset is DERIVABLE: length = 29*monthCount +
popcount(bits); NY chain from one anchor — the § 11 bits-sum invariant
test proves the chain for all 200 years).

**User's leap-extraction packing (WORKS — solves the 17-bit near-miss):**
main array = 12 REGULAR-month length bits + 4-bit leap position = exactly
16 bits/year (UInt16, 400 B); leap-month LENGTHS move to a side bit-array
(one bit per year = 25 B, or rank-compacted per leap year = 10 B).
Accessor rebuilds ordinal lengths by inserting the side bit at the leap
ordinal. Leap positions 1..12 all representable (required: § 5c saw ICU
compute fake m1L/m12L — never assume rarity in an encoding).

**Option table:**
| Layout | Binary | Structures | Start lookup | Note |
|---|---|---|---|---|
| UInt32 (shipped) | 800 B | 1 | O(1) | dumb, legible, clean pages |
| 3 B/year (ICU4X precedent) | 600 B | 1 | O(1) | ~4-line accessor change |
| 16-bit + leap bits + 6-bit offset side-array | ~575 B | 3 | O(1) | beats 3 B by 25 B only |
| 16-bit + leap bits, derived starts (lazy cache) | ~425 B | 2 | O(1) after init | **+~800 B DIRTY heap** |
| same, no cache (prefix-sum walk) | ~425 B | 2 | O(n≤200) | dateComponents ~65→~130-150 ns |

**Decisive argument for review:** const tables are CLEAN, page-shared
memory; runtime-derived arrays are DIRTY per-process memory. The 425 B
variant trades ~375 clean bytes for ~800 dirty bytes — a net loss by the
metric Apple perf reviewers optimize. Recommendation: ship 800 B UInt32;
PR text offers compaction with this analysis cited. EXPERIMENTS PLANNED
(user, next): prototype variants and measure real binary delta + bench
delta before final call.

### 11.19 Packing experiment RESULTS (2026-07-19; ChinesePackingExperiment.swift, research-only)

All variants regenerated from the shipped table and proven field-identical
to baseline for all 200 years. Microbench = year decode + start lookup +
synthetic month walk (identical across variants → deltas isolate the
layout cost), debug mode (same config as all our bench numbers; release
re-measure belongs to the 6.4 machine):

| Variant | Const bytes | ns/op | Δ vs A | Verdict |
|---|---|---|---|---|
| A UInt32 (shipped) | 800 | 334 | — | **ship** |
| B 3-byte (ICU4X layout) | 600 | 413 | +24% | viable fallback if review demands size; re-measure in release |
| C 16-bit + leap bits + packed 6-bit offsets | 575 | 802 | +140% | dead: 3 structures, decode dominates, saves 25 B over B |
| D 16-bit + lazy start cache | 425 (+800 dirty heap) | 358 | +7% | perf fine; dies on clean-vs-dirty memory |
| E 16-bit + prefix walk | 425 | 16,503 | +49× | dead, as predicted |

Conclusions: § 11.18's predictions held (E catastrophic, D dirty-memory
loss, C not worth 25 B). New data: B's decode costs +24% in DEBUG — not
free as assumed; likely compresses under optimization but unproven here
(Intel release SIGBUS). Decision: **ship A**; PR text offers B with these
measurements attached. User's leap-extraction encoding (Var16) is fully
implemented + verified in the experiment file for the record.

**Why ICU4X's 3-byte layout loses here despite winning there:** (a) B is
structurally unable to beat A — 3-byte records straddle alignment, so
every access is i*3 + three byte loads + reassembly vs A's single aligned
32-bit load; best case is a near-tie minus 200 B. Our +24% is debug-
inflated (three un-elided bounds checks); release should compress it to
~noise — first step on the 6.4 machine if a reviewer requests B. (b)
ICU4X's economics differ: Rust release-only measurements, AND their
packed year decodes ONCE into the DateInner at date creation with all
field accessors reading the unpacked copy — decode is cold-path, bytes
are hot-currency in their data-provider model. Our engine hits the table
on the dateComponents hot path (65 ns budget), flipping the weights.
General lesson for the PR text: no layout is best in the abstract — A
wins for OUR access pattern, table size, and clean-page economics; a
different hot path or a much larger table would legitimately pick B or D.

**Why we can't amortize the decode like ICU4X (the architectural root):**
ICU4X's Date<Chinese> CARRIES calendar state — creation decodes the packed
year once into ChineseDateInner; every accessor reads the unpacked copy
(icu4swift's packed-in-DateInner trick was the same, by design).
Foundation.Date is a bare Double — public ABI, no calendar state, no inner
representation to decode into — so every dateComponents call rediscovers
the year from scratch: the amortization surface doesn't exist. The only
alternative cache site is the shared _CalendarChinese singleton, which
must be thread-safe: an uncontended lock (~10-20 ns) costs several times
variant A's decode (one aligned load + shift-masks). We DO use the
ICU4X-in-spirit pattern where it pays — the fallback LockedState year
cache, where computation is μs-class astronomy. Same trade, opposite
sign, opposite decision. Bottom line: Foundation's stateless Date forces
decode-per-call, which is precisely why the layout with the cheapest
per-call decode — plain UInt32 — is correct here. The architecture chose
the layout.
