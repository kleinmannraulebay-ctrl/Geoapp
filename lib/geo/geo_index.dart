import 'geo_models.dart';
import 'point_in_polygon.dart';

/// Räumlicher Index über Features: 2°-Gitter-Buckets über den Bounding-Boxen.
///
/// Die Zuordnung eines Punktes zu Land + Region bleibt damit deutlich unter
/// 10 ms: Bucket-Lookup → Kandidaten → BBox-Check → Ray-Casting.
class GeoIndex {
  static const double _bucketDeg = 2.0;
  static const int _lonBuckets = 180; // 360 / 2

  final List<GeoFeature> features;
  final Map<int, List<int>> _buckets = {};

  GeoIndex(this.features) {
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final x0 = _lonBucket(f.minX), x1 = _lonBucket(f.maxX);
      final y0 = _latBucket(f.minY), y1 = _latBucket(f.maxY);
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          _buckets.putIfAbsent(y * _lonBuckets + x, () => <int>[]).add(i);
        }
      }
    }
  }

  static int _lonBucket(double lon) =>
      (((lon + 180.0) / _bucketDeg).floor()).clamp(0, _lonBuckets - 1);

  static int _latBucket(double lat) =>
      (((lat + 90.0) / _bucketDeg).floor()).clamp(0, 89);

  /// Erstes Feature, das den Punkt enthält, sonst `null`.
  GeoFeature? lookup(double lat, double lon) {
    final key = _latBucket(lat) * _lonBuckets + _lonBucket(lon);
    final candidates = _buckets[key];
    if (candidates == null) return null;
    for (final i in candidates) {
      if (pointInFeature(features[i], lon, lat)) return features[i];
    }
    return null;
  }

  /// Lookup mit Küsten-Toleranz: trifft der Punkt selbst kein Polygon
  /// (z. B. Strand + vereinfachte Küstenlinie), werden Versatzpunkte im
  /// Umkreis von ~3 km geprüft.
  GeoFeature? lookupWithFallback(double lat, double lon) {
    final direct = lookup(lat, lon);
    if (direct != null) return direct;
    const d = 0.03;
    for (final (dy, dx) in [
      (d, 0.0), (-d, 0.0), (0.0, d), (0.0, -d),
      (d, d), (d, -d), (-d, d), (-d, -d),
    ]) {
      final hit = lookup(lat + dy, lon + dx);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Alle Features, deren BBox das Rechteck schneidet (für die Karten-Ansicht).
  List<GeoFeature> inBounds(double south, double west, double north, double east) {
    final out = <GeoFeature>[];
    for (final f in features) {
      if (f.maxY < south || f.minY > north || f.maxX < west || f.minX > east) {
        continue;
      }
      out.add(f);
    }
    return out;
  }
}
