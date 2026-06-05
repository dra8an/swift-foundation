# Open issues — port/hebrew

Items that need a decision before the final PR to `swift-foundation`. Each entry
includes the question, options considered, and current lean. Resolve by striking
through or moving to a resolved section once a decision is locked in.

## 0. **[NON-NEGOTIABLE]** Match `_CalendarICU(.hebrew)` behavior exactly — Suite A **and** Suite B

**See `PARITY.md`** (Hebrew specifics) and **`PARITY_PROTOCOL.md`** (the
generic parity protocol every calendar port must follow).

**Suite A** (`_CalendarProtocol` probe): ✅ **green** — 13 topic-specific
tests covering ~300 dates × all protocol surfaces. Zero divergences.

**Suite B** (public `Calendar` API probe): ✅ **green** — 11 topic-specific
tests covering ~300 dates (matching Suite A topics through the full public
Calendar API) + baseline 10-date probe + DST sweep (17 wall-clocks) +
locale sweep (6 configs × 10 dates). Zero divergences.

**DST policy parity**: ✅ **green** — 16 wall-clocks × 4 (.former/.latter)²
policy combinations = 64 cases vs `_CalendarGregorian`. Zero divergences.

**Full Foundation suite on main**: ✅ **1510/1510 pass** (verified 2026-04-28).

All parity gaps from the original 2026-04-24 probe (tasks #12–17) are closed.
Suite B expansion (task #21, 2026-04-28) found and fixed two additional bugs
(#8 multi-field byAdding at Kislev 30, #9 nanosecond FP rounding).

Any divergence in either suite is a **bug** and blocks the PR. The same rule
applies verbatim to every subsequent calendar port.

## 1. Hebcal regression CSV size (1.7 MB)

**Question:** `Tests/FoundationEssentialsTests/HebrewRegressionTests.swift`
currently references a 1.7 MB CSV (73,414 daily rows, 1900–2100) that lives
outside the repo at `icu4swift/Tests/CalendarComplexTests/hebrew_1900_2100_hebcal.csv`.
Before the PR lands, the data needs to move into swift-foundation or be handled
another way. The repo's largest existing test fixture is ~746 KB, so 1.7 MB is
notable.

**Options:**

1. **Sample the CSV** — keep every Nth day. Weekly = ~240 KB (10,484 rows);
   monthly = ~55 KB (2,412 rows). Monthly sampling still catches every Adar I/II
   transition, every Cheshvan/Kislev length variation, every year-length boundary.
2. **Two-tier** — ship a ~50 KB monthly-sampled fixture in the repo for PR/CI;
   keep the full 73k as a `.disabled` developer-only test that references the
   external CSV path (same shape we have now). **Current lean.**
3. **Generator script** — regenerate from Hebcal (Node/JS) at test-setup time.
   Rejected: adds a Node dependency to Foundation's CI.
4. **Keep as-is (1.7 MB)** — justify in PR description. Risky; a maintainer
   may push back on fixture size.

**Action needed before PR:** pick an option, generate the appropriate fixture,
update `HebrewRegressionTests.swift` to load from SwiftPM's resource bundle
(not hardcoded filesystem path).

## 2. Deferred protocol-method coverage

**Question:** The following paths currently return `nil` / empty / approximate
in `_CalendarHebrew`. None are hit by the 165 tests that pass today, but
Apple's integrator may run a more exhaustive matrix:

**Update (2026-04-28):** Suite B expansion to ~300 dates exercised all these
paths through the public `Calendar` API and found 0 divergences except for
two bugs (#8 multi-field byAdding at Kislev 30, #9 nanosecond FP) which are
now fixed. The remaining concern is `wrappingComponents: true` for multi-field
adds, which still uses the carry-over path.

- `ordinality(of:in:for:)`: `(weekday, …)`, `(weekOfYear, …)`, `(weekOfMonth, …)`,
  `(quarter, …)`, `(yearForWeekOfYear, …)` combinations.
- `dateInterval(of:)`: `.weekOfYear`, `.weekOfMonth`, `.quarter`,
  `.yearForWeekOfYear`, `.isLeapMonth`, `.isRepeatedDay`.
- `dateComponents(_:from:to:)`: currently a crude second-based approximation,
  not the recursive multi-unit subtraction Foundation expects for accurate
  month/year differences.
- `date(byAdding:wrappingComponents: true)`: uses the same carry-over path as
  `false` (Foundation's "wrap within containing unit" semantics not fully
  implemented).

**Options:**

1. **Fill in before PR** — implement all four paths properly, mirror
   `_CalendarGregorian`'s shape. Est. 1-2 days of work.
2. **Ship with the paths returning nil/approximate; document the gap** in the
   PR description. The integrator can decide if it blocks merge. Foundation's
   own exhaustive `GregorianCalendar Compatibility` suite is `.disabled` by
   default, which suggests exhaustive edge-case matching is not universally
   required for new-calendar PRs.

**Current lean:** (1) — fill in before PR. Parity with `_CalendarGregorian` is
the path of least resistance.

## 3. Release-mode benchmark numbers

**Question:** All perf numbers in the Hebrew perf-test file are **debug-mode**
because `swiftpm-testing-helper` crashes with SIGBUS on Intel x86_64 + Swift
6.3.1 before release-mode tests can produce output. The PR narrative wants
release-mode absolutes, not just debug-mode ratios.

**Options:**

1. **Write a standalone executable target** (`BenchHebrew`) in `Package.swift`
   that runs the same benchmarks outside of `swift test`. `swift run -c release
   BenchHebrew` bypasses the crashing helper. Est. 30 min.
2. **Try on Apple Silicon** — the SIGBUS crash may be x86_64-specific. A quick
   run on any M-series Mac would verify.
3. **Try a newer toolchain** (Swift 6.4 nightly) — the bug may be fixed upstream.
4. **Accept debug-mode ratios only** for the initial PR; tell reviewers we'll
   supply release numbers when CI runs.

**Current lean:** (1) — standalone executable target. Reusable for every
subsequent calendar port.

## 4. Perf test DST sensitivity

**Question:** The `nextThousandHanukkahs` benchmark reports slightly different
numbers depending on which timezone the test process runs in (default system
timezone: DST-crossing zones produce different numbers than fixed-offset zones).
This makes PR-description numbers depend on the CI machine's locale.

**Options:**

1. **Pin the timezone** in the perf test: set a fixed timezone (e.g., `.gmt` or
   `America/Los_Angeles` to exercise DST) and document it.
2. **Report both** — one benchmark variant per major timezone class (fixed,
   DST-crossing).

**Current lean:** (1) — pin `.gmt` for the primary numbers plus a single
DST-zone variant to demonstrate correctness under DST.
