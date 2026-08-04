#!/usr/bin/env python3
"""Bereitet die Offline-Geodaten für die App auf.

Eingaben (Rohdaten, siehe README):
  ne_50m_admin_0_countries.geojson   – Natural Earth Länder (50m)
  ne_10m_admin_1_states_provinces.geojson – Natural Earth Regionen (10m)
  Städte über das Python-Paket `geonamescache` (GeoNames, CC-BY)

Ausgaben (nach assets/geo/):
  countries.geojson.gz – vereinfachte Länderpolygone inkl. Fläche/BBox
  regions.geojson.gz   – vereinfachte Regionspolygone inkl. Fläche/BBox
  cities.json.gz       – Top-Städte pro Land (Name, Koordinaten, Einwohner)

Aufruf:  python3 tool/prepare_assets.py <rohdaten-verzeichnis> <assets/geo-verzeichnis>
"""
import gzip
import json
import math
import os
import sys

EARTH_RADIUS_KM = 6371.0088
COORD_DECIMALS = 3          # ~110 m Genauigkeit, reicht fürs Rendering/PIP
REGION_SIMPLIFY_TOL = 0.02  # Grad, Douglas-Peucker für admin_1 (10m -> grob)
COUNTRY_SIMPLIFY_TOL = 0.01
MIN_RING_AREA_KM2 = 3.0     # Winz-Inseln verwerfen
CITIES_PER_COUNTRY = 40     # App zeigt standardmäßig 25, konfigurierbar


# ---------------------------------------------------------------- Geometrie

def perp_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def douglas_peucker(points, tol):
    """Iterative Douglas-Peucker-Vereinfachung (Stack statt Rekursion)."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i0, i1 = stack.pop()
        if i1 <= i0 + 1:
            continue
        dmax, imax = 0.0, -1
        a, b = points[i0], points[i1]
        for i in range(i0 + 1, i1):
            d = perp_dist(points[i], a, b)
            if d > dmax:
                dmax, imax = d, i
        if dmax > tol:
            keep[imax] = True
            stack.append((i0, imax))
            stack.append((imax, i1))
    return [p for p, k in zip(points, keep) if k]


def ring_area_km2(ring):
    """Sphärische Fläche eines Rings (Positionswinkel-Formel), in km²."""
    if len(ring) < 4:
        return 0.0
    total = 0.0
    n = len(ring) - 1  # letzter Punkt == erster Punkt
    for i in range(n):
        lon1, lat1 = ring[i]
        lon2, lat2 = ring[(i + 1) % n]
        total += math.radians(lon2 - lon1) * (
            2 + math.sin(math.radians(lat1)) + math.sin(math.radians(lat2)))
    return abs(total) * EARTH_RADIUS_KM * EARTH_RADIUS_KM / 2.0


def clean_ring(ring, tol):
    ring = [(round(x, COORD_DECIMALS), round(y, COORD_DECIMALS)) for x, y in ring]
    # aufeinanderfolgende Duplikate entfernen
    out = [ring[0]]
    for p in ring[1:]:
        if p != out[-1]:
            out.append(p)
    if len(out) < 4:
        return None
    if tol > 0:
        closed = out[0] == out[-1]
        body = douglas_peucker(out[:-1] if closed else out, tol)
        if len(body) < 3:
            return None
        out = body + [body[0]]
    if out[0] != out[-1]:
        out.append(out[0])
    if len(out) < 4:
        return None
    return out


def simplify_geometry(geom, tol):
    """Vereinfacht (Multi)Polygon, liefert (neue Koordinaten, Fläche km², bbox)."""
    if geom['type'] == 'Polygon':
        polys = [geom['coordinates']]
    elif geom['type'] == 'MultiPolygon':
        polys = geom['coordinates']
    else:
        return None, 0.0, None
    new_polys = []
    area = 0.0
    minx = miny = 1e9
    maxx = maxy = -1e9
    for poly in polys:
        outer = clean_ring(poly[0], tol)
        if outer is None:
            continue
        a = ring_area_km2(outer)
        if a < MIN_RING_AREA_KM2:
            continue
        rings = [outer]
        for hole in poly[1:]:
            h = clean_ring(hole, tol)
            if h is None:
                continue
            ha = ring_area_km2(h)
            if ha < MIN_RING_AREA_KM2:
                continue
            rings.append(h)
            a -= ha
        area += max(a, 0.0)
        new_polys.append(rings)
        for x, y in outer:
            minx, maxx = min(minx, x), max(maxx, x)
            miny, maxy = min(miny, y), max(maxy, y)
    if not new_polys:
        return None, 0.0, None
    coords = new_polys[0] if len(new_polys) == 1 else new_polys
    gtype = 'Polygon' if len(new_polys) == 1 else 'MultiPolygon'
    return {'type': gtype, 'coordinates': coords}, area, [minx, miny, maxx, maxy]


def write_gz(path, obj):
    raw = json.dumps(obj, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    with gzip.open(path, 'wb', compresslevel=9) as f:
        f.write(raw)
    print('  %-24s %6.2f MB (unkomprimiert %.2f MB)' % (
        os.path.basename(path), os.path.getsize(path) / 1e6, len(raw) / 1e6))


# ---------------------------------------------------------------- Pipeline

def prepare_countries(src_dir, out_dir):
    d = json.load(open(os.path.join(src_dir, 'ne_50m_admin_0.geojson')))
    feats = []
    iso2_by_a3 = {}
    for f in d['features']:
        p = f['properties']
        a3 = p['ADM0_A3']
        iso2 = p.get('ISO_A2_EH') or p.get('ISO_A2') or '-99'
        geom, area, bbox = simplify_geometry(f['geometry'], COUNTRY_SIMPLIFY_TOL)
        if geom is None:
            continue
        iso2_by_a3[a3] = iso2
        feats.append({
            'type': 'Feature',
            'properties': {
                'id': a3,
                'iso2': iso2,
                'name': p.get('NAME_DE') or p['ADMIN'],
                'nameEn': p['ADMIN'],
                'continent': p.get('CONTINENT') or 'Unbekannt',
                'areaKm2': round(area, 1),
                'bbox': bbox,
            },
            'geometry': geom,
        })
    feats.sort(key=lambda f: f['properties']['name'])
    write_gz(os.path.join(out_dir, 'countries.geojson.gz'),
             {'type': 'FeatureCollection', 'features': feats})
    print('  Länder: %d' % len(feats))
    return iso2_by_a3


def prepare_regions(src_dir, out_dir):
    d = json.load(open(os.path.join(src_dir, 'ne_10m_admin_1.geojson')))
    feats = []
    for f in d['features']:
        p = f['properties']
        geom, area, bbox = simplify_geometry(f['geometry'], REGION_SIMPLIFY_TOL)
        if geom is None:
            continue
        feats.append({
            'type': 'Feature',
            'properties': {
                'id': p['adm1_code'],
                'country': p['adm0_a3'],
                'name': p.get('name_de') or p.get('name') or p['adm1_code'],
                'areaKm2': round(area, 1),
                'bbox': bbox,
            },
            'geometry': geom,
        })
    write_gz(os.path.join(out_dir, 'regions.geojson.gz'),
             {'type': 'FeatureCollection', 'features': feats})
    print('  Regionen: %d' % len(feats))


def prepare_cities(out_dir, iso2_by_a3):
    import geonamescache
    gc = geonamescache.GeonamesCache()
    a3_by_iso2 = {v: k for k, v in iso2_by_a3.items()}
    by_country = {}
    for c in gc.get_cities().values():
        a3 = a3_by_iso2.get(c['countrycode'])
        if a3 is None:
            continue
        by_country.setdefault(a3, []).append(c)
    rows = []
    for a3, cities in by_country.items():
        cities.sort(key=lambda c: -c['population'])
        for c in cities[:CITIES_PER_COUNTRY]:
            rows.append([
                c['geonameid'],
                c['name'],
                a3,
                round(c['latitude'], 4),
                round(c['longitude'], 4),
                c['population'],
            ])
    rows.sort(key=lambda r: (r[2], -r[5]))
    write_gz(os.path.join(out_dir, 'cities.json.gz'),
             {'fields': ['id', 'name', 'country', 'lat', 'lon', 'pop'], 'rows': rows})
    print('  Städte: %d in %d Ländern' % (len(rows), len(by_country)))


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    out_dir = sys.argv[2] if len(sys.argv) > 2 else 'assets/geo'
    os.makedirs(out_dir, exist_ok=True)
    print('Länder …')
    iso2 = prepare_countries(src_dir, out_dir)
    print('Regionen …')
    prepare_regions(src_dir, out_dir)
    print('Städte …')
    prepare_cities(out_dir, iso2)
    print('Fertig.')


if __name__ == '__main__':
    main()
