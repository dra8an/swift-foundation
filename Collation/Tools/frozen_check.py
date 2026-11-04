#!/usr/bin/env python3
# The third matrix check (Docs/27): the FROZEN binary of 2026-10-30 (.build/l4/nowmo-base, -no-WMO at 22af5f68)
# next to bench_system, interleaved, min ns/op over R rounds. If the frozen binary reads its recorded values,
# the machine and the harness are fine and a change of the system side is macOS's own.
# Usage (repo root): python3 Collation/Tools/frozen_check.py Collation/Tools/bench_system [rounds=3]   (bench_system: run_benchmarks.sh builds it)
import subprocess, sys, re, collections
SYS = sys.argv[1]; R = int(sys.argv[2]) if len(sys.argv) > 2 else 3
FROZEN = ".build/l4/nowmo-base/BenchFoundation"
CORPORA = [("ascii", 300), ("latin", 300), ("cjk", 300), ("paths", 150), ("thai", 10)]
ROWS = ["localizedCompare", "compare(locale:)", "localizedStdCmp"]
pat = re.compile(r"\s*([A-Za-z().:_ ]+?)\s*:\s*([0-9.]+)\s*ns/op")
best = collections.defaultdict(lambda: float("inf"))
for r in range(R):
    for c, reps in CORPORA:
        order = [("frozen", FROZEN), ("sys", SYS)] if r % 2 == 0 else [("sys", SYS), ("frozen", FROZEN)]
        for side, b in order:
            out = subprocess.run([b, f"Collation/Tools/bench/bench-{c}.txt", str(reps)], capture_output=True, text=True).stdout
            for line in out.splitlines():
                m = pat.match(line)
                if m and m.group(1).strip() in ROWS:
                    k = (side, m.group(1).strip(), c)
                    best[k] = min(best[k], float(m.group(2)))
print(f"{'row':18s} {'side':7s} " + " ".join(f"{c:>6s}" for c, _ in CORPORA))
for row in ROWS:
    for side in ("frozen", "sys"):
        print(f"{row:18s} {side:7s} " + " ".join(f"{best[(side, row, c)]:6.0f}" for c, _ in CORPORA))
