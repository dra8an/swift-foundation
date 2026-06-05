# v24 — Move ICU-dependent Hebrew tests (back-sync from upstream `b1b8fdf`)

Back-sync of upstream commit `b1b8fdf` "Move ICU-dependent Hebrew calendar
tests to FoundationInternationalizationTests" (Tina Liu, 2026-05-20, on
`port/hebrew-main`). Applied 2026-06-04 on local `port/hebrew` (Swift 6.3)
atop v23.

## What it does

Three tests that construct `Calendar(identifier: .hebrew)` were SIGSEGV-ing
in `FoundationEssentialsTests` because that target doesn't link
`FoundationInternationalization`, so `_calendarICUClass()` returns nil. The
three tests are moved into a new file under the
`FoundationInternationalizationTests` target where the ICU backing is
available.

After v23's feature-flag gate, `Calendar(identifier: .hebrew)` now routes
to `_CalendarICU(.hebrew)` on the SPM build (the flag returns `false`
outside `FOUNDATION_FRAMEWORK`). So these three tests now exercise ICU's
Hebrew, not our pure-Swift one. That is upstream's intended design — the
parity probes (Suite A/B/C, DST policy, Hebcal regression) construct
`_CalendarHebrew` directly and bypass the gate, so they still exercise
our implementation.

## Files modified

- `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift` (-94):
  removed three tests:
  - `debug_hanukkahEnumerateFires_systemTZ`
  - `debug_hanukkahEnumerateFires`
  - `crossCheck_againstICU`
- `Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift`
  (NEW, +108): same three tests with their `private struct` renamed to
  `HebrewCalendarICUTests` and a clarifying file-level comment.

## Verification (2026-06-04, this iMac, Swift 6.3.1, debug, post-v24)

`time swift test --filter "Hebrew"` →
**58 tests in 8 suites passed after 46.4 s.** Suite count is 8 vs the 7
suites at v23 because of the new `HebrewCalendarICUTests` suite. Total
test count is unchanged (the three tests just live in a different file
now).

## Files captured

- `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift` (after-v24 state)
- `Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift` (after-v24 state)

## Restore

```sh
cp backup/v24-hebrew-test-split/Tests/FoundationEssentialsTests/HebrewCalendarTests.swift \
   Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
cp backup/v24-hebrew-test-split/Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift \
   Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift
```

To revert to v23 (drop v24 entirely):

```sh
cp backup/v23-frozen-pre-v24/Tests/FoundationEssentialsTests/HebrewCalendarTests.swift \
   Tests/FoundationEssentialsTests/HebrewCalendarTests.swift
rm Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift
```

## Source

```
git format-patch -1 b1b8fdfc5adc0f82718e62868d8c5e00ca9a796c --stdout
```

## State after v24

Local `port/hebrew` working tree is now **fully synchronized with the
upstream-merged Hebrew code** (modulo the v8–v22 perf + dedup stack that
sits on top). The branch is ready to feed the post-merge follow-up PRs
(`port/hebrew-shareable-apis` for v19–v22 dedup, `port/hebrew-fast-paths`
for v8–v15 perf).
