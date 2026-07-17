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
- **ICU's field conventions** (the parity target — verify all in Suite A
  discovery tests, do not trust this table blindly):
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
