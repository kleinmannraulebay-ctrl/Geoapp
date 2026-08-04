/// Räumliche Indizes für schnelle Punkt-Zuordnung (<10 ms pro Punkt).
///
/// [PolygonIndex]: gleichmäßiges Grad-Gitter über Polygon-Bounding-Boxen als
/// Vorfilter vor dem Ray-Casting.
/// [CityIndex]: Gitter-Bucket-Index für Radius-Suchen um Städte.
library;

import 'exploration_grid.dart';
import 'geo_models.dart';

class _Entry {
  final int featureIdx;
  final int polygonIdx;
  const _Entry(this.featureIdx, this.polygonIdx);
}

/// Gitter-Index über die Polygone einer Feature-Liste.
class PolygonIndex {
  final List<GeoFeature> features;
  final double cellDeg;
  final Map<int, List<_Entry>> _buckets = {};

  PolygonIndex(this.features, {this.cellDeg = 2.0}) {
    for (var f = 0; f < features.length; f++) {
      final polys = features[f].polygons;
      for (var p = 0; p < polys.length; p++) {
        final poly = polys[p];
        final x0 = _bx(poly.minLon), x1 = _bx(poly.maxLon);
        final y0 = _by(poly.minLat), y1 = _by(poly.maxLat);
        for (var x = x0; x <= x1; x++) {
          for (var y = y0; y <= y1; y++) {
            _buckets.putIfAbsent(_key(x, y), () => []).add(_Entry(f, p));
          }
        }
      }
    }
  }

  int _bx(double lon) => ((lon + 180.0) / cellDeg).floor();
  int _by(double lat) => ((lat + 90.0) / cellDeg).floor();
  int _key(int x, int y) => x * 100000 + y;

  /// Erstes Feature, das den Punkt enthält (oder null).
  GeoFeature? locate(double lon, double lat) {
    final bucket = _buckets[_key(_bx(lon), _by(lat))];
    if (bucket == null) return null;
    for (final e in bucket) {
      if (features[e.featureIdx].polygons[e.polygonIdx].contains(lon, lat)) {
        return features[e.featureIdx];
      }
    }
    return null;
  }

  /// Alle Features, deren BBox den Ausschnitt schneidet (fürs Rendering).
  List<GeoFeature> inBounds(
      double minLon, double minLat, double maxLon, double maxLat) {
    final seen = <int>{};
    final result = <GeoFeature>[];
    final x0 = _bx(minLon), x1 = _bx(maxLon);
    final y0 = _by(minLat), y1 = _by(maxLat);
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        final bucket = _buckets[_key(x, y)];
        if (bucket == null) continue;
        for (final e in bucket) {
          if (seen.add(e.featureIdx)) result.add(features[e.featureIdx]);
        }
      }
    }
    return result;
  }
}

/// Bucket-Index für Städte (1°-Gitter), Radius-Suche per Haversine.
class CityIndex {
  final List<City> cities;
  final Map<int, List<int>> _buckets = {};

  CityIndex(this.cities) {
    for (var i = 0; i < cities.length; i++) {
      _buckets
          .putIfAbsent(_key(cities[i].lon.floor(), cities[i].lat.floor()),
              () => [])
          .add(i);
    }
  }

  int _key(int x, int y) => (x + 180) * 1000 + (y + 90);

  /// Alle Städte im Umkreis von [radiusKm] um den Punkt.
  List<City> nearby(double lat, double lon, double radiusKm) {
    // 1° Länge ≥ ~78 km unterhalb von 45°; großzügig 1 Bucket + Randpuffer.
    final span = (radiusKm / 78.0).ceil() + 1;
    final result = <City>[];
    final cx = lon.floor(), cy = lat.floor();
    for (var x = cx - span; x <= cx + span; x++) {
      for (var y = cy - span; y <= cy + span; y++) {
        final bucket = _buckets[_key(((x + 180) % 360) - 180, y)];
        if (bucket == null) continue;
        for (final i in bucket) {
          final c = cities[i];
          if (ExplorationGrid.distanceKm(lat, lon, c.lat, c.lon) <= radiusKm) {
            result.add(c);
          }
        }
      }
    }
    return result;
  }
}
