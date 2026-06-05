# v9 — `DatesByMatching.Iterator` fast-path hoist

*2026-05-03*

**Status: tested + benchmarked, NOT yet committed.** Snapshotted on top of
v8 (which is also uncommitted). v9 supersedes v8 in the sense that it adds
a tighter optimization path; v8's `_enumerateDatesStep` wiring is still
there and still benefits the RecurrenceRule paths that route through it.

## Files in this snapshot

| File | Change since v8 |
|---|---|
| `Sources/FoundationEssentials/Calendar/Calendar.swift` | Unchanged from v8 (still has the `_calendarNextDate` proxy). |
| `Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift` | **v9 addition**: `DatesByMatching.Iterator.init` probes once and stores `usesFastPath: Bool`. `Iterator.next()` takes a fast inner branch when set, calling `_calendarNextDate` directly without going through `_enumerateDatesStep` (skips per-call policy recheck + `SearchStepResult` synth/destructure). v8's `_enumerateDatesStep` wiring is preserved (still helps RecurrenceRule paths that route through it). |

## Why hoist

Per benchmarks at v8: the Sequence API (`cal.dates(byMatching:)`) was
~7% slower than the block-based `cal.enumerateDates(...)` for the same
fast-path pattern (4,248 ns vs 3,983 ns p50). The block path uses a tight
hand-rolled while loop; the Sequence path went through `Iterator.next()` →
`_enumerateDatesStep` → policy recheck → proxy → protocol method. The
hoist eliminates the `_enumerateDatesStep` call and its overhead for
Sequence-API consumers.

## Verification at this snapshot

- `swift test --filter "Hebrew"` → 49/49 pass.
- `swift test --filter "Calendar"` → 165/165 pass.
- 73,414/73,414 Hebcal regression days unchanged.

## Package benchmark wins (`v8` → `v9`, p50, debug-mode):

| Benchmark | `v8` (step wiring only) | `v9` (+ Iterator hoist) | Δ |
|---|---:|---:|---:|
| `nextThousandThanksgivings` (ns) | 3,983 | 3,873 | -3% |
| `nextThousandThanksgivingsSequence` (ns) | 4,248 | 4,133 | -3% |
| `RecurrenceRuleThanksgivings` (µs) | 1,988 | 1,882 | -5% |
| `RecurrenceRuleThanksgivingMeals` (µs) | 1,704 | 1,625 | -5% |
| `RecurrenceRuleLaborDay` (µs) | 1,733 | 1,650 | -5% |
| `RecurrenceRuleBikeParties` (µs) | 1,684 | 1,638 | -3% |

Uniform 2–5% reduction across all framework benchmarks. The Sequence vs
block gap on p0 closed from 7.7% → 3.6%; the p50 gap (~6.7%) remained,
attributed to fundamental Swift `IteratorProtocol` per-call overhead.

## Why "questionable" (still uncommitted)

- The remaining ~3.6% p0 gap might be addressable but the marginal value
  is low.
- The combined v8 + v9 wiring touches three files
  (`Calendar.swift` proxy, `Calendar_Enumerate.swift` step + iterator).
  Want to make sure the architecture is solid before committing.
- The v8 wiring's per-call policy recheck still costs us on
  `_enumerateDatesStep` paths the iterator hoist doesn't intercept.
  Possible future cleanup: cache the policies-default check once and
  memoize the result.

## Restoration

```sh
cp backup/v9-iterator-fastpath-hoist/Sources/FoundationEssentials/Calendar/Calendar.swift \
   Sources/FoundationEssentials/Calendar/Calendar.swift
cp backup/v9-iterator-fastpath-hoist/Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift \
   Sources/FoundationEssentials/Calendar/Calendar_Enumerate.swift
```
