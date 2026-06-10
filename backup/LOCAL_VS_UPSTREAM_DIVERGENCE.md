# Local vs upstream divergence

Local `port/hebrew` carries two corrections that **do not exist in the upstream-shipped PR #2028 code**. This doc is the authoritative list. Future back-syncs must preserve these.

## Divergence #1 — Per-call probe in `Calendar.enumerateDates`

**File**: `Sources/FoundationEssentials/Calendar/Calendar.swift`.
**Function**: `enumerateDates(startingAfter:matching:matchingPolicy:repeatedTimePolicy:direction:using:)`.

### Upstream (PR #2028 shipped)

```swift
if matchingPolicy == .nextTime && repeatedTimePolicy == .first,
   _supportsNextDateFastPath {
    var current = start
    var stop = false
    while !stop {
        guard let next = _calendar.nextDate(after: current, matching: components, direction: direction) else {
            block(nil, false, &stop)
            return
        }
        ...
    }
}
```

### Local (port/hebrew, v26)

```swift
if matchingPolicy == .nextTime && repeatedTimePolicy == .first,
   _supportsNextDateFastPath,
   let firstMatch = _calendar.nextDate(after: start, matching: components, direction: direction) {
    var stop = false
    block(firstMatch, true, &stop)
    var current = firstMatch
    while !stop {
        guard let next = _calendar.nextDate(after: current, matching: components, direction: direction) else {
            block(nil, false, &stop)
            return
        }
        ...
    }
}
```

## Divergence #2 — Per-call probe in `DatesByMatching.Iterator.init`

**File**: `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift`.

### Upstream

```swift
self.usesFastPath = validates && matchingPolicy == .nextTime && repeatedTimePolicy == .first && calendar._supportsNextDateFastPath
```

### Local

```swift
self.usesFastPath = validates && matchingPolicy == .nextTime && repeatedTimePolicy == .first
    && calendar._supportsNextDateFastPath
    && calendar._calendarNextDate(after: start, matching: matchingComponents, direction: direction) != nil
```

## Why we diverge

The reviewer's `supportsNextDateFastPath: Bool` is a calendar-level "I implement the fast path" flag — not pattern-level "I handle THIS pattern." Hebrew's fast path covers `{month, day}`, `{month, weekday, weekdayOrdinal}`, `{month, weekday, weekOfMonth}`, partial time-of-day, and a few others — but not `{year}`, `{era}`, `{weekOfYear}`, `{yearForWeekOfYear}`, `{dayOfYear}`, `{day, weekOfMonth}`, `{weekdayOrdinal}` without weekday, `{weekday, day}`, or `{weekday, month}`. Patterns Hebrew can't fast-path return nil from `Hebrew.nextDate(...)`.

Upstream: Hebrew opts in (flag = true), framework commits to fast loop, Hebrew returns nil for an unsupported pattern → user gets nil. Silently breaks `date(bySetting: .year, ...)`, `date(bySetting: .dayOfYear, ...)`, etc.

Local: probe runs once when the iterator/enumerator starts. If Hebrew can't handle this pattern, probe returns nil and we fall through to the generic enumerate framework (which uses primitives + ICU-style semantics). All patterns work.

Verified by Suite B `metonicCycle_nineteenYears` and similar probes: **all 211 tests pass with the probe; 14 fail without it.**

## Cost of the probe

One extra `nextDate(after: start, matching: components, ...)` call per `enumerateDates` invocation, **gated on `_supportsNextDateFastPath`**. Non-opt-in calendars (Gregorian, Islamic, ICU-backed everything else) short-circuit before the probe — zero extra cost.

For Hebrew, the probe takes 1–5 µs (it's a real fast-path execution). For an `enumerateDates` invocation that produces N matches, the probe overhead is amortized over N. Negligible.

## Why upstream doesn't see this

PR #2028's tests exercise patterns Hebrew fully supports (`{month, weekday, weekdayOrdinal}` / Thanksgivings-style, etc.). The probe-or-fall-through gap doesn't surface in those tests. Our Suite B exercises `date(bySetting: .hour)`, `date(bySetting: .minute)`, `date(bySetting: .year)`, etc. — the patterns Hebrew bails on. Those broke; the probe fixes them.

## Going upstream (eventual)

Three avenues:

1. **Submit the probe as a follow-up PR.** Argument: "opt-in flag is necessary but not sufficient — per-pattern probe is the practical safety net for partial fast-path coverage." Cost analysis shows it's free for non-opt-in calendars, negligible for opt-in.
2. **Extend Hebrew's fast path to handle all patterns.** Implement `{year}`, `{era}`, `{weekOfYear}`, `{dayOfYear}`, `{weekday, day}`, `{weekday, month}`, etc. Eliminates the probe's necessity but is hours of new code per pattern. Reviewer would likely accept incrementally.
3. **Hybrid**: ship the probe as a near-term safety net; gradually expand Hebrew's fast-path coverage to make the probe redundant; eventually retire the probe.

Practical recommendation: stay local for now. Revisit when more calendars opt in (each one would either get the probe automatically or need full fast-path coverage upfront — the former is cheaper).

## Sync discipline

When future upstream commits modify `Calendar.enumerateDates` or `DatesByMatching.Iterator.init`, **preserve the probe** during back-sync. The risk is accepting an upstream edit that re-removes the probe.

Mechanically: on back-sync, after running `git apply --3way`, grep for `_supportsNextDateFastPath` in both files; if the probe call (`_calendar.nextDate(...)` / `calendar._calendarNextDate(...)`) is missing from the gate, restore it before committing.

## See also

- `backup/v26-pr2028-review-feedback/README.md` — v26's full back-sync notes including this divergence.
- `backup/v25-frozen-pre-v26/` — last-known state matching the upstream-shipped code.
