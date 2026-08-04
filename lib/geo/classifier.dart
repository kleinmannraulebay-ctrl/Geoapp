import 'geo_data.dart';
import 'grid.dart';
import 'spherical.dart';

/// Ergebnis der Zuordnung eines Roh-Punktes.
class ClassifiedPoint {
  final int pointId;
  final int timestamp; // ms Epoche
  final int cellId;
  final double cellAreaKm2;
  final String? country; // ADM0_A3
  final String? region; // adm1_code
  final List<int> cityIds; // Städte im Erkennungsradius

  const ClassifiedPoint({
    required this.pointId,
    required this.timestamp,
    required this.cellId,
    required this.cellAreaKm2,
    required this.country,
    required this.region,
    required this.cityIds,
  });
}

/// Roh-Punkt als transferierbares Tupel für das Isolate.
class RawPoint {
  final int id;
  final double lat;
  final double lon;
  final int timestamp;
  const RawPoint(this.id, this.lat, this.lon, this.timestamp);
}

/// Ordnet Punkte Land, Region, Rasterzelle und Städten zu.
/// Pure Dart – läuft im Ingest-Isolate.
List<ClassifiedPoint> classifyPoints(GeoData geo, List<RawPoint> points) {
  final out = <ClassifiedPoint>[];
  for (final p in points) {
    final cell = ExplorationGrid.cellIdFor(p.lat, p.lon);
    final region = geo.regionIndex.lookupWithFallback(p.lat, p.lon);
    // Land bevorzugt über die Region ableiten (konsistent bei Küsten-Fallback).
    final country = region != null
        ? region.country
        : geo.countryIndex.lookupWithFallback(p.lat, p.lon)?.id;

    final cityIds = <int>[];
    for (final city in geo.cityCandidates(p.lat, p.lon)) {
      if (haversineKm(p.lat, p.lon, city.lat, city.lon) <=
          city.detectionRadiusKm) {
        cityIds.add(city.id);
      }
    }

    out.add(ClassifiedPoint(
      pointId: p.id,
      timestamp: p.timestamp,
      cellId: cell,
      cellAreaKm2: ExplorationGrid.cellAreaKm2(cell),
      country: country,
      region: region?.id,
      cityIds: cityIds,
    ));
  }
  return out;
}
