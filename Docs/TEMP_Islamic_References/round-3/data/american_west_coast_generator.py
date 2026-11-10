# Westernmost point of the American mainland polygon at every 0.05 degree of latitude.
import json, sys
d = json.load(open(sys.argv[1]))
polys = []
for f in d['features']:
    g = f['geometry']
    for p in ([g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']): polys.append(p[0])
def inside(r, x, y):
    c = False
    for (x1, y1), (x2, y2) in zip(r, r[1:] + r[:1]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1): c = not c
    return c
ring = [r for r in polys if inside(r, -98, 38)][0]
segs = list(zip(ring, ring[1:] + ring[:1]))
for k in range(int(71.95 * 20), int(-53.85 * 20) - 1, -1):
    lat = k / 20
    xs = [x1 + (lat - y1) * (x2 - x1) / (y2 - y1) for (x1, y1), (x2, y2) in segs if (y1 > lat) != (y2 > lat)]
    if xs: print(f'{lat:.2f},{min(xs):.4f}')
