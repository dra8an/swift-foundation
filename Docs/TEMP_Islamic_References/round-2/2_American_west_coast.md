# Western coast of the American mainland (round 2, item 2)

**Source (provenance: official data set, public domain):** Natural Earth, 1:10m physical vector "land" (`ne_10m_land.geojson`),
**version 5.1.2** (release tag `v5.1.2`, 2022-05-13), from the official repository <https://github.com/nvkelso/natural-earth-vector>
(file SHA-256 prefix `1ac90796408bc6ad`).

**License:** public domain. Quote from the repository's LICENSE.md: "All versions of Natural Earth raster + vector map data found on
this website are in the public domain. You may use the maps in any manner, including modifying the content and design, electronic
dissemination, and offset printing." Terms: <http://www.naturalearthdata.com/about/terms-of-use/>. Copying into an open-source
repository is permitted.

## Method

1. Take the outer boundary of every land polygon (lake holes ignored).
2. The American mainland is the polygon that contains a point in Kansas (38 N, 98 W); it is the same single polygon that contains a
   point in Brazil (10 S, 55 W): Panama joins the two continents. It has 66,476 vertices. Every island (Vancouver Island, the
   Aleutians, Chiloé, Tierra del Fuego, ...) is a separate polygon and therefore excluded.
3. For each whole degree of latitude, intersect that polygon's boundary with the latitude line and keep the westernmost crossing.

Accuracy: the 1:10m scale is good to roughly 1 km. Longitudes are given to 4 decimals for reproducibility, not because the data is
that precise. **Place names: not provided** — Natural Earth's land layer carries no names, and attaching names from another source
would be guessing which feature lies at each crossing.

Exact intersections at whole degrees can miss narrow capes between them: Cape Prince of Wales (65.6 N, 168.1 W, the westernmost
point of the North American mainland) falls between the 65 N and 66 N rows. Interpolating between rows is a fair approximation for
a visibility search; a finer table can be generated with the same script.

## Table

Longitudes in degrees east (negative = west). At 54 S and 55 S there is no mainland: South America ends at Cape Froward (53.9 S);
everything further south is Tierra del Fuego and other islands.

| Latitude | Westernmost mainland longitude |
|---|---|
| 70 | -162.4911 |
| 69 | -163.9807 |
| 68 | -165.2405 |
| 67 | -162.4640 |
| 66 | -166.8825 |
| 65 | -166.6980 |
| 64 | -160.8873 |
| 63 | -164.7411 |
| 62 | -165.7564 |
| 61 | -165.1485 |
| 60 | -164.1218 |
| 59 | -161.8289 |
| 58 | -157.6250 |
| 57 | -158.6897 |
| 56 | -161.2394 |
| 55 | -163.2867 |
| 54 | -130.0843 |
| 53 | -128.5139 |
| 52 | -127.6578 |
| 51 | -127.5235 |
| 50 | -124.7852 |
| 49 | -123.0924 |
| 48 | -124.6748 |
| 47 | -124.1722 |
| 46 | -123.9267 |
| 45 | -124.0110 |
| 44 | -124.1225 |
| 43 | -124.4601 |
| 42 | -124.2147 |
| 41 | -124.1147 |
| 40 | -124.0208 |
| 39 | -123.6995 |
| 38 | -123.0221 |
| 37 | -122.1837 |
| 36 | -121.5041 |
| 35 | -120.6427 |
| 34 | -118.8076 |
| 33 | -117.2770 |
| 32 | -116.8540 |
| 31 | -116.3364 |
| 30 | -115.8017 |
| 29 | -114.6037 |
| 28 | -114.2070 |
| 27 | -114.0299 |
| 26 | -112.2036 |
| 25 | -112.1365 |
| 24 | -110.9173 |
| 23 | -110.0857 |
| 22 | -105.6500 |
| 21 | -105.3270 |
| 20 | -105.5025 |
| 19 | -104.2659 |
| 18 | -102.4263 |
| 17 | -100.2591 |
| 16 | -97.8074 |
| 15 | -92.7007 |
| 14 | -91.4192 |
| 13 | -87.6464 |
| 12 | -86.6703 |
| 11 | -85.7135 |
| 10 | -85.7128 |
| 9 | -83.6163 |
| 8 | -81.6655 |
| 7 | -77.6601 |
| 6 | -77.3671 |
| 5 | -77.3667 |
| 4 | -77.4192 |
| 3 | -77.7067 |
| 2 | -78.6670 |
| 1 | -79.6608 |
| 0 | -80.1137 |
| -1 | -80.8651 |
| -2 | -80.7549 |
| -3 | -79.8780 |
| -4 | -81.0114 |
| -5 | -81.0734 |
| -6 | -81.1429 |
| -7 | -79.8154 |
| -8 | -79.2179 |
| -9 | -78.6498 |
| -10 | -78.1975 |
| -11 | -77.6507 |
| -12 | -77.1409 |
| -13 | -76.4990 |
| -14 | -76.2818 |
| -15 | -75.4543 |
| -16 | -74.0328 |
| -17 | -72.1229 |
| -18 | -70.8936 |
| -19 | -70.3128 |
| -20 | -70.1233 |
| -21 | -70.1688 |
| -22 | -70.1918 |
| -23 | -70.3365 |
| -24 | -70.5247 |
| -25 | -70.4688 |
| -26 | -70.6322 |
| -27 | -70.7919 |
| -28 | -71.1429 |
| -29 | -71.4984 |
| -30 | -71.4066 |
| -31 | -71.6529 |
| -32 | -71.5118 |
| -33 | -71.5678 |
| -34 | -71.9052 |
| -35 | -72.2003 |
| -36 | -72.7948 |
| -37 | -73.1794 |
| -38 | -73.4756 |
| -39 | -73.3198 |
| -40 | -73.7002 |
| -41 | -73.9398 |
| -42 | -72.7688 |
| -43 | -72.7570 |
| -44 | -73.1387 |
| -45 | -73.4027 |
| -46 | -74.7295 |
| -47 | -73.9787 |
| -48 | -74.6136 |
| -49 | -74.4128 |
| -50 | -74.3578 |
| -51 | -74.2390 |
| -52 | -73.5791 |
| -53 | -73.4497 |
| -54 | no mainland |
| -55 | no mainland |

## Effect on the Diyanet rule (measured)

Measured in icu4swift (branch `islamic-crescent`) against Diyanet's 214 published month starts AH 1440-1457, best reading (±60°
latitude limit, topocentric altitude, America + Wellington exception): a crude latitude/longitude-box mask gave 210/214; this
coastline gives **212/214 (99.1%)**. A point counts as mainland America if it lies east of the coastline at its latitude. The two
remaining months (evenings 2021-06-10 and 2023-05-19) are not caused by the mask.

## Reproduce

`west_coast.py` (below) reads `ne_10m_land.geojson` and writes the table as CSV.

```python
import json, sys, csv
d = json.load(open(sys.argv[1]))
polys = []  # outer rings only
for f in d['features']:
    g = f['geometry']
    parts = [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']
    for p in parts: polys.append(p[0])
def inside(ring, x, y):
    c = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1): c = not c
    return c
refs = {'North America (Kansas 38N 98W)': (-98, 38), 'South America (Brazil 10S 55W)': (-55, -10)}
mainland = {}
for name, (x, y) in refs.items():
    hits = [i for i, r in enumerate(polys) if inside(r, x, y)]
    assert len(hits) == 1, (name, hits)
    mainland[name] = hits[0]
idx = sorted(set(mainland.values()))
print('mainland polygon indices', mainland, 'vertices', [len(polys[i]) for i in idx], file=sys.stderr)
rows = []
for lat in range(70, -56, -1):
    xs = []
    for i in idx:
        r = polys[i]
        for (x1, y1), (x2, y2) in zip(r, r[1:] + r[:1]):
            if (y1 > lat) != (y2 > lat):
                xs.append(x1 + (lat - y1) * (x2 - x1) / (y2 - y1))
            elif y1 == lat:
                xs.append(x1)
    rows.append((lat, min(xs) if xs else None))
w = csv.writer(open(sys.argv[2], 'w', newline=''), lineterminator='\n')
w.writerow(['latitude', 'westernmost_mainland_longitude'])
for lat, lon in rows: w.writerow([lat, '' if lon is None else f'{lon:.4f}'])
for lat, lon in rows: print(lat, 'no mainland' if lon is None else f'{lon:.3f}')
```
