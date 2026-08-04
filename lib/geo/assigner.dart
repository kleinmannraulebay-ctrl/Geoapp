/// Zuordnung von Track-Punkten zu Land, Region, Rasterzelle und Städten.
///
/// Die Batch-Zuordnung läuft über [assignBatch] in einem Isolate
/// (`compute`), damit die UI nicht blockiert. [GeoData] lebt dabei im
/// Haupt-Isolate; für den Isolate-Aufruf wird es mitgereicht (Dart kopiert
/// Objekte zwischen Isolates derselben Gruppe effizient).
library;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import 'exploration_grid.dart';
import 'geo_assets.dart';

/// Ein zuzuordnender Roh-Punkt.
class RawPoint {
  final int id;
  final double lat;
  final double lon;
  final int ts; // Unix-Millisekunden
  const RawPoint(this.id, this.lat, this.lon, this.ts);
}

/// Ergebnis der Zuordnung eines Punktes.
class AssignedPoint {
  final int id;
  final double lat;
  final double lon;
  final int ts;
  final String cellId;
  final double cellAreaKm2;
  final String? countryCode;
  final String? regionId;

  /// IDs der Städte, in deren Auto-Besuchs-Radius der Punkt liegt.
  final List<int> cityIds;

  const AssignedPoint({
    required this.id,
    required this.lat,
    required this.lon,
    required this.ts,
    required this.cellId,
    required this.cellAreaKm2,
    required this.countryCode,
    required this.regionId,
    required this.cityIds,
  });
}

/// Einen einzelnen Punkt zuordnen (synchron; für Tests und kleine Batches).
AssignedPoint assignPoint(GeoData geo, RawPoint p) {
  final latIdx = ExplorationGrid.latIndex(p.lat);
  final lonIdx = ExplorationGrid.lonIndex(p.lon);

  final country = geo.countryIndex.locate(p.lon, p.lat);
  String? regionId;
  if (country != null) {
    final region = geo.regionIndex.locate(p.lon, p.lat);
    // Nur Regionen des gefundenen Landes akzeptieren (vermeidet
    // Grenz-Artefakte durch unterschiedliche Vereinfachungsgrade).
    if (region != null && region.countryCode == country.id) {
      regionId = region.id;
    }
  }

  final cityIds = <int>[];
  for (final city
      in geo.cityIndex.nearby(p.lat, p.lon, AppConst.maxCityRadiusKm)) {
    final radius = AppConst.cityRadiusKm(city.population);
    if (ExplorationGrid.distanceKm(p.lat, p.lon, city.lat, city.lon) <=
        radius) {
      cityIds.add(city.id);
    }
  }

  return AssignedPoint(
    id: p.id,
    lat: p.lat,
    lon: p.lon,
    ts: p.ts,
    cellId: '$latIdx:$lonIdx',
    cellAreaKm2: ExplorationGrid.cellAreaKm2(latIdx),
    countryCode: country?.id,
    regionId: regionId,
    cityIds: cityIds,
  );
}

class _BatchArgs {
  final GeoData geo;
  final List<RawPoint> points;
  const _BatchArgs(this.geo, this.points);
}

List<AssignedPoint> _assignBatchSync(_BatchArgs args) =>
    [for (final p in args.points) assignPoint(args.geo, p)];

/// Batch-Zuordnung im Isolate.
Future<List<AssignedPoint>> assignBatch(
    GeoData geo, List<RawPoint> points) async {
  if (points.isEmpty) return const [];
  // Kleine Batches direkt zuordnen: der Isolate-Transfer von GeoData wäre
  // teurer als die Zuordnung selbst (<10 ms pro Punkt dank Grid-Index).
  if (points.length <= 64) {
    return _assignBatchSync(_BatchArgs(geo, points));
  }
  return compute(_assignBatchSync, _BatchArgs(geo, points));
}
