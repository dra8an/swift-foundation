# Foundation API Benchmark: Swift Collator vs System ICU

Measured 2026-10-29 at about 10:00 on Apple Silicon (macOS 26),
`run_benchmarks.sh` K=3 (min over interleaved runs, each itself min-over-9),
release builds, at `32d3946a`. Includes every optimization through §51 (ah):
new since the 2026-10-28 baseline is (ah) P3c — the first-byte-difference
path of the byte fast path on its own, with a branch-free Order conversion
(compare ascii / latin).

**Machine state:** 1-minute load 10.7 at the start of run B, 12.0 at its
end (run A: 12.2 → 10.7); on AC power, under `caffeinate -i`, more than an
hour after the last wake. An earlier pair the same morning (load 27–40, a
video call) was not recorded: its control drifted +2..+6%. **The tables
show run B** (the convention). Recorded on these grounds (the control
decides, not the load — Docs/27):

1. **The system-ICU control (Table 2) matches the reference within 1.3% in
   run B** (`localizedCompare` 195/364/371/304/498 against
   194/365/369/300/494; run A within 0.6%).
2. **Runs A and B agree:** our Table 1 cells within 1.1%; ICU C within
   2.2%.

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

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    51 |       195 | **3.82× faster** |
| Latin  |    50 |       364 | **7.28× faster** |
| CJK    |    70 |       371 | **5.30× faster** |
| Paths  |    69 |       304 | **4.41× faster** |
| Thai   |   264 |       498 | **1.89× faster** |

### localizedStandardCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    60 |       196 | **3.27× faster** |
| Latin  |    61 |       350 | **5.74× faster** |
| CJK    |    89 |       363 | **4.08× faster** |
| Paths  |    82 |       326 | **3.98× faster** |
| Thai   |   284 |       485 | **1.71× faster** |

### localizedCaseInsensitiveCompare(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    60 |       197 | **3.28× faster** |
| Latin  |    62 |       352 | **5.68× faster** |
| CJK    |    90 |       364 | **4.04× faster** |
| Paths  |    80 |       311 | **3.89× faster** |
| Thai   |   277 |       485 | **1.75× faster** |

### compare(_:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    68 |       309 | **4.54× faster** |
| Latin  |    70 |       477 | **6.81× faster** |
| CJK    |    93 |       484 | **5.20× faster** |
| Paths  |    93 |       415 | **4.46× faster** |
| Thai   |   290 |       626 | **2.16× faster** |

### compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]

New 2026-10-20: the options-translation path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |    85 |       311 | **3.66× faster** |
| Latin  |    86 |       467 | **5.43× faster** |
| CJK    |   116 |       489 | **4.22× faster** |
| Paths  |   110 |       423 | **3.85× faster** |
| Thai   |   310 |       559 | **1.80× faster** |

### localizedStandardContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   240 |       993 | **4.14× faster** |
| Latin  |   268 |      1436 | **5.36× faster** |
| CJK    |   285 |      1271 | **4.46× faster** |
| Paths  |   245 |       968 | **3.95× faster** |
| Thai   |   267 |      1379 | **5.16× faster** |

### localizedCaseInsensitiveContains(_:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   240 |      1001 | **4.17× faster** |
| Latin  |   270 |      1495 | **5.54× faster** |
| CJK    |   284 |      1284 | **4.52× faster** |
| Paths  |   203 |       980 | **4.83× faster** |
| Thai   |   266 |      1433 | **5.39× faster** |

### localizedStandardRange(of:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   305 |       995 | **3.26× faster** |
| Latin  |   333 |      1436 | **4.31× faster** |
| CJK    |   308 |      1273 | **4.13× faster** |
| Paths  |   301 |       990 | **3.29× faster** |
| Thai   |   401 |      1430 | **3.57× faster** |

### range(of:options:locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   110 |       322 | **2.93× faster** |
| Latin  |   363 |       786 | **2.17× faster** |
| CJK    |   335 |       583 | **1.74× faster** |
| Paths  |   135 |       317 | **2.35× faster** |
| Thai   |   417 |       715 | **1.71× faster** |

### range(of:options:.backwards,locale:)

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |   111 |       326 | **2.94× faster** |
| Latin  |   324 |       818 | **2.52× faster** |
| CJK    |   331 |       586 | **1.77× faster** |
| Paths  |   171 |       513 | **3.00× faster** |
| Thai   |   351 |       764 | **2.18× faster** |

### sorted(using: String.StandardComparator.localizedStandard)

New 2026-10-20. ns per ELEMENT of a sort (see "The sort rows" below).

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2199 |     14832 | **6.74× faster** |
| Latin  |  2280 |     17443 | **7.65× faster** |
| CJK    |  3815 |     18724 | **4.91× faster** |
| Paths  |   240 |      1298 | **5.41× faster** |
| Thai   |  1262 |      5731 | **4.54× faster** |

### sorted(using: String.Comparator(options: [], locale:))

New 2026-10-20. ns per element.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2098 |      5120 | **2.44× faster** |
| Latin  |  2174 |      7436 | **3.42× faster** |
| CJK    |  2608 |      7975 | **3.06× faster** |
| Paths  |   182 |       488 | **2.68× faster** |
| Thai   |  1093 |      2467 | **2.26× faster** |

### sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  3643 |     16467 | **4.52× faster** |
| Latin  |  3756 |     19032 | **5.07× faster** |
| CJK    |  5382 |     20401 | **3.79× faster** |
| Paths  |   324 |      1358 | **4.19× faster** |
| Thai   |  1749 |      6346 | **3.63× faster** |

### sorted(using: SortDescriptor(\.name, comparator: .localizedStandard))

New 2026-10-20. ns per element; sorts structs by a String key path.

| Corpus | Swift | System ICU | Speedup |
|--------|-------|-----------|---------|
| ASCII  |  2666 |     16438 | **6.17× faster** |
| Latin  |  2752 |     19002 | **6.90× faster** |
| CJK    |  4284 |     20401 | **4.76× faster** |
| Paths  |   249 |      1345 | **5.40× faster** |
| Thai   |  1398 |      6127 | **4.38× faster** |

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
| ASCII  |     9.3 |   9.3 | **1.00× (equal)** |    75.0 | 104.4 | **1.39× faster** |   127.0 | 0.82× (slower) |
| Latin  |     9.7 |  10.1 | **1.04× faster** |    95.0 | 121.0 | **1.27× faster** |   149.2 | 0.81× (slower) |
| CJK    |    19.3 |  40.8 | **2.11× faster** |   105.2 | 117.7 | **1.12× faster** |   156.2 | 0.75× (slower) |
| Paths  |    18.8 |  30.0 | **1.60× faster** |   179.8 | 373.3 | **2.08× faster** |   227.1 | 1.64× faster |
| Thai   |   164.9 | 172.8 | **1.05× faster** |   149.3 | 155.5 | **1.04× faster** |   201.2 | 0.77× (slower) |

Change against the 2026-10-28 baseline (run B):

| Corpus | compare | sortKey (inout) |
|--------|---------|-----------------|
| ASCII  | 9.9 → 9.3 (**−6.1%**; 0.94× → **1.00×**) | 75.6 → 75.0 (1.38× → 1.39×) |
| Latin  | 10.3 → 9.7 (**−5.8%**; 0.98× → **1.04× faster**) | 96.0 → 95.0 (1.26× → 1.27×) |
| CJK    | 18.6 → 19.3 (+3.8%; 2.20× → 2.11× faster) | 104.9 → 105.2 (1.13× → 1.12×) |
| Paths  | 19.4 → 18.8 (−3.1%; 1.52× → 1.60× faster) | 184.3 → 179.8 (1.99× → 2.08×) |
| Thai   | 163.2 → 164.9 (1.05× → 1.05× faster) | 152.5 → 149.3 (1.01× → 1.04×) |

The compare moves are §51 (ah) (P3c); sortKey did not change (its code is
the same, call for call).

Reproducibility, run A vs run B of the same matrix:

| Corpus | compare A/B | sortKey A/B | ICU compare A/B | ICU sortKey A/B |
|--------|-------------|-------------|-----------------|-----------------|
| ASCII  | 9.3 / 9.3 | 74.8 / 75.0 | 9.3 / 9.3 | 103.9 / 104.4 |
| Latin  | 9.7 / 9.7 | 94.9 / 95.0 | 10.1 / 10.1 | 120.9 / 121.0 |
| CJK    | 19.4 / 19.3 | 104.9 / 105.2 | 40.5 / 40.8 | 118.2 / 117.7 |
| Paths  | 18.8 / 18.8 | 177.8 / 179.8 | 29.4 / 30.0 | 365.3 / 373.3 |
| Thai   | 164.7 / 164.9 | 150.9 / 149.3 | 171.5 / 172.8 | 154.3 / 155.5 |

**Table 2 against 2026-10-28:** every cell within −2..+3%, except
`localizedCompare` ascii 47 → 51 (+9%; run A 50). In the WMO A/B of (ah)
one `localizedCompare` call executed 532 → 516 instructions with no
mispredictions (CPU Counters); this row moved between 47 and 51 across
`-no-WMO` builds of unchanged code before (§51 (ae), (ah)). Recorded as is.

## Analysis

**Engine (Table 1) against hand-tuned ICU C** — the only engine-versus-engine
comparison in this file:

(speedup = ICU C / ours, above 1 = ours faster)

- compare: ascii **1.00× (equal)**, latin **1.04× faster**, cjk **2.11×
  faster**, paths **1.60× faster**, thai **1.05× faster** — ascii and latin
  since §51 (ae), (af), (ah)
- sortKey (inout): ascii **1.39×**, latin **1.27×**, cjk **1.12×**, paths
  **2.08×**, thai **1.04× faster**

**All ten rows are at or ahead of ICU C**: ascii compare equals it (9.3
against 9.3 ns), every other row is faster. The `throws` and the two
`String` arguments of our API (Docs/27, ~1 ns) are included in our
numbers.

The allocating sortKey (`skRet`) is 0.75–0.82× of ICU's speed (1.64× faster
on paths) because it allocates a fresh `[UInt8]` per call BY API CONTRACT;
the inout twin is the one to compare against ICU.

**Foundation APIs (Table 2):** every cell is ahead of system ICU, floor 1.71× (14 APIs).
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
- **ICU C** in Table 1 should read about 9.5/10.1/40.8/29.7/172.0 compare
  and 106.1/122.1/119.3/369.6/154.7 sortKey (2026-10-21, run B). First check which ICU the
  checkout holds (`git -C $ICU_SRC branch --show-current`); a different ICU
  build can change this column for reasons that have nothing to do with load.
- **Run the matrix twice;** the two runs must agree.

Full explanation and per-machine notes: **Docs/27-benchmark-runbook.md**.
Intel numbers: **Docs/25**. Technique log: **optimization-targets.md**.
