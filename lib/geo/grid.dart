import 'dart:math' as math;

/// Globales 0,05°-Raster (~5,6 km Kantenlänge am Äquator, ~31 km² pro Zelle).
///
/// Zellen-IDs sind stabile Ganzzahlen: `latIndex * lonCells + lonIndex`.
/// Pure Dart, ohne Flutter-Abhängigkeiten – wird in Unit-Tests geprüft.
class ExplorationGrid {
  static const double cellSizeDeg = 0.05;
  static const int latCells = 3600; // 180 / 0.05
  static const int lonCells = 7200; // 360 / 0.05
  static const double _kmPerDegLat = 111.32;

  /// Zellen-ID für eine Koordinate.
  static int cellIdFor(double lat, double lon) {
    var latIdx = ((lat + 90.0) / cellSizeDeg).floor();
    if (latIdx < 0) latIdx = 0;
    if (latIdx >= latCells) latIdx = latCells - 1;
    var lonIdx = ((lon + 180.0) / cellSizeDeg).floor() % lonCells;
    if (lonIdx < 0) lonIdx += lonCells;
    return latIdx * lonCells + lonIdx;
  }

  /// Mittelpunkt der Zelle als (lat, lon).
  static (double, double) cellCenter(int cellId) {
    final latIdx = cellId ~/ lonCells;
    final lonIdx = cellId % lonCells;
    final lat = -90.0 + (latIdx + 0.5) * cellSizeDeg;
    final lon = -180.0 + (lonIdx + 0.5) * cellSizeDeg;
    return (lat, lon);
  }

  /// Ecken der Zelle: (südlicheBreite, westlicheLänge, nördlicheBreite, östlicheLänge).
  static (double, double, double, double) cellBounds(int cellId) {
    final latIdx = cellId ~/ lonCells;
    final lonIdx = cellId % lonCells;
    final south = -90.0 + latIdx * cellSizeDeg;
    final west = -180.0 + lonIdx * cellSizeDeg;
    return (south, west, south + cellSizeDeg, west + cellSizeDeg);
  }

  /// Näherungsfläche der Zelle in km² (breitengradabhängig).
  static double cellAreaKm2(int cellId) {
    final (lat, _) = cellCenter(cellId);
    final h = cellSizeDeg * _kmPerDegLat;
    final w = cellSizeDeg * _kmPerDegLat * math.cos(lat * math.pi / 180.0);
    return (h * w).abs();
  }
}
