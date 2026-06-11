# Buddhist + Japanese calendar port plan (composition over `_CalendarGregorian`)

Draft 2026-06-11. Pre-Hebrew-merge planning doc — execution starts after PR #2028 merges.

## Approach

Composition. Each new calendar holds a `_CalendarGregorian` instance and forwards everything that's Gregorian-equivalent; overrides only `era` + `year` extraction/construction. `final` on `_CalendarGregorian` is fine — we never subclass.

Each calendar conforms to `_CalendarProtocol`, gets routed via `_calendarClass(identifier:)`, gated behind its own feature flag (same staged-rollout pattern as Hebrew).

## Buddhist (BE — Buddhist Era)

### Semantics

- Year = Gregorian year + 543. Era is always `.buddhist` (single-era).
- Everything else (months, days, weeks, weekdays, leap years, time-of-day) identical to Gregorian.
- ICU identifier: `buddhist`.

### Files

- `Sources/FoundationEssentials/Calendar/Calendar_Buddhist.swift` (NEW).
- `Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` — add feature flag + router entry.

### Shape sketch

```swift
internal final class _CalendarBuddhist: _CalendarProtocol, @unchecked Sendable {
    private let gregorian: _CalendarGregorian
    let identifier: Calendar.Identifier = .buddhist
    // ... protocol stored properties (firstWeekday, minimumDaysInFirstWeek, timeZone, locale)
    // Use _CalendarUtility helpers same as Hebrew/Gregorian.
    
    static let yearOffset = 543
    
    func dateComponents(_ components: Calendar.ComponentSet, from date: Date) -> DateComponents {
        var dc = gregorian.dateComponents(components, from: date)
        if components.contains(.year), let y = dc.year { dc.year = y + Self.yearOffset }
        if components.contains(.era) { dc.era = 0 }   // single era
        return dc
    }
    
    func date(from components: DateComponents) -> Date? {
        var dc = components
        if let y = dc.year { dc.year = y - Self.yearOffset }
        dc.era = nil
        return gregorian.date(from: dc)
    }
    
    func date(byAdding: ..., to: Date, ...) -> Date? {
        gregorian.date(byAdding: ..., to: date, ...)   // year-add semantics unchanged
    }
    
    func dateComponents(..., from start: Date, to end: Date) -> DateComponents {
        var dc = gregorian.dateComponents(..., from: start, to: end)
        // year-difference unchanged (offset cancels)
        return dc
    }
    
    // Other methods: pure delegation to gregorian.
    var supportsNextDateFastPath: Bool { gregorian.supportsNextDateFastPath }   // free fast path
    func nextDate(..., matching: DateComponents, ...) -> Date? {
        var dc = components
        if let y = dc.year { dc.year = y - Self.yearOffset }   // remap before delegating
        return gregorian.nextDate(after: date, matching: dc, direction: direction)
    }
}
```

### Estimated effort

- Implementation: 200–300 LOC.
- Tests: Suite A (~10 tests), Suite B (~20 tests). Most parity divergences will be zero by construction.
- 1–2 weeks total including PR review.

### Edge cases

- Year 0 / BE 543 boundary.
- Era extraction at year 1 BE (Buddhist year 1 = Gregorian -542).
- `Calendar.Component.yearForWeekOfYear` should also be offset.
- `dateInterval(of: .era, for:)` — single era so duration is effectively `_inf_ti`.

## Japanese

### Semantics

- Era-based year. Each era has a start `Date` and a name (Meiji, Taishō, Shōwa, Heisei, Reiwa, …).
- Year-in-era = Gregorian year − era_start_year + 1 (with adjustment for partial first year — Reiwa year 1 = 2019-05-01 to 2019-12-31).
- Months/days/weeks identical to Gregorian.
- ICU identifier: `japanese`.

### Era table

Port `JapaneseEraData` directly from `<icu4swift>/Sources/CalendarJapanese/Japanese.swift`. Sorted-by-start-date array. New eras append.

### Files

- `Sources/FoundationEssentials/Calendar/Calendar_Japanese.swift` (NEW).
- Optional: `Sources/FoundationEssentials/Calendar/JapaneseEraData.swift` (NEW) — if we want the era table in its own file.

### Shape sketch

```swift
internal final class _CalendarJapanese: _CalendarProtocol, @unchecked Sendable {
    private let gregorian: _CalendarGregorian
    let identifier: Calendar.Identifier = .japanese
    
    func dateComponents(_ comps: Calendar.ComponentSet, from date: Date) -> DateComponents {
        var dc = gregorian.dateComponents(comps, from: date)
        if comps.contains(.era) || comps.contains(.year) {
            let (era, yearInEra) = JapaneseEraData.eraAndYear(for: date, gregorianYear: dc.year!)
            if comps.contains(.era) { dc.era = era }
            if comps.contains(.year) { dc.year = yearInEra }
        }
        return dc
    }
    
    func date(from components: DateComponents) -> Date? {
        guard let era = components.era, let year = components.year else { return nil }
        let gregYear = JapaneseEraData.gregorianYear(era: era, yearInEra: year)
        var dc = components
        dc.year = gregYear
        dc.era = nil
        return gregorian.date(from: dc)
    }
    
    // Era-aware nextDate, date(byAdding: .era, ...), etc. — minimal but real overrides.
}
```

### Estimated effort

- Implementation: 500–800 LOC (era table + boundary handling).
- Tests: Suite A (~15 tests including era boundaries), Suite B (~25 tests), plus a focused regression suite for era transitions.
- 3–5 weeks total including PR review.

### Edge cases

- Era boundary transitions (e.g., 2019-04-30 23:59 Heisei 31 → 2019-05-01 00:00 Reiwa 1).
- Year 1 of any era (Heisei 1 = Jan 8 1989 to Dec 31 1989, NOT a full year).
- `date(byAdding: .year, value: 1)` near era boundary — does year stay in same era or roll over? ICU's behavior is reference truth.
- `dateInterval(of: .era, for:)` — interval of the era containing `date`.
- `dateInterval(of: .year, for:)` near year-1 in era 1 — partial year.
- Future eras — table must be append-only, never reorder.

## Shared work for both

### Feature flag plumbing in `Calendar_Cache.swift`

Mirror the Hebrew pattern:

```swift
#if FOUNDATION_FRAMEWORK
internal func foundation_swift_buddhist_calendar_feature_enabled() -> Bool {
    _foundation_swift_buddhist_calendar_feature_enabled()
}
#else
internal func foundation_swift_buddhist_calendar_feature_enabled() -> Bool { return false }
#endif
// (same for japanese)

func _calendarClass(identifier: Calendar.Identifier) -> _CalendarProtocol.Type? {
    if identifier == .gregorian || identifier == .iso8601 { return _CalendarGregorian.self }
    else if foundation_swift_hebrew_calendar_feature_enabled() && identifier == .hebrew { return _CalendarHebrew.self }
    else if foundation_swift_buddhist_calendar_feature_enabled() && identifier == .buddhist { return _CalendarBuddhist.self }
    else if foundation_swift_japanese_calendar_feature_enabled() && identifier == .japanese { return _CalendarJapanese.self }
    else { return _calendarICUClass() }
}
```

The `_ForSwiftFoundation` underscored-binding for each new flag has to be added by Apple internally — they own that header. Until they add it, the flag returns `false` outside `FOUNDATION_FRAMEWORK`, which is correct for SPM build.

### Parity protocol (NON-NEGOTIABLE)

Per `PARITY_PROTOCOL.md`: each calendar must pass Suite A (protocol-level vs `_CalendarICU(.{calendar})`) + Suite B (public-API-level) with zero divergences before router flip.

Test files (mirror Hebrew naming):

- `Tests/FoundationInternationalizationTests/BuddhistICUComparisonProbe.swift` (Suite A, local-only — references `_CalendarICU`).
- `Tests/FoundationInternationalizationTests/BuddhistPublicAPIComparisonProbe.swift` (Suite B, local-only).
- `Tests/FoundationEssentialsTests/BuddhistCalendarTests.swift` (direct unit tests — UPSTREAM).
- `Tests/FoundationInternationalizationTests/BuddhistCalendarICUTests.swift` (UPSTREAM — tests that use `Calendar(identifier: .buddhist)`).
- Same shape for Japanese.

Suite C (RecurrenceRule parity) optional for these — Buddhist's RecurrenceRule path is identical to Gregorian by construction, so no new fast paths needed. Japanese might benefit from a Suite C if era transitions interact with recurrence rules in surprising ways.

### Composition pattern questions to resolve before coding

1. **Does the inner `_CalendarGregorian` need to share `firstWeekday` / `minimumDaysInFirstWeek` with the outer?** Probably yes — when user sets `cal.firstWeekday = 2` on a Buddhist calendar, the inner gregorian needs that too. Implementation: outer's setter propagates to inner.
2. **Equality / hash**: two Buddhist calendars are equal iff their inner Gregorians are equal. Inherits `hash(into:)` default impl from `_CalendarProtocol` extension — should work, since identifier is part of the tuple.
3. **TimeZone handling**: same as Hebrew — `utcDate(fromRataDie:)` uses `tz.secondsFromGMT(for:)` directly, not `skippedTimePolicy`. Verify the wrapped Gregorian's `timeZone` matches the outer's.

## Order of execution

1. **Start local development now — in parallel with PR #2028.** No file-level conflict: the only existing-file edit (`Calendar_Cache.swift` router entries) isn't touched by PR #2028. New source files (`Calendar_Buddhist.swift`, `Calendar_Japanese.swift`, parity probes) don't exist on either branch. Local `port/hebrew` already has `_CalendarUtility` + `_CalendarConstants` available for reuse.
2. **Buddhist first.** Smaller, validates the composition pattern, exercises the parity tests less aggressively (fewer boundary cases). 1 PR.
3. **Japanese second.** Builds on Buddhist's parity-test scaffolding. 1 PR.
4. **PR opening waits for PR #2028 to merge.** Buddhist's PR branch needs `upstream/main` to contain `_CalendarUtility` + `_CalendarConstants` (PR #2028 Commit 2) for clean cherry-picks. Local development carries on uninterrupted in the meantime — perfect use of the reviewer-cycle wait.

## Branching strategy (REVISED — single branch for both)

Decision 2026-06-11: both calendars share one branch. They're each small enough that separate PRs would be more overhead than value, and the shared infrastructure (feature flag pattern, composition pattern over Gregorian, parity test helpers) is the same.

| Branch | Machine | Based on | Role |
|---|---|---|---|
| `port/buddhist` (Buddhist + Japanese local research) | 6.3 iMac | `port/hebrew` | local research, both calendars' implementations + Suite A/B probes |
| `port/buddhist-japanese-main` (later) | 6.4 machine | latest `upstream/main` (post-merge Hebrew) | PR base, clean |

Workflow when ready to PR:
1. On 6.4 machine: `git checkout -b port/buddhist-japanese-main origin/upstream/main`.
2. Cherry-pick / copy both Buddhist + Japanese implementations from `port/buddhist`.
3. Strip local-only Suite A / B probes (which reference `_CalendarICU`).
4. Push → open one PR covering both calendars.

Single PR shape (proposed):
- Commit 1: Buddhist (`Calendar_Buddhist.swift` + feature flag + tests that ship upstream).
- Commit 2: Japanese (`Calendar_Japanese.swift` + `JapaneseEraData.swift` + feature flag + tests that ship upstream).

Same two-tier discipline we used for Hebrew → `port/hebrew-perf-and-dedup`, just with both calendars bundled.

## Open questions

1. **Should `_CalendarBuddhist` re-use the Hebrew-style fast paths?** Probably no special fast paths needed — delegation to Gregorian gives "free" fast paths for whatever Gregorian implements. Hebrew's perf work was Hebrew-specific (calendar arithmetic was slow); Buddhist's perf is the same as Gregorian's by construction.
2. **Does the upstream maintainer prefer a single PR with both, or two separate PRs?** Hebrew's reviewer (`itingliu`) likely has a preference. Worth asking in PR #2028 conversation or via the eventual Buddhist PR's description.
3. **Where does `JapaneseEraData` live?** Standalone file (`JapaneseEraData.swift`) for clarity, or inline in `Calendar_Japanese.swift`? Likely standalone — table will grow over time.
4. **Era-numbering convention for Japanese**: ICU numbers eras starting from "Taika" (Era 0 in the very old reckoning). Foundation might use a different convention. Verify against `_CalendarICU(.japanese)` early.
5. **Should we wait for the Tier 4 arithmetic-helper extraction first?** That would let Buddhist/Japanese call `_GregorianArithmetic.dateFromYMD(...)` directly without going through a class instance. Decision: skip Tier 4 for now — composition with a class instance is fine and avoids a larger refactor PR.

## Risk register

- **Feature flag flakiness on Apple platforms.** Hebrew's revert (`#2015`) was due to a missing platform import. Buddhist/Japanese inherit the same risk — non-Darwin libc needs `floor` etc. Mirror Hebrew's import block.
- **Era table mistakes (Japanese)** — date boundaries are public-record but easy to fat-finger. Validate the table against an authoritative source (`https://en.wikipedia.org/wiki/Japanese_era_name`) before locking it in.
- **Parity test undercoverage**. The Hebrew port found 9 bugs by expanding Suite A from ~10 dates to ~300. Plan for at least 300 dates per Suite A test, more for Japanese (era transitions need targeted dates).

## Reference

- icu4swift: `<icu4swift>/Sources/CalendarSimple/Buddhist.swift` (Buddhist) and `<icu4swift>/Sources/CalendarJapanese/Japanese.swift` (Japanese era data).
- `backup/HANDOFF.md` — current Hebrew state and patterns to follow.
- `backup/PARITY_PROTOCOL.md` — non-negotiable parity contract.
- `backup/PR_PLAN.md` — Hebrew PR plan, useful as a template.
- `backup/LOCAL_VS_UPSTREAM_DIVERGENCE.md` — the Option B probe pattern Buddhist/Japanese also benefit from.
