import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/geo_repository.dart';
import '../data/stats_service.dart';
import '../geo/geo_data.dart';
import '../services/backup_service.dart';
import 'settings.dart';

/// Geodaten (Assets) – einmalig geladen und im Speicher gehalten.
final geoDataProvider = FutureProvider<GeoData>((ref) => GeoRepository.load());

/// SQLite-Datenbank.
final databaseProvider =
    FutureProvider<AppDatabase>((ref) => AppDatabase.open());

/// Wird nach jedem Ingest / jeder manuellen Änderung erhöht,
/// damit Statistik-Provider neu laden.
final refreshTickProvider = StateProvider<int>((ref) => 0);

/// Komplette Statistik (Länder, Kontinente, Welt) aus den DB-Aggregaten.
final statsProvider = FutureProvider<StatsSnapshot>((ref) async {
  ref.watch(refreshTickProvider);
  final citiesPerCountry =
      ref.watch(settingsProvider.select((s) => s.citiesPerCountry));
  final geo = await ref.watch(geoDataProvider.future);
  final db = await ref.watch(databaseProvider.future);
  return StatsService.compute(
    geo: geo,
    countryStats: await db.countryStats(),
    regionStats: await db.regionStats(),
    visitDays: await db.countryVisitDays(),
    cityVisits: await db.cityVisits(),
    manualEntries: await db.manualEntries(),
    citiesPerCountry: citiesPerCountry,
  );
});

/// Erkundete Rasterzellen für das Fog-of-War-Overlay.
final exploredCellsProvider = FutureProvider<List<int>>((ref) async {
  ref.watch(refreshTickProvider);
  final db = await ref.watch(databaseProvider.future);
  return db.exploredCells();
});

/// Anzahl der Roh-Punkte (für die Einstellungen/Status-Anzeige).
final trackPointCountProvider = FutureProvider<int>((ref) async {
  ref.watch(refreshTickProvider);
  final db = await ref.watch(databaseProvider.future);
  return db.trackPointCount();
});

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  return BackupService(await ref.watch(databaseProvider.future));
});

