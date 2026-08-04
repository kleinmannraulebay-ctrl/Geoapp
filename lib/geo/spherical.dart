import 'dart:math' as math;
import 'dart:typed_data';

/// Sphärische Geometrie – pure Dart, ohne Flutter-Abhängigkeiten.
const double earthRadiusKm = 6371.0088;

double _rad(double deg) => deg * math.pi / 180.0;

/// Großkreis-Distanz (Haversine) in Kilometern.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Sphärische Fläche eines geschlossenen Rings in km².
///
/// [xy] ist eine flache Liste `[lon0, lat0, lon1, lat1, …]`; der Ring muss
/// geschlossen sein (erster Punkt == letzter Punkt) oder wird implizit
/// geschlossen.
double ringAreaKm2(Float64List xy) {
  final n = xy.length ~/ 2;
  if (n < 3) return 0.0;
  var total = 0.0;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final lon1 = xy[2 * i], lat1 = xy[2 * i + 1];
    final lon2 = xy[2 * j], lat2 = xy[2 * j + 1];
    total += _rad(lon2 - lon1) * (2 + math.sin(_rad(lat1)) + math.sin(_rad(lat2)));
  }
  return (total.abs() * earthRadiusKm * earthRadiusKm / 2.0);
}
