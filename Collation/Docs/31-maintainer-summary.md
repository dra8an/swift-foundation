# 31 — Summary for the swift-foundation maintainers

> Written 2026-11-09 for the upstream review of branch `port/collation`
> (fork `dra8an/swift-foundation`). Every number has its source in this
> repository; the sources are named in brackets.

## 1. What the port is

A Swift implementation of the Unicode Collation Algorithm (UTS #10) inside
`FoundationInternationalization`, so that the locale-aware string APIs work
on platforms without the Darwin Foundation framework (issue #284). It reads
ICU's collation data and follows the structure of ICU4C's collation runtime
(the "v2" design), from which parts are ported (`NOTICE.txt` has the entry
with ICU's license):

- It reads ICU's binary collation data ("UCol" format v5): the root data
  `ucadata.icu` and 98 compiled tailorings, taken from an ICU 79.0.1 build;
  the root data is byte for byte ICU's `ucadata-unihan.icu` of tag
  `release-78.3` (plus 12 bytes of fill from the packaged data build), so
  the two versions have the same root collation data. There is no
  runtime rule builder; a tailoring is a compiled binary
  (`utils/collation/extract_tailoring.c` extracts them from an ICU build).
- It normalizes to NFD on the fly (its own data, `nfd.bin`, generated from
  ICU's `nfc.txt`, Unicode 17).
- It has ICU's fast paths for Latin text ("fast Latin"), sort keys, and
  collation-aware search (`contains`, `range(of:)`).

Code: `Sources/FoundationInternationalization/Collation/` (15 files, 7,682
lines) and the Foundation wiring in `String/String+Collation.swift` (the
collator cache, 295 lines), `String/StringProtocol+Locale.swift` and
`String/String+SortComparator.swift`.

## 2. What it changes for users

**Darwin framework build (`FOUNDATION_FRAMEWORK`): nothing.**
`foundation_swift_collation_feature_enabled()` returns `false` there, and
the existing paths stay.

**All other builds (SwiftPM, the CMake build of the toolchain: Linux,
Windows):** these APIs collate with the engine, with the Darwin signatures:

- `localizedCompare`, `localizedCaseInsensitiveCompare`,
  `localizedStandardCompare`, `compare(_:options:range:locale:)`;
- `localizedStandardContains`, `localizedCaseInsensitiveContains`,
  `localizedStandardRange(of:)`, `range(of:options:range:locale:)`;
- `String.StandardComparator` (`.localizedStandard`, `.localized`) and
  `String.Comparator` with a locale, so the sorts with `SortDescriptor` and
  `KeyPathComparator` too;
- inside `#Predicate`: `localizedCompare` and `localizedStandardContains`.
  For these, two public types that the Darwin framework already has are now
  compiled in the other builds too: `PredicateExpressions.StringLocalizedCompare`
  and `PredicateExpressions.StringLocalizedStandardContains`, with their
  `build_localizedCompare` / `build_localizedStandardContains` functions and
  their conformances (`Predicate/LocalizedString.swift`, whose
  `#if FOUNDATION_FRAMEWORK` is gone). **These two types are new public API
  in the builds without the framework**; the tests are in
  `PredicateInternationalizationTests`.

A locale change invalidates the cached collators (`LocaleNotifications`).

## 3. Correctness

- **The UCA conformance files** (`CollationTest_NON_IGNORABLE_SHORT.txt`,
  `CollationTest_SHIFTED_SHORT.txt`), ICU's `collationtest.txt`, and ICU's
  collation test data `cmsccoll`, `g7coll`, `regcoll` and the per-locale
  suites, extracted to JSON (`Tests/.../Collation/Conformance/`).
- **Sort keys byte for byte equal to ICU's `ucol_getSortKey`**, across
  option sets and tailorings (`SortKeyTests.keysMatchICUByteForByte`,
  `TailoringTests.keysMatchICU`; reference keys generated with ICU 79.0.1,
  `Tests/.../Collation/Golden/`).
- **Internal invariants:** compare against sort-key order for every option
  set, the restart after a common prefix, the fast paths against the full
  path, search positions (`PositionInvariantTests`), concurrency with the
  Thread Sanitizer.
- 41 test files with 236 test functions, 75 of them parameterized; the
  package's full suite passes: 1587 tests in 142 suites.
- **One deliberate difference from ICU:** ICU's `ucol_strcoll` skips a
  common prefix in a way that is wrong for two option sets (alternate =
  shifted, backward secondary); its compare then disagrees with its own sort
  keys. Our compare agrees with the sort keys and UTS #10 (technique log
  §51 (z)).

## 4. Performance

Measured on Apple Silicon (M1 Max), macOS 27.2.1, Swift 6.5, the median of 6
runs (Docs/21, the recording of 2026-11-19 at `1cbc4682`; the baseline of
2026-11-17 read the same within 0.6% in this table).

**The engine against ICU4C** (EngineBench against ICU C, ICU 80.0.1, ns per
call; speedup = ICU / ours):

| corpus | compare | sortKey |
|---|---|---|
| ASCII | 7.6 / 9.3, 1.22× | 70.9 / 100.8, 1.42× |
| Latin | 7.9 / 10.1, 1.28× | 91.2 / 116.8, 1.28× |
| CJK | 17.8 / 40.7, 2.28× | 100.3 / 115.8, 1.15× |
| paths | 18.2 / 30.0, 1.65× | 173.1 / 351.0, 2.03× |
| Thai | 159.4 / 173.0, 1.08× | 142.2 / 151.8, 1.07× |

The API that returns a new `[UInt8]` key is 0.78–0.85× of ICU, which writes
into the caller's buffer; most of that difference is the new array itself
(§51 (be)).

**How these numbers compare with older ones** (technique log §52 (k)–(n)).
Recordings before 2026-11-13 show the compare rows 1.2–1.5 ns higher (for
example ascii 8.9, "1.04×"): the benchmark program's own loop cost that
much, and the C loop of the ICU side did not. The loop was corrected; the
engine did not change. The ICU reference was ICU 79.1 until 2026-11-16; ICU
80.0.1 has a sortKey that is 2–5% faster, so the sortKey speedups are a
little lower than in older recordings with the same Swift times. Each series
passes four checks (ICU C, macOS's own collation, a frozen binary of the
engine, and a count of the benchmark loop's instructions; Docs/27).

**The Foundation APIs against macOS's own implementation** (WMO release
build against `NSString` → CoreFoundation → ICU on the same machine;
mostly the bridge that the Swift path does not have): `localizedCompare`
12.4 / 13.0 / 24.1 / 23.8 / 167.1 ns against 201.8 / 347.6 / 355.9 / 313.4 /
507.6 ns; the lowest speedup of all rows 2.88× (Docs/21).

These Foundation numbers include a lock that this branch's base (`release/6.3`) takes on each call that uses the current locale; upstream removed it in 2026 (open point 10). With upstream's form of that read, `localizedCompare` reads 10.5 / 11.1 / 21.3 / 21.5 / 160.7 ns in an A/B on one thread, and calls from several threads no longer wait for each other.

**Collator creation** (the first collator of a process): 418 µs in a cold
process, 436 µs after a `Bundle.main` lookup; a tailoring 190–250 µs
(§51 (bf)).

## 5. Build changes

- **CMake:** `Collation/CMakeLists.txt` with the 15 sources;
  `String+Collation.swift` in `String/CMakeLists.txt`.
- **The data, compiled in:** a C target `_FoundationCollationData` (SwiftPM
  and CMake) with `ucadata.icu`, `nfd.bin` and the 98 tailorings as byte
  arrays, as swift-foundation-icu ships ICU's data. It adds 2.08 MB to the
  library and about 10 MB of generated text to the repository
  (`Sources/_FoundationCollationData/data/*.inc`). The generator is
  `utils/collation/gen_collation_data.py`; the input files stay in
  `Sources/FoundationInternationalization/Collation/Resources/`.
- **No resource bundle:** `FoundationInternationalization` has no SwiftPM
  resources any more; the file lookup in the engine exists only where the C
  data module does not (the bench tools, which copy the engine sources).
- **Checked:** the SwiftPM build and its full suite; the CMake build on
  macOS (with Xcode's `cmake` and `ninja`), whose library collates in a small
  program (root and Swedish).
- **One change in FoundationEssentials:** in
  `Locale/Locale_Notifications.swift`, `LocaleNotifications`, its `cache` and
  its `count()` are `package` (three words on three lines; no change of behaviour), so that the
  collator cache in `FoundationInternationalization` sees a change of the
  current locale. The port changes no other FoundationEssentials file.

## 6. Open points (for the maintainers to decide)

1. **Engine types: `package`, not `public` (done 2026-11-09).** `RootCollator`,
   `CollationData`, `NormalizationData` and `CollationOptions` were `public`
   in `FoundationInternationalization`, which made them Foundation API. They
   are now `package`: visible inside swift-foundation (the Foundation wiring,
   the benchmark harness in the same package), not to its clients. The tests
   use `@testable import`. The machine code of compare and sortKey did not
   change (instruction counts identical). One effect outside the library:
   another module of the package can no longer inline a synthesized member of
   a `package` type, so `RootCollator.Order.rawValue` became a call in the
   benchmark programs; they do not use it any more (technique log §52 (k)).
2. **Upstream `main` has an ICU-based compare (PR #1683),** behind the flag
   `FOUNDATION_ICU_STRING_COMPARE` (off by default), for
   `compare(_:options:range:locale:)` only; it opens and closes an ICU
   collator per call. This branch starts from `upstream/release/6.3`
   (`dbacc677`); a PR to `main` must replace or reconcile it (rebase plan:
   Docs/24). **Open question:** that change also adds a stub in
   FoundationEssentials (`String/StringProtocol+Stub.swift`, behind the same
   flag). Docs/24 proposes to remove it; the port so far changes one
   FoundationEssentials file, by access level only (section 5). Before the PR branch is made on a fresh
   upstream `main`: can our PR leave that file untouched (for example, the
   flag simply stays off), or does it need a FoundationEssentials change?
   That decision belongs to the owner of the branch and the maintainers.
3. **Not yet built or tested on Linux or Windows.** The CMake build was
   checked on macOS only. Needs another machine (Linux, Windows) or
   Docker; not possible on the development Mac.
4. **Big-endian hosts:** the data parsers have a byte-swapping path for
   big-endian hosts (`DataStorage.storeLittleEndian`), not yet run on such a
   host. Needs a big-endian machine or an emulator; not possible on the
   development Mac.
5. **Test-only data: in the test target (done 2026-11-09).** The NFD-only
   root data (`ucadata-nfd-only.icu`, 585 KB: ICU's root data without
   canonical closure, as ICU's `genuca` tool builds it with option `-X`;
   used only by the
   conformance and differential tests) moved to
   `Tests/.../Collation/TestData/`, loaded by `CollationTestData.rootNFDOnly()`;
   the library's own loader for it is gone. `FoundationInternationalization`
   now has no resources and ships no resource bundle.
6. **Scope cuts:** no custom rules at run time (no rule builder); NFD
   normalization cannot be turned off; script reordering only as the data
   supplies it.
7. **Data updates:** a new ICU version means: extract the tailorings
   (`utils/collation/extract_tailoring.c`), copy `ucadata.icu`, regenerate
   `nfd.bin` from ICU's `nfc.txt` (`swift utils/collation/gen_norm_data.swift
   <nfc.txt> <nfd.bin>`), regenerate the reference keys
   (`utils/collation/gen_golden.c`), then run
   `python3 utils/collation/gen_collation_data.py`. Check: for the same
   Unicode version, `gen_norm_data.swift` gives the old `nfd.bin` byte for
   byte (checked 2026-11-09 with ICU's `nfc.txt` of `release-78.3`).
8. **`Collation/`** (docs, tools, benchmarks, the technique log) is the
   working folder of the port and not meant for the upstream PR. **The data
   generators are, and they are in `utils/collation/` (2026-11-09),** next to
   upstream's own data updater (`utils/update-iana-charset-names`):
   `extract_tailoring.c`, `gen_norm_data.swift`, `gen_golden.c`,
   `gen_collation_data.py`, with a README that gives the order of a data
   update. **Since 2026-11-11 also the generators of the test data:**
   `gen_fuzz_corpus.py` (seed 42 gives the committed fuzz corpus byte for
   byte) and the four extractors of ICU4C's test sources
   (`extract_cmsccoll.py`, `extract_g7coll.py`, `extract_locale_suites.py`,
   `extract_regcoll.py`); the test comments point there.

9. **`LockedState` → `Mutex` at a move to a newer base.** The collation code uses upstream's `LockedState` (five locks: the collator cache, the tailoring cache, the fast-Latin cache), which exists on this branch's base, `release/6.3`. Upstream `main` replaced it with `Synchronization.Mutex` (swiftlang/swift-foundation#1840). A trial on 2026-11-12 showed one obstacle: `Mutex` checks that nothing that is not `Sendable` leaves the lock, and the explicit-locale cache returns a pointer to its published slot (memory that is never freed) from inside the lock. The clean fix adds one `@unchecked Sendable` wrapper for that pointer; the other four locks convert directly (one with a small rewrite). Owner's decision: keep `LockedState` until a PR needs the move (technique log §52 (i)).

10. **A lock on each current-locale call, on this base only (measured 2026-11-18; no change by the port).**

    **What happens.** The collator cache keeps the collator of the current locale and checks on every call that the locale did not change: it reads the locale generation, `LocaleNotifications.cache.count()` (FoundationEssentials, `Locale/Locale_Notifications.swift`), which upstream documents for exactly this use ("Compare that to a cached value to see if your cached `Locale.current`, `TimeZone.current`, or `Calendar.current` to see if it is out of date"). On `release/6.3` that count is an `Atomic<Int>` only under `FOUNDATION_FRAMEWORK`; in every other build it is a `LockedState<Int>`, so `count()` takes and releases a lock (`os_unfair_lock` on Darwin). The engine runs in exactly those other builds. So each `localizedCompare`, `localizedStandardCompare`, `localizedCaseInsensitiveCompare`, each localized search and each `.localizedStandard` comparison of a sort takes one process-wide lock. `compare(_:locale:)` and the other calls with an explicit locale do not read the count. The rest of the current-locale path takes no lock (one atomic load of a published slot).

    **The history of the file upstream** (swiftlang/swift-foundation; read from GitHub on 2026-11-18):

    | PR | merged | author | what it did to `Locale_Notifications.swift` |
    |---|---|---|---|
    | #719 "Improve performance of FormatStyle formatting when used in multithreaded context" | 2024-07-09 | Tony Parker | Added the file. `Atomic<Int>` under `#if !canImport(Darwin) \|\| FOUNDATION_FRAMEWORK`, `LockedState<Int>` otherwise: the package build on Darwin had the lock from the first day, Linux had the atomic. |
    | #724 "Still use canImport(Synchronization)" | 2024-07-09 | Tony Parker | The condition became `canImport(Synchronization) && (!canImport(Darwin) \|\| FOUNDATION_FRAMEWORK)`. |
    | #736 "Limit Synchronization usage to FOUNDATION_FRAMEWORK" | 2024-07-15 | Jeremy Schonfeld | The condition became `canImport(Synchronization) && FOUNDATION_FRAMEWORK`: from here on every build outside the framework has the lock, Linux too. The PR text: "There are some issues with using the `Synchronization` module from within the toolchain on Linux so for now we'll limit its usage to `FOUNDATION_FRAMEWORK` only". |
    | #744 "Revert formatting performance improvements" | 2024-07-19 | Tony Parker | Removed the file with the rest of #719. The PR text: "There appears to be some kind of race or memory smash in ICU after these, and we need more time to investigate the full root cause." |
    | #884 "Formatting performance improvements" | 2024-08-23 | Tony Parker | Brought the file back in the form of #736. The PR text: "Re-apply the diff from #719 (reverted in #744). We discovered the root cause was use of ICU's ability to set the malloc functions used, which can race." **This is the form on `release/6.3` and `release/6.3.1`, and on this branch.** |
    | #1840 "Replace LockedState with Mutex" | 2026-03-20 | Jeremy Schonfeld | Removed the conditions and the `LockedState` form: `let _count = Atomic<Int>(1)` in every build. The PR text: "Removes all conditionals around importing `Synchronization`". **This is the form on `main` and on the 6.4 branches (checked: `release/6.4.x`, `release/6.4.0`, `release/6.4.3`).** |
    | #2232 "Adopt @c @implementation in favor of @_cdecl" | 2026-09-09 | Jeremy Schonfeld | The exported C function of the framework build only; the count did not change. |

    The port's own changes to the file: commit `c7e2ff6e` (2026-07-20) made `LocaleNotifications`, its `cache` and its `count()` visible to `FoundationInternationalization` (`package`, three words); `80b10d12` (2026-11-17) restored upstream's whitespace. The port did not add the lock and did not change the count.

    **What the lock costs** (an A/B of two copies of this branch, WMO release build; the second copy has the four conditions of the file without `&& FOUNDATION_FRAMEWORK`, which is the code of #1840 for the count; technique log §52 (q)). One thread, ns per call, lock → atomic:

    | API | ASCII | Latin | CJK | paths | Thai |
    |---|---|---|---|---|---|
    | `localizedCompare` | 12.4 → 10.5 | 13.0 → 11.1 | 24.2 → 21.3 | 23.7 → 21.5 | 165.9 → 160.7 |
    | `localizedStandardCompare` | 14.6 → 12.7 | 15.2 → 13.3 | 31.6 → 29.0 | 26.7 → 26.8 | 166.9 → 161.5 |
    | `localizedCaseInsensitiveCompare` | 15.5 → 13.7 | 16.1 → 14.3 | 32.8 → 30.2 | 26.7 → 25.3 | 168.2 → 162.4 |
    | `localizedStandardContains` | 126.9 → 121.7 | 146.6 → 140.8 | 152.9 → 147.1 | 131.0 → 125.6 | 151.0 → 145.8 |

    About 1.9 ns of each short compare (15% on ASCII and Latin) and 5–6 ns of each localized search. The calls with an explicit locale and the direct engine calls are the same in both copies. Several threads that call `localizedCompare` at the same time (ASCII, each thread with its own strings; ns per call in each thread, and the total of all threads):

    | threads | with the lock | total, million calls / s | with the atomic read | total |
    |---:|---:|---:|---:|---:|
    | 1 | 14.5–15.0 | 67–69 | 11.9–12.2 | 82–84 |
    | 2 | 93–100 | 20–21 | 12.0–12.3 | 163–167 |
    | 4 | 201–203 | 20 | 12.6 | 316 |
    | 8 | 378–424 | 19–21 | 12.9–15.3 | 512–606 |

    With the lock, two threads together do less than one thread alone, and the total stays near 20 million calls per second for any number of threads. With the atomic read the total grows about 7 times at 8 threads. `compare(_:locale:)` in the same test scales in both copies (18.7 ns at 1 thread, 19.8 ns at 8), so the engine, its scratch buffers and its caches do not limit parallel calls; this one lock does. Limits of the measurement: one machine (M1 Max), ASCII only for the thread test, at most 8 threads, the WMO build only.

    **What it means.** On a base that has #1840 (`main`, `release/6.4.x`) the lock is gone, and the port's change to the file is still the three `package` words (the type, `cache` and `count()` are internal there). On `release/6.3` the port leaves the file as it is: the owner does not change FoundationEssentials beyond those three words (decision 2026-11-18). If the engine must ship on a base without #1840, taking that PR's form of the count is the maintainers' decision. In the package sources of this branch the collator cache is the only caller of `count()` (the framework build also exports it to C as `_localeNotificationCount`), so no other code of the package pays this lock.

## 7. A possible PR sequence

The port can go in as one PR or in steps. The steps of Docs/26 still apply in
outline: the core compare with the root data and a few tailorings, then sort
keys, the fast paths, search, the Foundation wiring, and the remaining
tailorings. The build changes of section 5 belong to the first step.

## 8. Gaps against the upstream contribution guide (to fix on the PR branch)

Upstream `main` has `CONTRIBUTING.md` and `CONTRIBUTION_GUIDELINE.md`
(added after this branch's fork point, upstream PR #2012; copies identical
to upstream `main` are at this repository's root). Counted on
2026-11-10 in the engine and its Foundation wiring:

| rule | state of the branch | what the PR branch needs |
|---|---|---|
| No comments that only explain what the code does, or that refer to the history of a change; no manual wrapping | **done 2026-11-10:** 121 comment lines in 17 files rewritten — no reference to the technique log or a § number is left, no measurement numbers (one kept where the number is the reason: a tailoring build takes ~0.2 ms, so the cache does not hold its lock during it), no references to `Collation/Tools`; the "why" of each choice stays. Checked file by file: the code without comments is identical **The tests and the rest, done 2026-11-11:** 34 history references in 27 test files rewritten (§ numbers, the technique log, `Docs/NN`, milestones, "the bug", "the old …", "oracle"), plus 6 more history or stale sentences in the sources (two said that script reordering is not supported, which it is; two described dynamic access scopes on the scratch iterators, which are pointers now); no manually wrapped comment is left in the Swift files: 252 wrapped lines joined into their paragraphs in 44 files (the C and Python generators in `utils/collation` keep their wrapped comments — accepted by the owner's decision, 2026-11-11) (list items, code, tables, the license header and the binary-layout table of `gen_norm_data.swift` kept as they are). Checked file by file: the code without comments is identical in all 45 changed Swift files | the history stays in `Collation/Docs` and goes into the PR descriptions |
| Avoid `Unsafe…Pointer` APIs unless no safe alternative exists; isolate them in small helpers | **Justified 2026-11-10, isolated where it is free 2026-11-12 (section 9):** 304 uses by kind (counted 2026-11-12, code lines only): read-only data views 139, pinned UTF-8 bytes 68, boxes and in-place pointers 48, raw pointers for reads without a lock 29, the rest 20. The hand-written allocation of the collator's four setup boxes is now one small owner type, `OwnedBox`, with the init and deinit of the standard library's `UniqueBox` and a TODO to switch to it at a macOS 27 minimum. Every other kind was tried in an isolated or safe form, and each form cost instructions on the compare path, or a call per read in a build without whole-module optimization; section 9 gives the numbers. Each kind has its reason at its central declaration in the source | put the section 9 table in the PR description; expect review discussion |
| `@unchecked Sendable` and `nonisolated(unsafe)`: a comment why it is safe, and a `// TODO:` migration path | **done 2026-11-10, 7 left since 2026-11-12:** each has an `@unchecked Sendable:` reason; 4 have a `// TODO:` migration path (`CollationData`, `NormalizationData` and `RootCollator.Storage`: one Sendable wrapper for the buffer views, and for `Storage` also `UniqueBox` for its setup boxes; `ThreadLocalScratch`: a standard thread-local API); 3 say why no migration is planned (`DataStorage`: raw memory; `FastLatinCache` and the collator cache's published slots: lock-free reads of published snapshots). Gone: `PoolLock` (2026-11-10, replaced by upstream's `LockedState`) and the one of `RootCollator` (2026-11-12: its only stored property is the Sendable storage, so the compiler checks it); no `nonisolated(unsafe)` | — |
| No force unwraps (`!`, `as!`) in sources or tests; `try` / `#require` in tests | **done 2026-11-10:** 88 in 13 test files → `try #require`, a `guard let` in one parser; 2 in the sources → `flatMap`, and `guard let … else { preconditionFailure(…) }` (the compiled wrapper code is identical). Left on purpose: 4 `unsafelyUnwrapped` in hot paths, part of the unsafe use (row 2). The new `preconditionFailure` cannot be reached from a test (a private helper, called only with stored-property key paths), so it has no exit test | — |
| Performance through `swift-benchmark` entries under `Benchmarks/` | **done 2026-11-10:** `Benchmarks/Benchmarks/Internationalization/BenchmarkCollation.swift` — the 14 Foundation APIs of Table 2 (5 compares, 5 searches, 4 sorts) on 5 corpora, 70 entries named `Collation-<API>-<corpus>`; the corpora in `Internationalization/Resources/` (our ascii, latin, cjk and paths corpora, and 200 lines of the shuffled Thai corpus); `CollationCorpora.swift` finds them through `Bundle.module` (a separate file: its import of the system Foundation must not reach the collation calls); one `resources:` line in `Benchmarks/Package.swift`. The engine types are `package`, so the benchmark package cannot measure the engine itself (Table 1). Checked on macOS: the compare and search rows agree with the WMO column of Docs/21 (`localizedCompare` ascii 13.4 ns against 12); the sort rows are nearer to the `-no-WMO` column. To build on this branch, `BenchmarkTimeZone.swift` got upstream's own fix of PR #1958 (`TimeZone.knownTimeZoneIdentifiers`). **`swift package benchmark` on macOS with `SWIFTCI_USE_LOCAL_DEPS` (found 2026-11-11):** the plugin's own tool fails to build — `swift-argument-parser` 1.7 and later import `FoundationEssentials` whenever `canImport(FoundationEssentials)` is true (its change #804), and the local package's `FoundationEssentials.swiftmodule` lies in the shared products folder, while its C module `_FoundationCShims` is visible only to its own dependents ("unable to resolve module dependency: '_FoundationCShims'"). A local pin to 1.6.2, which `package-benchmark` allows (`from: "1.6.0"`), avoids it: `swift package resolve swift-argument-parser --version 1.6.2` in `Benchmarks/` (`Package.resolved` is not committed). The same plugin run showed that the collation entries had inherited `scalingFactor: .kilo` from the other benchmarks of the target, which divided their times by 1000; they now set `.one`. A plugin run of all 70 entries on 2026-11-12 reported the time of one pass for each (`localizedCompare` ascii 2,751 ns for 199 compares, 13.8 ns each), within 0–11% of the direct runs | on a fresh upstream `main`, keep only the new files and the two added lines; run with `SWIFTCI_USE_LOCAL_DEPS=<a folder whose swift-foundation is this checkout>` |
| Every source file starts with the Swift.org license header | **done 2026-11-10:** the standard header (Copyright (c) 2026 Apple Inc. and the Swift project authors, Apache License v2.0 with Runtime Library Exception, the LICENSE and CONTRIBUTORS lines) added to the 15 engine files, 37 collation test files and the 4 generators in `utils/collation`; the damaged header of `String+Collation.swift` and the 3 test headers without the CONTRIBUTORS line made standard. Comments only: the code without comments is identical in all 57 Swift files | — |
| Derived work is listed in `NOTICE.txt` (it lists, for example, three Base64 sources) | **done 2026-11-10:** a `NOTICE.txt` entry for ICU's collation code (the ported parts of ICU4C's `i18n/collation*.cpp`, `common/ucharstrie.cpp`, `common/utrie2.cpp`) and ICU's collation data, with the Unicode License V3 of ICU `release-78.3`; the header of `RootCollator.swift` and section 1 name UTS #10 first and point to the entry; the NFD-only test data has a name that says what it is (`ucadata-nfd-only.icu`, `CollationTestData.rootNFDOnly()`) | confirm the form of the entry with the maintainers |
| Small PRs, one task each; squashed commits; tests that fail before and pass after | the sequence of section 7 fits | one PR per step, each with its tests |
| DocC documentation for new methods | the new `StringProtocol` collation methods follow the Darwin signatures; **done 2026-11-11:** every public method has DocC; the last 3 (`localizedCaseInsensitiveCompare`, `localizedStandardCompare`, `localizedCaseInsensitiveContains`) say what the comparison ignores and what still counts, from the options that the code sets (secondary strength; numeric for the standard compare). The protocol witnesses `compare`, `hash`, `encode`, `init(from:)` need none | — |
| Exit tests for new preconditions (`#expect(processExitsWith:)`) | **done 2026-11-11:** of the 9 `precondition` / `preconditionFailure` calls, the 4 that a caller can reach have an exit test (`PreconditionExitTests`, under `FOUNDATION_EXIT_TESTS` like upstream's): the `CEBuffer` subscript read and write out of range, `UCharsTrie.getValue()` without a value result, and tailoring data used as root data without its base. Each test checks the precondition's own message in the child's standard error (a changed message makes them fail). The other 5 cannot be reached through the API: the default of a switch over all 16 values of a 4-bit tag, a trie node value that is 0 or 1 by its encoding, a private function whose callers keep its bound, an invalid scalar from the NFD iterator, and a key path that is always a stored property | — |
| Tests and implementation work on all supported platforms by default; comments on platform conditionals | **done in the code 2026-11-10:** the engine imports `FoundationEssentials`, not `Foundation` (which on Linux and Windows is built on top of this package); `ScratchBuffers.swift` has upstream's import list (Darwin, Android, Bionic, Glibc, Musl, WinSDK, WASILibc) and a thread-local slot for each (pthread key; fiber-local storage on Windows; one slot on WASI, which is single-threaded); `PoolLock` (with `NSLock` outside Darwin) replaced by upstream's `LockedState`, which also drops one `@unchecked Sendable`; our June change around `FloatingPointRoundingRule: Codable` (`#if compiler(<6.2)`) removed — upstream's file is identical to the fork point again; the 21 test files with `import Foundation` use upstream's 3-way import, the resource folders come from one helper in the form of upstream's `ResourceUtilities`, and the two things that only the system Foundation gives (the NFD reference, bridged strings) are in `SystemFoundation.swift`, macOS only, with the reason. Checked on macOS: full suite 1576/140; the Thread Sanitizer run of the concurrency, cache, search, position and sort-key tests (95 tests) clean; BenchFoundation's machine code identical in every hot function (only cold paths changed: tailoring creation, cache insertion, deinit, the file loaders, the publish of a new current-locale slot). Found on the way: upstream's `LockedState` with a `Void` state gives a Thread Sanitizer report ("Swift access race" in `withLockUnchecked`) when two threads take it, also in a minimal test without collation code; with an `Int` state, none. The collator cache's write lock now has an `Int` state (the count of published slots), with a comment; `LockedState` itself is in FoundationEssentials and unchanged | a build and the tests on Linux and Windows (open point 3) |
| Merge-forward branching: target the earliest release branch that should get the change | not decided | choose `main` or a `release/6.x` branch; this also decides how open point 2 (#1683) is met |
| Public API through the Foundation Evolution process | the engine types are `package` (open point 1); the `StringProtocol` methods add Darwin's existing API to the other platforms | ask the workgroup whether API parity with Darwin needs a proposal (the guide has a shorter path for small API additions) |
| Parameterize test probes: test inputs as arguments, not hard-coded | **done 2026-11-11:** a review of the 192 tests without arguments found 36 that loop over, or list, independent hard-coded inputs; all 36 now take them as arguments (`@Test(arguments:)`, two collections where the inputs combine), 4 of them split where one body had two kinds of check. The other 156 check one fact or a sequence of steps, read their inputs from data files, or sweep generated ranges. 75 of the 233 test functions are parameterized; a wrong expected value makes exactly its own case fail, and the report names the input | — |
| No `print` in tests | none | — |

## 9. Why the engine uses unsafe pointers

The contribution guide asks for unsafe APIs only when no safe alternative exists, and asks to isolate them in a small, focused helper. The engine keeps its unsafe code on purpose: each kind replaces a safe form that cost measurable time on the hot paths. On 2026-11-12 each kind was also tried in an isolated or safe form. A form stayed only if it cost nothing: the machine code of every hot function identical, or no instruction more in any compare or sortKey call, in builds with and without whole-module optimization. One kind is now isolated; for the others, this section gives the measured cost of the isolated or safe form.

The older numbers come from the technique log (`Collation/Docs/optimization-targets.md`, § numbers in brackets) and from Docs/11, with the compiler and the machine of their time; they show the size of each cost, not today's exact value. The numbers of 2026-11-12 are from Swift 6.5 on macOS 27.2.1 (technique log §52).

**Counted 2026-11-12** (code lines only; `Unsafe…Pointer`, `withUnsafe…`, `withContiguousStorageIfAvailable`, `allocate` / `deallocate`, `assumingMemoryBound`, `bindMemory`, `Unmanaged`, `unsafeBitCast`, `unsafelyUnwrapped`): 304 uses.

**One fact limits every helper type.** In a build without whole-module optimization, each file compiles alone, and a method of a type in another file stays a call, also with `@inline(__always)`, `@inlinable`, `@_alwaysEmitIntoClient` or `@_transparent`. A view type with its own subscript thus costs one call for each element read, and its loop is no longer vectorized. A read through a stored property costs nothing (§52 (a)). A helper on a hot path must therefore give its reads through a stored property, or be in the same file as its readers.

| kind (uses) | the reason in the source | the safe form and its measured cost | the isolated form (2026-11-12) |
|---|---|---|---|
| **Read-only data views** (139): the tables, CEs and tries of the collation data, as `UnsafeBufferPointer` views into memory that one class owns | the header of `DataStorage`; `CollationDataView`, `ReorderingView`, `RestartSafety`, `FastLatinSetup` | Swift arrays as stored properties of the data structs. The CE iterator copies its data struct once per scalar. With arrays, each copy retained and released each array (eight per copy); with one owner, one retain; with the trivial view, none. ASCII compare went from 697 to ~239 ns, together with two smaller fixes of the same round [Docs/11, round 6]. `Span` cannot replace the views: it is non-escapable, so a stored property cannot hold it | **Not isolated.** `DataStorage` already owns all the memory: it allocates while the data is parsed and frees in `deinit`. A wrapper type for the views is free only if its readers use its stored buffer (`view.buffer[i]`), which leaves an unsafe buffer in every read; it would move the `@unchecked Sendable` reason of `CollationData` and `NormalizationData` into one type, for about 290 changed lines of hot code. Not done (owner's decision); the TODOs at the two types keep it as the migration path |
| **Pinned UTF-8 bytes** (68): the bytes of a contiguous string, from `withContiguousStorageIfAvailable` | `ScalarSource`; `CollationSearch.withPinnedUTF8`; `RootCollator.untraced`; `sharedPrefixLength` (8 bytes at a time) | The `String` iterator retains its string: with the pinned bytes, Thai compare went from 195.3 to 164.9 ns (−15.6%) and paths sortKey −9.5% [§51 (y)]. **`Span`, measured again 2026-11-12:** two short strings compared byte by byte take 2.97 ns with the pinned pointers and 5.60 ns with `utf8Span.span` (ASCII; Latin 2.71 / 5.37, CJK 2.94 / 6.77, paths 15.23 / 20.38, Thai 13.48 / 17.48), 43 against 103 instructions. The cost is in `String.utf8Span` itself: a call into the standard library, 27 instructions per string, which the compiler cannot inline. A span passed to another function now works (it trapped in 2026-07), and its index checks cost nothing; upstream's macOS 26 minimum removes the availability question, not this cost [§52 (g), §22]. `Span` could replace only the pinning for the length of one call: the CE iterators keep their byte source between calls, and a non-escapable span cannot be stored there. If the standard library makes `utf8Span` inlinable, the compare entry can move to `Span`; the measurement takes a few minutes to repeat. That is done for Linux and Windows in Swift `main` (swiftlang/swift#92546, 2026-09-24); on Apple platforms one branch for bridged `NSString` values still calls an internal function, which keeps the getter out of line there | **Not isolated.** One helper for the five places that pin two strings in `RootCollator.swift`: compare +1 instruction on ASCII and Latin, +10 on paths, +3..+5 on Thai; the compiler did not inline it into the options path [§52 (f)]. The pinning stays in its few places, each with `untraced` and its reason; search has its own helper |
| **Boxes and in-place pointers** (48): the setup boxes of `RootCollator.Storage`, the scratch CE iterators, the collator in its cache slot | the doc of `RootCollator.Storage`, `OwnedBox` and `DefaultFastLatinSetup`; `ScratchBuffers.left/right`; `CollatorCache.collatorPointer`, `RootCollator.withCollator` | A `var` property of a class opens a dynamically checked access scope at each `inout` use. With the scratch iterators behind pointers: Thai compare 215.7 → 197.3 ns (−8.2%), sortKey −3.1..−6.7% [§51 (k)]. The quick CJK setup by pointer: CJK compare −5.6% [§51 (b)]. The default fast-Latin setup in one box: ASCII compare −1.8%, Latin −2.6% [§50 (d)]. The collator used in place in its cache slot, with no retain on a reference count that all threads share: one `localizedCompare` 436 → 353 instructions, together with the internal default-options entry [§51 (ak)] | **Isolated: the four setup boxes** are `OwnedBox` values, a noncopyable owner of one value (allocation in init, freeing in deinit, one owner by the compiler's check); the hand-written `deinit` of `Storage` is gone. The machine code of every hot function is identical [§52 (b)]. `OwnedBox` has the init and deinit of the standard library's `UniqueBox` (SE-0517, macOS 27). Its API with `borrowing` parameters in the hot helpers: compare +15 instructions on ASCII (+10%), +16 Latin, +49 CJK, +19 paths, +62 Thai, because a borrowed value cannot stay in a local variable across the closures that pin the bytes [§52 (c)]; so `OwnedBox` gives its pointer, with a TODO to switch at a macOS 27 minimum. **Not isolated:** the scratch iterators in `OwnedBox` cost Thai compare +5.5 instructions per call (register moves), so they keep their pointer fields; the collator in its cache slot is reached only through one private helper (`withCollator`) and five entries in one file |
| **Raw pointers for reads without a lock** (29): the published slots of the collator cache, the fast-Latin cache, the thread-local scratch slot | `CollatorCache.PublishedSlots`, `FastLatinCache`, `ThreadLocalScratch` | A lock on each read (`LockedState`). The current-locale slot without its lock: one `localizedCompare` 516 → 436 instructions, `localizedCompare`, `localizedStandardCompare` and `localizedCaseInsensitiveCompare` −10..−15% in time [§51 (aj)]. A lock on the shared fast-Latin cache makes threads that share one collator much slower than threads with their own collators (the doc of `FastLatinCache`). The standard library has no thread-local storage API yet (a `// TODO:` in `ThreadLocalScratch`) | **Not isolated.** One helper type for the two "publish once, never free" slots would be in a third file, so each read through its method is a call in a build without whole-module optimization, on every `localizedCompare` [§52 (e)] |
| **The rest** (20) | `CEBuffer`; the sort-key writer's `RegionLevel`; `RootCollator.order(fromFastResult:)`, `bits(of:)`; the 4 `unsafelyUnwrapped` | `Array` for the CEs and the level bytes: `Array` calls its uniqueness check out of line at each append, and its clear runs the general `replaceSubrange`. `CEBuffer` (noncopyable, bounds checks kept): sortKey −4.6..−8.6%, Thai compare −8.3% [§51 (h)]. The writer's levels in one `withUnsafeTemporaryAllocation` region (ICU's `MaybeStackArray` idea): sortKey −2.1..−4.2% [§46 (a)] | `CEBuffer` is already a small, focused helper (noncopyable, with `Array`'s bounds check and exit tests); a TODO names its standard form, `UniqueArray` (SE-0527, macOS 27). The region pointer never leaves the writer. The bit cast and the 8-byte load each have their reason and a test |

**The standard library's owner types, measured in advance (2026-11-17, technique log §52 (o)).** `UniqueArray` (SE-0527) and `UniqueBox` (SE-0517) need macOS 27 as the minimum, so they cannot ship today; a scratch build with that minimum shows what they will cost. `UniqueArray<Int64>` in place of `CEBuffer` is a change of 15 lines: compare does not change, sortKey is 2–5% slower with Swift 6.5 (an append in a tight loop costs about 5 instructions more per character; reads cost about 3 fewer), and 7 of the 304 unsafe uses go away. With its batch append for a run of ASCII characters, long strings cost nothing and short strings 2–4% of sortKey. `UniqueBox` in place of `OwnedBox` would remove about 22 more uses, but it costs too much: the real type adds 15 instructions to each ASCII compare (it gives its value only through a borrow, so the hot code reaches it again through two more loads), and compare is 23–26% slower on ASCII, Latin and CJK. So the plan at a macOS 27 minimum is `UniqueArray` yes, `UniqueBox` no. About 275 uses (the data views, the pinned bytes, the reads without a lock) are not a case for either type.

**For the PR description, about `Span`:** "The engine pins string bytes with `withContiguousStorageIfAvailable` because `String.utf8Span` is an out-of-line call that roughly doubles the cost of comparing two short strings (measured with Swift 6.5), and because the CE iterators keep their source between calls, where a non-escapable `Span` cannot be stored."

**How the code limits the risk.** The data parsers check every part against the size of the data before they copy it, and a cut file throws (`DataParseTests`). The views never live longer than the class that owns their memory. The pinned bytes are read only inside the closure that pins them. `OwnedBox` and `CEBuffer` are noncopyable, so each block of memory has exactly one owner, and the compiler rejects a second one; `CEBuffer` keeps the bounds check of `Array`. The 4 `unsafelyUnwrapped` each have their reason in a comment: the caller tested the value first, or the buffer is never empty. The conformance suites, the reference sort keys of ICU, the position invariants and a Thread Sanitizer run of the concurrency tests exercise these paths.
