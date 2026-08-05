import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/geo/exploration_grid.dart';

void main() {
  group('Zell-Indizes', () {
    test('Eckwerte', () {
      expect(ExplorationGrid.latIndex(-90), 0);
      expect(ExplorationGrid.latIndex(90), ExplorationGrid.latCells - 1);
      expect(ExplorationGrid.lonIndex(-180), 0);
      // +180° ist derselbe Meridian wie -180°:
      expect(ExplorationGrid.lonIndex(180), 0);
    });

    test('Roundtrip cellId → parse → Zentrum in der Zelle', () {
      const lat = 52.52, lon = 13.405; // Berlin
      final id = ExplorationGrid.cellId(lat, lon);
      final (latIdx, lonIdx) = ExplorationGrid.parseCellId(id);
      final (cLat, cLon) = ExplorationGrid.cellCenter(latIdx, lonIdx);
      expect((cLat - lat).abs(), lessThan(ExplorationGrid.res));
      expect((cLon - lon).abs(), lessThan(ExplorationGrid.res));
      expect(ExplorationGrid.cellId(cLat, cLon), id);
    });

    test('Längen-Normalisierung über die Datumsgrenze', () {
      expect(ExplorationGrid.lonIndex(190), ExplorationGrid.lonIndex(-170));
      expect(ExplorationGrid.lonIndex(-190), ExplorationGrid.lonIndex(170));
    });
  });

  group('Zellfläche', () {
    test('Äquator-Zelle ≈ 1,24 km²', () {
      final a = ExplorationGrid.cellAreaKm2(ExplorationGrid.latIndex(0.0));
      expect(a, closeTo(1.236, 0.01));
    });

    test('Fläche nimmt zu den Polen ab', () {
      final equator = ExplorationGrid.cellAreaKm2(ExplorationGrid.latIndex(0));
      final mid = ExplorationGrid.cellAreaKm2(ExplorationGrid.latIndex(52));
      final polar = ExplorationGrid.cellAreaKm2(ExplorationGrid.latIndex(80));
      expect(mid, lessThan(equator));
      expect(polar, lessThan(mid));
      // cos(52°) ≈ 0,6157
      expect(mid / equator, closeTo(0.6157, 0.01));
    });

    test('Summe aller Breitenbänder ≈ Erdoberfläche', () {
      var sum = 0.0;
      for (var i = 0; i < ExplorationGrid.latCells; i++) {
        sum += ExplorationGrid.cellAreaKm2(i) * ExplorationGrid.lonCells;
      }
      expect(sum, closeTo(510e6, 1e6)); // ~510 Mio. km²
    });
  });

  group('Distanz (Haversine)', () {
    test('Berlin – München ≈ 504 km', () {
      final d =
          ExplorationGrid.distanceKm(52.5200, 13.4050, 48.1374, 11.5755);
      expect(d, closeTo(504, 5));
    });

    test('Identische Punkte → 0', () {
      expect(ExplorationGrid.distanceKm(10, 10, 10, 10), closeTo(0, 1e-9));
    });
  });
}
