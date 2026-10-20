# Interleaved BenchFoundation A/B over selected Table 2 rows (ascii, latin, cjk). Run from the repo root:
#   python3 Collation/Tools/ab/foundation_ab.py <base BenchFoundation> <variant BenchFoundation> [rounds=5]
# Note (2026-10-20): a FRESH release build with -no-whole-module-optimization fails in swift-syntax ("unable to open
# dependencies file"); build both sides with normal WMO into fresh scratch paths (allowed on machine 2, Docs/27).
import subprocess, sys, re, collections
base, var, rounds = sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 5
corpora = [("ascii", 300), ("latin", 300), ("cjk", 300)]
rows = ["localizedStdCmp", "compare(opts:loc:)", "sortStdComparator", "sortCmp(locale)", "sortKeyPathCmp", "sortSortDescriptor", "localizedCompare", "localizedCaseICmp"]
pat = re.compile(r"\s*([A-Za-z().:_ ]+?)\s*:\s*([0-9.]+)\s*ns/op")
res = collections.defaultdict(lambda: collections.defaultdict(list))
for r in range(rounds):
    for c, reps in corpora:
        order = [("base", base), ("var", var)] if r % 2 == 0 else [("var", var), ("base", base)]
        for side, b in order:
            out = subprocess.run([b, f"Collation/Tools/bench/bench-{c}.txt", str(reps)], capture_output=True, text=True).stdout
            for line in out.splitlines():
                m = pat.match(line)
                if m and m.group(1).strip() in rows: res[(c, m.group(1).strip())][side].append(float(m.group(2)))
for row in rows:
    for c, _ in corpora:
        d = res[(c, row)]
        if not d["base"]: continue
        b, v = d["base"], d["var"]; diffs = [y - x for x, y in zip(b, v)]
        md = sum(diffs) / len(diffs)
        signs = "".join("-" if x < 0 else "+" if x > 0 else "0" for x in diffs)
        print(f"{row:19s} {c:6s} base min {min(b):6.0f}  var min {min(v):6.0f}  ({100*(min(v)-min(b))/min(b):+5.1f}%)  mean diff {md:+7.1f} ({100*md/(sum(b)/len(b)):+5.1f}%)  {signs}")
