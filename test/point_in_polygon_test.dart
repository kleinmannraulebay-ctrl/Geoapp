import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/geo/point_in_polygon.dart';

Float64List ring(List<List<double>> pts) {
  final f = Float64List(pts.length * 2);
  for (var i = 0; i < pts.length; i++) {
    f[i * 2] = pts[i][0];
    f[i * 2 + 1] = pts[i][1];
  }
  return f;
}

void main() {
  group('rayCastRing', () {
    final square = ring([
      [0, 0],
      [10, 0],
      [10, 10],
      [0, 10],
    ]);

    test('Punkt im Inneren', () {
      expect(rayCastRing(square, 5, 5), isTrue);
    });

    test('Punkt außerhalb', () {
      expect(rayCastRing(square, 15, 5), isFalse);
      expect(rayCastRing(square, -1, 5), isFalse);
      expect(rayCastRing(square, 5, 11), isFalse);
    });

    test('Punkt nahe der Kante innen/außen', () {
      expect(rayCastRing(square, 9.999, 5), isTrue);
      expect(rayCastRing(square, 10.001, 5), isFalse);
    });
  });

  group('PackedPolygon', () {
    test('BBox-Vorfilter', () {
      final poly = PackedPolygon([
        ring([
          [0, 0],
          [10, 0],
          [10, 10],
          [0, 10],
        ]),
      ]);
      expect(poly.bboxContains(5, 5), isTrue);
      expect(poly.bboxContains(11, 5), isFalse);
      expect(poly.contains(5, 5), isTrue);
      expect(poly.contains(11, 5), isFalse);
    });

    test('Loch wird ausgespart (Even-Odd)', () {
      final poly = PackedPolygon([
        ring([
          [0, 0],
          [10, 0],
          [10, 10],
          [0, 10],
        ]),
        // Loch in der Mitte
        ring([
          [4, 4],
          [6, 4],
          [6, 6],
          [4, 6],
        ]),
      ]);
      expect(poly.contains(2, 2), isTrue); // im Polygon, nicht im Loch
      expect(poly.contains(5, 5), isFalse); // im Loch
      expect(poly.contains(6.5, 5), isTrue); // hinter dem Loch, im Polygon
    });

    test('Konkaves Polygon (L-Form)', () {
      final poly = PackedPolygon([
        ring([
          [0, 0],
          [10, 0],
          [10, 4],
          [4, 4],
          [4, 10],
          [0, 10],
        ]),
      ]);
      expect(poly.contains(2, 8), isTrue); // im vertikalen Arm
      expect(poly.contains(8, 2), isTrue); // im horizontalen Arm
      expect(poly.contains(8, 8), isFalse); // in der Aussparung
    });
  });
}
