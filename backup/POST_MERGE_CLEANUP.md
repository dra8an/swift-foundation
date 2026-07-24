# Post-merge cleanup & branch reconciliation model

> Written 2026-07-24, topology verified same day. This is the standing
> playbook for how research branches, PR branches, and upstream merges
> reconcile — including the two approved PRs (#2105, #2123) and the
> upcoming Gregorian refactoring. Cold readers: this doc assumes the
> workflow described in `HANDOFF.md` / `CHINESE_PLAN.md` §1.

## 1. The topology (verified 2026-07-24)

```
upstream/main ──┬── port/buddhist-japanese-main   PR #2105 (APPROVED, head d140a7cf + era trim 9e05da05… line)
                └── port/chinese-main             PR #2123 (APPROVED)

port/hebrew (FROZEN @ 67c538c, v26)
  └── port/buddhist (FROZEN @ ae2bc97 — never moved after port/chinese branched)
        └── port/chinese  ← THE LIVING TIP (92 commits past base: Chinese port
              + all #2105 review back-syncs through d140a7cf + era-trim
              back-sync 6e1b9f2)
```

## 2. The three invariants

1. **One living research branch at a time.** The moment a child branches,
   the parent FREEZES — it receives nothing ever again. All back-syncs of
   upstream/PR-side changes land on the living tip only. A frozen parent
   diverging from what its PR eventually merged is normal and harmless
   (`port/hebrew` diverged from #1953's merged form the same way);
   deliberate research-vs-upstream deltas are tracked in the divergence
   registry (currently in `project_chinese_port` memory + this backup/:
   Japanese era table plain-array, base shims; Hebrew's are in
   `LOCAL_VS_UPSTREAM_DIVERGENCE.md`).
2. **PR branches are siblings off `upstream/main`, never stacked on each
   other.** They interact only at merge time via trivial
   `Calendar_Cache.swift` flag adjacency.
3. **Back-sync direction is one-way: PR/upstream → living tip.** Research
   probes (Suites A/B/C, sweeps, strict) stay research-side; only code
   travels outward, via the 6.4 machine's clean branches.

## 3. Merge-event playbooks

### When PR #2105 (Buddhist/Japanese) merges

- [ ] Record the merge commit hash in memory + `HANDOFF.md` workstream table.
- [ ] Diff the PR's FINAL state vs the last back-synced point (`d140a7cf`
      + era trim): any late review fixups → back-sync to `port/chinese`,
      update divergence registry.
- [ ] Declare `port/buddhist` archival in `HANDOFF.md` (it already is,
      de facto).
- [ ] Rerun the B/J filter set on the tip (expected times:
      `EXPECTED_TIMES.md` row for the Japanese filter set).
- [ ] Feature flags remain OFF on SPM; Apple-side enablement is Apple's.

### When PR #2123 (Chinese) merges

- [ ] Same first three steps, applied to `port/chinese`'s Chinese content.
- [ ] `port/chinese` REMAINS the living tip afterward (until the next
      workstream branches off it — see §4).
- [ ] Close out: pending 6.4 release run results, richgillam HKO answer
      disposition, upstream icu#4070 outcome — record each in
      `CHINESE_PLAN.md`.

### Whichever PR merges SECOND

- [ ] Its branch needs a rebase on the 6.4 machine; the only expected
      conflict is `Calendar_Cache.swift` flag adjacency (both PRs add a
      feature-flag function + `_calendarClass` line). Resolution: keep both,
      order consistently with upstream's existing hebrew entry.

### Standing watch items (block none of the above)

- **icu#4019 / Apple ICU rebase**: when the bundled ICU picks up the
  pre-Meiji era removal, RE-ENABLE the three gated probes in
  `CalendarDailySweepParityProbe.swift` (`.disabled(...)` markers) and the
  pre-Meiji comparisons; re-run; record.
- **icu#4070**: Chinese upstream issue — outcome may adjust the extreme-date
  fix (`9fa022a` píngqì zone).

## 4. Gregorian refactoring — placement

- **Order: AFTER both #2105 and #2123 merge.** Rationale: it touches
  `_CalendarGregorian`, which Buddhist/Japanese wrap by composition; once
  B/J + Chinese are upstream, their tests ride upstream CI as the
  refactor's regression net, and there are no in-flight PRs to conflict.
- **PR side:** own clean branch off `upstream/main` (e.g.
  `port/gregorian-refactor-main`), own PR. Never stacked on the other PR
  branches.
- **Research side:** if probe-driven development is needed, branch
  `port/gregorian` off the `port/chinese` tip — at that moment
  `port/chinese` freezes and `port/gregorian` becomes the living tip
  (invariant 1 continues).
- **Safety net:** B/J touch Gregorian only through its public `_CalendarProtocol`
  surface, so internal refactors are insulated by design; the parity suites
  + daily sweeps (85k + 73k days) on the living tip are the alarm system —
  run them after every Gregorian-touching back-sync.
- **The active design is `GREGORIAN_VARIANTS_PLAN.md`** (ROC +
  Gregorian-variant dedup) — this playbook governs its branch/PR placement;
  that doc governs its content. It ships INSIDE PR A (see
  `REMAINING_CALENDARS_SCOPE.md`) because it only touches the flag-gated
  variant wrappers, not `_CalendarGregorian`.
- **Keep separate:** the older deferred SHAREABLE_APIS dedup *inside*
  `_CalendarGregorian` (#2028-era, `PR_PLAN.md`) touches live, non-gated
  code. Its own PR, any time after PR A.

## 5. End state after full cleanup

All three frozen research branches (`port/hebrew`, `port/buddhist`,
`port/chinese`) remain on the fork as archaeology; the living tip is
whatever the active workstream is; upstream/main contains Hebrew + Buddhist
+ Japanese + Chinese behind flags. Delete nothing — fork branches are cheap
and every PR's provenance stays reconstructible.
