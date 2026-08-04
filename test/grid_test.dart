import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/geo/grid.dart';

void main() {
  group('ExplorationGrid', () {
    test('Zellen-ID ist stabil und eindeutig', () {
      final a = ExplorationGrid.cellIdFor(52.52, 13.405); // Berlin
      final b = ExplorationGrid.cellIdFor(52.52, 13.405);
      final c = ExplorationGrid.cellIdFor(48.137, 11.575); // München
      expect(a, b);
      expect(a, isNot(c));
    });

    test('Punkte in derselben Zelle → gleiche ID', () {
      final a = ExplorationGrid.cellIdFor(52.520, 13.401);
      final b = ExplorationGrid.cellIdFor(52.523, 13.404);
      expect(a, b);
    });

    test('Roundtrip: Mittelpunkt liegt in der eigenen Zelle', () {
      for (final (lat, lon) in [
        (0.0, 0.0),
        (52.52, 13.405),
        (-33.87, 151.21),
        (71.0, -156.8),
        (-89.99, 179.99),
      ]) {
        final id = ExplorationGrid.cellIdFor(lat, lon);
        final (clat, clon) = ExplorationGrid.cellCenter(id);
        expect(ExplorationGrid.cellIdFor(clat, clon), id,
            reason: 'für ($lat, $lon)');
      }
    });

    test('cellBounds umschließen den Ursprungspunkt', () {
      const lat = 52.52, lon = 13.405;
      final id = ExplorationGrid.cellIdFor(lat, lon);
      final (south, west, north, east) = ExplorationGrid.cellBounds(id);
      expect(lat, inInclusiveRange(south, north));
      expect(lon, inInclusiveRange(west, east));
      expect(north - south, closeTo(0.05, 1e-9));
      expect(east - west, closeTo(0.05, 1e-9));
    });

    test('Zellfläche: ~31 km² am Äquator, halbiert bei 60° Breite', () {
      final equator = ExplorationGrid.cellAreaKm2(
          ExplorationGrid.cellIdFor(0.0, 0.0));
      final north = ExplorationGrid.cellAreaKm2(
          ExplorationGrid.cellIdFor(60.0, 0.0));
      expect(equator, closeTo(31.0, 1.0));
      expect(north / equator, closeTo(0.5, 0.02));
    });

    test('Randwerte werden geklemmt statt zu crashen', () {
      expect(() => ExplorationGrid.cellIdFor(90.0, 180.0), returnsNormally);
      expect(() => ExplorationGrid.cellIdFor(-90.0, -180.0), returnsNormally);
    });
  });
}
