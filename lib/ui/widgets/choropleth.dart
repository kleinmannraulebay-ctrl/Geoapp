/// Hilfsfunktionen: GeoFeatures → flutter_map-Polygone mit Besuchs-Färbung.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../geo/geo_models.dart';

/// Farbskala: Stufe 0 (nie besucht) bis 5 (intensiv bereist).
const stageColors = [
  Color(0x66455A64), // 0 – neutral/grau
  Color(0x8000695C), // 1
  Color(0x9900897B), // 2
  Color(0xB326A69A), // 3
  Color(0xCC4DB6AC), // 4
  Color(0xE080CBC4), // 5
];

const borderColor = Color(0xFF10181F);

/// Cache: Feature-ID → Ringe als LatLng-Listen (einmalig konvertiert).
final Map<String, List<List<List<LatLng>>>> _ringCache = {};

List<List<List<LatLng>>> _ringsOf(GeoFeature f) =>
    _ringCache.putIfAbsent(f.id, () {
      final polys = <List<List<LatLng>>>[];
      for (final p in f.polygons) {
        final rings = <List<LatLng>>[];
        for (final ring in p.rings) {
          final pts = <LatLng>[];
          for (var i = 0; i < ring.length; i += 2) {
            pts.add(LatLng(ring[i + 1], ring[i]));
          }
          rings.add(pts);
        }
        if (rings.isNotEmpty) polys.add(rings);
      }
      return polys;
    });

/// Polygone eines Features in einer Farbe (inkl. Löcher).
List<Polygon> featurePolygons(
  GeoFeature f, {
  required Color fill,
  Color border = borderColor,
  double borderWidth = 0.6,
}) {
  final result = <Polygon>[];
  for (final rings in _ringsOf(f)) {
    result.add(Polygon(
      points: rings.first,
      holePointsList: rings.length > 1 ? rings.sublist(1) : null,
      color: fill,
      borderColor: border,
      borderStrokeWidth: borderWidth,
    ));
  }
  return result;
}

/// Choropleth-Layer für Länder anhand der Intensitäts-Stufe (0–5).
List<Polygon> countryChoropleth(
  List<GeoFeature> countries,
  int Function(String code) stageOf, {
  double borderWidth = 0.6,
}) {
  final polygons = <Polygon>[];
  for (final c in countries) {
    final stage = stageOf(c.id).clamp(0, 5);
    polygons.addAll(featurePolygons(c,
        fill: stageColors[stage], borderWidth: borderWidth));
  }
  return polygons;
}

/// Regions-Layer: besuchte Regionen gefärbt, unbesuchte nur mit Umriss.
List<Polygon> regionChoropleth(
  List<GeoFeature> regions,
  bool Function(String regionId) isVisited,
) {
  final polygons = <Polygon>[];
  for (final r in regions) {
    final visited = isVisited(r.id);
    polygons.addAll(featurePolygons(
      r,
      fill: visited ? const Color(0xB326A69A) : const Color(0x1A455A64),
      border: const Color(0x8010181F),
      borderWidth: 0.5,
    ));
  }
  return polygons;
}
