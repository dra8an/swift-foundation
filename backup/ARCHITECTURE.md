# Hebrew calendar — architecture before & after

How the public `Calendar` API gets answered for `.hebrew` — old (ICU-backed)
vs new (pure-Swift `_CalendarHebrew`).

The shape of the dispatch is identical: `Calendar` (public struct) holds an
`any _CalendarProtocol` and forwards every observable surface through the
same ~10 primitives. The port replaced the *implementation* behind that
protocol, not the protocol itself.

---

## Old architecture — `_CalendarICU(.hebrew)`

```mermaid
flowchart LR
    classDef public fill:#e8f0ff,stroke:#3060b0,color:#000
    classDef proto fill:#fff4d8,stroke:#b07810,color:#000
    classDef icu fill:#ffd8d8,stroke:#b03030,color:#000
    classDef ext fill:#e0e0e0,stroke:#606060,color:#000

    subgraph PUB["public struct Calendar"]
        direction TB
        P_RANGE["minimumRange / maximumRange / range"]:::public
        P_DCMP["component / dateComponents (3 variants)"]:::public
        P_DATE["date(from:)"]:::public
        P_ADD["date(byAdding:) / dates(byAdding:)<br/>date(bySetting:) / date(bySettingHour:)"]:::public
        P_DIFF["dateComponents(_:from:to:)"]:::public
        P_INT["dateInterval / startOfDay"]:::public
        P_ORD["ordinality"]:::public
        P_CMP["compare / isDate(equalTo:granularity:)<br/>isDate(inSameDayAs:) / isDateIn{Today,Yesterday,Tomorrow}"]:::public
        P_WKND["isDateInWeekend / dateIntervalOfWeekend / nextWeekend"]:::public
        P_MATCH["enumerateDates / dates(byMatching:)<br/>nextDate(after:matching:) / date(_:matchesComponents:)"]:::public
    end

    subgraph PROTO["any _CalendarProtocol  (10 primitives)"]
        direction TB
        I1["minimumRange(of:)"]:::proto
        I2["maximumRange(of:)"]:::proto
        I3["range(of:in:for:)"]:::proto
        I4["ordinality(of:in:for:)"]:::proto
        I5["dateInterval(of:for:)"]:::proto
        I6["isDateInWeekend(_:)"]:::proto
        I7["date(from:)"]:::proto
        I8["dateComponents(_:from:in:)"]:::proto
        I9["date(byAdding:to:wrappingComponents:)"]:::proto
        I10["dateComponents(_:from:to:)"]:::proto
    end

    subgraph IMPL["_CalendarICU  (Objective-C++ shim)"]
        direction TB
        ICU_BRIDGE["Foundation bridge<br/>(ucal_*, NSCalendar)"]:::icu
    end

    subgraph LIB["ICU C/C++ library  (external)"]
        direction TB
        ICU_HCAL["icu::HebrewCalendar"]:::ext
        ICU_TZ["icu::TimeZone"]:::ext
        ICU_RES["ICU resource bundles<br/>(month names, weekend rules)"]:::ext
    end

    P_RANGE --> I1 & I2 & I3
    P_DCMP --> I8
    P_DATE --> I7
    P_ADD  --> I9
    P_DIFF --> I10
    P_INT  --> I5
    P_ORD  --> I4
    P_WKND --> I6 & I3 & I9
    P_CMP  --> I5 & I8 & I9
    P_MATCH --> I8 & I9 & I3 & I5

    I1 & I2 & I3 & I4 & I5 & I6 & I7 & I8 & I9 & I10 --> ICU_BRIDGE
    ICU_BRIDGE --> ICU_HCAL
    ICU_BRIDGE --> ICU_TZ
    ICU_HCAL --> ICU_RES
```

**Characteristics**

- Every primitive crossed an Objective-C++ bridge into ICU's C/C++ calendar code.
- `Calendar(.hebrew)` carried the cost of allocating an `icu::Calendar`
  per instance and round-tripping `UDate` (ms-since-1970 double) for every
  query.
- Behavior was defined by ICU. Any future ICU upgrade could shift edge
  cases (e.g. `.weekOfYear` for Adar II boundaries) silently.

---

## New architecture — `_CalendarHebrew` (pure Swift)

```mermaid
flowchart LR
    classDef public fill:#e8f0ff,stroke:#3060b0,color:#000
    classDef proto fill:#fff4d8,stroke:#b07810,color:#000
    classDef swift fill:#d8f5d8,stroke:#308030,color:#000
    classDef arith fill:#cfe9cf,stroke:#206020,color:#000

    subgraph PUB["public struct Calendar  (unchanged)"]
        direction TB
        P_RANGE["minimumRange / maximumRange / range"]:::public
        P_DCMP["component / dateComponents (3 variants)"]:::public
        P_DATE["date(from:)"]:::public
        P_ADD["date(byAdding:) / dates(byAdding:)<br/>date(bySetting:) / date(bySettingHour:)"]:::public
        P_DIFF["dateComponents(_:from:to:)"]:::public
        P_INT["dateInterval / startOfDay"]:::public
        P_ORD["ordinality"]:::public
        P_CMP["compare / isDate(equalTo:granularity:)<br/>isDate(inSameDayAs:) / isDateIn{Today,Yesterday,Tomorrow}"]:::public
        P_WKND["isDateInWeekend / dateIntervalOfWeekend / nextWeekend"]:::public
        P_MATCH["enumerateDates / dates(byMatching:)<br/>nextDate(after:matching:) / date(_:matchesComponents:)"]:::public
    end

    subgraph PROTO["any _CalendarProtocol  (same 10 primitives)"]
        direction TB
        I1["minimumRange(of:)"]:::proto
        I2["maximumRange(of:)"]:::proto
        I3["range(of:in:for:)"]:::proto
        I4["ordinality(of:in:for:)"]:::proto
        I5["dateInterval(of:for:)"]:::proto
        I6["isDateInWeekend(_:)"]:::proto
        I7["date(from:)"]:::proto
        I8["dateComponents(_:from:in:)"]:::proto
        I9["date(byAdding:to:wrappingComponents:)"]:::proto
        I10["dateComponents(_:from:to:)"]:::proto
    end

    subgraph IMPL["_CalendarHebrew  (pure Swift, FoundationEssentials)"]
        direction TB
        H_FIELDS["dateComponents fill-out:<br/>weekdayOrdinal / weekOfMonth / weekOfYear /<br/>yearForWeekOfYear / quarter / dayOfYear / isLeapMonth"]:::swift
        H_RANGE["bounds tables (matching ICU):<br/>min/max for year, weekOfYear,<br/>weekdayOrdinal, weekOfMonth, …"]:::swift
        H_ORD["ordinality tables<br/>(mcount / mquarter / firstWeekday-aware)"]:::swift
        H_INT["dateInterval logic<br/>(.era → ~inf_ti, .quarter, .weekOfYear,<br/>.weekOfMonth, .yearForWeekOfYear)"]:::swift
        H_ADD["date(byAdding:) including<br/>.yearForWeekOfYear (was no-op pre-port)"]:::swift
        H_TZ["TimeZone.rawAndDaylightSavingTimeOffset<br/>(internal API — direct, no probes)"]:::swift
    end

    subgraph ARITH["HebrewArithmetic  (Reingold & Dershowitz)"]
        direction TB
        A_LEAP["isLeapYear  (Metonic 19-yr cycle)"]:::arith
        A_MOLAD["elapsedDays / molad arithmetic"]:::arith
        A_YEARDATA["YearData (cached per conversion):<br/>year start, length, leap flag"]:::arith
        A_FIXED["fixedFromHebrew / hebrewFromFixed<br/>(biblical month ordering internally)"]:::arith
        A_CIVIL["civil ↔ biblical month conversion<br/>(Tishrei = month 1 publicly)"]:::arith
    end

    P_RANGE --> I1 & I2 & I3
    P_DCMP --> I8
    P_DATE --> I7
    P_ADD  --> I9
    P_DIFF --> I10
    P_INT  --> I5
    P_ORD  --> I4
    P_WKND --> I6 & I3 & I9
    P_CMP  --> I5 & I8 & I9
    P_MATCH --> I8 & I9 & I3 & I5

    I1 & I2 --> H_RANGE
    I3 --> H_RANGE & H_FIELDS
    I4 --> H_ORD
    I5 --> H_INT
    I6 -. "Sat-only,<br/>locale-driven" .- I6
    I7 --> A_FIXED & A_CIVIL
    I8 --> H_FIELDS & H_TZ
    I9 --> H_ADD & A_FIXED
    I10 --> H_FIELDS

    H_FIELDS --> A_FIXED & A_YEARDATA & A_CIVIL
    H_RANGE  --> A_YEARDATA
    H_ORD    --> A_YEARDATA & A_FIXED
    H_INT    --> A_FIXED & A_YEARDATA
    H_ADD    --> A_FIXED & A_LEAP & A_CIVIL

    A_FIXED  --> A_MOLAD & A_LEAP
    A_YEARDATA --> A_MOLAD & A_LEAP
```

**Characteristics**

- No process-out call. Every primitive is value-typed Swift down to RataDie
  (fixed-day) arithmetic.
- `_CalendarHebrew` is a class but final and pinned per-instance; arithmetic
  is `Sendable` and lock-free.
- UTC↔local boundaries match `_CalendarGregorian` exactly: extraction uses
  `secondsFromGMT(for:)`, construction uses `rawAndDaylightSavingTimeOffset(for:repeatedTimePolicy:)`
  (skipped policy not passed through, matching Gregorian's call shape).
- Behavior is pinned by parity probes (Suite A + Suite B), the Hebcal
  regression, and direct policy-parity tests. Future ICU changes can no
  longer move our edge cases.

---

## What changed at the seams

| Seam | Old | New |
|---|---|---|
| `_CalendarProtocol` shape | unchanged | unchanged |
| Router (`_calendarClass(.hebrew)`) | `_CalendarICU.self` | `_CalendarHebrew.self` |
| Per-call cost | ObjC++ bridge + ICU `UDate` round-trip | Swift inline arithmetic |
| DST handling | ICU + Foundation `TimeZone` | internal `rawAndDaylightSavingTimeOffset` |
| Source of truth for edge cases | ICU resource bundles | `HebrewArithmetic` + parity probes |
| Tested observable surface | implicit (whatever ICU did) | 10 primitives + ~25 public methods, ~300 dates × 13 topics in both Suite A (protocol) and Suite B (public API) + DST policy parity (64 cases) + locale variations (6 configs) + Hebcal 73k-day regression + full Foundation suite (1510 tests) — all green |

The crucial property: **the public `Calendar` API and the `_CalendarProtocol`
are the same in both diagrams.** The port is a swap of the leaf
implementation behind the protocol. Every call site outside
`Sources/FoundationEssentials/Calendar/Calendar_Cache.swift` is unaware the
change happened — which is exactly what the parity protocol guarantees.
