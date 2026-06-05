# `v21` — Shared accessor helpers via `_CalendarUtility`

*2026-05-20*

**Status: tested + parity-verified, NOT committed.** Substantial
de-duplication of Hebrew + Gregorian. Static helpers — no protocol
changes, no composition struct, no class-layout changes.

## What's in this snapshot

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/CalendarUtility.swift` (NEW) | New file. `internal enum _CalendarUtility` with 5 static helpers: `validatedFirstWeekday`, `resolveFirstWeekday`, `clampedMinimumDaysInFirstWeek`, `resolveMinimumDaysInFirstWeek`, `resolvedCopyArgs`. |
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Thinned `firstWeekday` + `minimumDaysInFirstWeek` getters/setters to one-line forwarders. Thinned `copy()` body from ~24 lines to ~8 lines. |
| `Sources/FoundationEssentials/Calendar/Calendar_Gregorian.swift` | Same changes. |

## What changed

Before (Hebrew, same code in Gregorian):

```swift
var firstWeekday: Int {
    set {
        precondition(newValue >= 1 && newValue <= 7, "Weekday should be in the range of 1...7")
        _firstWeekday = newValue
    }
    get {
        if let _firstWeekday {
            return _firstWeekday
        } else if let locale {
            return locale.firstDayOfWeek.icuIndex
        } else {
            return 1
        }
    }
}
```

After:

```swift
var firstWeekday: Int {
    set { _firstWeekday = _CalendarUtility.validatedFirstWeekday(newValue) }
    get { _CalendarUtility.resolveFirstWeekday(stored: _firstWeekday, locale: locale) }
}
```

Same pattern for `minimumDaysInFirstWeek`. Same pattern for `copy()`:
the 24-line "resolve override or current" logic becomes a single call
to `_CalendarUtility.resolvedCopyArgs(...)` returning a 4-field tuple.

## Why this approach (instead of protocol-default impls)

The naive way to share these would be default impls in
`_CalendarProtocol` extension. But the getters read `_firstWeekday`
(private storage not in the protocol), so default impls would require
either polluting the protocol with `_firstWeekday`/`_minimumDaysInFirstWeek`
as `package` requirements, or doing a composition-struct refactor.

The simpler way — used here — is **static helpers that take all the
state they need as parameters**. Each calendar keeps its own storage;
the logic moves to a shared place; getters/setters become one-line
forwarders. Same trick as v20's `hash(into:)` extraction, but for
methods that read private state too.

No protocol changes. No composition struct. No class-layout changes
(SPM cache footgun doesn't apply). The 5 conformers other than Hebrew
+ Gregorian are completely unaffected — they keep their own
implementations.

## Code reduction (Hebrew + Gregorian combined)

Approximate LOC counts before vs after:

| Block | Before | After | Reduction |
|---|---:|---:|---:|
| `firstWeekday` getter/setter (per calendar) | 14 | 4 | -10 × 2 = -20 |
| `minimumDaysInFirstWeek` getter/setter (per calendar) | 16 | 4 | -12 × 2 = -24 |
| `copy()` body (per calendar) | 22 | 7 | -15 × 2 = -30 |
| **Total in Hebrew + Gregorian** | **104** | **30** | **-74** |
| `_CalendarUtility.swift` (new) | 0 | 79 | +79 |
| **Net** | **104** | **109** | **+5** |

The net line count is barely changed, but **the duplicated logic now
exists in exactly one place**. Future calendars (Coptic, Islamic, etc.)
will use the helpers and save ~50 lines each. The architectural win is
real even though the immediate diff isn't dramatic.

## Parity

- 174/174 Calendar+RecurrenceRule tests pass (unchanged from v20).
- 58/58 Hebrew tests pass (unchanged).
- Suite C 0 divergences.
- Verified on **incremental build** — no class-layout changes means
  the SPM cache footgun doesn't apply, plain `swift test` works fine.

## Reviewer context

PR #1953 comment #7 (`itingliu` on `Calendar_Hebrew.swift:142`):
> "if I read it correctly, this file is a duplicate of Gregorian Calendar
> up at least until this point. Can we factor out common logic?"

v20 addressed `hash(into:)`. v21 addresses the bigger duplication:
the getter/setter logic for `firstWeekday` + `minimumDaysInFirstWeek`,
plus the `copy()` body. Roughly 50+ lines of the original ~140-line
"duplicate of Gregorian" surface area are now actually de-duplicated.

Remaining duplication not yet addressed by v19/v20/v21:
- `init` body (~50 lines per calendar) — has calendar-specific defaults (ISO8601 for Gregorian) so structurally harder to factor.
- The stored properties themselves (~5 lines per calendar) — would need composition struct.

## Restoration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
cp backup/v21-shareable-apis-accessor-helpers/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
```

To roll back to v20: delete `CalendarUtility.swift`, then restore
`Calendar_Hebrew.swift` + `Calendar_Gregorian.swift` from
`backup/v20-frozen-pre-v21/`.
