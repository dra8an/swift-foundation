# v23-frozen-pre-v24

Safety snapshot of `Tests/FoundationEssentialsTests/HebrewCalendarTests.swift`
captured 2026-06-04 immediately before applying v24 (back-sync of upstream
`b1b8fdf` "Move ICU-dependent Hebrew calendar tests to
FoundationInternationalizationTests").

## Restore

```sh
cp backup/v23-frozen-pre-v24/Tests/FoundationEssentialsTests/HebrewCalendarTests.swift \
   Tests/FoundationEssentialsTests/HebrewCalendarTests.swift

# And remove the file v24 created (since the patch was net-additive otherwise):
rm Tests/FoundationInternationalizationTests/HebrewCalendarICUTests.swift
```
