# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-11-02 at about 12:05 on Apple Silicon (macOS 26.4, 25E190),
`run_benchmarks.sh` K=3 (min over interleaved runs, each itself min-over-9),
release builds, at `f8a9debb`. Includes every optimization through §51 (ap):
new since the 2026-10-30 baseline are (an) `@_specialize` on the generic
wrappers, (ao) identical strength on the bytes path (`.localizedStandard`),
(ap) the quick CJK compare for ja, zh, th and shifted options.

**Machine state:** 1-minute load 22 at the start of run B, 20 at its end
(run A: 20 → 22); on AC power, under `caffeinate -i`, about 2 hours after a
restart. **The tables show run B** (the second pair of the day; a first pair
an hour earlier gave the same picture).

**The macOS anomaly — read this before the Table 2 speedups.** From
2026-11-02 the system-ICU side read **1–14% slower** than its reference, in
four runs, with the same macOS build: `localizedCompare` 210/381/388/315/511
against the long-term 194/365/369/300/494, `compare(_:locale:)` +6..+14%.
The machine and the harness were checked and are not the cause:

1. **ICU C** (plain C, independent of macOS's collation) read its gates
   within 1–2% (compare 9.3/10.1/40.9/29.5/173.0, sortKey
   103.9/120.9/117.8/369.6/154.9).
2. **Our binary of 2026-10-30** (`22af5f68`, `-no-WMO`), run today next to
   the system side, read its recorded numbers again (`localizedCompare`
   40/37/59/57/258 against 40/41/61/57/258; `localizedStandardCompare`
   54/56/83/75/276 against 54/55/83/75/273), while the system side read
   +1..+14%.
3. No harness file changed since 2026-10-29; the same swiftly toolchain
   (`main-snapshot-2026-04-27`) and Xcode.

**Decision (user, 2026-11-02): Table 2 compares against the long-term
macOS reference, not against today's slower macOS** — a conservative
speedup: our ns of today (real, by 1 and 2) against the fastest macOS
measured on this machine. The reference is 194/365/369/300/494 for
`localizedCompare` and the recorded system values of 2026-10-30 for the
other 13 APIs; today's measured system values are in the last column.
After the planned macOS update, the macOS side changes for real: a new
reference then, from two runs on a quiet machine, checked with ICU C and the
2026-10-30 binary (Docs/27).

**Runs A and B agree:** Table 1 within 1.2% (ours and ICU C).

**ICU note.** The ICU C reference (`bench_icu`) links against the local ICU
checkout: ICU 79.1 with Unicode 18 data, not the 79.0.1 data that our
collator bundles. On 2026-10-23 the checkout was on branch `main` (headers
79.1), with the libraries unchanged since 2026-10-21 14:45 (built on the
CLDR 49 integration branch `ICU-23250-CLDR-79-integration-beta4`). Its speed
matches 79.0.1, so the ratios stay comparable. Its KEYS do not: do not
generate golden files from that checkout (technique log §49).

**The harness:** the Swift loop costs about 1 ns per call more than the C
loop, and that is the call shape of our API (`throws`, two `String`
arguments, `options`), which every caller pays. `bench_icu` gives
`ucol_getSortKey` UTF-16 that it converted before its timer, because that
function takes UTF-16 only; that stays by decision. Details: Docs/27, "What
the harness itself costs".

Same Foundation APIs, two backends:

- **Swift Collator**: `BenchFoundation`, release, `-no-WMO` (Docs/27 —
  required on machine 1, a handicap here, so these UNDERSTATE the framework
  build)
- **System ICU**: pre-compiled `bench_system` (system Foundation → NSString →
  CoreFoundation → ICU)

Table 2 values are whole nanoseconds (both sources truncate, the same way in
every run).

## Results (ns/op)

### localizedCompare(_:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |    34 |       194 | **5.71× faster** | 210 |
| Latin  |    35 |       365 | **10.43× faster** | 381 |
| CJK    |    48 |       369 | **7.69× faster** | 388 |
| Paths  |    40 |       300 | **7.50× faster** | 315 |
| Thai   |   234 |       494 | **2.11× faster** | 511 |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |    40 |       200 | **5.00× faster** | 211 |
| Latin  |    42 |       359 | **8.55× faster** | 367 |
| CJK    |    68 |       369 | **5.43× faster** | 379 |
| Paths  |    56 |       328 | **5.86× faster** | 336 |
| Thai   |   249 |       495 | **1.99× faster** | 498 |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |    40 |       201 | **5.03× faster** | 214 |
| Latin  |    42 |       358 | **8.52× faster** | 369 |
| CJK    |    69 |       371 | **5.38× faster** | 381 |
| Paths  |    55 |       314 | **5.71× faster** | 323 |
| Thai   |   250 |       495 | **1.98× faster** | 497 |

### compare(_:locale:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |    41 |       317 | **7.73× faster** | 362 |
| Latin  |    43 |       482 | **11.21× faster** | 527 |
| CJK    |    56 |       489 | **8.73× faster** | 539 |
| Paths  |    48 |       416 | **8.67× faster** | 460 |
| Thai   |   242 |       640 | **2.64× faster** | 675 |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |    61 |       317 | **5.20× faster** | 363 |
| Latin  |    62 |       472 | **7.61× faster** | 514 |
| CJK    |    91 |       485 | **5.33× faster** | 533 |
| Paths  |    75 |       425 | **5.67× faster** | 468 |
| Thai   |   270 |       572 | **2.12× faster** | 607 |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |   222 |      1012 | **4.56× faster** | 1066 |
| Latin  |   252 |      1454 | **5.77× faster** | 1512 |
| CJK    |   265 |      1297 | **4.89× faster** | 1355 |
| Paths  |   217 |       990 | **4.56× faster** | 1056 |
| Thai   |   241 |      1411 | **5.85× faster** | 1461 |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |   221 |      1027 | **4.65× faster** | 1077 |
| Latin  |   251 |      1512 | **6.02× faster** | 1568 |
| CJK    |   264 |      1307 | **4.95× faster** | 1360 |
| Paths  |   175 |       998 | **5.70× faster** | 1060 |
| Thai   |   240 |      1462 | **6.09× faster** | 1514 |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |   286 |      1018 | **3.56× faster** | 1068 |
| Latin  |   314 |      1456 | **4.64× faster** | 1511 |
| CJK    |   287 |      1295 | **4.51× faster** | 1357 |
| Paths  |   272 |      1001 | **3.68× faster** | 1067 |
| Thai   |   370 |      1463 | **3.95× faster** | 1512 |

### range(of:options:locale:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |    85 |       329 | **3.87× faster** | 357 |
| Latin  |   342 |       797 | **2.33× faster** | 822 |
| CJK    |   312 |       593 | **1.90× faster** | 625 |
| Paths  |    96 |       318 | **3.31× faster** | 351 |
| Thai   |   378 |       729 | **1.93× faster** | 753 |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |    88 |       332 | **3.77× faster** | 361 |
| Latin  |   303 |       829 | **2.74× faster** | 857 |
| CJK    |   305 |       598 | **1.96× faster** | 630 |
| Paths  |   135 |       514 | **3.81× faster** | 550 |
| Thai   |   319 |       780 | **2.45× faster** | 802 |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |  2049 |     15144 | **7.39× faster** | 16244 |
| Latin  |  2131 |     17795 | **8.35× faster** | 18780 |
| CJK    |  2491 |     18812 | **7.55× faster** | 19966 |
| Paths  |   218 |      1299 | **5.96× faster** | 1363 |
| Thai   |   976 |      5844 | **5.99× faster** | 6176 |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |  1751 |      5197 | **2.97× faster** | 5760 |
| Latin  |  1827 |      7637 | **4.18× faster** | 8085 |
| CJK    |  2254 |      7939 | **3.52× faster** | 8589 |
| Paths  |   156 |       487 | **3.12× faster** | 520 |
| Thai   |   949 |      2513 | **2.65× faster** | 2701 |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |  3539 |     16866 | **4.77× faster** | 17906 |
| Latin  |  3661 |     19376 | **5.29× faster** | 20577 |
| CJK    |  4155 |     20885 | **5.03× faster** | 21736 |
| Paths  |   307 |      1388 | **4.52× faster** | 1463 |
| Thai   |  1483 |      6451 | **4.35× faster** | 6648 |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU (reference) | Speedup | System ICU measured 2026-11-02 |
|--------|-------|-----------|---------|---------|
| ASCII  |  2538 |     16702 | **6.58× faster** | 17799 |
| Latin  |  2639 |     19404 | **7.35× faster** | 20435 |
| CJK    |  3038 |     20537 | **6.76× faster** | 21527 |
| Paths  |   226 |      1347 | **5.96× faster** | 1438 |
| Thai   |  1122 |      6228 | **5.55× faster** | 6629 |

### The sort rows

One op is one ELEMENT of a sort. Swift's sort makes about 14 comparisons
per element on these 200-line corpora (counted; not n·log2(n) ≈ 7.6), so ns
per element ≈ 14 × (ns per comparison) plus the sort's own work. Each pass sorts max(1, reps / 50) times (6 sorts of 200
lines on ascii; 1 sort of ~33k lines on thai). The paths and thai corpora
are SORTED files, so their sorts make far fewer comparisons per element:
compare the two sides within a corpus, never one corpus with another.

### Direct RootCollator (EngineBench, full WMO) — Table 1

ICU column: ICU C, 79.1 libraries with Unicode 18 data (see the ICU note).
One decimal, run B. **Speedup = ICU C / ours: above 1 means ours is
faster** — the same convention as Table 2. Since 2026-10-29, when every
compare and sortKey row reached ICU C, Table 1 shows the speedup; before,
it showed the ratio ours / ICU (below 1 = faster), and older text in this
file's history and in the technique log uses that ratio.

| Corpus | compare | ICU | speedup | sortKey (inout) | ICU | speedup | sortKey (alloc) | speedup |
|--------|---------|-----|---------|---------|-----|---------|---------|---------|
| ASCII  |     9.3 |   9.3 | **1.00× (equal)** |    77.5 | 103.9 | **1.34× faster** |   133.8 | 0.78× (slower) |
| Latin  |     9.6 |  10.1 | **1.05× faster** |    97.3 | 120.9 | **1.24× faster** |   155.8 | 0.78× (slower) |
| CJK    |    19.0 |  40.9 | **2.15× faster** |   105.5 | 117.8 | **1.12× faster** |   159.2 | 0.74× (slower) |
| Paths  |    19.3 |  29.5 | **1.53× faster** |   195.8 | 369.6 | **1.89× faster** |   248.1 | 1.49× faster |
| Thai   |   162.9 | 173.0 | **1.06× faster** |   148.8 | 154.9 | **1.04× faster** |   206.2 | 0.75× (slower) |

Change against the 2026-10-30 baseline (run B; that run read ~2% slow):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 9.4 → 9.3 (1.00× → 1.00×) | 76.9 → 77.5 (1.38× → 1.34×) |
| Latin  | 10.0 → 9.6 (1.03× → 1.05×) | 97.3 → 97.3 (1.27× → 1.24×) |
| CJK    | 19.7 → 19.0 (2.10× → 2.15×) | 107.3 → 105.5 (1.11× → 1.12×) |
| Paths  | 18.9 → 19.3 (1.59× → 1.53×) | 189.5 → 195.8 (1.96× → 1.89×) |
| Thai   | 167.5 → 162.9 (1.05× → 1.06×) | 152.3 → 148.8 (1.03× → 1.04×) |

The engine's compare changed only in §51 (ap) (the quick CJK dispatch; its
A/B: cjk −1.3..−3.0%, paths −1.8 / +0.8%); sortKey did not change. Paths
sortKey 189.5 → 195.8 (+3.3%): its code did not change; on 2026-10-30 one
call executed 2487 instructions against 2466 in §51 (ah), and EngineBench
A/Bs showed it moving with the layout (+3.9% plain, −0.2% aligned; §51 (am)).
Not counted again after §51 (ap).

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 9.3 / 9.3 | 77.3 / 77.5 | 9.3 / 9.3 | 104.0 / 103.9 |
| Latin  | 9.6 / 9.6 | 97.2 / 97.3 | 10.1 / 10.1 | 121.4 / 120.9 |
| CJK    | 19.0 / 19.0 | 105.7 / 105.5 | 40.6 / 40.9 | 117.3 / 117.8 |
| Paths  | 19.3 / 19.3 | 195.6 / 195.8 | 29.4 / 29.5 | 365.5 / 369.6 |
| Thai   | 162.8 / 162.9 | 148.0 / 148.8 | 171.0 / 173.0 | 154.3 / 154.9 |

**Table 2 against 2026-10-30, our ns (the speedups also changed reference:
see the anomaly above):**

| API (ns, `-no-WMO`) | ascii | latin | cjk | paths | thai |
|---|---|---|---|---|---|
| `localizedCompare` | 40 → 34 | 41 → 35 | 61 → 48 | 57 → 40 | 258 → 234 |
| `compare(_:locale:)` | 44 → 41 | 41 → 43 | 63 → 56 | 62 → 48 | 261 → 242 |
| `compare(_:options:range:locale:)` | 69 → 61 | 71 → 62 | 101 → 91 | 92 → 75 | 295 → 270 |
| `localizedStandardCompare` | 54 → 40 | 55 → 42 | 83 → 68 | 75 → 56 | 273 → 249 |
| `localizedCaseInsensitiveCompare` | 53 → 40 | 54 → 42 | 83 → 69 | 73 → 55 | 271 → 250 |
| `range(of:options:locale:)` | 95 → 85 | 354 → 342 | 320 → 312 | 111 → 96 | 399 → 378 |
| `sorted(using: .localizedStandard)`, per element | 2014 → 2049 | 2092 → 2131 | **3630 → 2491** | 225 → 218 | **1196 → 976** |
| `sorted(using: String.Comparator(…))`, per element | 1722 → 1751 | 1790 → 1827 | 2224 → 2254 | 156 → 156 | 977 → 949 |

`compare(_:locale:)` latin 41 → 43 and the ascii / latin sorts +1.7..+2.1%
include the accepted `-no-WMO` cost of §51 (ap) (+8 instructions on the
default-options entry for ascii / latin); in WMO, the framework's build
mode, those rows did not lose. The contains rows and `localizedStandardRange`
are 2–8% faster; the thai and cjk sorts gain from §51 (ao).

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

(speedup = ICU C / ours, above 1 = ours faster)

- compare: ascii **1.00× (equal)**, latin **1.05× faster**, cjk **2.15×
  faster**, paths **1.53× faster**, thai **1.06× faster** — ascii and latin
  since §51 (ae), (af), (ah)
- sortKey (inout): ascii **1.34×**, latin **1.24×**, cjk **1.12×**, paths
  **1.89×**, thai **1.04× faster**

**All ten rows are at or ahead of ICU C**: ascii compare equals it (9.3
against 9.3 ns), every other row is faster. The `throws` and the two
`String` arguments of our API (Docs/27, ~1 ns) are included in our
numbers.

The allocating sortKey (`skRet`) is 0.74–0.78× of ICU's speed (1.49× faster
on paths) because it allocates a fresh `[UInt8]` per call BY API CONTRACT;
the inout twin is the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.90× against the long-term reference (14 APIs; `range(of:locale:)` cjk).
Most of that lead comes from removing the system path's NSString →
CoreFoundation → C++ bridge layers, not from the collation engine. Do not use
Table 2 as evidence about engine quality; Table 1 is that evidence. Against
the 2026-10-20 14:35 run, the wrapper rows moved with §51 (p) (the generic
String conversion removed): `localizedCompare` 59/62/82/78/304 →
48/51/70/65/285, `localizedStandardCompare` 72/74/106/94/311 →
63/65/99/85/311, `compare(_:locale:)` 85 → 70 and the options compare
101 → 89 on ascii, `range(of:locale:)` ascii 119 → 108; contains and
`localizedStandardRange` −1..−2%. This table uses the `-no-WMO` build; the
WMO A/B of §51 (p) shows larger gains. Thai is the weakest family; it is
also the engine's slowest corpus.

**The sort rows, split (2026-10-20, temporary probe rows; ascii, load ~58,
so approximate).** Swift's sort makes **14.0 comparisons per element** on 200
lines (counted), not n·log2(n) ≈ 7.6 — an earlier version of this paragraph
assumed 7.6 and gave 280–330 ns per comparison, about twice too much.
Per comparison (ns per element ÷ 14):

| how the sort compares | ns per comparison |
|---|---:|
| `sorted { (try? collator.compare($0, $1)) == .ascending }` (engine) | ~20 |
| `sorted { $0.localizedCompare($1) == .orderedAscending }` | ~67 |
| `sorted { comparator.compare($0, $1) == … }`, `String.Comparator` | ~74 |
| `sorted(using: String.Comparator(…))` | ~153 |
| `sorted { comparator.compare … }`, `.localizedStandard` | ~103 |
| `sorted(using: .localizedStandard)` | ~183 |
| `sorted(using: SortDescriptor(…))` | ~210 |
| `sorted(using: KeyPathComparator(…))` | ~288 |

So `Sequence.sorted(using:)` itself adds ~80 ns per comparison: it is a
public generic in FoundationEssentials that is not `@inlinable`, so a caller
in another module runs the unspecialized generic sort (elements moved through
value witnesses, every comparison through the `SortComparator` witness
table). The system side runs the same generic code. `.localizedStandard`
costs ~31 ns more per call than `localizedStandardCompare`, and
`KeyPathComparator` ~100 ns more than `SortDescriptor`.

## How to reproduce

```sh
cd swift-foundation-collation
ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2 \
ICU_BUILD=$ICU_SRC/icu4c/source \
  caffeinate -i /Users/dragan/Projects/dra8an/swift-foundation-collation/Collation/Tools/run_benchmarks.sh 3   # absolute path: HANDOFF START HERE, "Full matrix"
```

K=3 takes about 6–8 minutes (14 Table 2 APIs). Check the machine first — load average, memory,
and the time since the last wake (Docs/27):

```sh
sysctl -n vm.loadavg; memory_pressure | grep "free percentage"
pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -3
```

Sanity gates before you record a run:

- **The load control:** system ICU in Table 2 should read about
  194/365/369/300/494 for `localizedCompare`. If it drifts by more than
  ~3%, the box is too busy to record.
- **ICU C** in Table 1 should read about 9.3/10.1/40.8/30.0/172.8 compare
  and 104.4/121.0/117.7/373.3/155.5 sortKey (2026-10-29, run B). First check which ICU the
  checkout holds (`git -C $ICU_SRC branch --show-current`); a different ICU
  build can change this column for reasons that have nothing to do with load.
- **Run the matrix twice;** the two runs must agree.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
