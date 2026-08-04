/// Datenmodelle für die offline gebündelten Geodaten.
library;

import 'dart:typed_data';

import 'point_in_polygon.dart';

/// Land (admin_0) oder Region (admin_1) mit gepackter Geometrie.
class GeoFeature {
  /// Stabile ID: Länder = ISO/ADM0-A3-Code (z. B. "DEU"),
  /// Regionen = Natural-Earth adm1_code (z. B. "DEU-1563").
  final String id;
  final String name;

  /// Bei Regionen: Code des Landes; bei Ländern identisch mit [id].
  final String countryCode;

  /// Nur bei Ländern gesetzt (deutsch, z. B. "Europa").
  final String continent;

  /// Gesamtfläche in km² (aus der unsimplifizierten Geometrie berechnet).
  final double areaKm2;

  final List<PackedPolygon> polygons;

  GeoFeature({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.continent,
    required this.areaKm2,
    required this.polygons,
  });

  bool contains(double lon, double lat) {
    for (final p in polygons) {
      if (p.contains(lon, lat)) return true;
    }
    return false;
  }

  /// Bounding-Box über alle Polygone: (minLon, minLat, maxLon, maxLat).
  (double, double, double, double) get bbox {
    var minLon = double.infinity, minLat = double.infinity;
    var maxLon = double.negativeInfinity, maxLat = double.negativeInfinity;
    for (final p in polygons) {
      if (p.minLon < minLon) minLon = p.minLon;
      if (p.minLat < minLat) minLat = p.minLat;
      if (p.maxLon > maxLon) maxLon = p.maxLon;
      if (p.maxLat > maxLat) maxLat = p.maxLat;
    }
    return (minLon, minLat, maxLon, maxLat);
  }
}

class City {
  final int id;
  final String name;
  final String countryCode;
  final String regionName;
  final double lat;
  final double lon;
  final int population;
  final bool isCapital;

  const City({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.regionName,
    required this.lat,
    required this.lon,
    required this.population,
    required this.isCapital,
  });
}

/// GeoJSON-Geometrie (Polygon/MultiPolygon) in gepackte Polygone umwandeln.
List<PackedPolygon> packGeometry(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String;
  final coords = geometry['coordinates'] as List;
  final polys = type == 'Polygon' ? [coords] : coords;
  final result = <PackedPolygon>[];
  for (final rings in polys) {
    final packed = <Float64List>[];
    for (final ring in rings as List) {
      final pts = ring as List;
      final f = Float64List(pts.length * 2);
      for (var i = 0; i < pts.length; i++) {
        final p = pts[i] as List;
        f[i * 2] = (p[0] as num).toDouble();
        f[i * 2 + 1] = (p[1] as num).toDouble();
      }
      packed.add(f);
    }
    if (packed.isNotEmpty) result.add(PackedPolygon(packed));
  }
  return result;
}
