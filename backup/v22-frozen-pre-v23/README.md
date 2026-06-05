# v22-frozen-pre-v23

Safety snapshot of v22 state for files about to be modified by v23
(back-sync of upstream `f94c6ac` "Fix missing `floor` and add a feature
flag", authored by Tina Liu 2026-05-20 on `port/hebrew-main`).

Captured 2026-06-04 immediately before applying the v23 patch.

## Files captured

- `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift`
- `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift`

## Restore

```sh
cp backup/v22-frozen-pre-v23/Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift
cp backup/v22-frozen-pre-v23/Sources/FoundationEssentials/Calendar/Calendar_Cache.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Cache.swift
```
