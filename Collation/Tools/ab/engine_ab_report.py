# Report for engine_ab.sh output: per metric and corpus, the minimum of each side, the mean of (variant − base) and the per-round signs.
import sys,re,collections
d=collections.defaultdict(lambda: collections.defaultdict(dict))
for l in open(sys.argv[1]):
    m=re.match(r'(\d+) (\w+) (\w+) RootCollator\.(\w+)\s*: ([\d.]+) ns/op',l)
    if m: r,c,s,metric,v=m.groups(); d[(c,metric)][int(r)][s]=float(v)
for metric in ['cmp','sk','skRet']:
    print(f"== {metric}")
    for c in ['ascii','latin','cjk','paths','thai']:
        rs=d[(c,metric)]
        if not rs: continue
        b=[rs[r]['base'] for r in rs]; v=[rs[r]['var'] for r in rs]
        diffs=[rs[r]['var']-rs[r]['base'] for r in sorted(rs)]
        md=sum(diffs)/len(diffs)
        print(f"{c:6s} base min {min(b):7.1f}  var min {min(v):7.1f}  min {100*(min(v)-min(b))/min(b):+5.1f}%  mean diff {md:+6.2f} ns ({100*md/(sum(b)/len(b)):+5.1f}%)  signs {''.join('-' if x<0 else '+' if x>0 else '0' for x in diffs)}")
