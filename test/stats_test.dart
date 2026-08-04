import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/data/app_database.dart';
import 'package:reise_tracker/data/stats_service.dart';
import 'package:reise_tracker/geo/classifier.dart';
import 'package:reise_tracker/geo/geo_data.dart';
import 'package:reise_tracker/geo/geo_models.dart';

Float64List _ring(List<List<double>> pts) {
  final out = Float64List(pts.length * 2);
  for (var i = 0; i < pts.length; i++) {
    out[2 * i] = pts[i][0];
    out[2 * i + 1] = pts[i][1];
  }
  return out;
}

GeoFeature _square(String id,
    {required double west,
    required double south,
    required double size,
    required double areaKm2,
    String? country,
    String continent = 'Europe',
    String iso2 = 'XX'}) {
  return GeoFeature(
    id: id,
    country: country ?? id,
    name: id,
    continent: country == null ? continent : '',
    iso2: country == null ? iso2 : '',
    areaKm2: areaKm2,
    minX: west,
    minY: south,
    maxX: west + size,
    maxY: south + size,
    parts: [
      PolyPart(
          _ring([
            [west, south],
            [west + size, south],
            [west + size, south + size],
            [west, south + size],
            [west, south],
          ]),
          const [])
    ],
  );
}

GeoData _testGeo() {
  // Land LND (10°×10°) mit zwei Regionen (je 10°×5°) und zwei Städten.
  return GeoData(
    countries: [
      _square('LND', west: 0, south: 0, size: 10, areaKm2: 1000),
    ],
    regions: [
      _square('LND-NORD',
          west: 0, south: 5, size: 5, areaKm2: 500, country: 'LND'),
      _square('LND-SUED',
          west: 0, south: 0, size: 5, areaKm2: 500, country: 'LND'),
    ],
    cities: const [
      City(id: 1, name: 'Metropolis', country: 'LND',
          lat: 2, lon: 2, population: 6000000),
      City(id: 2, name: 'Kleinstadt', country: 'LND',
          lat: 8, lon: 2, population: 20000),
    ],
  );
}

void main() {
  group('CountryAgg-Prozentformeln', () {
    StatsSnapshot compute({
      Map<String, AreaStats> countryStats = const {},
      Map<String, AreaStats> regionStats = const {},
      Map<String, int> visitDays = const {},
      Map<int, CityVisit> cityVisits = const {},
      List<ManualEntry> manual = const [],
    }) {
      return StatsService.compute(
        geo: _testGeo(),
        countryStats: countryStats,
        regionStats: regionStats,
        visitDays: visitDays,
        cityVisits: cityVisits,
        manualEntries: manual,
        citiesPerCountry: 25,
      );
    }

    test('unbesuchtes Land: alles 0', () {
      final s = compute();
      final a = s.byCountry['LND']!;
      expect(a.visited, isFalse);
      expect(a.regionPct, 0);
      expect(a.cityPct, 0);
      expect(a.areaPct, 0);
      expect(a.level, 0);
    });

    test('Flächen-Prozent = erkundete Fläche ÷ Landesfläche', () {
      final s = compute(
        countryStats: {
          'LND': const AreaStats('LND', null, 250, 8, 1000, 2000),
        },
        visitDays: {'LND': 1},
      );
      expect(s.byCountry['LND']!.areaPct, closeTo(0.25, 1e-9));
    });

    test('Flächen-Prozent wird bei Überlappung auf 100 % gedeckelt', () {
      final s = compute(
        countryStats: {
          'LND': const AreaStats('LND', null, 1400, 50, 1000, 2000),
        },
      );
      expect(s.byCountry['LND']!.areaPct, 1.0);
    });

    test('Regionen-Prozent = besuchte ÷ Gesamtzahl', () {
      final s = compute(
        regionStats: {
          'LND-NORD': const AreaStats('LND-NORD', 'LND', 30, 1, 1, 2),
        },
      );
      final a = s.byCountry['LND']!;
      expect(a.regionsTotal, 2);
      expect(a.regionsVisited, 1);
      expect(a.regionPct, 0.5);
    });

    test('Städte-Prozent zählt auto+manuell, aber nicht unterdrückte', () {
      final s = compute(cityVisits: {
        1: const CityVisit(1, VisitSource.auto, 1000),
        2: const CityVisit(2, VisitSource.suppressed, null),
      });
      final a = s.byCountry['LND']!;
      expect(a.citiesTotal, 2);
      expect(a.citiesVisited, 1);
      expect(a.cityPct, 0.5);
    });

    test('manueller Eintrag markiert Land und Region als besucht', () {
      final s = compute(manual: [
        const ManualEntry(
            country: 'LND',
            region: 'LND-SUED',
            dateFrom: '2019-06-01',
            dateTo: '2019-06-15',
            createdAt: 1),
      ]);
      final a = s.byCountry['LND']!;
      expect(a.visited, isTrue);
      expect(a.regionsVisited, 1);
      expect(s.visitedRegions, contains('LND-SUED'));
      // Erstbesuch aus dem manuellen Zeitraum übernommen.
      expect(a.firstTs, DateTime.parse('2019-06-01').millisecondsSinceEpoch);
    });

    test('Kontinent- und Welt-Aggregation', () {
      final s = compute(
        countryStats: {
          'LND': const AreaStats('LND', null, 100, 4, 1, 2),
        },
        visitDays: {'LND': 2},
      );
      expect(s.world.countriesTotal, 1);
      expect(s.world.countriesVisited, 1);
      expect(s.world.areaPct, closeTo(0.1, 1e-9));
      expect(s.continents.single.name, 'Europa');
    });
  });

  group('Intensitätsstufen (Choropleth)', () {
    test('Stufen nach Besuchstagen', () {
      expect(CountryAgg.levelFor(0, false), 0);
      expect(CountryAgg.levelFor(0, true), 1);
      expect(CountryAgg.levelFor(1, true), 1);
      expect(CountryAgg.levelFor(3, true), 2);
      expect(CountryAgg.levelFor(7, true), 3);
      expect(CountryAgg.levelFor(15, true), 4);
      expect(CountryAgg.levelFor(30, true), 5);
      expect(CountryAgg.levelFor(365, true), 5);
    });
  });

  group('Städte-Erkennung', () {
    test('Radius skaliert mit Einwohnerzahl', () {
      const small = City(id: 1, name: 'a', country: 'X',
          lat: 0, lon: 0, population: 20000);
      const mid = City(id: 2, name: 'b', country: 'X',
          lat: 0, lon: 0, population: 400000);
      const metro = City(id: 3, name: 'c', country: 'X',
          lat: 0, lon: 0, population: 8000000);
      expect(small.detectionRadiusKm, 5);
      expect(mid.detectionRadiusKm, 12);
      expect(metro.detectionRadiusKm, 25);
    });

    test('classifyPoints erkennt Stadtbesuch im Radius', () {
      final geo = _testGeo();
      // ~11 km neben Metropolis (Radius 25 km) → Treffer;
      // Kleinstadt (Radius 5 km) ist weit weg.
      final result = classifyPoints(
          geo, [const RawPoint(1, 2.1, 2.0, 1700000000000)]);
      expect(result.single.cityIds, [1]);
      expect(result.single.country, 'LND');
      expect(result.single.region, 'LND-SUED');
    });

    test('classifyPoints: Punkt im Ozean → kein Land', () {
      final geo = _testGeo();
      final result = classifyPoints(
          geo, [const RawPoint(1, -50.0, -50.0, 1700000000000)]);
      expect(result.single.country, isNull);
      expect(result.single.region, isNull);
      expect(result.single.cityIds, isEmpty);
    });
  });
}
