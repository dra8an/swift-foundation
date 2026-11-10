# 31 — Summary for the swift-foundation maintainers

> Written 2026-11-09 for the upstream review of branch `port/collation`
> (fork `dra8an/swift-foundation`). Every number has its source in this
> repository; the sources are named in brackets.

## 1. What the port is

A Swift implementation of the Unicode Collation Algorithm (UTS #10) inside
`FoundationInternationalization`, so that the locale-aware string APIs work
on platforms without the Darwin Foundation framework (issue #284). It follows
ICU4C's collation runtime (the "v2" design) and the ICU4X model:

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

Code: `Sources/FoundationInternationalization/Collation/` (15 files, 7,459
lines) and the Foundation wiring in `String/String+Collation.swift` (the
collator cache, 287 lines), `String/StringProtocol+Locale.swift` and
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
  `KeyPathComparator` too.

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
- 39 test files with 225 test functions, most of them parameterized; the
  package's full suite passes: 1576 tests in 140 suites.
- **One deliberate difference from ICU:** ICU's `ucol_strcoll` skips a
  common prefix in a way that is wrong for two option sets (alternate =
  shifted, backward secondary); its compare then disagrees with its own sort
  keys. Our compare agrees with the sort keys and UTS #10 (technique log
  §51 (z)).

## 4. Performance

Measured on Apple Silicon (M1 Max), macOS 27.2.1, Swift 6.5, the median of 4
runs (Docs/21, 2026-11-06).

**The engine against ICU4C** (EngineBench against ICU C, ns per call;
speedup = ICU / ours):

| corpus | compare | sortKey |
|---|---|---|
| ASCII | 8.9 / 9.3, 1.04× | 71.8 / 104.0, 1.45× |
| Latin | 9.1 / 10.1, 1.11× | 92.1 / 120.7, 1.31× |
| CJK | 18.4 / 40.5, 2.20× | 101.1 / 119.8, 1.19× |
| paths | 19.9 / 29.5, 1.49× | 173.4 / 365.3, 2.11× |
| Thai | 160.4 / 172.2, 1.07× | 143.1 / 153.9, 1.08× |

The API that returns a new `[UInt8]` key is 0.80–0.86× of ICU, which writes
into the caller's buffer; most of that difference is the new array itself
(§51 (be)).

**The Foundation APIs against macOS's own implementation** (WMO release
build against `NSString` → CoreFoundation → ICU on the same machine;
mostly the bridge that the Swift path does not have): `localizedCompare`
12 / 12 / 24 / 23.5 / 166 ns against 201 / 349 / 356 / 313 / 504 ns; the
lowest speedup of all rows 2.90× (Docs/21).

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

## 6. Open points (for the maintainers to decide)

1. **Engine types: `package`, not `public` (done 2026-11-09).** `RootCollator`,
   `CollationData`, `NormalizationData` and `CollationOptions` were `public`
   in `FoundationInternationalization`, which made them Foundation API. They
   are now `package`: visible inside swift-foundation (the Foundation wiring,
   the benchmark harness in the same package), not to its clients. The tests
   use `@testable import`. The machine code of compare and sortKey did not
   change (instruction counts identical).
2. **Upstream `main` has an ICU-based compare (PR #1683),** behind the flag
   `FOUNDATION_ICU_STRING_COMPARE` (off by default), for
   `compare(_:options:range:locale:)` only; it opens and closes an ICU
   collator per call. This branch starts from `upstream/release/6.3`
   (`dbacc677`); a PR to `main` must replace or reconcile it (rebase plan:
   Docs/24). **Open question:** that change also adds a stub in
   FoundationEssentials (`String/StringProtocol+Stub.swift`, behind the same
   flag). Docs/24 proposes to remove it; the port so far makes no
   FoundationEssentials change. Before the PR branch is made on a fresh
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
5. **Test-only data: in the test target (done 2026-11-09).** The ICU4X
   variant of the root data (`ucadata-icu4x.icu`, 585 KB, used only by the
   conformance and differential tests) moved to
   `Tests/.../Collation/TestData/`, loaded by `CollationTestData.rootICU4X()`;
   `CollationData.rootICU4X()` is gone. `FoundationInternationalization`
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
   update.

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
| No comments that only explain what the code does, or that refer to the history of a change; no manual wrapping | **done 2026-11-10:** 121 comment lines in 17 files rewritten — no reference to the technique log or a § number is left, no measurement numbers (one kept where the number is the reason: a tailoring build takes ~0.2 ms, so the cache does not hold its lock during it), no references to `Collation/Tools`; the "why" of each choice stays. Checked file by file: the code without comments is identical | the history stays in `Collation/Docs` and goes into the PR descriptions |
| Avoid `Unsafe…Pointer` APIs unless no safe alternative exists; isolate them in small helpers | 250 uses, by kind (counted 2026-11-10): read-only data views 104, pinned UTF-8 bytes 45, one-object boxes and in-place pointers 42, raw pointers 18, small rest. **Justified 2026-11-10 (section 9):** each kind has its reason at its central declaration in the source (added: why not `Span`, the reason for each of the 4 `unsafelyUnwrapped`, the setup boxes of `RootCollator.Storage`; the code without comments is identical); section 9 gives the measured cost of the safe form of each kind. No use moved: each allocation is already in the init and deinit of the type that owns the memory | put the section 9 table in the PR description; expect review discussion |
| `@unchecked Sendable` and `nonisolated(unsafe)`: a comment why it is safe, and a `// TODO:` migration path | **done 2026-11-10:** all 9 have an `@unchecked Sendable:` reason; 6 have a `// TODO:` migration path (one Sendable wrapper for the buffer views; `LockedState` for the tailoring cache; a standard thread-local API); 3 say why no migration is planned (raw memory, lock-free published snapshots) | — |
| No force unwraps (`!`, `as!`) in sources or tests; `try` / `#require` in tests | **done 2026-11-10:** 88 in 13 test files → `try #require`, a `guard let` in one parser; 2 in the sources → `flatMap`, and `guard let … else { preconditionFailure(…) }` (the compiled wrapper code is identical). Left on purpose: 4 `unsafelyUnwrapped` in hot paths, part of the unsafe use (row 2). The new `preconditionFailure` cannot be reached from a test (a private helper, called only with stored-property key paths), so it has no exit test | — |
| Performance through `swift-benchmark` entries under `Benchmarks/` | the benchmarks live in `Collation/` (not part of the PR) | `Benchmarks/` entries for the numbers the PR claims |
| Small PRs, one task each; squashed commits; tests that fail before and pass after | the sequence of section 7 fits | one PR per step, each with its tests |
| DocC documentation for new methods | the new `StringProtocol` collation methods follow the Darwin signatures; their DocC is partly there | complete DocC on every method that the PR adds |
| Merge-forward branching: target the earliest release branch that should get the change | not decided | choose `main` or a `release/6.x` branch; this also decides how open point 2 (#1683) is met |
| Public API through the Foundation Evolution process | the engine types are `package` (open point 1); the `StringProtocol` methods add Darwin's existing API to the other platforms | ask the workgroup whether API parity with Darwin needs a proposal (the guide has a shorter path for small API additions) |
| No `print` in tests | none | — |

## 9. Why the engine uses unsafe pointers

The contribution guide asks for unsafe APIs only when no safe alternative exists. The engine keeps its unsafe code on purpose: each kind replaces a safe form that cost measurable time on the hot paths. This section gives, for each kind, where the source states the reason, the safe form, and the cost of the safe form as measured when the change went in.

The numbers come from the technique log (`Collation/Docs/optimization-targets.md`, § numbers in brackets) and from Docs/11. They are from the time of each change, with the compiler and the machine of that time. They are not measured again; they show the size of each cost, not today's exact value.

| kind (uses) | the reason in the source | the safe form | its measured cost |
|---|---|---|---|
| **Read-only data views** (104): the tables, CEs and tries of the collation data, as `UnsafeBufferPointer` views into memory that one class owns | the header of `DataStorage`; `CollationDataView`, `ReorderingView`, `RestartSafety`, `FastLatinSetup` | Swift arrays as stored properties of the data structs | The CE iterator copies its data struct once per scalar. With arrays, each copy retained and released each array (eight per copy); with one owner, one retain; with the trivial view, none. ASCII compare went from 697 to ~239 ns, together with two smaller fixes of the same round [Docs/11, round 6]. `Span` cannot replace the views: it is non-escapable, so a stored property cannot hold it. |
| **Pinned UTF-8 bytes** (45): the bytes of a contiguous string, from `withContiguousStorageIfAvailable` | `ScalarSource`; `CollationSearch.withPinnedUTF8`; `RootCollator.untraced`; `sharedPrefixLength` (8 bytes at a time) | the `String` iterator in the scratch iterators; `String.utf8Span` | The `String` iterator retains its string. When the NFD input moved from it to the pinned bytes, Thai compare went from 195.3 to 164.9 ns (−15.6%) and paths sortKey −9.5% [§51 (y)]. `utf8Span` needs macOS 26 (the package supports macOS 15). On two short strings its two property chains cost ~10 ns against ~4 ns for the two nested closures, and in 2026-07 a `Span` passed into another function trapped in the lifetime checker [§22]. |
| **Boxes and in-place pointers** (42): the setup boxes of `RootCollator.Storage`, the scratch iterators, the collator in its cache slot | the doc of `RootCollator.Storage` and `DefaultFastLatinSetup`; `ScratchBuffers.left/right`; `CollatorCache.collatorPointer`, `RootCollator.withCollator` | `var` stored properties of a class; a copy of the collator out of the cache | A `var` property of a class opens a dynamically checked access scope at each `inout` use. With the scratch iterators behind pointers: Thai compare 215.7 → 197.3 ns (−8.2%), sortKey −3.1..−6.7% [§51 (k)]. The quick CJK setup by pointer: CJK compare −5.6% [§51 (b)]. The default fast-Latin setup in one box: ASCII compare −1.8%, Latin −2.6% [§50 (d)]. The collator used in place in its cache slot, with no retain on a reference count that all threads share: one `localizedCompare` 436 → 353 instructions, together with the internal default-options entry [§51 (ak)]. |
| **Raw pointers for reads without a lock** (18): the published slots of the collator cache, the fast-Latin cache, the thread-local scratch slot, the `DataStorage` allocations | `CollatorCache.PublishedSlots`, `FastLatinCache`, `ThreadLocalScratch`, `DataStorage` | a lock on each read (`LockedState`) | The current-locale slot without its lock: one `localizedCompare` 516 → 436 instructions, `localizedCompare`, `localizedStandardCompare` and `localizedCaseInsensitiveCompare` −10..−15% in time [§51 (aj)]. A lock on the shared fast-Latin cache makes threads that share one collator much slower than threads with their own collators (the doc of `FastLatinCache`). The standard library has no thread-local storage API yet (a `// TODO:` in `ThreadLocalScratch`). |
| **The rest** | `CEBuffer`; the sort-key writer's `RegionLevel`; `PoolLock` | `Array` for the CEs and the level bytes; `NSLock` | `Array` calls its uniqueness check out of line at each append, and its clear runs the general `replaceSubrange`. `CEBuffer` (noncopyable, bounds checks kept): sortKey −4.6..−8.6%, Thai compare −8.3% [§51 (h)]. The writer's levels in one `withUnsafeTemporaryAllocation` region (ICU's `MaybeStackArray` idea): sortKey −2.1..−4.2% [§46 (a)]. `os_unfair_lock` must have a stable address, so it is allocated. |

**How the code limits the risk.** The data parsers check every part against the size of the data before they copy it, and a cut file throws (`DataParseTests`). The views never live longer than the class that owns their memory. The pinned bytes are read only inside the closure that pins them. `CEBuffer` keeps the bounds check of `Array`. The 4 `unsafelyUnwrapped` each have their reason in a comment: the caller tested the value first, or the buffer is never empty. The conformance suites, the reference sort keys of ICU, the position invariants and a Thread Sanitizer run of the concurrency tests exercise these paths.

