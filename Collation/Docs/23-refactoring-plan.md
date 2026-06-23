# Refactoring Plan: Move Collation into FoundationInternationalization

## Goal

Move collation sources from `Collation/Sources/Collation/` into
`Sources/FoundationInternationalization/Collation/` so they live alongside
Calendar, Locale, TimeZone, etc. — matching the Foundation project structure.

## Why

The current layout has Collation as a separate SwiftPM target that
FoundationInternationalization depends on. This creates:
- A cross-module boundary that required `@inlinable` to work around
- An unusual project structure (nested package within the repo)
- A dependency direction that doesn't match how Foundation subsystems
  are organized (they're subdirectories, not separate modules)

## Pre-flight

- [ ] Ensure working tree is clean
- [ ] All tests pass before starting (`swift test` from repo root — 941)
- [ ] Tag or note the current commit as rollback point

## Phase 1: Move source files

### 1.1 Create target directory
```
mkdir -p Sources/FoundationInternationalization/Collation
```

### 1.2 Move 15 source files
```
Collation/Sources/Collation/*.swift
  → Sources/FoundationInternationalization/Collation/
```
Files:
- CollationCompare.swift
- CollationConstants.swift
- CollationData.swift
- CollationElements.swift
- CollationFastLatin.swift
- CollationOptions.swift
- CollationSearch.swift
- DataStorage.swift
- NFDIterator.swift
- NormalizationData.swift
- RootCollator.swift
- ScratchBuffers.swift
- SortKey.swift
- UCharsTrie.swift
- UTrie2.swift

### 1.3 Move resources
```
Collation/Sources/Collation/Resources/
  → Sources/FoundationInternationalization/Collation/Resources/
```
Contents: ucadata.icu, ucadata-icu4x.icu, nfd.bin, tailorings/ (98 .bin files)
Total size: ~2.8 MB

### 1.4 Move test files
```
Collation/Tests/CollationTests/*.swift
  → Tests/FoundationInternationalizationTests/Collation/
```
18 test files + 2 resource directories (Golden/ 3.7 MB, Conformance/ 5.3 MB)

## Phase 2: Update Package.swift

### 2.1 Remove Collation target
Delete the `.target(name: "Collation", ...)` block.

### 2.2 Remove Collation dependency from FoundationInternationalization
Remove `.target(name: "Collation")` from the dependencies array.

### 2.3 Add resources to FoundationInternationalization
Add to the target's `resources:` array (or create one if it doesn't exist):
```swift
resources: [
    .copy("Collation/Resources/ucadata.icu"),
    .copy("Collation/Resources/ucadata-icu4x.icu"),
    .copy("Collation/Resources/nfd.bin"),
    .copy("Collation/Resources/tailorings"),
]
```

### 2.4 Add test resources
Add to FoundationInternationalizationTests:
```swift
resources: [
    .copy("Collation/Golden"),
    .copy("Collation/Conformance"),
]
```

### 2.5 Remove BenchFoundation's Collation dependency
BenchFoundation should depend only on FoundationInternationalization
(Collation is now part of it). Also remove `import Collation` from
BenchFoundation/main.swift.

### 2.6 Update `FOUNDATION_COLLATION` define
May no longer be needed — the code is in the same module. If kept for
conditional compilation (e.g., to allow building without collation),
leave it. If not needed, remove the define and all `#if FOUNDATION_COLLATION`
guards.

## Phase 3: Update imports

### 3.1 Remove `import Collation` from FoundationInternationalization files
3 files:
- `Sources/.../String/String+Collation.swift` — remove `import Collation`
- `Sources/.../String/String+SortComparator.swift` — remove `import Collation`
- `Sources/.../String/StringProtocol+Locale.swift` — remove `import Collation`
- `Sources/.../Predicate/LocalizedString.swift` — no import to remove

### 3.2 Update test imports
18 test files: change `@testable import Collation` to
`@testable import FoundationInternationalization`

### 3.3 Update BenchFoundation
Remove `import Collation`, keep `import FoundationInternationalization`.

## Phase 4: Update access control

### 4.1 Downgrade `public` to `package` or `internal`
Types that were `public` because they needed cross-module visibility can
now be `package` (visible within the swift-foundation package) or
`internal` (visible within FoundationInternationalization only).

Candidates:
- `RootCollator` — `package` (used by String+Collation.swift in same module)
- `CollationOptions` — `package`
- `CollationData.root()`, `.tailoring(named:)` — `package`
- `NormalizationData.standard()` — `package`
- `RootCollator.Order` — `package`
- `RootCollator.CollationError` — `package`

### 4.2 Remove `@inlinable` / `@usableFromInline`
No longer needed — same module, WMO handles inlining automatically.
Remove from:
- `RootCollator.compare()` — remove `@inlinable`
- `RootCollator._compare()` — remove entirely (collapse back into `compare`)

## Phase 5: Update resource loading

### 5.1 Verify Bundle.module
`Bundle.module` resolves to the target's own resource bundle. After the
move, it should resolve to FoundationInternationalization's bundle. Verify
that `CollationData.root()` and `NormalizationData.standard()` still find
their resources.

### 5.2 Test resource paths
The resource copy paths in Package.swift must match the actual directory
structure. If resources are at `Collation/Resources/ucadata.icu`, the
`.copy()` path must be `"Collation/Resources/ucadata.icu"`.

## Phase 6: Handle standalone tools

### 6.1 Keep Collation/Tools/ in place
The tools (bench_icu.c, extract_tailoring.c, gen_golden.c, Python scripts)
are standalone C/Python programs. They don't depend on the Swift package
structure. Keep them at `Collation/Tools/`.

### 6.2 Keep Collation/Docs/ in place
Documentation stays at `Collation/Docs/`. No reason to move it.

### 6.3 Bench target
The standalone `Bench` target (direct RootCollator benchmark) currently
lives at `Collation/Sources/Bench/`. Options:
- **(a)** Move to root Package.swift as an executable target
- **(b)** Keep a minimal `Collation/Package.swift` with just Bench
- **(c)** Fold into BenchFoundation

Decision needed.

### 6.4 GenNormData target
Currently at `Collation/Sources/GenNormData/`. Rarely used (only when
regenerating nfd.bin). Options:
- **(a)** Move to root Package.swift
- **(b)** Keep standalone with minimal Package.swift
- **(c)** Make it a script instead

Decision needed.

## Phase 7: Verify

- [ ] `swift build` from repo root — succeeds
- [ ] `swift test` from repo root — 941+ tests pass
- [ ] `swift build -c release --target BenchFoundation` — builds
- [ ] BenchFoundation benchmark numbers match pre-refactor
- [ ] `swift -O Collation/Tools/bench_system_foundation.swift` — still works
- [ ] Collation bench (if kept) — still works

## Phase 8: Update documentation

### 8.1 CLAUDE.md
Update all path references from `Collation/Sources/Collation/` to
`Sources/FoundationInternationalization/Collation/`.

### 8.2 HANDOFF.md
- Code map section: update all paths
- "How to work" section: update build/test commands
- "Where everything is" section: update paths

### 8.3 Docs/19-integration-plan.md
Update file paths in the "Files changed" table.

### 8.4 Docs/20-integration-quickref.md
Update module structure diagram.

### 8.5 Docs/22-cross-module-inlining.md
Note that `@inlinable` is no longer needed (same module).

### 8.6 Memory files
Update project-m8-integration-state.md and project-refactor-risk.md.

## Phase 9: Prepare for upstream PR

### 9.1 Identify files that are ours only (not for upstream)
These files exist in our fork for development, benchmarking, and
documentation but should NOT be included in a PR to swiftlang/swift-foundation:

**Collation/Tools/** — all of it:
- `bench_icu.c`, `bench_icu` (compiled binary)
- `bench_system_foundation.swift`
- `extract_tailoring.c`, `extract_tailoring` (compiled binary)
- `gen_golden.c`
- `extract_cmsccoll.py`, `extract_g7coll.py`, `extract_locale_suites.py`,
  `extract_regcoll.py`, `gen_fuzz_corpus.py`
- `bench/` (corpus files for benchmarking)

**Collation/Docs/** — all of it:
- 24 markdown documents (strategy, milestone reports, performance analysis,
  decision records, handoff, benchmark results)
- These are project history/development docs, not upstream documentation

**Collation/Sources/Bench/** — standalone collation benchmark
**Collation/Sources/BenchFoundation/** — Foundation API benchmark
**Collation/Sources/GenNormData/** — nfd.bin generator tool
**Collation/Package.swift** — standalone package manifest (if kept)
**CLAUDE.md** — project instructions for Claude Code

### 9.2 What goes upstream
Only the production code and its tests:
- `Sources/FoundationInternationalization/Collation/*.swift` (15 files)
- `Sources/FoundationInternationalization/Collation/Resources/` (data files)
- `Sources/FoundationInternationalization/String/String+Collation.swift`
- `Sources/FoundationInternationalization/String/String+SortComparator.swift` (modified)
- `Sources/FoundationInternationalization/String/StringProtocol+Locale.swift` (modified)
- `Sources/FoundationInternationalization/Predicate/LocalizedString.swift` (modified)
- `Tests/FoundationInternationalizationTests/Collation/` (18 test files + resources)
- `Package.swift` (modified — resources, no Collation target)

### 9.3 PR preparation approach
When creating the upstream PR:
- Create from a clean branch off upstream/main (not port/collation)
- Cherry-pick or reconstruct only the production changes
- Exclude `Collation/Tools/`, `Collation/Docs/`, bench targets, CLAUDE.md
- Squash into logical commits (integration, search, tailorings, tests)

## Phase 10: Clean up

### 10.1 Remove old Collation/Package.swift
Or keep a minimal one for Bench/GenNormData if those stay standalone.

### 10.2 Remove FOUNDATION_COLLATION flag (optional)
If all collation code is unconditionally part of FoundationInternationalization,
the flag and all `#if FOUNDATION_COLLATION` guards can be removed. This
simplifies the code but means collation is always compiled in.

### 9.3 Commit
One commit with all changes. Message should explain the move and note
that no logic changed.

## Risk checklist

- [ ] No logic changes — pure file moves + import/access updates
- [ ] Resource loading works after move (Bundle.module resolves correctly)
- [ ] Bench numbers unchanged (same-module WMO ≥ @inlinable performance)
- [ ] All 941+ tests pass
- [ ] No `import Collation` remains anywhere
- [ ] All doc paths updated
- [ ] Git history preserved (git tracks moves if content is similar)

## Estimated effort

~2-3 hours of mechanical work. No judgment calls except Phase 6
(what to do with Bench and GenNormData).

## Appendix: All benchmark commands (pre-refactor)

Reference of every benchmark command, what it measures, and what paths
need updating after the refactor.

### 1. Direct Collation vs ICU (RootCollator.compare / sortKey)

**What:** Raw collation engine performance, no Foundation API overhead.
**Measures:** Our `RootCollator.compare()` and `sortKey()` vs ICU's
`ucol_strcoll()` and `ucol_getSortKey()`.

```sh
# Our collator:
cd Collation
swift build -c release
.build/out/Products/Release/Bench Tools/bench/bench-ascii.txt 200

# ICU 79:
cd Collation/Tools
ICU_SRC=/Users/dragan/Projects/Unicode/icu-DraganBesevic-2
ICU_BUILD=$ICU_SRC/icu4c/source
clang bench_icu.c -O2 -o bench_icu \
  -I $ICU_SRC/icu4c/source/common -I $ICU_SRC/icu4c/source/i18n \
  -L $ICU_BUILD/lib -licuuc -licui18n -licudata
DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./bench_icu Tools/bench/bench-ascii.txt 200
```

**Corpora:** `Tools/bench/bench-{ascii,latin,cjk,paths,thai}.txt`
**Source:** `Collation/Sources/Bench/main.swift`, `Collation/Tools/bench_icu.c`
**After refactor:** Bench target path may change (see Phase 6.3)

### 2. Foundation API: our collator vs system ICU

**What:** Same Foundation APIs (`localizedCompare`, `compare(locale:)`,
`localizedStandardCompare`, `localizedStandardContains`), two backends.
**Measures:** Integration overhead + collation performance through the
Foundation API layer.

```sh
# Our collator (via SwiftPM FoundationInternationalization):
cd swift-foundation-collation  # repo root
swift run -c release BenchFoundation Collation/Tools/bench/bench-ascii.txt 200

# System ICU (via system Foundation, NSString → ICU):
swift -O Collation/Tools/bench_system_foundation.swift \
  Collation/Tools/bench/bench-ascii.txt 200
```

**Source:** `Collation/Sources/BenchFoundation/main.swift`,
`Collation/Tools/bench_system_foundation.swift`
**After refactor:** BenchFoundation target moves or stays (see Phase 6.3).
`bench_system_foundation.swift` stays in `Collation/Tools/` (standalone).

### 3. Baseline numbers (confirmed pre-refactor, 2026-06-23)

**Direct collation (ns/op):**

| Corpus | compare (ours) | compare (ICU) | sortKey (ours) | sortKey (ICU) |
|--------|---------------|--------------|---------------|--------------|
| ASCII  | 26            | 9            | 215           | 104          |
| Latin  | 25            | 10           | 235           | 120          |
| CJK    | 128           | 41           | 228           | 118          |
| Paths  | 65            | 29           | 533           | 371          |

**Foundation API (ns/op, post-refactor — same module, no @inlinable needed):**

| API | Corpus | Ours | System ICU | Speedup |
|-----|--------|------|-----------|---------|
| `localizedCompare` | ASCII | 128 | 195 | **1.5× faster** |
| `localizedCompare` | Latin | 128 | 358 | **2.8× faster** |
| `localizedCompare` | CJK | 238 | 368 | **1.5× faster** |
| `localizedCompare` | paths | 165 | 299 | **1.8× faster** |
| `localizedStdCmp` | ASCII | 136 | 197 | **1.4× faster** |
| `localizedStdCmp` | Latin | 136 | 349 | **2.6× faster** |
| `localizedStdCmp` | CJK | 242 | 358 | **1.5× faster** |
| `localizedStdCmp` | paths | 185 | 318 | **1.7× faster** |
| `compare(locale:)` | ASCII | 298 | 313 | **1.1× faster** |
| `compare(locale:)` | Latin | 298 | 482 | **1.6× faster** |
| `compare(locale:)` | CJK | 448 | 487 | **1.1× faster** |
| `compare(locale:)` | paths | 342 | 412 | **1.2× faster** |

**Refactor result:** numbers match or slightly beat pre-refactor. Same-module
WMO provides the same inlining benefit that `@inlinable` gave across modules.

