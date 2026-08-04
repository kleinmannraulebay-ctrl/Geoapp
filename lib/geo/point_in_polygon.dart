/// Ray-Casting (Even-Odd-Regel) auf gepackten Koordinaten-Ringen.
///
/// Ringe sind als `Float64List` gepackt: `[lon0, lat0, lon1, lat1, ...]`,
/// nicht geschlossen (letzter Punkt ≠ erster Punkt).
/// Die Even-Odd-Regel über alle Ringe eines Polygons behandelt Löcher
/// automatisch korrekt.
library;

import 'dart:typed_data';

/// Ein Polygon (Außenring + Löcher) mit vorberechneter Bounding-Box.
class PackedPolygon {
  final double minLon, minLat, maxLon, maxLat;
  final List<Float64List> rings;

  PackedPolygon(this.rings)
      : minLon = _min(rings, 0),
        minLat = _min(rings, 1),
        maxLon = _max(rings, 0),
        maxLat = _max(rings, 1);

  static double _min(List<Float64List> rings, int off) {
    var v = double.infinity;
    final r = rings.first;
    for (var i = off; i < r.length; i += 2) {
      if (r[i] < v) v = r[i];
    }
    return v;
  }

  static double _max(List<Float64List> rings, int off) {
    var v = double.negativeInfinity;
    final r = rings.first;
    for (var i = off; i < r.length; i += 2) {
      if (r[i] > v) v = r[i];
    }
    return v;
  }

  bool bboxContains(double lon, double lat) =>
      lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat;

  /// Punkt-in-Polygon inkl. Löcher (Even-Odd über alle Ringe).
  bool contains(double lon, double lat) {
    if (!bboxContains(lon, lat)) return false;
    var inside = false;
    for (final ring in rings) {
      if (rayCastRing(ring, lon, lat)) inside = !inside;
    }
    return inside;
  }
}

/// Klassisches Ray-Casting gegen einen einzelnen Ring.
/// Gibt zurück, ob der Strahl den Ring eine ungerade Anzahl mal kreuzt.
bool rayCastRing(Float64List ring, double lon, double lat) {
  var inside = false;
  final n = ring.length ~/ 2;
  var j = n - 1;
  for (var i = 0; i < n; i++) {
    final xi = ring[i * 2], yi = ring[i * 2 + 1];
    final xj = ring[j * 2], yj = ring[j * 2 + 1];
    // Kante (j -> i): kreuzt sie den horizontalen Strahl nach rechts?
    if ((yi > lat) != (yj > lat)) {
      final xCross = (xj - xi) * (lat - yi) / (yj - yi) + xi;
      if (lon < xCross) inside = !inside;
    }
    j = i;
  }
  return inside;
}
