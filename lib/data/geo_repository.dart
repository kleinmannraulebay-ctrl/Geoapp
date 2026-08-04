import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;

import '../geo/geo_data.dart';

/// Lädt die gebündelten Geo-Assets und parst sie in einem Isolate,
/// damit der UI-Thread nicht blockiert (~6 MB JSON).
class GeoRepository {
  static Future<GeoData> load() async {
    final countries = await rootBundle.load('assets/geo/countries.geojson.gz');
    final regions = await rootBundle.load('assets/geo/regions.geojson.gz');
    final cities = await rootBundle.load('assets/geo/cities.json.gz');

    final cBytes = countries.buffer.asUint8List();
    final rBytes = regions.buffer.asUint8List();
    final sBytes = cities.buffer.asUint8List();

    return Isolate.run(() => buildGeoData(cBytes, rBytes, sBytes));
  }
}
