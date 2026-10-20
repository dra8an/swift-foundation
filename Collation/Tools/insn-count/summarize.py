#!/usr/bin/env python3
# Summarize a count_insns .jsonl file: mean instructions per call by function ("fn") or by function + source line ("line").
# Usage: summarize.py <file.jsonl> [fn|line] [top N] [skip first K calls (e.g. 2 for sortKey: the bench's first keys grow the array)]
import json, sys, collections
f = sys.argv[1]; mode = sys.argv[2] if len(sys.argv) > 2 else 'fn'
top = int(sys.argv[3]) if len(sys.argv) > 3 else 30; skip = int(sys.argv[4]) if len(sys.argv) > 4 else 0
rows = [json.loads(l) for l in open(f)][skip:]
c = collections.Counter()
for r in rows:
    for k, v in r['by_key'].items():
        mod, fn, where = k.split('|', 2)
        c[fn.split('(')[0][-60:] if mode == 'fn' else (fn.split('(')[0][-40:], where)] += v
print(f"{len(rows)} calls, mean {sum(r['total'] for r in rows)/len(rows):.1f} instructions")
for k, v in c.most_common(top): print(f"{v/len(rows):8.1f}  {k}")
