import 'dart:typed_data';

/// Geometrie-Modelle – pure Dart, isolate-transferierbar (Float64List).

/// Ein Polygon-Teil: äußerer Ring plus optionale Löcher.
/// Ringe sind flache Listen `[lon0, lat0, lon1, lat1, …]`.
class PolyPart {
  final Float64List outer;
  final List<Float64List> holes;
  final double minX, minY, maxX, maxY;

  PolyPart(this.outer, this.holes)
      : minX = _min(outer, 0),
        minY = _min(outer, 1),
        maxX = _max(outer, 0),
        maxY = _max(outer, 1);

  static double _min(Float64List xy, int off) {
    var v = double.infinity;
    for (var i = off; i < xy.length; i += 2) {
      if (xy[i] < v) v = xy[i];
    }
    return v;
  }

  static double _max(Float64List xy, int off) {
    var v = double.negativeInfinity;
    for (var i = off; i < xy.length; i += 2) {
      if (xy[i] > v) v = xy[i];
    }
    return v;
  }
}

/// Ein Land oder eine Region als (Multi-)Polygon mit Metadaten.
class GeoFeature {
  final String id;

  /// ADM0_A3 des Landes (bei Regionen: Zugehörigkeit, bei Ländern == id).
  final String country;
  final String name;
  final String continent; // nur bei Ländern gefüllt, sonst ''
  final String iso2; // nur bei Ländern gefüllt, sonst ''
  final double areaKm2;
  final double minX, minY, maxX, maxY;
  final List<PolyPart> parts;

  GeoFeature({
    required this.id,
    required this.country,
    required this.name,
    this.continent = '',
    this.iso2 = '',
    required this.areaKm2,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.parts,
  });
}

/// Eine Stadt aus dem gebündelten Datensatz.
class City {
  final int id;
  final String name;
  final String country; // ADM0_A3
  final double lat;
  final double lon;
  final int population;

  const City({
    required this.id,
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
    required this.population,
  });

  /// Erkennungsradius in km, skaliert mit der Einwohnerzahl
  /// (5 km Kleinstadt … 25 km Metropole).
  double get detectionRadiusKm {
    if (population >= 5000000) return 25;
    if (population >= 1000000) return 18;
    if (population >= 250000) return 12;
    if (population >= 100000) return 8;
    return 5;
  }
}
