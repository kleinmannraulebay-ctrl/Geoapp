/// Globales Erkundungsraster: 0,05°-Zellen (≈ 20–31 km² je nach Breite).
///
/// Zell-IDs sind stabil und kompakt: `"<latIdx>:<lonIdx>"` mit
/// `latIdx ∈ [0, 3600)` und `lonIdx ∈ [0, 7200)`.
library;

import 'dart:math' as math;

class ExplorationGrid {
  ExplorationGrid._();

  static const double res = 0.05;
  static const int latCells = 3600; // 180 / 0.05
  static const int lonCells = 7200; // 360 / 0.05
  static const double _earthR = 6371.0088; // km

  static int latIndex(double lat) {
    final i = ((lat + 90.0) / res).floor();
    return i.clamp(0, latCells - 1);
  }

  static int lonIndex(double lon) {
    // Länge auf [-180, 180) normalisieren, dann indexieren.
    var l = lon;
    while (l < -180) {
      l += 360;
    }
    while (l >= 180) {
      l -= 360;
    }
    final i = ((l + 180.0) / res).floor();
    return i.clamp(0, lonCells - 1);
  }

  static String cellId(double lat, double lon) =>
      '${latIndex(lat)}:${lonIndex(lon)}';

  static (int, int) parseCellId(String id) {
    final sep = id.indexOf(':');
    return (int.parse(id.substring(0, sep)), int.parse(id.substring(sep + 1)));
  }

  /// Südwest-Ecke der Zelle.
  static (double lat, double lon) cellSouthWest(int latIdx, int lonIdx) =>
      (latIdx * res - 90.0, lonIdx * res - 180.0);

  static (double lat, double lon) cellCenter(int latIdx, int lonIdx) =>
      (latIdx * res - 90.0 + res / 2, lonIdx * res - 180.0 + res / 2);

  /// Exakte sphärische Fläche einer Zelle in km² (hängt nur von der Breite ab):
  /// A = R² · Δλ · (sin φ₂ − sin φ₁)
  static double cellAreaKm2(int latIdx) {
    final lat1 = (latIdx * res - 90.0) * math.pi / 180.0;
    final lat2 = ((latIdx + 1) * res - 90.0) * math.pi / 180.0;
    final dLon = res * math.pi / 180.0;
    return (_earthR * _earthR * dLon * (math.sin(lat2) - math.sin(lat1))).abs();
  }

  /// Großkreis-Distanz in km (Haversine).
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const degToRad = math.pi / 180.0;
    final dLat = (lat2 - lat1) * degToRad;
    final dLon = (lon2 - lon1) * degToRad;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1 * degToRad) *
            math.cos(lat2 * degToRad) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * _earthR * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
  }
}
