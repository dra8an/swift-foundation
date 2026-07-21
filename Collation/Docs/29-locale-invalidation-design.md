# Locale-Change Invalidation for Current-Locale Collator Caches

> Decision record, 2026-07-20. Closes the last standing audit-list
> design item (optimization-targets.md, THE ALLOCATION/RESOLUTION
> HUNT list). Decided: option C, generation-count revalidation —
> implemented alongside this note.

## The problem

`CollatorCache` holds three caches:

1. **`currentCache`** — the collator for `Locale.current`, resolved
   once by `collatorForCurrentLocale()` on first use. Serves every
   `localized*` String API and (since §40) `StandardComparator`.
2. **`lastLocale`** — the §38 one-slot cache for explicit-locale
   calls. Keyed by the caller-supplied locale's identifier.
3. **The per-language collator dictionary** — keyed by resolved
   tailoring name; collation data is immutable.

Caches 2 and 3 cannot go stale: their keys come from the caller or
from immutable data. Cache 1 CAN: if the user changes the system
language mid-process, `Locale.current` starts returning the new
locale, but `currentCache` keeps serving the collator resolved for
the old one. `localizedCompare` would keep sorting Swedish as German
until process restart.

## The behavioral contract we must match

On Darwin, the system `localized*` APIs follow the current locale at
call time: the NSString entry points resolve through the cached
current CFLocale, which is invalidated by the distributed
preferences-change notification. A mid-process language change is
picked up by the next call. Our backend must not silently weaken
that.

On non-Darwin platforms the current locale is effectively fixed at
process start (environment-derived; there is no system change
signal), so the gap is Darwin-only in practice — but Darwin is
exactly where the feature flag will eventually flip this code on.

## The options

**A. Status quo — resolve once, never invalidate.** Zero cost, wrong
behavior on Darwin locale changes. Rejected: it is the review
question we would be asked upstream, with no good answer.

**B. Per-call revalidation against `Locale.current` itself.**
Correct, but the accessor costs ~90 ns (§40 measured it per
comparison in the comparator path — that finding is why the current
cache exists). Rejected on cost.

**C. Generation-count revalidation.** FoundationEssentials already
maintains `LocaleNotifications.cache`, "a global generation count for
updated Locale information", with a documented contract: *"Compare
that to a cached value to see if your cached `Locale.current` … is
out of date."* `reset()` — invoked by the platform preference-change
notification paths, and already called from
FoundationInternationalization's own Locale_ObjC bridge — bumps the
count and clears `LocaleCache`/`CalendarCache`/`TimeZoneCache`. The
cross-module read is established practice (Locale_Bridge.swift reads
`LocaleCache.cache` today).

## Decision: option C

`currentCache` stores `(collator, generation)`. Each
`collatorForCurrentLocale()` call reads
`LocaleNotifications.cache.count()` and compares: match → cached
collator; mismatch → re-resolve from the (freshly rebuilt)
`Locale.current` and store with the new generation.

Cost, measured (BF -no-WMO, interleaved K=3, ascii): the package
build's `LocaleNotifications.count()` is a `LockedState` round-trip —
localizedCompare 135→151 (+16 ns), localizedStandardCompare +18,
caseInsensitive +15; the search/contains rows +2..7 (amortized);
engine and explicit-locale rows neutral. In the FRAMEWORK build —
the deployment where mid-process locale changes actually occur — the
count is a relaxed atomic load, ~1–2 ns. The package-build cost is
accepted: correctness contract over nanoseconds, and the rows remain
2.8–6× ahead of system ICU. If review wants the package-build cost
back, the lever is relaxing FE's `Atomic` guard
(`canImport(Synchronization) && FOUNDATION_FRAMEWORK`) — an upstream
decision, not ours to take unilaterally.

This is exactly the "resolve once, revalidate cheaply" shape the
audit note hypothesized — using the mechanism Foundation documents
for this exact purpose, and the same one Calendar and TimeZone use
process-wide.

## What deliberately does NOT invalidate

- The per-language collator dictionary: collation data for "de" does
  not change when the user switches to German — the cache key just
  changes which entry is fetched. Nothing stale.
- The §38 one-slot explicit-locale cache: keyed by the identifier of
  a locale the CALLER passed; if the caller holds `Locale.current`
  from before a change, Foundation's own semantics say that value is
  a snapshot — matching `Locale` behavior, not a staleness bug.
- `String.StandardComparator.localizedStandard` instances hold no
  locale state (§40): they resolve through
  `collatorForCurrentLocale()` per comparison and inherit the fix.

## Test strategy

The internal test hooks make this directly testable without touching
real system state: `LocaleNotifications.cache.reset()` (bumps the
generation and clears the current-locale cache) followed by
`LocaleCache.cache.resetCurrent(to:)` with french preferences flips
`Locale.current` to a tailored locale mid-process; the regression
test asserts `localizedCompare` picks up the fr-CA collator (and
back). Serialized: the hooks mutate process-global state.

## Upstream framing

When proposing: present this as following the documented
`LocaleNotifications` contract, alongside CalendarCache/TimeZoneCache
as precedent. The one open question for review is whether the
collator cache should ALSO be cleared eagerly in
`LocaleNotifications.reset()` (the Calendar shape) instead of lazily
revalidated; lazy was chosen here because `reset()` lives in
FoundationEssentials, which cannot reference
FoundationInternationalization types without a new hook — the lazy
generation check needs no new API surface between the modules.
