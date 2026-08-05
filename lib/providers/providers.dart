/// Riverpod-Provider: Geodaten, Datenbank, Services, Einstellungen, Statistik.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../geo/geo_assets.dart';
import '../services/backup_service.dart';
import '../services/stats_service.dart';

final geoDataProvider = FutureProvider<GeoData>((ref) => GeoData.load());

final databaseProvider = FutureProvider<Database>((ref) => AppDatabase.open());

final statsServiceProvider = FutureProvider<StatsService>((ref) async {
  final geo = await ref.watch(geoDataProvider.future);
  final db = await ref.watch(databaseProvider.future);
  return StatsService(db, geo);
});

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return BackupService(db);
});

/// Wird nach jeder Datenänderung erhöht; Statistik-Provider hängen daran.
final statsVersionProvider = StateProvider<int>((ref) => 0);

/// Einstellungen (persistiert in der settings-Tabelle).
class SettingsState {
  final bool trackingEnabled;
  final int intervalMin;
  final int topCities;
  final bool fogEnabled;

  const SettingsState({
    this.trackingEnabled = false,
    this.intervalMin = AppConst.defaultIntervalMin,
    this.topCities = AppConst.defaultTopCities,
    this.fogEnabled = false,
  });

  SettingsState copyWith({
    bool? trackingEnabled,
    int? intervalMin,
    int? topCities,
    bool? fogEnabled,
  }) =>
      SettingsState(
        trackingEnabled: trackingEnabled ?? this.trackingEnabled,
        intervalMin: intervalMin ?? this.intervalMin,
        topCities: topCities ?? this.topCities,
        fogEnabled: fogEnabled ?? this.fogEnabled,
      );
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _load();
    return const SettingsState();
  }

  Future<void> _load() async {
    final db = await ref.read(databaseProvider.future);
    final tracking = await AppDatabase.getSetting(db, 'tracking') == '1';
    final interval =
        int.tryParse(await AppDatabase.getSetting(db, 'interval') ?? '') ??
            AppConst.defaultIntervalMin;
    final topCities =
        int.tryParse(await AppDatabase.getSetting(db, 'topCities') ?? '') ??
            AppConst.defaultTopCities;
    final fog = await AppDatabase.getSetting(db, 'fog') == '1';
    state = SettingsState(
      trackingEnabled: tracking,
      intervalMin: interval,
      topCities: topCities,
      fogEnabled: fog,
    );
  }

  Future<void> _persist(String key, String value) async {
    final db = await ref.read(databaseProvider.future);
    await AppDatabase.setSetting(db, key, value);
  }

  void setTracking(bool on) {
    state = state.copyWith(trackingEnabled: on);
    _persist('tracking', on ? '1' : '0');
  }

  void setInterval(int min) {
    state = state.copyWith(intervalMin: min.clamp(10, 15));
    _persist('interval', state.intervalMin.toString());
  }

  void setTopCities(int n) {
    state = state.copyWith(topCities: n);
    _persist('topCities', n.toString());
  }

  void setFog(bool on) {
    state = state.copyWith(fogEnabled: on);
    _persist('fog', on ? '1' : '0');
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

/// Statistik aller Länder (liest nur Aggregat-Tabellen).
final countryStatsProvider =
    FutureProvider<Map<String, CountryStats>>((ref) async {
  ref.watch(statsVersionProvider);
  final topN = ref.watch(settingsProvider.select((s) => s.topCities));
  final stats = await ref.watch(statsServiceProvider.future);
  return stats.allCountryStats(topN: topN);
});

final worldStatsProvider = FutureProvider<WorldStats>((ref) async {
  final byCountry = await ref.watch(countryStatsProvider.future);
  final stats = await ref.watch(statsServiceProvider.future);
  return stats.worldStats(byCountry);
});

/// Erkundete Zellen (Fog of War).
final visitedCellsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(statsVersionProvider);
  final stats = await ref.watch(statsServiceProvider.future);
  return stats.visitedCellIds();
});

final manualEntriesProvider = FutureProvider<List<ManualEntry>>((ref) async {
  ref.watch(statsVersionProvider);
  final stats = await ref.watch(statsServiceProvider.future);
  return stats.manualEntries();
});

/// Besuchte Regionen eines Landes.
final visitedRegionsProvider =
    FutureProvider.family<Set<String>, String>((ref, countryCode) async {
  ref.watch(statsVersionProvider);
  final stats = await ref.watch(statsServiceProvider.future);
  return stats.visitedRegionIds(countryCode);
});

/// Alle besuchten Städte (grüne Punkte auf der Karte).
final visitedCityIdsProvider = FutureProvider<Set<int>>((ref) async {
  ref.watch(statsVersionProvider);
  final stats = await ref.watch(statsServiceProvider.future);
  return stats.allVisitedCityIds();
});

/// Städte-Besuchsstatus eines Landes.
final cityVisitsProvider =
    FutureProvider.family<Map<int, CityVisit>, String>((ref, code) async {
  ref.watch(statsVersionProvider);
  final stats = await ref.watch(statsServiceProvider.future);
  return stats.cityVisits(code);
});
