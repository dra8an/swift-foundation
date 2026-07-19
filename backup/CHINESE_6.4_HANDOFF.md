# Chinese calendar — 6.4 machine handoff (M5, 2026-07-19)

Mirror of BUDDHIST_JAPANESE_6.4_HANDOFF.md. Research branch: `port/chinese`
(6.3 iMac), head = c4 `b2d5d5f`. Master context: `backup/CHINESE_PLAN.md`
(§ 11 = findings/registry, § 12 = two-tier test strategy).

## Cut the feature branch

`port/chinese-main` off `upstream/main`, code only. Cherry-pick/port EXACTLY
these (§ 12.1):

1. `Sources/FoundationEssentials/Calendar/Calendar_Chinese.swift`
2. `Calendar_Cache.swift` — flag (both #if branches hard-false) + routing line
3. `Sources/FoundationEssentials/Calendar/CMakeLists.txt` — **ADD
   Calendar_Chinese.swift — NOT registered on the research branch** (B/J lesson)
4. `Benchmarks/.../BenchmarkCalendar.swift` — ChineseCalendar 5-shape block
5. `Tests/FoundationInternationalizationTests/ChineseRecurrenceRuleParityProbe.swift`
6. `Tests/FoundationEssentialsTests/ChineseCalendarTests.swift`

Reconcile `Calendar_Cache.swift` with whatever #2105 merged. Check protocol
drift vs `reference_calendar_protocol_baseline` memory before building.

## ⚠ NEVER include (§ 12.2)

- `backup/` anything — esp. `duffett-smith-port/` (contingency, needs explicit
  user agreement) and `chncmp-harness/`
- `ChineseICUComparisonProbe`, `ChinesePublicAPIComparisonProbe`,
  `ChineseTableGeneratorProbe`, `ChineseInvariantProbe`,
  `ChineseDebugTraceProbe` (TracingCalendar + Hebrew leap-shape check —
  Hebrew fix is a PENDING USER DECISION, do not patch Calendar_Hebrew)
- `ChineseLiuReferenceProbe` — **GPL-3.0-derived data; cite results in PR
  text only**
- Chinese additions in shared CalendarDailySweep/StrictPolicy probes
- HKO CSV / any external data files

## Verify on 6.4 before opening PR

Research-branch full suite first (`swift test --filter "chinese|Chinese"`,
~20 s, all green at c4), then feature-branch build + ChineseCalendarTests +
RecurrenceRule probe + release-mode run (blocked on 6.3 Intel).

## Draft PR description (edit, don't expand)

**Add a pure-Swift Chinese calendar implementation behind a feature flag**

Follows the Hebrew (#1953/#2028) and Buddhist/Japanese (#2105) pattern:
`_CalendarChinese` behind `foundation_swift_chinese_calendar_feature_enabled()`
(hard-false; zero behavior change until enabled).

Design: baked table for Chinese years 1901–2100 (200 × UInt32 = **800 B**,
packed month-length bits + leap index + new-year offset), generated from
`_CalendarICU(.chinese)` — parity by construction. Outside that range, ICU's
own chnsecal rules layer over Reingold/Dershowitz (Meeus) astronomy at UTC+8
(~400 LOC + ~3 KB coefficients). Total addition ~1,300 LOC, one file.

Verification (exhaustive suites on the research branch; distilled tests here):
- Daily parity vs ICU, 1899–2102 (74,510 days): zero divergence in the baked
  range outside two months where ICU emits impossible `day=0` fields
  (2057-09, 2097-08 — an ICU internal inconsistency, documented).
- Cross-checked against Hong Kong Observatory's official tables (1901–2100):
  matches except exactly ICU's 3 known HKO deviations (kept for parity).
- Out-of-range dates validated against the promulgated Qing record (4
  independent sources) and Yuk Tung Liu's DE441 computation for 2101–2200:
  97/100 years exact; the 3 diffs are within Liu's own stated uncertainty.
  Intentional divergences from ICU there (ICU's Duffett-Smith astronomy has
  no ΔT and errs 25–60 min; e.g. it invents leap months in 1794/1813/1889).
- Benchmarks (debug): dateComponents 3.2×, round-trip 3.9×, allocations
  18.6×, copy-on-write 37× vs ICU. `nextDate` fast path deliberately
  deferred to a follow-up PR (leap-month match semantics), as with #2105.

## After opening

Watch reviews from this machine; size questions → argue absolute costs +
packing density (never "ICU already ships bigger"); update HANDOFF.md.
