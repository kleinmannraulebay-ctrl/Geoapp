import 'dart:isolate';

import '../data/app_database.dart';
import '../geo/classifier.dart';
import '../geo/geo_data.dart';

/// Verarbeitet unklassifizierte Roh-Punkte:
/// Zuordnung (Land/Region/Zelle/Städte) läuft in einem Isolate,
/// die DB-Schreibvorgänge danach transaktional im Hauptisolate.
class IngestService {
  final AppDatabase dbase;
  final GeoData geo;
  bool _running = false;

  IngestService(this.dbase, this.geo);

  /// Liefert die Anzahl verarbeiteter Punkte.
  Future<int> ingestPending() async {
    if (_running) return 0;
    _running = true;
    try {
      var total = 0;
      while (true) {
        final points = await dbase.unprocessedPoints(limit: 500);
        if (points.isEmpty) break;
        final g = geo;
        final classified =
            await Isolate.run(() => classifyPoints(g, points));
        await dbase.applyClassified(classified);
        total += points.length;
        if (points.length < 500) break;
      }
      return total;
    } finally {
      _running = false;
    }
  }
}
