import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/core/constants.dart';
import 'package:reise_tracker/data/models.dart';

void main() {
  group('Städte-Radius nach Einwohnerzahl', () {
    test('Stufen', () {
      expect(AppConst.cityRadiusKm(10000), 5);
      expect(AppConst.cityRadiusKm(49999), 5);
      expect(AppConst.cityRadiusKm(50000), 8);
      expect(AppConst.cityRadiusKm(200000), 10);
      expect(AppConst.cityRadiusKm(500000), 12);
      expect(AppConst.cityRadiusKm(1000000), 18);
      expect(AppConst.cityRadiusKm(5000000), 25);
      expect(AppConst.cityRadiusKm(20000000), 25);
    });

    test('Radius nie größer als das Suchfenster', () {
      for (final pop in [0, 1e4, 1e5, 1e6, 1e7, 1e8]) {
        expect(AppConst.cityRadiusKm(pop.toInt()),
            lessThanOrEqualTo(AppConst.maxCityRadiusKm));
      }
    });
  });

  group('Flug-Filter', () {
    test('Reisen am Boden werden nicht gefiltert', () {
      expect(AppConst.isLikelyFlight(0, 0), isFalse); // Stillstand
      expect(AppConst.isLikelyFlight(36, 200), isFalse); // Auto, 130 km/h
      expect(AppConst.isLikelyFlight(83, 300), isFalse); // ICE, 300 km/h
      expect(AppConst.isLikelyFlight(30, 2800), isFalse); // Pass-Straße
    });

    test('Flüge werden gefiltert', () {
      expect(AppConst.isLikelyFlight(240, 11000), isTrue); // Reiseflug
      expect(AppConst.isLikelyFlight(80, 3000), isTrue); // Landeanflug
      expect(AppConst.isLikelyFlight(120, 0), isTrue); // > 360 km/h
    });
  });

  group('Intensitäts-Stufen (Choropleth)', () {
    test('Grenzwerte', () {
      expect(AppConst.intensityStage(0), 0);
      expect(AppConst.intensityStage(1), 1);
      expect(AppConst.intensityStage(2), 1);
      expect(AppConst.intensityStage(3), 2);
      expect(AppConst.intensityStage(7), 3);
      expect(AppConst.intensityStage(14), 4);
      expect(AppConst.intensityStage(30), 5);
      expect(AppConst.intensityStage(1000), 5);
    });
  });

  group('Prozentformeln', () {
    test('areaPercent klemmt auf [0, 1]', () {
      expect(AppConst.areaPercent(50, 100), 0.5);
      expect(AppConst.areaPercent(150, 100), 1.0);
      expect(AppConst.areaPercent(-5, 100), 0.0);
      expect(AppConst.areaPercent(10, 0), 0.0);
    });

    test('ratioPercent', () {
      expect(AppConst.ratioPercent(5, 25), 0.2);
      expect(AppConst.ratioPercent(30, 25), 1.0);
      expect(AppConst.ratioPercent(0, 0), 0.0);
    });

    test('CountryStats leitet Prozente korrekt ab', () {
      const s = CountryStats(
        code: 'DEU',
        name: 'Deutschland',
        continent: 'Europa',
        areaKm2: 357000,
        exploredKm2: 3570,
        regionsVisited: 4,
        regionsTotal: 16,
        citiesVisited: 5,
        citiesListed: 25,
        hasAuto: true,
      );
      expect(s.areaPercent, closeTo(0.01, 1e-9));
      expect(s.regionPercent, closeTo(0.25, 1e-9));
      expect(s.cityPercent, closeTo(0.2, 1e-9));
      expect(s.visited, isTrue);
    });

    test('Unbesuchtes Land', () {
      const s = CountryStats(
        code: 'JPN',
        name: 'Japan',
        continent: 'Asien',
        areaKm2: 377000,
      );
      expect(s.visited, isFalse);
      expect(s.areaPercent, 0);
      expect(s.regionPercent, 0);
      expect(s.cityPercent, 0);
    });
  });
}
