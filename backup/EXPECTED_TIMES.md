# Expected command timings

**Rule: if a command runs >10% longer than the expected upper bound below,
STOP IMMEDIATELY and investigate. Do not wait. Don't assume a longer compile
or "maybe it'll finish soon."**

Previous failure mode that prompted this doc: I waited silently while
benchmark crashes flew by in the output, and didn't notice until the user
pointed them out. Symptoms of a stall include: file output stuck at 0 bytes
for >30s, ETA progress not advancing, log timestamps frozen.

All times are debug-mode on this Intel iMac 2019 + Swift 6.3.1 + macOS 15.7.3.

## Build

| Command | Expected | Hard limit (10% rule) |
|---|---:|---:|
| `swift build` (no source change) | ~3 s | 4 s |
| `swift build` (Calendar_Hebrew.swift only changed) | ~20–30 s | 33 s |
| `swift build` (Calendar.swift / Calendar_Enumerate.swift changed — wider rebuild) | ~25 s | 28 s |
| `swift build` (cold / cleaned) | ~80–100 s | 110 s |

## Tests

| Command | Expected | Hard limit |
|---|---:|---:|
| `swift test --filter "Hebrew"` (leaf-only edit, e.g. `Calendar_Hebrew.swift`) | ~45–50 s | 55 s |
| `swift test --filter "Hebrew"` (after non-leaf edit + `swift build`) | ~115–125 s | **140 s** |
| `swift test --filter "Calendar"` | ~5–10 s after compile | TBD |
| `swift test --filter "Calendar\|Hebrew"` (leaf-only) | ~50–60 s after compile | 66 s |
| `swift test --filter "EnumerateMicroProfile"` | ~3–4 s test + compile time | TBD |
| Full `swift test` | many minutes | abort if >5× any partial |

**Compile-after-edit on non-leaf files:**
Editing `Calendar.swift`, `Calendar_Enumerate.swift`, or other shared-code
files triggers `swift test`'s incremental rebuild of Tests/ targets —
adds ~60–80 s on top of the test runtime, even if you already ran
`swift build` (which only builds the source target, not the test bundles).
So Hebrew filter post-edit on shared code is ~2 min.

**Lesson learned 2026-05-03:** got caught not setting timeout high enough
for this case; command went background and triggered a "stop" alert. Always
set `swift test` timeout to ≥140 s when edits touched non-leaf files.

## Package benchmarks

| Command | Expected | Hard limit |
|---|---:|---:|
| Full unfiltered run (~9 calendar benchmarks + ~10 locale/TZ + 3 crashing) | ~5–7 min | 8 min |
| Full run incl. Hebrew+Buddhist+Japanese `*Calendar-*` benches, **flags=false (ICU-backed)** | ~13–16 min | 18 min |
| Same, **flags=true (pure-Swift)** | TBD (expect well under ICU run) | 18 min until measured |
| Filtered to ALL calendar benchmarks `--filter "nextThousand\|Recurrence\|CurrentDate"` | ~3–4 min | 5 min |
| Filtered to ONE benchmark `--filter "^<name>$"` (anchored) | ~1.5 min cold (incl. BenchmarkTool build), ~30–40 s warm | 2 min cold |

**Why the ICU-backed full run is slow (2026-06-11):** the per-calendar
`*-allocationsForFixedCalendar` / `*-copyOnWritePerformance` benches use
`.mega` scaling (1M iterations per sample); at ICU speeds (~4–20 µs/iter)
one sample takes 4–20+ s, and there are 15 such benches across
Hebrew/Buddhist/Japanese. Measured 2026-06-11: ~15 min wall.

**Iteration discipline:**
- For "is this change directionally helping?" use single-benchmark filter
  (~30–90s round trip).
- Only run the full filtered set when you want the cross-benchmark picture
  for documentation.
- The unanchored regex `nextThousand|Recurrence|CurrentDate` matched 0
  things in one early attempt (cause unknown — possibly stale build).
  **Anchor with `^name$` for exact-match.** Substring match still works
  with the unanchored form when the build is healthy.

**Three pre-existing failing benchmarks** (unrelated to Hebrew port) are
in `BenchmarkCalendar.swift` lines 179, 205, 214 (firstWeekday=0, en_US
locale asserts). They print "Likely your benchmark crashed" + "1 benchmark
job(s) failed during runtime". Filtering avoids them entirely.

## What "stop immediately" means

When a command exceeds the hard limit:

1. **Foreground commands**: nothing to stop on my side — the wrapper will
   timeout. Investigate the partial output for stall signals (process not
   responding, output frozen, etc.).
2. **`run_in_background: true` commands**: call `TaskStop` immediately, read
   the partial output file, and report findings to the user. Do NOT start
   another command on top.
3. **Monitor commands**: their stdout filter should already surface the
   stall — but if it's silent for longer than expected, kill it.

## Updating this doc

Add a new row whenever a previously-untimed command becomes load-bearing,
or revise a row when a measurement shifts ±20% from what's listed. Don't
let stale numbers rot — outdated bounds defeat the purpose.

## Chinese (added 2026-07-19)

| Task | Expected | Abort at |
|---|---|---|
| `swift test --filter "[Cc]hinese"` (all Chinese probes; the `\|` alternation form silently matches 0 tests from a script — use the char class) | ~60–70 s (measured 63 s on 2026-07-30). Was ~30–35 s until PR #2123's `748229e3` removed the out-of-range caches; the probes hammer out-of-range years far harder than any real caller, so they absorb the full 1.6–1.8× slowdown. Not a regression — do not investigate. | 100 s |
| `swift test --filter "[Jj]apanese" --filter "DailySweep" --filter "StrictPolicy"` (Japanese suites + B/J sweeps/strict + era-inheritance golden tests, 51 tests; measured 2026-07-24) | ~6 s tests, plus ~4 min build after a FoundationEssentials edit | 30 s tests |
| Chinese bench run, `^ChineseCalendar-.*$`, debug | ~60–90 s incl. build | 3 min |
| chineseEnumerateCNYCallbackCount scratch | ~2 s | 10 s |
| ChineseMeanZoneProbe (filter MeanZone) | ~1 s + build | 10 s |
