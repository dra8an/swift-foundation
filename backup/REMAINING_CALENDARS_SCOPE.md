# Remaining calendars — scope & PR sequencing

> Written 2026-07-24. Scopes the completion of Foundation's calendar set
> after PRs #2105 (Buddhist/Japanese) and #2123 (Chinese) merge.
> Facts marked ✅ were verified against source on this date; items marked
> ⚠ are open questions that must be resolved before committing to scope.

## 1. Inventory — all 27 `Calendar.Identifier` cases

✅ Verified against `Calendar.swift` (enum cases + CLDR string mapping) and
Apple ICU's `gCalTypes` table in `icuSources/i18n/calendar.cpp`.

### Done (6 identifiers, 4 implementations)

| Identifier | Implementation | Status |
|---|---|---|
| `gregorian`, `iso8601` | `_CalendarGregorian` | upstream, live (not flag-gated) |
| `hebrew` | `_CalendarHebrew` | merged (#1953/#2028), flag-gated |
| `buddhist` | `_CalendarBuddhist` | PR #2105 approved |
| `japanese` | `_CalendarJapanese` | PR #2105 approved |
| `chinese` | `_CalendarChinese` | PR #2123 approved |

### Remaining (21 identifiers) — grouped by the agreed PR split

**PR A — "the rest" (8 identifiers) + Gregorian-variant refactor**
`republicOfChina`, `coptic`, `ethiopicAmeteMihret`, `ethiopicAmeteAlem`,
`indian`, `persian`, `dangi`, `vietnamese` ⚠

**PR B — Islamic family (4 identifiers)**
`islamic`, `islamicCivil`, `islamicTabular`, `islamicUmmAlQura`

**PR C — Hindu family (9 identifiers), last**
`vikram`, `gujarati`, `kannada`, `marathi`, `telugu` (lunisolar);
`bangla`, `malayalam`, `odia`, `tamil` (solar)

6 + 8 + 4 + 9 = 27 ✅

## 2. PR A — detail

### 2.1 Dependencies

Blocked on **both** #2105 and #2123 merging:
- the variant refactor rewrites `_CalendarBuddhist`/`_CalendarJapanese` (#2105);
- Dangi reuses the Chinese astronomical engine (#2123).

Per `POST_MERGE_CLEANUP.md`: PR branch is a sibling off `upstream/main`;
research continues on the living tip (a new `port/calendars` off
`port/chinese`, at which point `port/chinese` freezes).

### 2.2 Gregorian-variant refactor (design already exists)

`GREGORIAN_VARIANTS_PLAN.md` §3c is the accepted design: a generic wrapper
over a static `_GregorianEraPolicy`, replacing the ~110-line delegation
shell that Buddhist and Japanese each clone. Measured there: ~350 lines for
three calendars vs ~550 by cloning again; each further variant ≈ +30 lines.

**Important risk distinction — two different "Gregorian refactors" exist:**

| Work | Touches | Risk |
|---|---|---|
| **Variant-shell dedup** (this PR) | `_CalendarBuddhist`, `_CalendarJapanese`, new shared wrapper + ROC policy | LOW — all flag-gated, `_CalendarGregorian` untouched |
| SHAREABLE_APIS dedup inside `_CalendarGregorian` (deferred at #2028; see `PR_PLAN.md`) | `_CalendarGregorian` itself — **live, not flag-gated** | HIGHER — do NOT bundle; separate PR |

Recommend PR A carries only the first. ROC then lands as a ~30-line policy,
which doubles as proof the new shape works.

### 2.3 Per-calendar scope

| Calendar | ICU implementation | icu4swift prior art ✅ | Class | Notes |
|---|---|---|---|---|
| `republicOfChina` | `roc` (Gregorian variant, year − 1911) | `CalendarSimple/Roc.swift` | trivial | Era policy under the new wrapper. Two eras (Minguo / before). |
| `coptic` | `coptic` | `CalendarComplex/Coptic.swift` + `CopticArithmetic.swift` | simple arithmetic | 13 months (12×30 + epagomenal). |
| `ethiopicAmeteMihret` | `ethiopic` | `CalendarComplex/Ethiopian.swift` | simple arithmetic | **Same core as Coptic**, different epoch. |
| `ethiopicAmeteAlem` | `ethiopic-amete-alem` | `CalendarComplex/EthiopianAmeteAlem.swift` | simple arithmetic | Ethiopic with the alternate era system. |
| `indian` | `indian` | `CalendarComplex/Indian.swift` | simple arithmetic | Saka; fixed month lengths, Gregorian-tied leap rule. |
| `persian` | `persian` | `CalendarComplex/Persian.swift` | moderate arithmetic | icu4swift uses the 33-year rule + 78-entry correction table. ⚠ see §5.2. |
| `dangi` | `dangi` — ✅ `class DangiCalendar : public ChineseCalendar`, overriding only `getType`, `getRelatedYear`/`setRelatedYear`, `getSetting` (epoch + zone) | Chinese/Dangi in `CalendarAstronomical` + `Docs/Dangi.md` | astronomical, **but thin** | Engine is fully reused; see §2.4. |
| `vietnamese` | ⚠ **absent from ICU's `gCalTypes`** | none | unknown | See §5.1 — may not be a real calendar at all. |

Three of the eight (Coptic + both Ethiopic) collapse onto one arithmetic
core, so PR A is realistically **five implementations + one refactor**.

### 2.4 Dangi — corrected assessment

An earlier draft called Dangi "the heaviest item in PR A." ✅ Source check
says otherwise: ICU's `DangiCalendar` *subclasses* `ChineseCalendar` and
overrides only four members — `getType`, `getRelatedYear`/`setRelatedYear`,
and `getSetting` (which supplies the epoch year and the astronomer time
zone). Structurally it really is "the Chinese engine at a different
meridian," exactly as intuition suggests.

The engine work does **not** repeat: packed year data, bit-op field math,
extreme-date/píngqì handling all carry over from `_CalendarChinese`.

What genuinely remains, and it is modest:

1. **Its own baked table** — under the bake-from-ICU strategy the data is
   per-identifier. Generation is automated (parameterize the existing
   generator by identifier); a range decision is needed, same shape as
   Chinese.
2. **A specific edge-case band worth targeted probes.** ✅ Korea's
   astronomer zone is piecewise-historical, not a flat UTC+9
   (`dangical.cpp` comments): ≤1908-04-01 GMT+8; 1908-04-01→1911-12-31
   GMT+8.5; 1912-01-01→1954-03-20 GMT+9; 1954-03-21→1961-08-09 GMT+8.5;
   1961-08-10→ GMT+9. **Crucially, bake-from-ICU absorbs this** — we record
   what ICU computes and never reimplement the zone logic — but those five
   transition years are exactly where a table-generation bug would hide, so
   they get dense probe coverage.
3. **Era/related-year semantics** — `getRelatedYear` is overridden, so the
   cycle/era field mapping needs its own discovery probe rather than an
   assumption that it matches Chinese.

Revised: Dangi is **cheaper than Persian**, whose reference-verification
risk (§5.2) and correction table make it the riskier item in PR A.

## 3. PR B — Islamic family

| Calendar | ICU | icu4swift prior art ✅ | Class |
|---|---|---|---|
| `islamicCivil` | `islamic-civil` | `IslamicTabular.swift` (epoch-parameterized, shared) | trivial |
| `islamicTabular` | `islamic-tbla` | same file, different epoch | trivial |
| `islamicUmmAlQura` | `islamic-umalqura` | `IslamicUmmAlQura.swift` — 301-entry baked table (KACST→ICU4C→ICU4X lineage) | baked data |
| `islamic` | `islamic` (astronomical/observational) | `IslamicAstronomical.swift` + `Docs/ISLAMIC_ASTRONOMICAL.md` | **hard** |

Rationale for separating: three are near-free, but `islamic` is
astronomical and is the one calendar whose ICU parity is least predictable.
Isolating it keeps the cheap three from being held hostage.
(ICU also has `islamic-rgsa`; Foundation exposes no identifier for it —
out of scope.)

## 4. PR C — Hindu family (last)

Apple ICU implements these in `icuSources/i18n/hinducal.cpp` ✅ as a class
hierarchy: `HinduLunarCalendar` base → `HinduSolarCalendar`, plus per-region
subclasses (`HinduLunisolarVikram/Gujarati/Kannada/Marathi/Telugu`,
`HinduSolarBangla/Malayalam/Odia/Tamil`). Apple-specific — not standard CLDR.

icu4swift's `CalendarHindu` covers Tamil, Bengali, Odia, Malayalam (solar)
and Amanta/Purnimanta (lunisolar) with an Ayanamsa model. ⚠ The mapping is
**not 1:1** with Foundation's nine identifiers — icu4swift models two
lunisolar *systems*, ICU exposes five regional lunisolar *variants*.
Resolving that mapping is PR C's first task. Deferred deliberately: it is
the largest family and the least standard.

## 5. Open questions — resolve before starting PR A

### 5.1 ⚠ `vietnamese` — is it real?
Foundation has the identifier and includes it in `Calendar.hasRepeatingMonths`
(implying lunisolar), but **`"vietnamese"` does not appear in ICU's
`gCalTypes`**. ICU falls back to Gregorian for unknown calendar types, so
`_CalendarICU(.vietnamese)` may simply behave as Gregorian.
**Verification (cheap, one probe):** construct `_CalendarICU(.vietnamese)`
and compare its fields against `_CalendarICU(.gregorian)` and
`_CalendarICU(.chinese)` on a spread of dates.
Outcomes: (a) Gregorian passthrough → trivial or arguably nothing to do;
(b) genuinely lunisolar → a Chinese-engine facade like Dangi.
Until answered, treat PR A as **7 confirmed + 1 unknown**.

### 5.2 ⚠ Persian: which reference?
Same trap as Chinese/HKO. icu4swift's Persian was validated against its own
reference (`Docs/Persian_reference.md`), **not** against ICU. ICU's
`PersianCalendar` must be the parity target. Run discovery probes over the
33-year cycle boundaries and the correction-table years before assuming the
icu4swift table transfers.

### 5.3 Dangi baked-data range
Chinese settled on a bake-from-ICU strategy. Dangi should reuse it — decide
whether to bake a separate Dangi table or parameterize the Chinese
generator by meridian (preferred; ICU derives `dangical` from `chnsecal`).

### 5.4 PR A size — pre-planned fracture line
PR A is ~5 implementations + a shared refactor + parity suites for each.
If reviewers balk at the size, split at the natural seam:
**A1** = variant refactor + ROC (proves the shape);
**A2** = Coptic/Ethiopic×2 + Indian + Persian (pure arithmetic, no shared-code change);
**A3** = Dangi (+ Vietnamese if real).
Deciding this in advance means a split costs a rebase, not a redesign.

## 6. Shared-core dedup across the OTHER families

The Gregorian-variant refactor is not a one-off — **every remaining family
has the same shape**, and ICU itself is the evidence: it models each family
as a base class plus thin subclasses. We cannot use inheritance
(`_CalendarGregorian` and friends are `final` for devirtualization, and
un-finaling will not pass review — `GREGORIAN_VARIANTS_PLAN.md` §3a), so
the sanctioned Swift shape is the same one chosen there:

> **a generic wrapper parameterized by a static policy type** (§3c) — NOT
> protocol-witness defaults (§3b, rejected on reviewer-taste grounds after
> PR #2091: don't default a witness when conformances diverge in real
> behavior).

Family-by-family opportunity:

| Family | ICU's own structure | Dedup shape | Prior art |
|---|---|---|---|
| Gregorian variants — buddhist, japanese, roc | separate classes, shared Gregorian math | **planned**: generic wrapper + era policy | `GREGORIAN_VARIANTS_PLAN.md` |
| Coptic / Ethiopic ×2 | `CopticCalendar`, `EthiopicCalendar` (+ amete-alem mode) | one arithmetic core + epoch/era policy | icu4swift `CopticArithmetic.swift` shared by Coptic + both Ethiopic ✅ |
| Islamic civil / tabular | epoch-differing tabular math | one arithmetic core, epoch-parameterized | icu4swift: literally one impl for both ✅ |
| Lunisolar — chinese, dangi (+vietnamese?) | `DangiCalendar : ChineseCalendar` ✅ | one engine + per-calendar (epoch, zone, data) policy | `_CalendarChinese` already exists |
| Hindu ×9 | `HinduLunarCalendar` → `HinduSolarCalendar` → 9 regional subclasses ✅ | **two engines + nine ~30-line policies** | icu4swift `CalendarHindu` |

**Sequencing rule — dedup follows evidence, with one exception.** The
Gregorian refactor is justified because three concrete instances exist and
the duplication was measured. For a family being written fresh, prefer:
implement, observe the real duplication, then extract. The exception is a
family whose homogeneity is already proven by ICU's own hierarchy — Coptic/
Ethiopic and especially Hindu ×9 — where designing the shared core up front
is obviously correct; cloning a wrapper shell nine times would be absurd.

**Practical implication per PR:**
- **PR A** — ships the Gregorian-variant wrapper; writes Coptic/Ethiopic
  against a shared arithmetic core from the start; Dangi as a policy over
  the Chinese engine.
- **PR B** — civil/tabular share one epoch-parameterized core; UmmAlQura
  layers a baked table over it (and already falls back to Civil outside its
  range, per icu4swift).
- **PR C** — the shared-core design *is* the plan: two engines, nine
  policies. Do the mapping study first (§4), then build the cores.

Net effect: the per-calendar marginal cost keeps falling — the last nine
calendars should be the cheapest of the whole effort, not the most
expensive.

## 7. Test strategy — marginal cost is now low

The probe infrastructure built for B/J and Chinese is parameterized, so each
new calendar costs far less than the first ones did:

- `CalendarStrictPolicyParityProbe.swift` — takes a `calendars` list
  (already runs buddhist/japanese/chinese); a new calendar = one line + a
  `makePair` case.
- `CalendarDailySweepParityProbe.swift` — add one sweep test per calendar.
- Suites A/B/C — copy the Japanese templates; the public-API surface list
  (components, intervals, ordinality, ranges, adds, bySetting, compare,
  weekends, enumerate, from:to) is calendar-agnostic.
- `BenchmarkCalendar.swift` — the mirrored 5-shape block per calendar.

**Discovery before suites, always.** Every calendar so far produced at least
one surprise (Buddhist `quarter=0`; Japanese `dateInterval(.era)` and the
Meiji date; Chinese píngqì extremes; the pre-Taika clamp). Budget for one
documented ICU quirk or one real bug per calendar.

Parity bar is unchanged and non-negotiable: zero divergences vs
`_CalendarICU`, per `PARITY_PROTOCOL.md`.

## 8. Sequencing summary

```
#2105 + #2123 merge
   ↓  (post-merge checklists in POST_MERGE_CLEANUP.md)
PR A: variant refactor + ROC + Coptic/Ethiopic×2 + Indian + Persian + Dangi [+ Vietnamese?]
   ↓
PR B: islamic-civil + islamic-tbla + umalqura + islamic
   ↓
PR C: Hindu ×9  (mapping study first)
   ↓
(separate, any time after A) SHAREABLE_APIS dedup inside _CalendarGregorian
```

After PR C, Foundation's entire 27-identifier calendar set has a pure-Swift
implementation behind feature flags.

## 9. Effort shape (relative, not calendar-time)

Anchored on actuals: Hebrew was the expensive one (new protocol surface,
fast paths, two PRs, months of review); Buddhist+Japanese were ~2 thin
wrappers; Chinese was one heavy astronomical calendar with prior art.

| Item | Relative cost | Driver |
|---|---|---|
| Variant refactor + ROC | ~0.5 calendar | design already done in `GREGORIAN_VARIANTS_PLAN.md` |
| Coptic + Ethiopic ×2 | ~1 calendar total | one shared arithmetic core, three facades |
| Indian | ~0.75 calendar | straightforward arithmetic |
| Persian | ~1 calendar | correction table + reference-verification risk (§5.2) |
| Dangi | ~0.75 calendar | engine fully reused (§2.4); cost is its own baked table + zone-transition probes |
| Islamic ×3 (civil/tbla/umalqura) | ~1 calendar total | shared arithmetic + one baked table |
| `islamic` (astronomical) | ~2 calendars | least predictable ICU parity |
| Hindu ×9 | ~4 calendars | mapping study + two engines + nine facades |

Dominant cost throughout is **parity validation and discovery**, not
implementation — every calendar so far has been more test than code.
