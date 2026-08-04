import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/geo/spherical.dart';

Float64List ring(List<List<double>> pts) {
  final out = Float64List(pts.length * 2);
  for (var i = 0; i < pts.length; i++) {
    out[2 * i] = pts[i][0];
    out[2 * i + 1] = pts[i][1];
  }
  return out;
}

void main() {
  group('haversineKm', () {
    test('Berlin → München ≈ 504 km', () {
      final d = haversineKm(52.5200, 13.4050, 48.1372, 11.5756);
      expect(d, closeTo(504, 6));
    });

    test('identische Punkte → 0', () {
      expect(haversineKm(10, 10, 10, 10), 0);
    });
  });

  group('ringAreaKm2', () {
    test('1°×1° am Äquator ≈ 12.364 km²', () {
      final r = ring([
        [0, 0],
        [1, 0],
        [1, 1],
        [0, 1],
        [0, 0],
      ]);
      // Referenzwert: (πR/180)² · cos(0.5°) ≈ 12.363 km²
      expect(ringAreaKm2(r), closeTo(12363, 60));
    });

    test('Fläche unabhängig von der Umlaufrichtung', () {
      final cw = ring([
        [0, 0],
        [0, 1],
        [1, 1],
        [1, 0],
        [0, 0],
      ]);
      final ccw = ring([
        [0, 0],
        [1, 0],
        [1, 1],
        [0, 1],
        [0, 0],
      ]);
      expect(ringAreaKm2(cw), closeTo(ringAreaKm2(ccw), 1e-6));
    });

    test('degenerierter Ring → 0', () {
      expect(ringAreaKm2(ring([[0, 0], [1, 1]])), 0);
    });
  });
}
