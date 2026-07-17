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
- **Out-of-range policy options** (decide with strategy):
  1. Fall back to `_CalendarICU`-matching *arithmetic approximation* —
     hard to make parity-clean; probably wrong choice.
  2. Port the astronomy ONLY as fallback (Strategy A shrunk to a
     correctness-nonessential path) — most work.
  3. Clamp/saturate at range edges and document — simplest; ICU itself is
     astronomically dubious far out; probes then cover in-range only, with
     the boundary behavior explicitly tested and documented.
  Recommendation: start with 3, leave 2 as a follow-up if review demands.

**Recommendation: B.** It's the icu4swift architecture with ICU replacing
HKO as the data source, it matches ICU4X's own approach, and it converts
the parity problem into a generation+verification problem we can brute-force
with in-process ICU.

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
  `Calendar_ChineseData.swift` — decide by size (~1,000 packed UInt32s +
  new-year offsets).
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
  `BUDDHIST_JAPANESE_6.4_HANDOFF.md`) + draft PR description.
- (M6: Dangi, if user opts in — probes are parameterized to make this cheap.)

## 10. Open questions for the user (answer at M0)

1. Strategy A vs **B (recommended)**; if B: range (default 1600–2600) and
   out-of-range policy (default: clamp + document).
2. Dangi in Phase 1, Phase 2, or defer indefinitely?
3. Same single-branch/single-PR bundling as B/J, or Chinese standalone PR?
   (Standalone recommended — it's a big review on its own.)
