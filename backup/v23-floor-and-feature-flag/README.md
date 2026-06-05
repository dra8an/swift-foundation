# v23 — Floor imports + Hebrew feature flag (back-sync from upstream `f94c6ac`)

Back-sync of upstream commit `f94c6ac` "Fix missing `floor` and add a
feature flag" (Tina Liu, 2026-05-20, on `port/hebrew-main`). Applied
2026-06-04 on local `port/hebrew` (Swift 6.3) atop v22.

## What it does

1. **Adds platform-specific libc imports** for `floor()` in
   `Calendar_Hebrew.swift`. On Darwin, `floor` comes via `import os`. On
   other platforms it comes from the platform libc:
   - `Bionic` (Android)
   - `Glibc` (Linux glibc)
   - `Musl` (Linux musl)
   - `CRT` (Windows)
   - `WASILibc` (WASI)
   Without these imports, non-Darwin builds failed to find `floor` — this
   was a confirmed root cause of the upstream PR #2015 revert.

2. **Adds the Hebrew feature flag** in `Calendar_Cache.swift`. Hebrew
   routing in `_calendarClass(identifier:)` is now gated:
   ```swift
   } else if foundation_swift_hebrew_calendar_feature_enabled() && identifier == .hebrew {
       return _CalendarHebrew.self
   }
   ```
   The flag binds to `_foundation_swift_hebrew_calendar_feature_enabled()`
   via `_ForSwiftFoundation` on `FOUNDATION_FRAMEWORK` builds, and
   returns `false` everywhere else (including the SPM build on this
   iMac).

## Implication for tests on this iMac

Because we build SPM-style (NOT `FOUNDATION_FRAMEWORK`), the flag returns
`false`. So `Calendar(identifier: .hebrew)` now routes to
`_calendarICUClass()` → `_CalendarICU(.hebrew)`, NOT `_CalendarHebrew`.

- Parity probes (Suite A, Suite B, Suite C, DST parity, Hebcal
  regression) construct `_CalendarHebrew` instances **directly** so they
  bypass the gate and continue exercising our pure-Swift implementation.
- Any test that uses `Calendar(identifier: .hebrew)` will now exercise
  ICU. The companion v24 back-sync (`b1b8fdf`) moves the three such
  tests in `HebrewCalendarTests.swift` to a new
  `HebrewCalendarICUTests.swift` to reflect this.

## Files modified

- `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` (+10):
  `#elseif canImport(Bionic) / ... / #elseif os(WASI)` import block.
- `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` (+13/-1):
  feature-flag binding + gate.

## Files captured

- `Calendar_Hebrew.swift` (after-v23 state)
- `Calendar_Cache.swift` (after-v23 state)

## Restore

```sh
cp backup/v23-floor-and-feature-flag/Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
cp backup/v23-floor-and-feature-flag/Sources/FoundationEssentials/Calendar/Calendar_Cache.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
```

## Source

```
git format-patch -1 f94c6acd7d6ef46ff0dec0b9dea285d8a6bba9ba --stdout
```

## Next

v24 (`b1b8fdf` "Move ICU-dependent Hebrew calendar tests to FoundationInternationalizationTests").
