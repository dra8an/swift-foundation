---
name: Shareable APIs across Foundation calendars
description: Planning doc for the post-PR-1953 follow-up that extracts shared logic out of `_CalendarHebrew` (and `_CalendarGregorian`) into a common base. Anchored on reviewer comments in PR #1953.
type: reference
---

# Shareable APIs: extraction plan for the post-PR-1953 follow-up

**Status (2026-05-20)**:

- **v19**: ✅ Constants → `_CalendarConstants` enum (2026-05-18).
- **v20**: ✅ `hash(into:)` default impl in `_CalendarProtocol` (2026-05-18).
- **v21**: ✅ Accessor helpers (firstWeekday, minimumDaysInFirstWeek, copy()) via new `_CalendarUtility` enum with **static helpers** (2026-05-20). Took ~74 lines of Hebrew+Gregorian duplication and moved the logic into one place. Each calendar's getter/setter/copy body is now a one-line forwarder. No protocol changes, no composition struct, no class-layout changes — turned out the original "Tier 2 vs Tier 3 design fork" was a false dilemma. Static helpers with explicit parameters bypass both.
- **v22**: ✅ `isDateInWeekend` body extracted to `_CalendarUtility.isDateInWeekend(weekday:timeInDay:weekendRange:)` (2026-05-21). Hebrew + Gregorian thinned by 64 lines combined; ~35 lines added to utility. Net -29 LOC. Side benefit: Hebrew's `timeInDay` computation aligned to Gregorian's integer-truncation pattern, fixing previously-flagged fractional-second divergence.
- **Remaining work** (not yet scoped as tiers — depends on reviewer reaction to v19+v20+v21+v22):
  - **`init` body**: Hebrew + Gregorian each have ~50 lines of init logic. Some validation overlap, but calendar-specific defaults (ISO8601 in Gregorian) are interleaved. Harder to share cleanly.
  - **Stored properties themselves**: would need composition struct (`_CalendarProperties`). Biggest layout-changing refactor — only worth doing if the reviewer wants more after v19+v20+v21.
  - **Pure math helpers**: `weekNumber` is the only true Hebrew↔Gregorian duplicate. Others (`weekday(fromRataDie:)`, `secondsInDay(from:)`, `utcDate(fromRataDie:...)`) are Hebrew-only currently. Worth doing as "infrastructure for future calendars" but not as direct duplication reduction.
  - **`isDateInWeekend`**: small known divergence vs Gregorian (fractional seconds, DST instant offset) — worth fixing when we extract it.

Captures (a) the reviewer's specific asks, (b) the broader
extraction scope we identified earlier, and (c) what NOT to extract.

## Motivation

PR #1953 reviewer `@itingliu` flagged two duplication asks:

- **[Comment #6](https://github.com/swiftlang/swift-foundation/pull/1953#discussion_r3216545828)** on `Calendar_Hebrew.swift:39` — *"As we mentioned previously, these constants overlap with those in GregorianCalendar. We should extra these out so they can be shared"*. Targets the time-unit constants (`kSecondsInWeek`, `kSecondsInDay`, `kSecondsInHour`, `kSecondsInMinute`, `inf_ti`).
- **[Comment #7](https://github.com/swiftlang/swift-foundation/pull/1953#discussion_r3216553050)** on `Calendar_Hebrew.swift:142` — *"if I read it correctly, this file is a duplicate of Gregorian Calendar up at least until this point. Can we factor out common logic?"*. Targets the property storage + init/copy/hash boilerplate that's the first ~140 lines of the class body.

`@dra8an` replied (#13): *"I was planning to do this in a separate PR, but please let me know if you think I should do it in this one."* Reviewer agreed (#14): *"ah thanks that works too"*. So **this is a separate PR**, not a PR-#1953 blocker.

Independent of the reviewer, we've also identified ~10 calendar-agnostic arithmetic helpers inside `_CalendarHebrew` that mirror logic in `_CalendarGregorian` (the `// Matches _CalendarGregorian.foo exactly` comments scattered through the file). Those are natural Tier 2 candidates for the same refactor.

## Where shared code lives — the three homes

Not everything sharable goes in the same place. Decision rule, with examples from what we've already done:

| Kind of code | Home | Why | Examples |
|---|---|---|---|
| **Shared values / sentinels** — pure numeric or `let`-style constants | New `internal enum _CalendarConstants` (Swift namespace) | Constants aren't functions or storage; they're just values. Static lets in an enum are the idiomatic Swift namespace. | `kSecondsInDay`, `kSecondsInWeek`, `inf_ti` — moved here in v19. |
| **Instance methods that need `self` and read protocol-required fields** | `_CalendarProtocol` extension as default impl | The protocol already requires the fields. A default impl in the extension lets every conformer inherit the same behavior; conformers with different semantics can override (Swift dispatches to the override automatically). | `hash(into:)` — moved here in v20. (`nextDate`, `localeIdentifier`, etc. were already there from earlier work.) |
| **Pure functions on already-decomposed inputs** — no `self`, no instance state | New `internal enum _CalendarUtility` (utility namespace, static methods) | These don't need calendar identity. Putting them on the protocol would just clutter the protocol surface. A free-standing utility enum keeps the API surface clean and the helpers callable without an instance (also easier to unit-test). | `weekNumber(desiredDay:dayOfPeriod:weekday:firstWeekday:minimumDaysInFirstWeek:)` — pure math, takes 5 ints. `weekday(fromRataDie:)` — modular arithmetic on an int. `utcDate(fromRataDie:secondsInDay:in:repeatedTimePolicy:skippedTimePolicy:)` — RD↔Date math + TZ query. Planned for Tier 4. |
| **Stored properties shared across calendars** | Composition struct (`_CalendarProperties`) held by each calendar | Storage can't live in a protocol extension — Swift forbids stored properties in extensions. Only a struct/class can hold state. Each calendar would have `let properties: _CalendarProperties` instead of individual fields. | `identifier`, `locale`, `timeZone`, `_firstWeekday`, `_minimumDaysInFirstWeek`. Planned for Tier 3. |

### Quick decision tree

When considering "should I extract this duplicated code?", ask:

```
Is it just a value (number, sentinel, magic constant)?
└─ Yes → _CalendarConstants enum (or similar namespace)

Is it a method that reads instance state?
├─ Are all the fields it reads already in _CalendarProtocol?
│   └─ Yes → _CalendarProtocol extension as default impl
│
└─ Does it only need plain inputs, no instance state?
    └─ Yes → _CalendarUtility enum, static method

Is it the storage itself (a stored property)?
└─ Yes → composition struct (_CalendarProperties or similar)
```

### Hard case: methods that read private storage not on the protocol

The `firstWeekday` getter reads `_firstWeekday` (private stored property). That's calendar state, but it's not on the protocol. So the rule above doesn't cleanly answer. Two choices when this comes up:

- **Add the private storage to the protocol** — extends `_CalendarProtocol` with `var _firstWeekday: Int? { get set }`. Lets the getter become a default impl. Cost: pollutes the protocol with implementation detail, forces all 5 conformers to provide them.
- **Move the storage to a composition struct** — `_CalendarProperties` owns `_firstWeekday`, and exposes `firstWeekday` as a property. Each calendar forwards. Cost: bigger refactor, class layout change.

Neither is "wrong". Tier 2 will need this decision; Tier 3 commits to the composition path.

## Scope summary

| Snapshot | What | Reviewer-anchored? | Status |
|---|---|---|---|
| **v19** | Time-unit constants (`kSecondsIn*`, `inf_ti`) → `_CalendarConstants` enum | ✓ Comment #6 | **✅ done** |
| **v20** | `hash(into:)` default impl in `_CalendarProtocol` extension | ✓ Comment #7 (partial) | **✅ done** |
| **v21** | Accessor helpers (`firstWeekday`, `minimumDaysInFirstWeek`, `copy()`) via static methods in new `_CalendarUtility` enum | ✓ Comment #7 (substantive) | **✅ done** |
| **v22** | `isDateInWeekend` body extracted to `_CalendarUtility` (with side-benefit fractional-second alignment fix) | ✓ Comment #7 (small) | **✅ done** |
| open | `init` body extraction (calendar-specific defaults interleaved with validation) | ✓ Comment #7 (remaining) | scoped, not started |
| open | Composition struct for stored properties (`_CalendarProperties`) | ✓ Comment #7 (deeper) | only if reviewer wants more |
| open | Pure math helpers infrastructure (`weekNumber` is the one true Hebrew↔Gregorian duplicate; others are Hebrew-only) | future calendars | nice-to-have |

## Tier 0 — Time-unit constants

**Current locations**:
- `Calendar_Hebrew.swift:39–43` (and `inf_ti` at line 45)
- `Calendar_Gregorian.swift` (same constants, also instance properties — though some are static)

**Constants**:

```swift
let kSecondsInWeek = 604_800
let kSecondsInDay = 86400
let kSecondsInHour = 3600
let kSecondsInMinute = 60
let inf_ti: TimeInterval = 4398046511104.0
```

**Proposed extraction**: a free-standing file `Sources/FoundationEssentials/Calendar/CalendarConstants.swift` exposing these as `internal` enum statics:

```swift
internal enum _CalendarConstants {
    static let secondsInWeek = 604_800
    static let secondsInDay = 86400
    static let secondsInHour = 3600
    static let secondsInMinute = 60
    /// Sentinel used by unbounded-search loops in date arithmetic.
    static let infiniteTimeInterval: TimeInterval = 4398046511104.0
}
```

Drop the `k`-prefix (Foundation modern convention). Drop the per-instance storage in both calendars; replace call sites with `_CalendarConstants.secondsInDay` etc.

**Risk**: minimal. Pure numeric values. Compiler-checked replacement.

**Where to land**: first commit of the follow-up PR. Builds confidence before the bigger property-storage refactor.

## Tier 1 — `hash(into:)` default impl ✅ done (v20)

Moved Hebrew's + Gregorian's identical 8-line `hash(into:)` body into a default impl on `_CalendarProtocol`'s extension. Both calendars now inherit it. Three other conformers (`_CalendarAutoupdating`, `_CalendarICU`, `_CalendarBridged`) keep their own overrides because they have genuinely different hash semantics. See `backup/v20-shareable-apis-tier1a-hash-default/README.md` for details.

## Tier 2 — Property accessor defaults (planning)

### What's duplicated

Hebrew and Gregorian have identical 14-line `firstWeekday` getter/setter:

```swift
var firstWeekday: Int {
    set { precondition(newValue >= 1 && newValue <= 7); _firstWeekday = newValue }
    get {
        if let _firstWeekday { return _firstWeekday }
        else if let locale { return locale.firstDayOfWeek.icuIndex }
        else { return 1 }
    }
}
```

Same shape for `minimumDaysInFirstWeek`. Total ~30 lines of identical code.

### Why it's hard

The getter reads `_firstWeekday` — a *private* stored property NOT in `_CalendarProtocol`. For a default-impl approach to work, the private storage has to be exposed as a protocol requirement. Two paths:

- **Pollute the protocol.** Add `_firstWeekday` / `_minimumDaysInFirstWeek` as `package` requirements. All 5 conformers must comply (including `_CalendarAutoupdating` and `_CalendarBridged`, which currently delegate to wrapped calendars).
- **Skip this tier; do Tier 3 directly.** Composition struct owns the storage AND the getter/setter logic. Replaces both Tier 2 and the storage parts.

### Conformer status reality

The duplicated boilerplate spans all 5 `_CalendarProtocol` conformers, not just Hebrew + Gregorian:

- `_CalendarAutoupdating` — likely forwards to a wrapped calendar.
- `_CalendarHebrew` — has the standard storage.
- `_CalendarGregorian` — has the standard storage.
- `_CalendarICU` — has thread-locked variants (`_locked_firstWeekday`).
- `_CalendarBridged` — wraps an NSCalendar.

Path A would require auditing each of these.

## Tier 3 — Property storage composition (planning, deferred)

**Deferral trigger (decided 2026-06-05):** Tier 3 is the bigger win
(layout-changing refactor that compresses each conformer's init/copy/
hash/storage from ~50–80 lines to a few delegating lines), but it's
also the riskiest. We deliberately defer it until **conformer count
reaches ≥3 non-Gregorian pure-Swift calendars** (i.e., after Islamic /
Persian / Coptic / Japanese land alongside Hebrew). At that point the
duplication-pain crosses the threshold where the refactor pays for
itself in upcoming-port savings and the per-conformer LOC win matches
the refactor cost. Until then, the modest Tier 0/1/2 extractions are
sufficient — they establish the shared-helper pattern and give future
ports a head start without committing to the bigger composition.


### What it does

Replace each calendar's individual stored properties (`identifier`, `locale`, `timeZone`, `_firstWeekday`, `_minimumDaysInFirstWeek`) with a single struct held by composition:

```swift
internal struct _CalendarProperties {
    let identifier: Calendar.Identifier
    var locale: Locale?
    var timeZone: TimeZone
    var _firstWeekday: Int?
    var _minimumDaysInFirstWeek: Int?
}

internal final class _CalendarHebrew: _CalendarProtocol {
    var properties: _CalendarProperties
    // accessors forward to properties
}
```

### Why it's the biggest

- Class layout changes for all 5 conformers (strict `clean-test.sh` discipline required — see `BUILD_CACHE_PROTOCOL.md`).
- Every `init` has to be rewritten to populate the struct.
- Every place in the calendar that reads `self.identifier` etc. now goes through the struct (`self.properties.identifier`).

### Why it might replace Tier 2

If storage moves into the struct, the `firstWeekday` getter can also live on the struct (or forward from the calendar). The "expose `_firstWeekday` to the protocol" problem goes away. Tier 3 partly *replaces* Tier 2 instead of building on it.

## Tier 4 — Pure math helpers → `_CalendarUtility` enum

Functions that are calendar-agnostic on their inputs — no `self`, no instance state. These don't belong in `_CalendarProtocol` (would just clutter the protocol surface) and don't belong in a composition struct (they're not state). Static methods on a utility enum is the right home.

| API | Current location | Why pure |
|---|---|---|
| `weekNumber(desiredDay:dayOfPeriod:weekday:firstWeekday:minimumDaysInFirstWeek:) -> Int` | Hebrew line ~819, Gregorian equivalent | 5 Int inputs, Int output. Comment literally says "calendar-agnostic once the inputs are known." |
| `weekday(fromRataDie:) -> Int` | Hebrew lines ~1243, ~1292 inline | Pure modular RD math: `(rd % 7) + offset`. |
| `secondsInDay(from: DateComponents) -> Double` | Hebrew line ~1018 | `h*3600 + m*60 + s + ns/1e9`. |
| `rataDieAndSecondsInDay(localSeconds:rdAtDateReference:) -> (rd, secondsInDay)` | Hebrew line ~620 | Pure Date arithmetic. Takes the RD-at-Date-reference constant as a parameter. |
| `utcDate(fromRataDie:secondsInDay:in:repeatedTimePolicy:skippedTimePolicy:rdAtDateReference:) -> Date` | Hebrew line ~636 | Pure RD ↔ Date + TZ query. Takes the RD-at-Date-reference constant as a parameter. |

**Proposed shape**:

```swift
internal enum _CalendarUtility {
    static func weekNumber(desiredDay: Int, dayOfPeriod: Int, weekday: Int,
                            firstWeekday: Int, minimumDaysInFirstWeek: Int) -> Int

    static func weekday(fromRataDie rd: Int64) -> Int  // 1..7, Sun=1

    static func secondsInDay(from components: DateComponents) -> Double

    static func rataDieAndSecondsInDay(localSeconds: Double, rdAtDateReference: Int64) -> (rd: Int64, secondsInDay: Double)

    static func utcDate(fromRataDie rd: Int64, secondsInDay: Double, in timeZone: TimeZone,
                       repeatedTimePolicy: TimeZone.DaylightSavingTimePolicy,
                       skippedTimePolicy: TimeZone.DaylightSavingTimePolicy,
                       rdAtDateReference: Int64) -> Date
}
```

The RD-at-Date-reference constant (R.D. day-number of Foundation's `Date` reference instant — Jan 1 2001 00:00 UTC) could alternatively live in `_CalendarConstants` since it's universal. Passing it as a parameter keeps the function fully pure; promoting it to a constant trades a bit of purity for less verbose call sites. To be decided when implementing.

**Risk**: low. Pure functions; per-calendar arithmetic stays in place; only the helpers move. No class-layout changes — `clean-test.sh` discipline still recommended but the cache-staleness risk doesn't apply.

**Where to land**: independent of Tier 1/2/3; can go in any order. Possibly its own commit / PR.

### NOT in Tier 4 (belong elsewhere)

These were initially considered for Tier 4 but actually need `self`:

- **`isDateInWeekend(_:)`** — reads `self.locale`, `self.timeZone`, calls `self.dateComponents([.weekday], ...)`. Belongs as a `_CalendarProtocol` default impl (same mechanism as v20's hash). Future Tier-1-like work.
- **Multi-unit subtraction algorithm in `dateComponents(_:from:to:)`** — calls `self.date(byAdding:)` and `self.date(from:)`. Also Tier-1-like.

## Tier 5 — Almost-shared (deferred; not in this PR)

Logic that *almost* shares but has a small calendar-specific knob. Worth refactoring eventually, but the closure/callback design adds friction.

| API | Knob | Note |
|---|---|---|
| `dateComponents(_:from:in:)` skeleton | The year/month/day decomposition (`HebrewArithmetic.hebrewFromFixed` vs Gregorian's equivalent) | Could take a `yearMonthDayFromRD: (Int64) -> (Int, Int, Int)` closure. Defer. |
| `date(from:)` validation + offset path | `fixedFromYMD` + leap-month/skipped-month rules | Same pattern as above. Defer. |
| Fast-path `nextDate` skeleton — gate + dispatch | The per-shape helpers are inherently calendar-specific | Hard to share — punt. |
| `date(byAdding:)` field-application sequence | The order is shared (year → month → week/day → time); each step's clamping rules are calendar-specific | Defer. |

## What NOT to extract

Per-calendar arithmetic, leap-year/leap-month rules, era handling, epoch math, ICU-specific behavior preserved by each calendar:

- Anything inside `HebrewArithmetic` — Reingold & Dershowitz formulas, civil↔biblical month conversion, year data, leap rules.
- The fast-path *implementations* (`nextMonthWeekdayOrdinalMatch` etc.) — bake in calendar-specific arithmetic.
- Calendar-specific component validation (Adar I leap-only, Kislev 29/30, etc.).
- The Gregorian-Julian cutover handling (`gregorianStartDate`) — only relevant to Gregorian.

## Implementation order recommendation

Tiers are sequential in numbering but can be done in different orders depending on appetite for risk:

- **Already done**: Tier 0 (v19) + Tier 1 (v20).
- **Next clean win**: Tier 4 (pure math helpers). No design dilemmas, no class-layout changes. Can be done independently of Tier 2/3.
- **Architectural decision needed**: Tier 2 vs Tier 3. Tier 2 pollutes the protocol; Tier 3 is a bigger composition refactor that *replaces* Tier 2's need. Decide based on reviewer preference or your own judgment.
- **Deferred**: Tier 5.

Each commit should:
- Reference the relevant PR #1953 comment in its commit message (#6 for Tier 0; #7 for Tier 1/2/3).
- Run our local Suite A + Suite B + Suite C + Hebcal regression on `port/hebrew` before pushing — these don't run on `port/hebrew-main` but the regression nets are intact locally.
- Use `./scripts/clean-test.sh` if the change touches stored properties (Tier 3). For other tiers (constants, hash, math helpers), incremental `swift test` is fine.

## Sync to `port/hebrew-main` (and back-sync workflow)

Currently each tier is being done directly on `port/hebrew` as a v-numbered snapshot (v19 = Tier 0, v20 = Tier 1, etc.) ahead of PR #1953 merging. When `port/hebrew-main` is ready, these commits will be cherry-picked / re-applied onto a new branch off `port/hebrew-main` for the upstream follow-up PR.

This local-first approach is important because:
- Our local Suite A/B/C verifies the extraction didn't break Hebrew parity (those tests don't exist on `port/hebrew-main`).
- The v8–v15 perf stack on `port/hebrew` builds on top of the `_CalendarHebrew` shape; the refactor work has to stay consistent with that stack.

## Cross-references

- **PR #1953**: <https://github.com/swiftlang/swift-foundation/pull/1953>
  - Comment #6 (constants): <https://github.com/swiftlang/swift-foundation/pull/1953#discussion_r3216545828>
  - Comment #7 (duplicate up to line 142): <https://github.com/swiftlang/swift-foundation/pull/1953#discussion_r3216553050>
- **Earlier discussion** of the arithmetic-helpers tier: session conversation on 2026-05-07 (also captured implicitly in `FAST_PATHS_OVERVIEW.md`).
- **`MAIN_MERGE.md`**: workflow for landing changes upstream and back-syncing.
- **`SHARED_CODE_SAFETY.md`**: precedent for "non-Hebrew calendars must remain behavior-equivalent" — applies here too. Tier 1's `_CalendarProtocol` default-impl additions should follow the same pattern.

## Open questions for whenever you start the work

- For Tier 1 design (A) vs (B), do upstream maintainers have a preference? Could be worth asking `@itingliu` in the follow-up PR's description.
- Should `_CalendarBase` / `_CalendarProperties` (if A) or the protocol-default helpers (if B) live in `Sources/FoundationEssentials/Calendar/Calendar_Protocol.swift`, in a new file, or somewhere else? Foundation's existing convention for shared protocol machinery may dictate.
- Tier 2's `_CalendarUtility` enum naming — does Foundation prefer `_CalendarMath`, `_CalendarHelpers`, `_RataDie` (for the RD-specific parts), or something else?
- Do we extract Gregorian's matching helpers at the same time, or do we move Hebrew's and leave Gregorian's duplicate until a second pass? Reviewer is asking to "factor out common logic" — the cleanest fix is both calendars use the shared APIs in the same commit, but the diff size grows. Worth confirming.
