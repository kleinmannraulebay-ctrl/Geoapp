/// Lädt und parst die gebündelten Geodaten-Assets (gzip-komprimiertes
/// GeoJSON). Das Parsen läuft in einem Isolate, damit die UI nicht blockiert.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'geo_models.dart';
import 'spatial_index.dart';

/// Alle statischen Geodaten der App, einmalig geladen.
class GeoData {
  final List<GeoFeature> countries;
  final List<GeoFeature> regions;
  final List<City> cities;

  late final PolygonIndex countryIndex = PolygonIndex(countries);
  late final PolygonIndex regionIndex = PolygonIndex(regions, cellDeg: 1.0);
  late final CityIndex cityIndex = CityIndex(cities);

  late final Map<String, GeoFeature> countryByCode = {
    for (final c in countries) c.id: c,
  };
  late final Map<String, GeoFeature> regionById = {
    for (final r in regions) r.id: r,
  };
  late final Map<String, List<GeoFeature>> regionsByCountry = _groupRegions();
  late final Map<int, City> cityById = {for (final c in cities) c.id: c};

  /// Städte pro Land, absteigend nach Einwohnerzahl (Asset ist vorsortiert).
  late final Map<String, List<City>> citiesByCountry = _groupCities();

  GeoData({required this.countries, required this.regions, required this.cities});

  Map<String, List<GeoFeature>> _groupRegions() {
    final map = <String, List<GeoFeature>>{};
    for (final r in regions) {
      map.putIfAbsent(r.countryCode, () => []).add(r);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    return map;
  }

  Map<String, List<City>> _groupCities() {
    final map = <String, List<City>>{};
    for (final c in cities) {
      map.putIfAbsent(c.countryCode, () => []).add(c);
    }
    return map;
  }

  /// Die für die Checkliste "gelisteten" Städte eines Landes (Top-N).
  List<City> topCities(String countryCode, int topN) {
    final list = citiesByCountry[countryCode] ?? const [];
    return list.length <= topN ? list : list.sublist(0, topN);
  }

  static Future<GeoData> load() async {
    final countriesBytes =
        await rootBundle.load('assets/geo/countries.json.gz');
    final regionsBytes = await rootBundle.load('assets/geo/regions.json.gz');
    final citiesBytes = await rootBundle.load('assets/geo/cities.json.gz');
    return compute(_parseAll, <Uint8List>[
      countriesBytes.buffer.asUint8List(),
      regionsBytes.buffer.asUint8List(),
      citiesBytes.buffer.asUint8List(),
    ]);
  }
}

GeoData _parseAll(List<Uint8List> raw) {
  final countriesJson = _decodeGz(raw[0]) as Map<String, dynamic>;
  final regionsJson = _decodeGz(raw[1]) as Map<String, dynamic>;
  final citiesJson = _decodeGz(raw[2]) as List;

  final countries = <GeoFeature>[];
  for (final f in countriesJson['features'] as List) {
    final props = f['properties'] as Map<String, dynamic>;
    countries.add(GeoFeature(
      id: props['code'] as String,
      name: props['name'] as String,
      countryCode: props['code'] as String,
      continent: (props['continent'] as String?) ?? 'Ozeanien',
      areaKm2: (props['area'] as num).toDouble(),
      polygons: packGeometry(f['geometry'] as Map<String, dynamic>),
    ));
  }

  final regions = <GeoFeature>[];
  for (final f in regionsJson['features'] as List) {
    final props = f['properties'] as Map<String, dynamic>;
    final id = props['id'] as String?;
    if (id == null) continue;
    regions.add(GeoFeature(
      id: id,
      name: props['name'] as String,
      countryCode: props['code'] as String,
      continent: '',
      areaKm2: (props['area'] as num).toDouble(),
      polygons: packGeometry(f['geometry'] as Map<String, dynamic>),
    ));
  }

  final cities = <City>[
    for (final c in citiesJson)
      City(
        id: c['id'] as int,
        name: c['n'] as String,
        countryCode: c['c'] as String,
        regionName: (c['r'] as String?) ?? '',
        lat: (c['lat'] as num).toDouble(),
        lon: (c['lon'] as num).toDouble(),
        population: c['pop'] as int,
        isCapital: c['cap'] == 1,
      ),
  ];

  final data = GeoData(countries: countries, regions: regions, cities: cities);
  // Indizes bereits im Isolate aufbauen, damit der erste Zugriff im
  // UI-Isolate nicht blockiert.
  data.countryIndex;
  data.regionIndex;
  data.cityIndex;
  data.regionsByCountry;
  data.citiesByCountry;
  return data;
}

dynamic _decodeGz(Uint8List bytes) =>
    json.decode(utf8.decode(gzip.decode(bytes)));
