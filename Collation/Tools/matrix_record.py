#!/usr/bin/env python3
# Docs/21 tables from SEVERAL matrix runs of the same binaries: the MEDIAN of each cell, and a mark ‡ on every cell
# whose runs differ by 5% or more (a "two-level" cell; its range is listed). The recording rule since 2026-11-04:
# record the median of at least 4 runs (technique log §51 (au), Docs/27 "Recording").
# Usage (repo root): python3 Collation/Tools/matrix_record.py <run1.txt> <run2.txt> ... > tables.md
#   The run files are the outputs of Collation/Tools/run_benchmarks.sh.
import re, sys, statistics

# The gates of the checks (Docs/27; set 2026-11-04 from 6 runs, Swift 6.5, macOS 27.2.1).
GATE_ICU_CMP = {'ascii': 9.3, 'latin': 10.1, 'cjk': 40.7, 'paths': 29.5, 'thai': 172.0}
GATE_ICU_SK = {'ascii': 104.1, 'latin': 120.7, 'cjk': 119.3, 'paths': 365.2, 'thai': 153.7}
GATE_MACOS = {'ascii': 200, 'latin': 341, 'cjk': 354, 'paths': 314, 'thai': 502}  # system localizedCompare
CORP = ['ascii', 'latin', 'cjk', 'paths', 'thai']
NAME = {'ascii': 'ASCII', 'latin': 'Latin', 'cjk': 'CJK', 'paths': 'Paths', 'thai': 'Thai'}
TITLES = [
    ('localizedCompare', 'localizedCompare(_:)'),
    ('localizedStdCmp', 'localizedStandardCompare(_:)'),
    ('localizedCaseICmp', 'localizedCaseInsensitiveCompare(_:)'),
    ('compare(locale:)', 'compare(_:locale:)'),
    ('compare(opts:loc:)', 'compare(_:options:range:locale:) — options [.caseInsensitive, .diacriticInsensitive]'),
    ('localizedStdContns', 'localizedStandardContains(_:)'),
    ('localizedCaseICnt', 'localizedCaseInsensitiveContains(_:)'),
    ('localizedStdRange', 'localizedStandardRange(of:)'),
    ('range(of:locale:)', 'range(of:options:locale:)'),
    ('range(backwards)', 'range(of:options:.backwards,locale:)'),
    ('sortStdComparator', 'sorted(using: String.StandardComparator.localizedStandard) — ns per ELEMENT'),
    ('sortCmp(locale)', 'sorted(using: String.Comparator(options: [], locale:)) — ns per element'),
    ('sortKeyPathCmp', 'sorted(using: KeyPathComparator(\\.name, comparator: .localizedStandard)) — ns per element'),
    ('sortSortDescriptor', 'sorted(using: SortDescriptor(\\.name, comparator: .localizedStandard)) — ns per element'),
]

def parse(f):
    t1, t2, api = {}, {}, None
    for l in open(f):
        m = re.match(r'--- (.+) ---', l)
        if m: api = m.group(1); continue
        m = re.match(r'(ascii|latin|cjk|paths|thai)\s+\|\s+(\S+)\s+(\S+)\s+\S+\s+\|\s+(\S+)\s+\S+\s*$', l)
        if m and api:
            t2[(api, m.group(1))] = tuple(float(x) for x in m.group(2, 3, 4)); continue
        m = re.match(r'(ascii|latin|cjk|paths|thai)\s+\|\s+(\S+)\s+(\S+)\s+\S+\s+\|\s+(\S+)\s+(\S+)\s+\S+\s+\|\s+(\S+)\s+\S+\s*$', l)
        if m and not api:
            t1[m.group(1)] = tuple(float(x) for x in m.group(2, 3, 4, 5, 6))
    return t1, t2

runs = [parse(f) for f in sys.argv[1:]]
if len(runs) < 4:
    print(f'NOTE: {len(runs)} runs; the recording rule asks for at least 4.\n')
two_level = []

def med(values):
    return statistics.median(values)

def spread(values):
    m = med(values)
    return (max(values) - min(values)) / m if m else 0

def t2cell(api, c, i, label):
    v = [r[1][(api, c)][i] for r in runs]
    m = med(v)
    if spread(v) >= 0.05:
        two_level.append((api, c, label, min(v), max(v)))
        return m, f'{m:.0f}‡'
    return m, (f'{m:.0f}' if float(m).is_integer() else f'{m:.1f}')

# The checks.
print(f'Checks over {len(runs)} runs (median; gates of Docs/27):\n')
icu_c = {c: med([r[0][c][0] for r in runs]) for c in CORP}
icu_s = {c: med([r[0][c][2] for r in runs]) for c in CORP}
mac = {c: med([r[1][('localizedCompare', c)][0] for r in runs]) for c in CORP}
dev = lambda a, g: max(abs(a[c] / g[c] - 1) * 100 for c in CORP)
print(f"- ICU C compare {'/'.join(f'{icu_c[c]:.1f}' for c in CORP)} (gates {'/'.join(f'{GATE_ICU_CMP[c]:.1f}' for c in CORP)}): within {dev(icu_c, GATE_ICU_CMP):.1f}%")
print(f"- ICU C sortKey {'/'.join(f'{icu_s[c]:.1f}' for c in CORP)} (gates {'/'.join(f'{GATE_ICU_SK[c]:.1f}' for c in CORP)}): within {dev(icu_s, GATE_ICU_SK):.1f}%")
print(f"- macOS localizedCompare {'/'.join(f'{mac[c]:.0f}' for c in CORP)} (reference {'/'.join(str(GATE_MACOS[c]) for c in CORP)}): within {dev(mac, GATE_MACOS):.1f}%")
print('  (a run set counts if ICU C is within 2% and macOS within 2.5%)\n')

floor_w, floor_n = (1e9, ''), (1e9, '')
for api, title in TITLES:
    print(f'### {title}\n')
    print('| Corpus | Swift, WMO | Speedup | Swift, `-no-WMO` | Speedup | System ICU |')
    print('|--------|-----------:|---------|-----------------:|---------|-----------:|')
    for c in CORP:
        s, ss = t2cell(api, c, 0, 'System ICU')
        n, ns = t2cell(api, c, 1, '`-no-WMO`')
        w, ws = t2cell(api, c, 2, 'WMO')
        print(f'| {NAME[c]:6s} | {ws} | **{s / w:.2f}× faster** | {ns} | {s / n:.2f}× faster | {ss} |')
        if s / w < floor_w[0]: floor_w = (s / w, f'{api} {c}')
        if s / n < floor_n[0]: floor_n = (s / n, f'{api} {c}')
    print()
print(f'‡ Two-level cells (the runs differ by 5% or more; the median is recorded), with the range over the {len(runs)} runs:')
for api, c, label, lo, hi in two_level:
    print(f'- {api}, {NAME[c]}, {label}: {lo:.0f}–{hi:.0f}')
print()
print(f'Floor (lowest speedup): WMO {floor_w[0]:.2f}× ({floor_w[1]}); `-no-WMO` {floor_n[0]:.2f}× ({floor_n[1]}).\n')

print('### Direct RootCollator (EngineBench, full WMO) — Table 1\n')
print('| Corpus | compare | ICU | speedup | sortKey (inout) | ICU | speedup | sortKey (alloc) | speedup |')
print('|--------|--------:|----:|---------|----------------:|----:|---------|----------------:|---------|')
t1_two = []
for c in CORP:
    cols = [med([r[0][c][i] for r in runs]) for i in range(5)]
    for i, label in ((1, 'compare'), (3, 'sortKey'), (4, 'sortKey (alloc)')):
        v = [r[0][c][i] for r in runs]
        if spread(v) >= 0.05: t1_two.append((c, label, min(v), max(v)))
    ic, oc, isk, osk, osr = cols
    def sp(i, o):
        r = i / o
        return f'**{r:.2f}× faster**' if r > 1.004 else (f'{r:.2f}× (slower)' if r < 0.996 else f'**{r:.2f}× (equal)**')
    mark = lambda label: '‡' if any(t[0] == c and t[1] == label for t in t1_two) else ''
    print(f"| {NAME[c]:6s} | {oc:.1f}{mark('compare')} | {ic:.1f} | {sp(ic, oc)} | {osk:.1f}{mark('sortKey')} | {isk:.1f} | {sp(isk, osk)} | {osr:.1f}{mark('sortKey (alloc)')} | {sp(isk, osr)} |")
print()
if t1_two:
    print('‡ Two-level cells in Table 1, with the range: ' + '; '.join(f'{NAME[c]} {label} {lo:.1f}–{hi:.1f}' for c, label, lo, hi in t1_two))
    print()
