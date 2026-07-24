# Gregorian-variant calendars: shared-core design (ROC + dedup)

Decision-evolution log for eliminating the duplicated wrapper shell in the
pseudo-Gregorian calendars. Started 2026-07-23 from the user's concern:
Buddhist and Japanese each re-implement the same delegation scaffolding
around `_CalendarGregorian` because it is `final`; adding ROC (Minguo)
the same way would make a third copy.

## § 1. Problem statement (2026-07-23)

- `_CalendarGregorian` (3,055 lines) is `final`, deliberately: upstream's
  perf posture relies on devirtualized dispatch on the hot path.
  Inheritance is not available and un-finaling it will not pass review.
- `_CalendarBuddhist` (153 lines) and `_CalendarJapanese` (469 lines) are
  composition wrappers holding a `gregorian` instance. The genuinely
  per-calendar content is small (era range, era interval, year mapping;
  Japanese adds the era table and mid-year era boundaries). The rest is
  a repeated shell: property forwarding (locale/timeZone/firstWeekday/
  minimumDaysInFirstWeek), copy(), hash(), range/ordinality/dateInterval/
  isDateInWeekend passthroughs, and the convert-in/adjust-out pattern
  around date(from:), dateComponents, byAdding, from:to.
- ROC repeats the shell a third time. Every future pseudo-Gregorian
  (if any) repeats it again.

## § 2. Current measurements (research branch, synced to PR #2105 final)

| File | Lines | Of which shell (approx.) |
|---|---|---|
| Calendar_Buddhist.swift | 153 | ~110 |
| Calendar_Japanese.swift | 469 | ~110 |
| Calendar_Gregorian.swift | 3,055 | n/a (the delegate) |

Estimated after refactor: shared variant class ~200 lines, Buddhist
policy ~30, ROC policy ~30, Japanese policy ~250 (era table + hooks).
Net for three calendars ≈ 510 lines vs ≈ 775 by cloning the shell again;
each further pseudo-Gregorian ≈ +30 instead of +150.

## § 3. Options considered

### 3a. Subclass _CalendarGregorian — REJECTED
Blocked by `final`; un-finaling deoptimizes the hot path (devirtualization)
and invites fragile-base coupling. Upstream will not take it.

### 3b. Protocol with default witness implementations — REJECTED (soft)
A `_GregorianBackedCalendar` protocol refining `_CalendarProtocol` with
defaulted forwarding methods. Works, but collides head-on with the new
guideline rule (PR #2091, itingliu): "Do not provide a default
protocol-witness implementation when existing conformances already
diverge in real behavior." The forwarding defaults are uniform today,
but the rule signals reviewer taste; avoid the debate.

### 3c. Generic wrapper over an era policy — RECOMMENDED

```swift
// Policies are enums with only static functions; they are never instantiated and cost nothing at runtime.
protocol _GregorianEraPolicy: Sendable {
    static var identifier: Calendar.Identifier { get }
    static var eraRange: Range<Int> { get }
    static func toGregorian(_ components: inout DateComponents)
    static func fromGregorian(_ components: inout DateComponents, requested: Calendar.ComponentSet)
    static func eraInterval(containing date: Date) -> DateInterval?
}

final class _CalendarGregorianVariant<Policy: _GregorianEraPolicy>: _CalendarProtocol {
    let gregorian: _CalendarGregorian
    // forwarding shell + convert-in/adjust-out plumbing, written once
}

typealias _CalendarBuddhist = _CalendarGregorianVariant<BuddhistEra>   // year = gregorian + 543
typealias _CalendarROC      = _CalendarGregorianVariant<ROCEra>        // year = gregorian - 1911, era 0/1 at 1912 boundary
typealias _CalendarJapanese = _CalendarGregorianVariant<JapaneseEra>   // policy carries the 237-entry era table
```

Why this shape wins:
- Each specialization is still `final` and statically dispatched, so the
  performance argument that justified `final` on Gregorian is preserved.
- Policies are pure value-level mapping logic, trivially testable.
- Japanese keeps its genuinely hard content (era table, mid-year era
  starts, per-era year ranges) inside its policy; the shell dedupes.
- Zero change to _CalendarProtocol or Gregorian itself.

Open design points (need decisions):
1. Policy hook surface for Japanese: the minimal set above suffices for
   Buddhist/ROC; Japanese needs additional hooks (per-era year range,
   era-boundary handling in adds, addingEra behavior). Enumerate them
   from the current Calendar_Japanese and decide whether they become
   optional protocol requirements with no-op defaults for Buddhist/ROC
   (careful: same default-witness taste question as 3b, though here the
   protocol is ours and narrow) or a single richer required surface.
2. Class name and file layout: one file for the variant class + one per
   policy, vs one file total. Guideline says file names track type names.
3. ROC specifics: era 1 (minguo) from 1912; era 0 (before-minguo) counts
   backward, mirroring ICU. Verify against _CalendarICU(.republicOfChina)
   behavior, including the year-0/negative handling.
4. Whether Calendar_Cache's flag routing gets one shared flag or
   per-calendar flags (precedent: per-calendar).

## § 4. Sequencing (recommended)

1. Do NOT restructure PR #2105: it is approved; reopening a finished
   review to refactor costs goodwill and time.
2. Land #2105 and #2123 as they are.
3. Prototype the variant refactor on THIS research branch, where the
   exhaustive B/J probe suites (105 tests / 25 suites currently green)
   gate behavior-neutrality of the refactor.
4. Ship it upstream as the ROC PR: "Add the Republic of China calendar
   by extracting a shared Gregorian-variant core." The diff adds a
   calendar while shrinking net lines, the strongest review story this
   refactor can have, timed exactly when the third duplication would
   otherwise appear.

## § 5. Decision log

- 2026-07-23: problem raised by user; options 3a-3c drafted; sequencing
  proposal drafted. User comments pending, nothing decided yet.
- 2026-07-23 (user Q1): can the variant be a struct instead of a class,
  given that Foundation people prefer to avoid classes? Answer: no, and
  the framework itself is the reason. The protocol every calendar
  backend implements, `_CalendarProtocol`, is declared with AnyObject,
  so only a class may implement it. That is not an accident: Calendar
  keeps one backend object per identifier in a cache, and every
  Calendar value for that identifier points at the same single backend
  object. Only when someone changes a property (say the time zone) does
  that calendar first make its own private copy of the backend and
  modify that. The arrangement needs objects that can be shared by
  pointing at them; structs get copied every time they are passed
  around, so there would be nothing to share.
  The concern behind the question is still satisfied, though. The
  dislike of classes is about adding new ones that carry runtime cost,
  and this refactor goes the opposite way: today there are three
  separate wrapper classes (Buddhist, Japanese, and ROC would be the
  third); afterward there is one, and the calendars are just names for
  that one class filled in with different era rules. The new code we
  write is not classes at all: the era rules live in enums containing
  only static functions, never instantiated, costing nothing at
  runtime. The only object ever created is the same one created today,
  the wrapper holding its Gregorian helper.
- 2026-07-24: Japanese era table TRIMMED by decision: all pre-Meiji
  eras removed, 5 remain (Meiji 232, Taisho 233, Showa 234, Heisei 235,
  Reiwa 236). ICU index numbering must be preserved — renumbering 1-5
  would break every modern date's era value vs ICU and shipping
  Foundation; verify at back-sync. Executed by the 6.4 machine on the
  PR branch; research branch follows by back-sync. Consequences for
  this design: the Japanese policy shrinks from ~250 lines to roughly
  90 — the drop is pure data deletion (237 table rows → 5); the ~80
  lines of era logic (lookups, eraInterval, year mapping both ways,
  first-era clamp) survive unchanged, since they are needed for 5 eras
  exactly as for 237. § 2 estimates shift accordingly. Japanese remains
  the largest policy and still needs its extra hooks, so open point 1
  (hook surface) narrows but does not go away.
  Pre-Meiji behavior: see the landed entry below, which supersedes
  the clamp assumption this entry was written with.
- 2026-07-24 (landed): the trim shipped as PR #2105 commit 9e65da05
  with a better mechanism than the clamp assumed above. CLDR dropped
  the pre-Meiji era data and ICU is adopting inheritEras: gregorian
  (unicode-org/icu#4019, ICU-23341), so dates before Meiji report the
  inherited Gregorian era (0 = BCE, 1 = CE) with Gregorian years,
  falling straight out of the existing _CalendarGregorian delegation
  (the CE era interval is clipped at Meiji's start). Numbering
  verified sparse and preserved (Meiji 232 … Reiwa 236; 2…231
  undefined). This is NOT a deliberate divergence from ICU: it
  matches unreleased ICU; only the bundled ICU (still shipping the
  237-era data) differs, so the pre-Meiji parity probes are disabled
  with re-enable-on-Apple-rebase notes rather than carved out of
  PARITY_PROTOCOL. Golden values pinned ICU-independently in
  JapaneseGregorianEraInheritanceTests. The first-era clamp is gone
  from the policy hook surface (pre-Meiji needs no Japanese logic at
  all, delegation covers it). Watch item: icu#4019 joins icu#4070
  for Apple-rebase reconciliation.
