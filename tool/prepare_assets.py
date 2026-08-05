#!/usr/bin/env python3
"""Bereitet die Offline-Geodaten-Assets für die App auf.

Quellen (Natural Earth, Public Domain, gespiegelt auf GitHub):
  - ne_50m_admin_0_countries.geojson      -> assets/geo/countries.json.gz
  - ne_10m_admin_1_states_provinces.geojson -> assets/geo/regions.json.gz
  - ne_10m_populated_places_simple.geojson  -> assets/geo/cities.json.gz

Schritte: Download (falls nicht vorhanden), Attribut-Reduktion (deutsche Namen),
Douglas-Peucker-Vereinfachung, Koordinaten-Quantisierung, sphärische
Flächenberechnung pro Feature, gzip-Kompression.

Aufruf:  python3 tool/prepare_assets.py [--workdir /pfad/zu/downloads]
Benötigt nur die Python-Standardbibliothek.
"""
import argparse
import gzip
import json
import math
import os
import sys
import urllib.request

BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
SOURCES = {
    "admin0": "ne_50m_admin_0_countries.geojson",
    "admin1": "ne_10m_admin_1_states_provinces.geojson",
    "places": "ne_10m_populated_places_simple.geojson",
}

EARTH_R = 6371.0088  # km

CONTINENT_DE = {
    "Africa": "Afrika",
    "Antarctica": "Antarktis",
    "Asia": "Asien",
    "Europe": "Europa",
    "North America": "Nordamerika",
    "Oceania": "Ozeanien",
    "South America": "Südamerika",
    "Seven seas (open ocean)": "Ozeanien",
}


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print(f"  vorhanden: {dest}")
        return
    print(f"  lade {url}")
    urllib.request.urlretrieve(url, dest)


# ---------------------------------------------------------------- Geometrie

def dp_simplify(points, tol):
    """Douglas-Peucker auf einer Punktliste [(lon, lat), ...] (iterativ)."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        seg2 = dx * dx + dy * dy
        dmax, imax = -1.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            if seg2 == 0:
                d2 = (px - ax) ** 2 + (py - ay) ** 2
            else:
                t = ((px - ax) * dx + (py - ay) * dy) / seg2
                t = 0.0 if t < 0 else (1.0 if t > 1 else t)
                qx, qy = ax + t * dx, ay + t * dy
                d2 = (px - qx) ** 2 + (py - qy) ** 2
            if d2 > dmax:
                dmax, imax = d2, i
        if dmax > tol * tol:
            keep[imax] = True
            stack.append((a, imax))
            stack.append((imax, b))
    return [p for p, k in zip(points, keep) if k]


def ring_area_km2(ring):
    """Sphärische Flächenberechnung eines Rings (l'Huilier/Green), km²."""
    if len(ring) < 3:
        return 0.0
    total = 0.0
    for i in range(len(ring)):
        lon1, lat1 = ring[i]
        lon2, lat2 = ring[(i + 1) % len(ring)]
        total += math.radians(lon2 - lon1) * (
            2 + math.sin(math.radians(lat1)) + math.sin(math.radians(lat2))
        )
    return abs(total * EARTH_R * EARTH_R / 2.0)


def simplify_geometry(geom, tol, min_ring_area):
    """Vereinfacht Polygon/MultiPolygon, entfernt Mini-Ringe, rundet auf 3 Nachkommastellen."""
    def clean_ring(ring):
        pts = [(round(x, 3), round(y, 3)) for x, y in ring]
        # Duplikate nach Rundung entfernen
        out = [pts[0]]
        for p in pts[1:]:
            if p != out[-1]:
                out.append(p)
        if len(out) > 2 and out[0] == out[-1]:
            out = out[:-1]
        return out

    def process_poly(rings):
        result = []
        for j, ring in enumerate(rings):
            simplified = dp_simplify(ring, tol)
            if len(simplified) < 4:
                if j == 0:
                    return None  # Außenring kollabiert -> Polygon weg
                continue
            if ring_area_km2(simplified) < min_ring_area:
                if j == 0:
                    return None
                continue
            cleaned = clean_ring(simplified)
            if len(cleaned) < 3:
                if j == 0:
                    return None
                continue
            result.append(cleaned)
        return result or None

    if geom["type"] == "Polygon":
        polys = [geom["coordinates"]]
    elif geom["type"] == "MultiPolygon":
        polys = geom["coordinates"]
    else:
        return None
    out = []
    for rings in polys:
        p = process_poly(rings)
        if p:
            out.append(p)
    if not out:
        return None
    if len(out) == 1:
        return {"type": "Polygon", "coordinates": out[0]}
    return {"type": "MultiPolygon", "coordinates": out}


def geometry_area_km2(geom):
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    total = 0.0
    for rings in polys:
        if not rings:
            continue
        total += ring_area_km2(rings[0])
        for hole in rings[1:]:
            total -= ring_area_km2(hole)
    return max(total, 0.0)


def write_gz(path, obj):
    raw = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with gzip.open(path, "wb", compresslevel=9) as f:
        f.write(raw)
    print(f"  {path}: {len(raw) / 1e6:.2f} MB roh, {os.path.getsize(path) / 1e6:.2f} MB gz")


# ---------------------------------------------------------------- Verarbeitung

def country_code(props):
    """Stabiler 3-Buchstaben-Code; ISO_A3 ist bei NE teils '-99' (z. B. Frankreich)."""
    iso = props.get("ISO_A3") or props.get("iso_a3") or "-99"
    if iso and iso != "-99":
        return iso
    return props.get("ADM0_A3") or props.get("adm0_a3")


def process_admin0(src, out):
    data = json.load(open(src, encoding="utf-8"))
    feats = []
    for f in data["features"]:
        p = f["properties"]
        if p.get("TYPE") in ("Dependency",) and p.get("POP_EST", 0) == 0:
            pass  # unbewohnte Abhängigkeiten trotzdem behalten (Karte soll lückenlos sein)
        code = country_code(p)
        geom = simplify_geometry(f["geometry"], tol=0.02, min_ring_area=25.0)
        if not geom:
            geom = simplify_geometry(f["geometry"], tol=0.005, min_ring_area=0.0)
        if not geom or not code:
            continue
        iso2 = p.get("ISO_A2") or ""
        if iso2 == "-99":
            # Natural-Earth-Luecken (z. B. Frankreich, Norwegen)
            iso2 = {"FRA": "FR", "NOR": "NO", "KOS": "XK"}.get(code, "")
        feats.append({
            "type": "Feature",
            "properties": {
                "code": code,
                "iso2": iso2,
                "name": p.get("NAME_DE") or p.get("NAME") or p.get("ADMIN"),
                "continent": CONTINENT_DE.get(p.get("CONTINENT"), p.get("CONTINENT")),
                "area": round(geometry_area_km2(f["geometry"]), 1),
            },
            "geometry": geom,
        })
    print(f"  admin0: {len(feats)} Länder")
    write_gz(out, {"type": "FeatureCollection", "features": feats})
    return {f["properties"]["code"] for f in feats}


def process_admin1(src, out, valid_codes):
    data = json.load(open(src, encoding="utf-8"))
    feats = []
    for f in data["features"]:
        p = f["properties"]
        code = p.get("adm0_a3")
        if code not in valid_codes:
            continue
        geom = simplify_geometry(f["geometry"], tol=0.02, min_ring_area=15.0)
        if not geom:
            # Kleinstregionen (Inseln, Stadtstaaten) nicht verlieren: feiner simplifizieren
            geom = simplify_geometry(f["geometry"], tol=0.002, min_ring_area=0.0)
        if not geom:
            continue
        area = p.get("area_sqkm") or 0
        if not area:
            area = geometry_area_km2(f["geometry"])
        feats.append({
            "type": "Feature",
            "properties": {
                "id": p.get("adm1_code"),
                "code": code,
                "name": p.get("name_de") or p.get("name") or p.get("name_en") or "?",
                "area": round(area, 1),
            },
            "geometry": geom,
        })
    print(f"  admin1: {len(feats)} Regionen")
    write_gz(out, {"type": "FeatureCollection", "features": feats})


def process_places(src, out, valid_codes):
    data = json.load(open(src, encoding="utf-8"))
    cities = []
    for f in data["features"]:
        p = f["properties"]
        code = p.get("adm0_a3") or p.get("sov_a3")
        if code not in valid_codes:
            continue
        pop = int(p.get("pop_max") or 0)
        cities.append({
            "id": int(p["ne_id"]),
            "n": p.get("name") or p.get("nameascii"),
            "c": code,
            "r": p.get("adm1name") or "",
            "lat": round(float(p["latitude"]), 4),
            "lon": round(float(p["longitude"]), 4),
            "pop": pop,
            "cap": 1 if p.get("adm0cap") == 1.0 or p.get("adm0cap") == 1 else 0,
        })
    cities.sort(key=lambda c: (-c["pop"], c["n"]))
    print(f"  places: {len(cities)} Städte")
    write_gz(out, cities)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workdir", default="build_assets")
    args = ap.parse_args()
    os.makedirs(args.workdir, exist_ok=True)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outdir = os.path.join(root, "assets", "geo")
    os.makedirs(outdir, exist_ok=True)

    print("1/4 Download")
    paths = {}
    for key, name in SOURCES.items():
        dest = os.path.join(args.workdir, name)
        download(BASE + name, dest)
        paths[key] = dest

    print("2/4 Länder")
    codes = process_admin0(paths["admin0"], os.path.join(outdir, "countries.json.gz"))
    print("3/4 Regionen")
    process_admin1(paths["admin1"], os.path.join(outdir, "regions.json.gz"), codes)
    print("4/4 Städte")
    process_places(paths["places"], os.path.join(outdir, "cities.json.gz"), codes)
    print("fertig.")


if __name__ == "__main__":
    sys.exit(main())
