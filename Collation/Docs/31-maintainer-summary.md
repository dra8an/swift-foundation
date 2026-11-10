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
  `ucadata.icu` and 98 compiled tailorings, from ICU 79.0.1. There is no
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
| No comments that only explain what the code does, or that refer to the history of a change; no manual wrapping | 182 references to the technique log or a § number, 59 comment lines with measurements (ns, instructions, %), in 964 comment lines | keep only the non-obvious "why"; the history stays in `Collation/Docs` and goes into the PR descriptions |
| Avoid `Unsafe…Pointer` APIs unless no safe alternative exists; isolate them in small helpers | 254 uses (data views, pinned UTF-8 bytes, scratch buffers) | a short justification per kind of use (performance, measured); keep them inside small helpers; expect review discussion |
| `@unchecked Sendable` and `nonisolated(unsafe)`: a comment why it is safe, and a `// TODO:` migration path | **done 2026-11-10:** all 9 have an `@unchecked Sendable:` reason; 6 have a `// TODO:` migration path (one Sendable wrapper for the buffer views; `LockedState` for the tailoring cache; a standard thread-local API); 3 say why no migration is planned (raw memory, lock-free published snapshots) | — |
| No force unwraps (`!`, `as!`) in sources or tests; `try` / `#require` in tests | **done 2026-11-10:** 88 in 13 test files → `try #require`, a `guard let` in one parser; 2 in the sources → `flatMap`, and `guard let … else { preconditionFailure(…) }` (the compiled wrapper code is identical). Left on purpose: 4 `unsafelyUnwrapped` in hot paths, part of the unsafe use (row 2). The new `preconditionFailure` cannot be reached from a test (a private helper, called only with stored-property key paths), so it has no exit test | — |
| Performance through `swift-benchmark` entries under `Benchmarks/` | the benchmarks live in `Collation/` (not part of the PR) | `Benchmarks/` entries for the numbers the PR claims |
| Small PRs, one task each; squashed commits; tests that fail before and pass after | the sequence of section 7 fits | one PR per step, each with its tests |
| DocC documentation for new methods | the new `StringProtocol` collation methods follow the Darwin signatures; their DocC is partly there | complete DocC on every method that the PR adds |
| Merge-forward branching: target the earliest release branch that should get the change | not decided | choose `main` or a `release/6.x` branch; this also decides how open point 2 (#1683) is met |
| Public API through the Foundation Evolution process | the engine types are `package` (open point 1); the `StringProtocol` methods add Darwin's existing API to the other platforms | ask the workgroup whether API parity with Darwin needs a proposal (the guide has a shorter path for small API additions) |
| No `print` in tests | none | — |

