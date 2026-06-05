# `v20` — SHAREABLE_APIS Tier 1A: `hash(into:)` default impl

*2026-05-18*

**Status: tested + parity-verified, NOT committed.** Second step of the
SHAREABLE_APIS refactor (after Tier 0 v19). Smallest viable Tier 1 step —
moves `hash(into:)` to a `_CalendarProtocol` default impl, de-duplicating
2 of 5 conformer hash bodies (Hebrew + Gregorian). PR #1953 reviewer
comment #7 partially addressed.

See `backup/SHAREABLE_APIS.md` § "Scope reality" for the 1A/1B/1C sub-tier
breakdown.

## What's in this snapshot

| File | Change |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar_Protocol.swift` | Added `package func hash(into hasher: inout Hasher)` default impl in the `_CalendarProtocol` extension. Hashes the standard 7-field tuple: `identifier`, `timeZone`, `firstWeekday`, `minimumDaysInFirstWeek`, `localeIdentifier`, `preferredFirstWeekday`, `preferredMinimumDaysInFirstweek`. All 7 are existing protocol requirements — no new requirements added. |
| `Sources/FoundationEssentials/Calendar/Calendar_Hebrew.swift` | Removed `hash(into:)` implementation (8 lines). Replaced with a `// hash(into:) uses the _CalendarProtocol default impl.` marker comment. |
| `Sources/FoundationEssentials/Calendar/Calendar_Gregorian.swift` | Same removal + marker. |

Three conformers **keep their hash overrides** (different semantics):
- `_CalendarAutoupdating.hash(into:)` — `hasher.combine(1)` sentinel (all autoupdating instances compare equal).
- `_CalendarICU.hash(into:)` — uses `_locked_firstWeekday`/`_locked_minimumDaysInFirstWeek` (private locked accessors) inside a lock. Default uses public `firstWeekday`/`minimumDaysInFirstWeek` getters. Different access path, possibly different values — kept as override.
- `_CalendarBridged.hash(into:)` — `hasher.combine(_calendar)` — hashes underlying NSCalendar instance.

## Why this isn't bigger

See `SHAREABLE_APIS.md` § "Scope reality (discovered 2026-05-18 while
planning Tier 1)". Short version: extending the same default-impl
technique to `firstWeekday`/`minimumDaysInFirstWeek` getters/setters
requires either polluting `_CalendarProtocol` with `_firstWeekday` /
`_minimumDaysInFirstWeek` impl-detail requirements (Tier 1B) or
introducing a `_CalendarProperties` composition struct (Tier 1C). v20
deliberately stops here to validate the protocol-extension technique
on the cleanest case before escalating scope.

## Parity

- 174/174 Calendar+RecurrenceRule tests pass (unchanged from v19).
- 58/58 Hebrew tests pass (unchanged).
- Suite C 0 divergences.
- Verified via `./scripts/clean-test.sh "Calendar|RecurrenceRule"` —
  full clean rebuild (359s) + test (103s) = 464s total. First real
  use of the v19-incident protocol; worked as designed.

## Performance

No expected change. `hash(into:)` is rarely called in hot paths (only
when calendars are used as dictionary keys / set members). Default
impl is byte-identical to the removed Hebrew/Gregorian bodies. Not
re-benchmarked.

## Reviewer context

PR #1953 comment #7 (`itingliu` on `Calendar_Hebrew.swift:142`):
> "if I read it correctly, this file is a duplicate of Gregorian Calendar
> up at least until this point. Can we factor out common logic?"

v20 addresses ONE specific piece (`hash(into:)`). The rest of comment
#7's surface area (init, copy, firstWeekday/minimumDaysInFirstWeek
getters/setters) is in Tier 1B and 1C, planned but not yet scheduled.

When this PR lands (after PR #1953 merges), the diff hunk for Hebrew
+ Gregorian will be tiny: -8 lines each, replaced with a 1-line
comment. The new default impl in `_CalendarProtocol` extension is +18
lines. Net: -32 / +18 ≈ -14 LOC across the three files. Modest, but
proves the technique.

## Restoration

```sh
cd /Users/draganbesevic/Projects/claude/swift-foundation
cp backup/v20-shareable-apis-tier1a-hash-default/Sources/FoundationEssentials/Calendar/*.swift \
   Sources/FoundationEssentials/Calendar/
```

To roll back to v19 (with original hash impls in Hebrew + Gregorian):
- Restore `Calendar_Hebrew.swift`, `Calendar_Gregorian.swift`, and
  `Calendar_Protocol.swift` from `backup/v19-frozen-pre-v20/`.

## Next: Tier 1B (protocol-required storage + getter/setter defaults)

Per `SHAREABLE_APIS.md`. Adds `_firstWeekday` / `_minimumDaysInFirstWeek`
as `package` protocol requirements, moves the getter/setter logic to
defaults. Affects all 5 conformers (need to verify each has matching
storage). Larger PR.
