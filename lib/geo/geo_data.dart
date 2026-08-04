import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'geo_index.dart';
import 'geo_models.dart';

/// Kompletter, im Speicher gehaltener Geodatensatz der App.
///
/// Wird aus den gebündelten Assets geparst (in einem Isolate, siehe
/// GeoRepository) und sowohl von der UI (Karte, Tap-Lookup) als auch vom
/// Ingest-Isolate (Punkt-Zuordnung) verwendet.
class GeoData {
  final List<GeoFeature> countries;
  final List<GeoFeature> regions;
  final List<City> cities;
  final GeoIndex countryIndex;
  final GeoIndex regionIndex;

  /// 1°-Buckets über den Städten für schnelle Umkreis-Suche.
  final Map<int, List<int>> _cityBuckets = {};

  GeoData({required this.countries, required this.regions, required this.cities})
      : countryIndex = GeoIndex(countries),
        regionIndex = GeoIndex(regions) {
    for (var i = 0; i < cities.length; i++) {
      final c = cities[i];
      final y = (c.lat + 90).floor().clamp(0, 179);
      final x = (c.lon + 180).floor().clamp(0, 359);
      _cityBuckets.putIfAbsent(y * 360 + x, () => <int>[]).add(i);
    }
  }

  GeoFeature? countryById(String id) {
    for (final c in countries) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<GeoFeature> regionsOf(String countryId) =>
      regions.where((r) => r.country == countryId).toList();

  List<City> citiesOf(String countryId, {int limit = 25}) {
    final list = cities.where((c) => c.country == countryId).toList()
      ..sort((a, b) => b.population.compareTo(a.population));
    return list.length > limit ? list.sublist(0, limit) : list;
  }

  /// Kandidaten-Städte im Umfeld (±1°-Buckets) eines Punktes.
  List<City> cityCandidates(double lat, double lon) {
    final out = <City>[];
    final y0 = (lat + 90).floor(), x0 = (lon + 180).floor();
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final y = (y0 + dy).clamp(0, 179);
        final x = (x0 + dx) % 360;
        final ids = _cityBuckets[y * 360 + (x < 0 ? x + 360 : x)];
        if (ids != null) {
          for (final i in ids) {
            out.add(cities[i]);
          }
        }
      }
    }
    return out;
  }
}

// --------------------------------------------------------------- Parsing

GeoFeature _parseFeature(Map<String, dynamic> f, {required bool isCountry}) {
  final props = f['properties'] as Map<String, dynamic>;
  final geom = f['geometry'] as Map<String, dynamic>;
  final type = geom['type'] as String;
  final coords = geom['coordinates'] as List;
  final polys = type == 'Polygon' ? [coords] : coords;

  Float64List ringToFlat(List ring) {
    final out = Float64List(ring.length * 2);
    for (var i = 0; i < ring.length; i++) {
      final pt = ring[i] as List;
      out[2 * i] = (pt[0] as num).toDouble();
      out[2 * i + 1] = (pt[1] as num).toDouble();
    }
    return out;
  }

  final parts = <PolyPart>[];
  for (final poly in polys) {
    final rings = poly as List;
    if (rings.isEmpty) continue;
    parts.add(PolyPart(
      ringToFlat(rings.first as List),
      [for (var i = 1; i < rings.length; i++) ringToFlat(rings[i] as List)],
    ));
  }

  final bbox = (props['bbox'] as List).map((e) => (e as num).toDouble()).toList();
  return GeoFeature(
    id: props['id'] as String,
    country: isCountry ? props['id'] as String : props['country'] as String,
    name: props['name'] as String,
    continent: isCountry ? (props['continent'] as String? ?? '') : '',
    iso2: isCountry ? (props['iso2'] as String? ?? '') : '',
    areaKm2: (props['areaKm2'] as num).toDouble(),
    minX: bbox[0],
    minY: bbox[1],
    maxX: bbox[2],
    maxY: bbox[3],
    parts: parts,
  );
}

List<GeoFeature> parseFeatureCollectionGz(Uint8List gzBytes,
    {required bool isCountry}) {
  final json =
      jsonDecode(utf8.decode(gzip.decode(gzBytes))) as Map<String, dynamic>;
  final features = json['features'] as List;
  return [
    for (final f in features)
      _parseFeature(f as Map<String, dynamic>, isCountry: isCountry)
  ];
}

List<City> parseCitiesGz(Uint8List gzBytes) {
  final json =
      jsonDecode(utf8.decode(gzip.decode(gzBytes))) as Map<String, dynamic>;
  final rows = json['rows'] as List;
  return [
    for (final r in rows.cast<List>())
      City(
        id: (r[0] as num).toInt(),
        name: r[1] as String,
        country: r[2] as String,
        lat: (r[3] as num).toDouble(),
        lon: (r[4] as num).toDouble(),
        population: (r[5] as num).toInt(),
      )
  ];
}

/// Baut den kompletten Geodatensatz aus den drei Asset-Byte-Puffern.
/// Läuft in einem Isolate (teuer: ~6 MB JSON).
GeoData buildGeoData(
    Uint8List countriesGz, Uint8List regionsGz, Uint8List citiesGz) {
  return GeoData(
    countries: parseFeatureCollectionGz(countriesGz, isCountry: true),
    regions: parseFeatureCollectionGz(regionsGz, isCountry: false),
    cities: parseCitiesGz(citiesGz),
  );
}
