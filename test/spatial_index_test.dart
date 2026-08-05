import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/geo/geo_models.dart';
import 'package:reise_tracker/geo/point_in_polygon.dart';
import 'package:reise_tracker/geo/spatial_index.dart';

Float64List _ring(List<List<double>> pts) {
  final f = Float64List(pts.length * 2);
  for (var i = 0; i < pts.length; i++) {
    f[i * 2] = pts[i][0];
    f[i * 2 + 1] = pts[i][1];
  }
  return f;
}

GeoFeature _square(String id, double minLon, double minLat, double size) =>
    GeoFeature(
      id: id,
      name: id,
      countryCode: id,
      continent: '',
      areaKm2: 1,
      polygons: [
        PackedPolygon([
          _ring([
            [minLon, minLat],
            [minLon + size, minLat],
            [minLon + size, minLat + size],
            [minLon, minLat + size],
          ]),
        ]),
      ],
    );

void main() {
  group('PolygonIndex', () {
    final features = [
      _square('A', 0, 0, 5),
      _square('B', 10, 10, 5),
      _square('C', -20, -20, 5),
    ];
    final index = PolygonIndex(features);

    test('locate findet das richtige Feature', () {
      expect(index.locate(2, 2)?.id, 'A');
      expect(index.locate(12, 12)?.id, 'B');
      expect(index.locate(-18, -18)?.id, 'C');
    });

    test('locate liefert null im Niemandsland', () {
      expect(index.locate(50, 50), isNull);
      expect(index.locate(7, 7), isNull); // zwischen A und B
    });

    test('inBounds liefert Features im Ausschnitt', () {
      final hits = index.inBounds(-1, -1, 6, 6).map((f) => f.id).toSet();
      expect(hits, contains('A'));
      expect(hits, isNot(contains('C')));
    });

    test('Zuordnung bleibt unter 10 ms pro Punkt', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        index.locate(2 + (i % 3), 2 + (i % 3));
      }
      sw.stop();
      expect(sw.elapsedMilliseconds / 1000, lessThan(10));
    });
  });

  group('CityIndex', () {
    const berlin = City(
      id: 1,
      name: 'Berlin',
      countryCode: 'DEU',
      regionName: 'Berlin',
      lat: 52.52,
      lon: 13.405,
      population: 3700000,
      isCapital: true,
    );
    const potsdam = City(
      id: 2,
      name: 'Potsdam',
      countryCode: 'DEU',
      regionName: 'Brandenburg',
      lat: 52.396,
      lon: 13.058,
      population: 180000,
      isCapital: false,
    );
    const muenchen = City(
      id: 3,
      name: 'München',
      countryCode: 'DEU',
      regionName: 'Bayern',
      lat: 48.137,
      lon: 11.575,
      population: 1500000,
      isCapital: false,
    );
    final index = CityIndex(const [berlin, potsdam, muenchen]);

    test('nearby findet Städte im Radius', () {
      // Punkt in Berlin-Mitte: Berlin (25-km-Klasse) muss dabei sein.
      final hits = index.nearby(52.52, 13.40, 25).map((c) => c.id).toSet();
      expect(hits, contains(1));
      expect(hits, isNot(contains(3))); // München ist ~500 km entfernt
    });

    test('kleine Radien schließen weiter entfernte Städte aus', () {
      // ~25 km westlich von Berlin-Zentrum, nahe Potsdam.
      final hits = index.nearby(52.40, 13.06, 8).map((c) => c.id).toSet();
      expect(hits, contains(2));
      expect(hits, isNot(contains(1)));
    });
  });
}
