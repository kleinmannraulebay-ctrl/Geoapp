import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../geo/geo_models.dart';

/// Farbskala der Besuchsintensität: Stufe 0 (nie besucht) bis 5.
class ChoroplethPalette {
  static const Color ocean = Color(0xFF0D1B2A);
  static const Color oceanLight = Color(0xFFB8D0E0);
  static const Color border = Color(0x66FFFFFF);

  static const List<Color> _levels = [
    Color(0xFF37393F), // 0 – nie besucht (neutralgrau)
    Color(0xFF1D4E4A), // 1
    Color(0xFF1F6E5F), // 2
    Color(0xFF2E9270), // 3
    Color(0xFF52B87D), // 4
    Color(0xFF8FDE8C), // 5
  ];

  static Color forLevel(int level) =>
      _levels[level.clamp(0, _levels.length - 1)];

  /// Intensitätsstufe für Regionen anhand des erkundeten Flächenanteils.
  static int levelForAreaPct(double pct) {
    if (pct <= 0) return 1; // besucht, aber kaum erkundet
    if (pct >= 0.5) return 5;
    if (pct >= 0.2) return 4;
    if (pct >= 0.05) return 3;
    return 2;
  }
}

/// Konvertiert Feature-Geometrien einmalig in LatLng-Listen und cached sie
/// (die Konvertierung ist zu teuer, um sie pro Frame zu wiederholen).
class PolygonCache {
  static final Expando<List<(List<LatLng>, List<List<LatLng>>)>> _cache =
      Expando();

  static List<(List<LatLng>, List<List<LatLng>>)> partsOf(GeoFeature f) {
    var cached = _cache[f];
    if (cached != null) return cached;
    cached = [
      for (final part in f.parts)
        (
          _toLatLng(part.outer),
          [for (final h in part.holes) _toLatLng(h)],
        )
    ];
    _cache[f] = cached;
    return cached;
  }

  static List<LatLng> _toLatLng(Float64List xy) {
    final n = xy.length ~/ 2;
    return [
      for (var i = 0; i < n; i++) LatLng(xy[2 * i + 1], xy[2 * i]),
    ];
  }

  /// Baut die flutter_map-Polygone eines Features in einer Füllfarbe.
  static List<Polygon> polygonsOf(GeoFeature f, Color fill,
      {double borderWidth = 0.6}) {
    return [
      for (final (outer, holes) in partsOf(f))
        Polygon(
          points: outer,
          holePointsList: holes.isEmpty ? null : holes,
          color: fill,
          borderColor: ChoroplethPalette.border,
          borderStrokeWidth: borderWidth,
        )
    ];
  }
}
