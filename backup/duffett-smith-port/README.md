# Duffett-Smith astronomy port (CONTINGENCY — do not ship without agreement)

**⚠ This port must NOT be included in any feature branch or PR unless the
user explicitly agrees.** It exists so that, if upstream review demands
ICU-exact out-of-range behavior for the Chinese calendar, the switch is a
drop-in instead of a research project. Decision context: `backup/CHINESE_PLAN.md`
§ 5 (out-of-range policy) and § 5b (2026-07-17 engine research).

Faithful Swift port of the subset of ICU4C's `CalendarAstronomer`
(`i18n/astro.cpp`, Duffett-Smith "Practical Astronomy With Your
Calculator") + the astronomy glue from `i18n/chnsecal.cpp` that the
Chinese calendar needs. Fidelity rules honored (see § 5b Q3): pure UT
(NO ΔT — ICU has none), Kepler epsilon 1e-5, `ceil()` millisecond
stepping + recursive anti-divergence restart in `timeOfAngle`,
floor-based angle normalization, flat UTC+8, ICU's epoch literals.

- `Sources/dsverify/DuffettSmithAstronomer.swift` — astro.cpp subset (~170 LOC)
- `Sources/dsverify/ChineseAstro.swift` — chnsecal glue (~150 LOC, incl.
  Apple's chnsecal-level adjustment tables behind a default-off flag)
- `Sources/dsverify/main.swift` — day-level parity sweep vs macOS system
  ICU (`Calendar(identifier: .chinese)`) over 1500–1700, 1900–2100,
  2150–2350, plus a month-start check vs the HKO CSV

## Verified status (2026-07-17)

`swift run -c release dsverify`:

- **Out of range (the port's domain): 0 divergent days / 146,827**
  (1500–1700 and 2150–2350) vs system ICU. There Apple ICU = pure
  upstream Duffett-Smith, so this is exact `_CalendarICU` parity.
- In range 1900–2100: 538 divergent days across 16 month-runs — **by
  design**: Apple ICU replaces the astronomy there with baked tables
  (`astro.cpp` `newMoonDates[]` ~2,500 instants + `sunLongitudeAdjustmts`,
  rdar://15539491&16688723; plus chnsecal `newYearAdj`/`winterSolsticeAdj`,
  rdar://17888673). Apple's own comment: tables are "accurate to one
  minute of time instead of 25, 60, or worse". In-range parity is the
  baked-year-table strategy's job (sweep `_CalendarICU`), not this port's.
- Pure Duffett-Smith skill vs HKO authority in 1901–2099: 15 missed month
  starts / 2,461 (Apple-tables ICU: 3; icu4swift Reingold: 1; Moshier: 1).

If this port is ever activated as the out-of-range fallback, the parity
probe against `_CalendarICU` can extend to the full supported year range.
