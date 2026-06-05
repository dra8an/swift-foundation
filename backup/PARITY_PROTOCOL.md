# Parity protocol — every pure-Swift calendar port must match ICU

**Status:** Non-negotiable. This document is load-bearing for the entire
Foundation calendar port. It describes the contract that `_CalendarX` (any
pure-Swift calendar class replacing an ICU-backed one) must satisfy before
its router flip is acceptable for the final PR.

## ⚠ CRITICAL — parity covers the **entire public `Calendar` API**, not just `_CalendarProtocol`

The router flip in `_calendarClass(identifier:)` is the moment every app in
the world stops calling `_CalendarICU(.X)` and starts calling `_CalendarX`.
**From that instant forward, any behavioral difference is a regression in
production.** There is no gentle rollout, no opt-in flag, no staged exposure.

Because of this, parity testing cannot stop at the ~10 `_CalendarProtocol`
primitives. Foundation's `Calendar` struct exposes **~41 public methods**
on top of the protocol. Many are generic wrappers that delegate cleanly to
the protocol (and so come for free if the protocol is right). But **several
carry calendar-specific logic of their own inside `Calendar.swift`** — e.g.,
week-boundary handling in `compare(_:to:toGranularity:)`, weekend-edge
semantics in `dateIntervalOfWeekend`, multi-unit recursive subtraction in
`dateComponents(_:from:to:)`. These can silently diverge even when the
protocol methods match.

**Therefore the parity contract for every calendar port is:**

1. **All ~10 `_CalendarProtocol` methods** must match `_CalendarICU`'s output
   across every observable field, every `(smaller, larger)` pair, every
   component in dateInterval / range / byAdding, and every bound in
   minimumRange / maximumRange.

2. **Every public `Calendar` method** that takes calendar-dependent input
   or produces calendar-dependent output must **also** be directly probed
   against `_CalendarICU(.X)`-backed `Calendar` and produce identical
   results. That means writing a separate public-API probe alongside the
   protocol probe.

3. **Both probes must show zero divergences** across the full required
   date set (multiple edge-case dates per calendar) before the router flip.

**This is not a joke.** A calendar that passes the protocol probe but has
never been tested against `Calendar.compare(...)` or `Calendar.nextWeekend(...)`
is **not** a drop-in replacement for `_CalendarICU`. Shipping it is a
production regression.

## Why

Foundation's public `Calendar` API has been shipped for a decade backed by
ICU4C. Every app written against `Calendar(identifier: .X)` observes specific
behavior on every protocol method — not just the common `date(from:)` /
`dateComponents(_:from:)` paths. A drop-in pure-Swift replacement is only
a drop-in replacement if it matches that observable behavior **exactly**,
including:

- Every field populated by `dateComponents(_:from:in:)`.
- Every `(smaller, larger)` pair in `ordinality(of:in:for:)`.
- Every case in `dateInterval(of:for:)`.
- Every `date(byAdding:)` component.
- Every `minimumRange` / `maximumRange` entry.
- Every `range(of:in:for:)` pair in the common matrix.

Even obscure fields like `.weekdayOrdinal` or `.yearForWeekOfYear` are
observable — tests and apps call them. A nil where ICU returned an Int, or
a bounds mismatch on `minimumRange(of: .year)`, is a behavioral regression.

**Therefore: every calendar port requires a side-by-side ICU parity probe
that produces zero divergences from the ICU baseline.**

## The probe

Each pure-Swift calendar gets a diagnostic test file in
`Tests/FoundationInternationalizationTests/<X>ICUComparisonProbe.swift`
(must be in the Internationalization target so it can `@testable import`
both `FoundationEssentials` and `FoundationInternationalization`).

Template is in `backup/PARITY_PROTOCOL.md` § "Template probe" below.
Hebrew's concrete instance is
`Tests/FoundationInternationalizationTests/HebrewICUComparisonProbe.swift`
— use it as the starting reference when porting a new calendar.

### What the probe exercises — **TWO distinct probe suites required**

#### Suite A: `_CalendarProtocol` direct probe (`<X>ICUComparisonProbe.swift`)

Instantiates `_CalendarICU(identifier: .X, ...)` and `_CalendarX(...)` side
by side, picks multiple edge-case dates, and compares their output on every
observable protocol surface:

1. **`dateComponents(_:from:in:)` query.** 15 fields per date:
   `.era`, `.year`, `.month`, `.day`, `.hour`, `.minute`, `.second`,
   `.weekday`, `.weekdayOrdinal`, `.quarter`, `.weekOfMonth`, `.weekOfYear`,
   `.yearForWeekOfYear`, `.dayOfYear`, `.isLeapMonth`.

2. **`dateInterval(of: X, for:)`.** 9 components per date:
   `.era`, `.year`, `.month`, `.day`, `.hour`, `.quarter`,
   `.weekOfYear`, `.weekOfMonth`, `.yearForWeekOfYear`.

3. **`ordinality(of: smaller, in: larger, for:)`.** 12 pairs per date
   covering {day, month, quarter, weekOfYear, weekOfMonth, weekday,
   weekdayOrdinal, hour} × {year, month, quarter, weekOfYear, day}.

4. **`range(of: smaller, in: larger, for:)`.** 5 critical pairs:
   `(.day, .year)`, `(.day, .month)`, `(.month, .year)`,
   `(.weekOfYear, .year)`, `(.weekOfMonth, .month)`.

5. **`date(byAdding: <component>, value: 1, to:)`.** 9 components:
   `.day`, `.weekOfYear`, `.weekOfMonth`, `.weekdayOrdinal`, `.month`,
   `.year`, `.quarter`, `.yearForWeekOfYear`, `.hour`.

6. **`minimumRange(of:)` / `maximumRange(of:)`.** 13 components:
   all of the Calendar.Component values except `.calendar` and `.timeZone`.

#### Suite B: Public `Calendar` API probe (`<X>PublicAPIComparisonProbe.swift`)

Instantiates **two `Calendar` structs** (one routed to `_CalendarICU(.X)`
before the flip, one routed to `_CalendarX` after) with identical locale /
timeZone, and compares every **public `Calendar` method** whose output
depends on the underlying calendar. This catches divergences in public-API
wrappers that have their own calendar-specific logic layered over the
protocol.

Complete list of public methods that MUST be probed:

**Direct queries:**
- `component(_:from:)` — for every `Calendar.Component`.
- `dateComponents(_:from:)`, `dateComponents(in:from:)`,
  `dateComponents(_:from:to:)` (Date variant), `dateComponents(_:from:to:)`
  (DateComponents variant).
- `range(of:in:for:)`, `ordinality(of:in:for:)`,
  `dateInterval(of:start:interval:for:)` (inout variant).

**Arithmetic:**
- `date(from:)`, `date(byAdding:to:wrappingComponents:)` (both overloads:
  `DateComponents` and `(Component, value:)`).
- `date(bySetting:value:of:)` — sets component to a value.
- `date(bySettingHour:minute:second:of:...)` — sets time.
- `dates(byAdding:...)` sequences (both overloads).
- `startOfDay(for:)`.

**Comparisons:**
- `compare(_:to:toGranularity:)` — every granularity, across DST edges.
- `isDate(_:equalTo:toGranularity:)` — every granularity.
- `isDate(_:inSameDayAs:)`.
- `isDateInToday/Yesterday/Tomorrow(_:)` — each.
- `date(_:matchesComponents:)`.

**Weekend queries (calendar-specific! these frequently diverge):**
- `isDateInWeekend(_:)`.
- `dateIntervalOfWeekend(containing:)` (both overloads).
- `nextWeekend(startingAfter:direction:)` (both overloads, both directions).

**Enumeration:**
- `enumerateDates(startingAfter:matching:matchingPolicy:
  repeatedTimePolicy:direction:using:)` — multiple matching policies,
  both directions, with/without DST crossing.
- `nextDate(after:matching:matchingPolicy:repeatedTimePolicy:direction:)`.
- `dates(byMatching:startingAt:in:matchingPolicy:...)`.

**NOT exhaustive but required minimum.** Any new `Calendar` method added
to Foundation in the future is covered by the contract the moment it ships.

### Probe dates (multiple required)

A single probe date is **not sufficient**. Each calendar has
calendar-specific edge cases (leap years, month boundaries, year boundaries,
date-line-adjacent times in DST zones, etc.). Minimum required coverage:

- **One common-year date** away from any boundary.
- **One leap-year date** away from any boundary.
- **First day of a year** (tests `.year` interval + all `month = 1` paths).
- **Last day of a year** (stresses year rollover + `.dayOfYear`).
- **A date around any calendar-specific quirk** — e.g., for Hebrew: Adar I ↔
  Adar II transition; Cheshvan 29/30 boundary; Kislev 29/30 boundary. For
  Islamic: month-length boundaries. For Chinese: leap month boundaries.
  For Hindu: any sankranti / solar-month boundary.
- **A DST-crossing timezone probe** (e.g., `America/Los_Angeles` around the
  spring-forward weekend) — exercise `date(byAdding: .day)` and
  `dateInterval(of: .day)` at the hour-off-by-one day.

### Acceptance criterion — **BOTH suites must pass**

Zero divergences across **both** Suite A (`_CalendarProtocol`) **and**
Suite B (public `Calendar` API) over the full required date set. A calendar
port whose protocol probe is green but whose public-API probe hasn't even
been written is **not ready to ship** regardless of how clean the protocol
numbers look.

Any difference in either suite is either:

1. A **bug to fix**, or
2. An **accepted divergence** documented in the calendar's per-calendar
   `PARITY.md` with explicit justification **plus** an explicit
   acknowledgment that this divergence will be user-visible from the
   moment of the router flip.

No row may silently stay red. No public API may be untested.

## Per-calendar artifacts

For each calendar X that gets a pure-Swift implementation, the following
MUST exist and be green before the router flip:

### 1. `backup/PARITY_<X>.md` (per-calendar parity requirement)

Captured from a run of the X probes against multiple dates, with every
diverging row marked **MUST match** (and a fix plan) or **accepted
divergence** (with explicit user-visible-regression acknowledgment).
Hebrew's version: `backup/PARITY.md`.

Must document:
- Protocol-suite results (Suite A).
- Public-API-suite results (Suite B).
- Every edge-case probe date exercised.

### 2. `Tests/FoundationInternationalizationTests/<X>ICUComparisonProbe.swift`

**Suite A** — the `_CalendarProtocol` probe. Copies the Hebrew template
shape with the calendar identifier and probe-date list adjusted. Kept in
the repo; re-run after every change to `_CalendarX`.

### 3. `Tests/FoundationInternationalizationTests/<X>PublicAPIComparisonProbe.swift`

**Suite B** — the public `Calendar` API probe. Builds two `Calendar`
structs (one routed to `_CalendarICU(.X)`, one routed to `_CalendarX`) and
exercises every Calendar public method listed above. Same date set as
Suite A, same "zero divergences" acceptance criterion.

### 4. Tasks blocking PR submission

Each PARITY gap in either suite becomes a task. The calendar's router flip
to `_CalendarX` cannot land until **both** probes show zero divergences
across the required date set.

## Rollout plan

| Calendar | PARITY.md | Protocol probe | Public-API probe | Status |
|---|---|---|---|---|
| `.hebrew` | `backup/PARITY.md` | `HebrewICUComparisonProbe.swift` ✅ 0 divergences | **missing — must be added before merge** | protocol suite green; public-API suite not yet written |
| `.coptic` | TBD | TBD | TBD | — |
| `.ethiopicAmeteMihret` | TBD | TBD | TBD | — |
| `.ethiopicAmeteAlem` | TBD | TBD | TBD | — |
| `.islamicCivil` | TBD | TBD | TBD | — |
| `.islamicTabular` | TBD | TBD | TBD | — |
| `.islamicUmmAlQura` | TBD | TBD | TBD | — |
| `.islamic` (observational) | TBD | TBD | TBD | — |
| `.persian` | TBD | TBD | TBD | — |
| `.indian` | TBD | TBD | TBD | — |
| `.buddhist` | TBD | TBD (derives from Gregorian) | TBD | — |
| `.republicOfChina` | TBD | TBD (derives from Gregorian) | TBD | — |
| `.japanese` | TBD | TBD | TBD | — |
| `.chinese` | TBD | TBD | TBD | — |
| `.dangi` | TBD | TBD | TBD | — |
| `.vietnamese` | TBD | TBD | TBD | — |
| `.gujarati` / `.kannada` / `.marathi` / `.telugu` / `.vikram` | TBD | TBD | TBD | — |

Each row advances from *TBD* → *protocol probe green* → *public-API probe
green* → *router flipped* → *PR-ready*. A calendar is **not PR-ready**
until both probes show zero divergences.

## Protocol rules

1. **No router flip without BOTH probes passing.** A `_CalendarX` whose
   protocol probe is green but whose public-API probe has not been run
   (or has any divergence) is **not ready**. The temptation to ship early
   on protocol-only parity and "come back to fix the public API later"
   must be resisted — every `Calendar` user in the world starts hitting
   the new code the instant the router flips. Observability of any gap
   means it's a production regression for apps that call `Calendar.compare`,
   `Calendar.nextWeekend`, `Calendar.dates(byMatching:)`, etc.

2. **The probe is cheap to run** (milliseconds per date × ~10 dates =
   sub-second). Running it after every meaningful code change to
   `_CalendarX` takes no time and catches regressions immediately.

3. **Accepted divergences require justification.** If ICU's behavior is
   genuinely wrong (e.g., `ICU .quarter = 0` for Hebrew, which is not
   a valid 1..4 value), the per-calendar PARITY.md can accept the
   divergence — but must explain why, cite the ICU source, and note whether
   the "correct" behavior is planned for a future revision.

4. **The probe is extended, not replaced, per calendar.** Future ports add
   more date cases as they discover calendar-specific edge conditions.
   The Hebrew probe has `Adar I/II` and `Cheshvan/Kislev 29-30`; Chinese
   will need leap-month boundaries; Hindu will need sankranti edges.

## Template probe

The Hebrew probe (`HebrewICUComparisonProbe.swift`) is the canonical
starting point. To port it to calendar X:

1. Copy the file to `<X>ICUComparisonProbe.swift`.
2. Change `@Suite("Hebrew ICU Comparison Probe")` → `@Suite("<X> ICU Comparison Probe")`.
3. Change both `_CalendarICU(...)` and `_CalendarHebrew(...)` instantiations to use `identifier: .X` and the pure-Swift class `_CalendarX`.
4. Expand the probe date list to include calendar-specific edge cases.
5. Run; diff against ICU; capture the diff in `backup/PARITY_<X>.md`; file tasks for each gap.

That's the entire rollout per calendar.
