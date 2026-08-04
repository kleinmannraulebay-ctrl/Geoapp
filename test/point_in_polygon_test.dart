import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reise_tracker/geo/geo_index.dart';
import 'package:reise_tracker/geo/geo_models.dart';
import 'package:reise_tracker/geo/point_in_polygon.dart';

Float64List ring(List<List<double>> pts) {
  final out = Float64List(pts.length * 2);
  for (var i = 0; i < pts.length; i++) {
    out[2 * i] = pts[i][0];
    out[2 * i + 1] = pts[i][1];
  }
  return out;
}

GeoFeature squareFeature(String id,
    {required double west,
    required double south,
    required double size,
    List<List<double>>? hole,
    String? country}) {
  final outer = ring([
    [west, south],
    [west + size, south],
    [west + size, south + size],
    [west, south + size],
    [west, south],
  ]);
  return GeoFeature(
    id: id,
    country: country ?? id,
    name: id,
    areaKm2: 0,
    minX: west,
    minY: south,
    maxX: west + size,
    maxY: south + size,
    parts: [
      PolyPart(outer, [if (hole != null) ring(hole)])
    ],
  );
}

void main() {
  group('pointInRing (Ray-Casting)', () {
    final square = ring([
      [0, 0],
      [10, 0],
      [10, 10],
      [0, 10],
      [0, 0],
    ]);

    test('Punkt innen', () {
      expect(pointInRing(square, 5, 5), isTrue);
    });

    test('Punkt außen', () {
      expect(pointInRing(square, 15, 5), isFalse);
      expect(pointInRing(square, -1, 5), isFalse);
      expect(pointInRing(square, 5, 11), isFalse);
    });

    test('Punkt nahe der Kante', () {
      expect(pointInRing(square, 9.999, 5), isTrue);
      expect(pointInRing(square, 10.001, 5), isFalse);
    });

    test('konkaves Polygon (L-Form)', () {
      final l = ring([
        [0, 0],
        [10, 0],
        [10, 4],
        [4, 4],
        [4, 10],
        [0, 10],
        [0, 0],
      ]);
      expect(pointInRing(l, 2, 8), isTrue); // im schmalen Arm
      expect(pointInRing(l, 8, 2), isTrue); // im breiten Arm
      expect(pointInRing(l, 8, 8), isFalse); // in der Aussparung
    });
  });

  group('pointInFeature (mit Loch)', () {
    final f = squareFeature('X',
        west: 0,
        south: 0,
        size: 10,
        hole: [
          [4, 4],
          [6, 4],
          [6, 6],
          [4, 6],
          [4, 4],
        ]);

    test('innen, aber außerhalb des Lochs', () {
      expect(pointInFeature(f, 2, 2), isTrue);
    });

    test('im Loch → nicht enthalten', () {
      expect(pointInFeature(f, 5, 5), isFalse);
    });

    test('BBox-Vorfilter greift', () {
      expect(pointInFeature(f, 50, 50), isFalse);
    });
  });

  group('GeoIndex', () {
    final features = [
      squareFeature('A', west: 0, south: 0, size: 10),
      squareFeature('B', west: 20, south: 20, size: 10),
      squareFeature('C', west: 25, south: 25, size: 2),
    ];
    final index = GeoIndex(features);

    test('findet das richtige Feature', () {
      expect(index.lookup(5, 5)?.id, 'A');
      expect(index.lookup(22, 22)?.id, 'B');
    });

    test('kleineres Feature in Überlappungszone auffindbar', () {
      // C liegt in B; lookup liefert irgendein enthaltendes Feature.
      final hit = index.lookup(26, 26);
      expect(hit, isNotNull);
      expect(['B', 'C'], contains(hit!.id));
    });

    test('Ozean → null', () {
      expect(index.lookup(-50, -50), isNull);
    });

    test('Küsten-Fallback findet nahes Feature', () {
      // Punkt knapp außerhalb von A (0.02° westlich).
      expect(index.lookup(5, -0.02), isNull);
      expect(index.lookupWithFallback(5, -0.02)?.id, 'A');
    });

    test('inBounds filtert nach BBox', () {
      final hits = index.inBounds(-1, -1, 11, 11).map((f) => f.id).toList();
      expect(hits, ['A']);
    });
  });
}
