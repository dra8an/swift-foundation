---
name: SPM build-cache protocol for stored-property refactors
description: SPM's incremental compilation can leave stale `.swiftmodule` artifacts after stored-property refactors on cross-module-imported internal classes, causing runtime SIGSEGV in tests even though the build succeeds. This doc captures the decision (always clean-test for storage refactors), the scripts (`scripts/clean-test.sh`, `scripts/diagnose-test-crash.sh`), and the root cause.
type: reference
---

# Build-cache protocol for stored-property refactors

**Audience**: anyone touching the v8-v15 perf stack, the SHAREABLE_APIS
refactor, or any future change that adds/removes/reorders stored
properties on `_CalendarHebrew`, `_CalendarGregorian`, `_CalendarICU`, or
other widely-imported `internal` classes in Foundation.

**TL;DR**: Use `./scripts/clean-test.sh "<filter>"` instead of plain
`swift test` whenever your refactor touches class storage. If you forget
and a test crashes with SIGSEGV, run `./scripts/diagnose-test-crash.sh`
to confirm it's the cache issue (not a real regression) before bisecting.

## The footgun (root cause)

SPM's incremental compilation tracks **module info dependencies**, not
**class layout dependencies**. When `FoundationEssentials._CalendarGregorian`
has a stored property removed:

1. ✅ SPM sees the `.swift` file changed, recompiles `FoundationEssentials`.
2. ❌ SPM does NOT recompile `FoundationInternationalization` or the test
   bundles. Their `.swiftmodule` says they depend on `_CalendarGregorian`'s
   *API surface* (which didn't change — it's still an `internal final
   class` with the same init signature). The internal *layout* change is
   invisible to the dependency tracker.
3. ✅ Linker happily mixes the new `FoundationEssentials.o` with the old
   `FoundationInternationalization.o` (no type-name mismatch).
4. ❌ At runtime: test code allocates `_CalendarGregorian` instances
   thinking they have the *old* layout (with stored properties at certain
   offsets). The new code writes past the actual (smaller) object. The
   first read of any stale-layout-dependent property crashes the process
   with **SIGSEGV (signal 11)**.

This is a real Swift/SPM bug (not user error), worth filing upstream at
<https://github.com/swiftlang/swift-package-manager/issues> at some
point. The compiler flag `-enable-library-evolution` would force
opaque layout (avoiding the issue) but at a runtime perf cost — not
something Foundation enables for `internal` types.

## Decision (codified 2026-05-18 after v19 incident)

**For any refactor that adds, removes, or reorders stored properties on
widely-imported `internal` classes:**

- Use `./scripts/clean-test.sh "<filter>"` from the repo root.
- It removes `.build/*/debug`, rebuilds fully (~5–7 min), then runs
  tests. Reports timing + clean PASS/FAIL.
- Cost: ~7 min per refactor verification vs ~20s incremental. Far
  cheaper than the alternative: bisecting code that isn't actually
  wrong, in panic, after a SIGSEGV.

**If you forget and tests crash with SIGSEGV anyway:**

- Run `./scripts/diagnose-test-crash.sh "<filter>"`.
- It re-runs the test incrementally (to confirm the failure), then if
  it sees signal 11, force-cleans and retests. Reports verdict:
  - `✓ CACHE STALENESS CONFIRMED` — your code is fine, just use
    `clean-test.sh` for the rest of this refactor session.
  - `✘ REAL REGRESSION` — clean rebuild also crashes, bisect the code.

**Don't ever spend more than 5 minutes bisecting a SIGSEGV mid-test
before trying a clean rebuild.** That's the lesson from v19 — I spent
~30 minutes assuming the crash was a real regression before trying the
clean rebuild that fixed it instantly.

## Scripts

Both scripts live at `<repo>/scripts/` and are versioned. Both expect to
be run from the repo root (they auto-locate themselves via `dirname $0`).

### `scripts/clean-test.sh`

```sh
./scripts/clean-test.sh                          # defaults to Calendar|RecurrenceRule|Hebrew
./scripts/clean-test.sh Hebrew
./scripts/clean-test.sh "Calendar|RecurrenceRule"
```

What it does:
1. `cd <repo-root>`
2. `rm -rf .build/*/debug`
3. `swift build` (full rebuild)
4. `swift test --filter "<filter>"`
5. Prints timing breakdown + PASS/FAIL verdict.

Use this **proactively** whenever you know your change touches storage.

### `scripts/diagnose-test-crash.sh`

```sh
./scripts/diagnose-test-crash.sh                          # defaults to Calendar|RecurrenceRule|Hebrew
./scripts/diagnose-test-crash.sh Hebrew
```

What it does:
1. Runs incremental `swift test`. If it passes, exits 0.
2. If it fails: checks log for `signal code 11`.
   - If not signal 11 → real test failure, exits with that code.
   - If signal 11 → likely cache issue. Continue to step 3.
3. `rm -rf .build/*/debug`, full rebuild, retest.
4. Reports verdict (cache staleness vs real regression).

Use this **reactively** when a test crashes unexpectedly. Saves you
from deciding "is it the cache or my code?" by hand.

## When this applies (and when it doesn't)

**Applies** (use clean-test.sh):
- Adding, removing, or reordering stored `let`/`var` properties on
  `_CalendarHebrew`, `_CalendarGregorian`, `_CalendarICU`, or any
  similar widely-imported `internal` class.
- SHAREABLE_APIS Tier 1 work (storage/init/copy/hash refactor) — every
  step.
- Changing the property *type* of a stored property (different size →
  different layout).

**Doesn't apply** (plain `swift test` is fine):
- Adding new methods or extensions.
- Changing function bodies without touching stored properties.
- Comment-only changes (v18 was this).
- Adding new files (v19's `CalendarConstants.swift` alone was this).

When in doubt, use clean-test.sh. The 7-minute cost is cheaper than
30 minutes of misdiagnosis.

## v19 incident timeline (so we remember)

- 2026-05-18 ~14:30: Applied v19 Tier 0 (extracted 5 constants to
  `_CalendarConstants` enum, removed instance properties from
  `_CalendarHebrew` + `_CalendarGregorian`).
- 14:34: Build succeeded. `swift test --filter "Hebrew"` → 58/58 ✓.
- 14:35: `swift test --filter "Calendar|RecurrenceRule"` → SIGSEGV in
  `swiftpm-testing-helper`. First crash.
- 14:38: Retry. Same crash.
- 14:40: User: "It's not flake. You broke something."
- 14:45–15:10: Bisected: reverted to v18 (passed), re-applied v19 in
  3 steps (step 1 = new file alone, step 2 = + Hebrew changes,
  step 3 = + Gregorian changes). Step 3 crashed.
- 15:15: Further bisect: kept Gregorian instance properties + used
  `_CalendarConstants.X` at callsites — passed. So removing the
  stored properties was the trigger.
- 15:20: Tried `rm -rf .build/x86_64-apple-macosx/debug` + full rebuild
  → tests pass.
- **Total time lost to bisecting: ~30 minutes.** Avoidable with this
  protocol.

## Related references

- `backup/HANDOFF.md` § Post-PR-merge action plan + Quick-verify build note.
- `backup/SHAREABLE_APIS.md` § Tier 1 — when applied, will be the
  next big test of this protocol (storage/init/copy/hash refactor
  changes layout extensively).
- `backup/v19-shareable-apis-tier0-constants/README.md` § "Important
  build note".
- Cross-session memory: `~/.claude/.../memory/feedback_spm_class_layout_cache.md`.

## Future work (not blocking)

1. **File the Swift/SPM bug.** Minimal reproducer: a two-module package,
   internal class in module A with a stored property, module B that
   imports A and instantiates the class. Modify A to remove the
   property. `swift build` succeeds, `swift test` crashes. Likely
   already known/reported but worth searching first.
2. **CI: clean builds for PRs.** If we ever set up local CI that mirrors
   GitHub Actions, ensure it does clean rebuilds (not incremental) so
   it doesn't share this footgun.
3. **Pre-commit git hook**: scan staged diff for added/removed `let`
   or `var` at class scope in any `_Calendar*.swift` file. If found,
   warn and suggest `clean-test.sh`. Not urgent; the manual protocol
   suffices for now.
