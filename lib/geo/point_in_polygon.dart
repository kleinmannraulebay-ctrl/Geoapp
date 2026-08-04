import 'dart:typed_data';

import 'geo_models.dart';

/// Ray-Casting-Test: liegt (lon, lat) innerhalb des Rings?
///
/// [xy] ist eine flache Liste `[lon0, lat0, lon1, lat1, …]`.
bool pointInRing(Float64List xy, double lon, double lat) {
  final n = xy.length ~/ 2;
  if (n < 3) return false;
  var inside = false;
  var xj = xy[2 * (n - 1)];
  var yj = xy[2 * (n - 1) + 1];
  for (var i = 0; i < n; i++) {
    final xi = xy[2 * i];
    final yi = xy[2 * i + 1];
    if (((yi > lat) != (yj > lat)) &&
        (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
      inside = !inside;
    }
    xj = xi;
    yj = yi;
  }
  return inside;
}

/// Liegt der Punkt im Polygon-Teil (äußerer Ring, Löcher ausgenommen)?
bool pointInPart(PolyPart part, double lon, double lat) {
  if (lon < part.minX || lon > part.maxX || lat < part.minY || lat > part.maxY) {
    return false;
  }
  if (!pointInRing(part.outer, lon, lat)) return false;
  for (final hole in part.holes) {
    if (pointInRing(hole, lon, lat)) return false;
  }
  return true;
}

/// Liegt der Punkt im Feature (Bounding-Box-Vorfilter + Ray-Casting)?
bool pointInFeature(GeoFeature f, double lon, double lat) {
  if (lon < f.minX || lon > f.maxX || lat < f.minY || lat > f.maxY) {
    return false;
  }
  for (final part in f.parts) {
    if (pointInPart(part, lon, lat)) return true;
  }
  return false;
}
