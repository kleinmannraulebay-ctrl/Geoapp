/// Inkrementelle Statistik-Fortschreibung.
///
/// Der Tracking-Service schreibt nur Roh-Punkte (`processed = 0`).
/// [processPendingPoints] ordnet sie (im Isolate) Land/Region/Zelle/Städten
/// zu und schreibt die Aggregat-Tabellen fort — Statistiken werden also nie
/// über alle Punkte neu berechnet.
library;

import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../geo/exploration_grid.dart';
import '../geo/assigner.dart';
import '../geo/geo_assets.dart';
import '../geo/geo_models.dart';

class StatsService {
  final Database db;
  final GeoData geo;

  StatsService(this.db, this.geo);

  /// Region, in der eine Stadt liegt (per Punkt-in-Polygon, mit Länder-Check).
  String? regionIdForCity(City city) {
    final r = geo.regionIndex.locate(city.lon, city.lat);
    return (r != null && r.countryCode == city.countryCode) ? r.id : null;
  }

  // ------------------------------------------------------------------
  // Punkte verarbeiten
  // ------------------------------------------------------------------

  /// Verarbeitet alle unverarbeiteten Punkte. Liefert die Anzahl.
  Future<int> processPendingPoints() async {
    await _backfillCityRegions();
    await _ensureGridResolution();
    var total = 0;
    while (true) {
      final rows = await db.query('track_points',
          where: 'processed = 0', orderBy: 'ts ASC', limit: 500);
      if (rows.isEmpty) break;
      final raw = [
        for (final r in rows)
          RawPoint(r['id'] as int, r['lat'] as double, r['lon'] as double,
              r['ts'] as int),
      ];
      final assigned = await assignBatch(geo, raw);
      await db.transaction((txn) async {
        for (final a in assigned) {
          await _applyPoint(txn, a);
        }
      });
      total += assigned.length;
      if (rows.length < 500) break;
    }
    return total;
  }

  Future<void> _applyPoint(Transaction txn, AssignedPoint a) async {
    await txn.update(
      'track_points',
      {
        'processed': 1,
        'cell_id': a.cellId,
        'country_code': a.countryCode,
        'region_id': a.regionId,
      },
      where: 'id = ?',
      whereArgs: [a.id],
    );

    // --- Rasterzelle ---
    final cellRows = await txn.query('visited_cells',
        columns: ['cell_id'], where: 'cell_id = ?', whereArgs: [a.cellId]);
    final isNewCell = cellRows.isEmpty;
    if (isNewCell) {
      await txn.insert('visited_cells', {
        'cell_id': a.cellId,
        'country_code': a.countryCode,
        'region_id': a.regionId,
        'area_km2': a.cellAreaKm2,
        'first_ts': a.ts,
        'last_ts': a.ts,
      });
    } else {
      await txn.rawUpdate(
          'UPDATE visited_cells SET last_ts = MAX(last_ts, ?) WHERE cell_id = ?',
          [a.ts, a.cellId]);
    }

    // --- Land ---
    final code = a.countryCode;
    if (code != null) {
      final addedArea = isNewCell ? a.cellAreaKm2 : 0.0;
      await txn.rawInsert('''
        INSERT INTO country_visits(country_code, first_ts, last_ts, explored_km2, has_auto)
        VALUES(?, ?, ?, ?, 1)
        ON CONFLICT(country_code) DO UPDATE SET
          first_ts = MIN(COALESCE(first_ts, 1e15), excluded.first_ts),
          last_ts = MAX(COALESCE(last_ts, 0), excluded.last_ts),
          explored_km2 = explored_km2 + ?,
          has_auto = 1
      ''', [code, a.ts, a.ts, addedArea, addedArea]);

      final day = _dayString(a.ts);
      await txn.rawInsert(
          'INSERT OR IGNORE INTO visit_days(country_code, day) VALUES(?, ?)',
          [code, day]);

      // --- Region ---
      final regionId = a.regionId;
      if (regionId != null) {
        await txn.rawInsert('''
          INSERT INTO region_visits(region_id, country_code, first_ts, last_ts, explored_km2, has_auto)
          VALUES(?, ?, ?, ?, ?, 1)
          ON CONFLICT(region_id) DO UPDATE SET
            first_ts = MIN(COALESCE(first_ts, 1e15), excluded.first_ts),
            last_ts = MAX(COALESCE(last_ts, 0), excluded.last_ts),
            explored_km2 = explored_km2 + ?,
            has_auto = 1
        ''', [regionId, code, a.ts, a.ts, addedArea, addedArea]);
      }
    }

    // --- Städte (Auto-Besuch) ---
    for (final cityId in a.cityIds) {
      final city = geo.cityById[cityId];
      if (city == null) continue;
      // Nur einfügen, wenn es noch keinen Eintrag gibt: manuell gesetzte
      // Häkchen (und manuell entfernte, status='dismissed') bleiben
      // unangetastet.
      await txn.rawInsert('''
        INSERT OR IGNORE INTO city_visits(city_id, country_code, region_id, first_ts, status, source)
        VALUES(?, ?, ?, ?, 'visited', 'auto')
      ''', [cityId, city.countryCode, regionIdForCity(city), a.ts]);
      await txn.rawUpdate('''
        UPDATE city_visits SET first_ts = MIN(COALESCE(first_ts, 1e15), ?)
        WHERE city_id = ? AND source = 'auto'
      ''', [a.ts, cityId]);
    }
  }

  /// Wurde die Rasterauflösung geändert (App-Update), sind gespeicherte
  /// Zell-IDs wertlos: Auto-Aggregate verwerfen und alle Roh-Punkte neu
  /// verarbeiten (manuelle Einträge und Städte-Häkchen bleiben erhalten).
  Future<void> _ensureGridResolution() async {
    const current = ExplorationGrid.res;
    final stored = await AppDatabase.getSetting(db, 'grid_res');
    if (stored != null && double.tryParse(stored) == current) return;
    if (stored == null) {
      final rows =
          await db.rawQuery('SELECT COUNT(*) AS n FROM visited_cells');
      final hasCells = ((rows.first['n'] as int?) ?? 0) > 0;
      if (!hasCells) {
        // Frische Installation – nichts neu zu berechnen.
        await AppDatabase.setSetting(db, 'grid_res', current.toString());
        return;
      }
    }
    await db.transaction((txn) async {
      await txn.delete('visited_cells');
      await txn.delete('visit_days');
      await txn.rawUpdate(
          'UPDATE country_visits SET has_auto = 0, explored_km2 = 0');
      await txn.delete('country_visits',
          where: 'has_manual = 0');
      await txn.rawUpdate(
          'UPDATE region_visits SET has_auto = 0, explored_km2 = 0');
      await txn.delete('region_visits', where: 'has_manual = 0');
      await txn.rawUpdate('UPDATE track_points SET processed = 0');
    });
    await AppDatabase.setSetting(db, 'grid_res', current.toString());
    // Die Punkte verarbeitet processPendingPoints() im Anschluss.
  }

  /// Einmalige Nacharbeit nach der Schema-Migration v2: Region der bereits
  /// gespeicherten Städte-Besuche nachtragen und für manuell abgehakte
  /// Städte Region + Land als besucht markieren.
  Future<void> _backfillCityRegions() async {
    final rows = await db.query('city_visits', where: 'region_id IS NULL');
    for (final r in rows) {
      final city = geo.cityById[r['city_id'] as int];
      if (city == null) continue;
      final regionId = regionIdForCity(city);
      if (regionId == null) continue;
      await db.update('city_visits', {'region_id': regionId},
          where: 'city_id = ?', whereArgs: [r['city_id']]);
      if (r['status'] == 'visited' && r['source'] == 'manual') {
        await _applyManualEffects(city.countryCode, regionId, null, null, null,
            (r['first_ts'] as int?) ?? DateTime.now().millisecondsSinceEpoch);
      }
    }
  }

  static String _dayString(int tsMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(tsMillis);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  // ------------------------------------------------------------------
  // Manuelle Einträge
  // ------------------------------------------------------------------

  Future<int> addManualEntry({
    required String type,
    required String countryCode,
    String? regionId,
    int? cityId,
    String? dateFrom,
    String? dateTo,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Stadt impliziert ihre Region: fehlt die Region, aus der Stadt ableiten.
    if (cityId != null && regionId == null) {
      final city = geo.cityById[cityId];
      if (city != null) regionId = regionIdForCity(city);
    }
    final id = await db.insert('manual_entries', {
      'type': type,
      'country_code': countryCode,
      'region_id': regionId,
      'city_id': cityId,
      'date_from': dateFrom,
      'date_to': dateTo,
      'note': note,
      'created_ts': now,
    });
    await _applyManualEffects(
        countryCode, regionId, cityId, dateFrom, dateTo, now);
    return id;
  }

  Future<void> updateManualEntry(ManualEntry entry) async {
    await db.update(
      'manual_entries',
      {
        'type': entry.type,
        'country_code': entry.countryCode,
        'region_id': entry.regionId,
        'city_id': entry.cityId,
        'date_from': entry.dateFrom,
        'date_to': entry.dateTo,
        'note': entry.note,
      },
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    // Flags neu ableiten (der alte Bezug kann weggefallen sein) und die
    // Wirkung des geänderten Eintrags anwenden (legt fehlende
    // country/region_visits-Zeilen an, merged Zeiträume).
    await recomputeManualFlags();
    await _applyManualEffects(entry.countryCode, entry.regionId, entry.cityId,
        entry.dateFrom, entry.dateTo, entry.createdTs);
  }

  Future<void> deleteManualEntry(int id) async {
    await db.delete('manual_entries', where: 'id = ?', whereArgs: [id]);
    await recomputeManualFlags();
  }

  Future<List<ManualEntry>> manualEntries() async {
    final rows = await db.query('manual_entries', orderBy: 'created_ts DESC');
    return [for (final r in rows) ManualEntry.fromRow(r)];
  }

  Future<void> _applyManualEffects(String countryCode, String? regionId,
      int? cityId, String? dateFrom, String? dateTo, int createdTs) async {
    final ts = _entryTs(dateFrom, dateTo, createdTs);
    await db.rawInsert('''
      INSERT INTO country_visits(country_code, first_ts, last_ts, has_manual)
      VALUES(?, ?, ?, 1)
      ON CONFLICT(country_code) DO UPDATE SET
        first_ts = MIN(COALESCE(first_ts, 1e15), excluded.first_ts),
        last_ts = MAX(COALESCE(last_ts, 0), excluded.last_ts),
        has_manual = 1
    ''', [countryCode, ts.$1, ts.$2]);

    if (regionId != null) {
      await db.rawInsert('''
        INSERT INTO region_visits(region_id, country_code, first_ts, last_ts, has_manual)
        VALUES(?, ?, ?, ?, 1)
        ON CONFLICT(region_id) DO UPDATE SET
          first_ts = MIN(COALESCE(first_ts, 1e15), excluded.first_ts),
          last_ts = MAX(COALESCE(last_ts, 0), excluded.last_ts),
          has_manual = 1
      ''', [regionId, countryCode, ts.$1, ts.$2]);
    }

    if (cityId != null) {
      await db.rawInsert('''
        INSERT INTO city_visits(city_id, country_code, region_id, first_ts, status, source)
        VALUES(?, ?, ?, ?, 'visited', 'manual')
        ON CONFLICT(city_id) DO UPDATE SET
          status = 'visited',
          source = 'manual',
          region_id = COALESCE(city_visits.region_id, excluded.region_id),
          first_ts = MIN(COALESCE(first_ts, 1e15), excluded.first_ts)
      ''', [cityId, countryCode, regionId, ts.$1]);
    }
  }

  (int, int) _entryTs(String? dateFrom, String? dateTo, int fallback) {
    int? parse(String? s) =>
        s == null ? null : DateTime.tryParse(s)?.millisecondsSinceEpoch;
    final from = parse(dateFrom) ?? parse(dateTo) ?? fallback;
    final to = parse(dateTo) ?? from;
    return (from, to);
  }

  /// Baut die `has_manual`-Flags nach Löschen/Bearbeiten neu auf.
  /// Rein manuelle Besuche ohne verbleibende Einträge werden entfernt;
  /// Auto-Daten (`has_auto`, Zellen, Punkte) bleiben unberührt.
  Future<void> recomputeManualFlags() async {
    await db.transaction((txn) async {
      // Manuell besuchte Städte stützen die Besucht-Markierung ihres
      // Landes bzw. ihrer Region ebenfalls (Stadt ⇒ Region ⇒ Land).
      await txn.rawUpdate('''
        UPDATE country_visits SET has_manual =
          EXISTS(SELECT 1 FROM manual_entries m
                 WHERE m.country_code = country_visits.country_code)
          OR EXISTS(SELECT 1 FROM city_visits cv
                 WHERE cv.country_code = country_visits.country_code
                   AND cv.status = 'visited' AND cv.source = 'manual')
      ''');
      await txn.delete('country_visits',
          where: 'has_auto = 0 AND has_manual = 0');

      await txn.rawUpdate('''
        UPDATE region_visits SET has_manual =
          EXISTS(SELECT 1 FROM manual_entries m
                 WHERE m.region_id = region_visits.region_id)
          OR EXISTS(SELECT 1 FROM city_visits cv
                 WHERE cv.region_id = region_visits.region_id
                   AND cv.status = 'visited' AND cv.source = 'manual')
      ''');
      await txn.delete('region_visits',
          where: 'has_auto = 0 AND has_manual = 0');

      // Städte-Häkchen bleiben beim Löschen eines manuellen Eintrags
      // bewusst bestehen: manuelle Häkchen aus der Checkliste und aus
      // Einträgen sind nicht unterscheidbar, und ein versehentlich
      // entferntes Häkchen wäre ärgerlicher. Abwählen geht jederzeit
      // über die Städte-Checkliste.
    });
  }

  // ------------------------------------------------------------------
  // Städte-Checkliste
  // ------------------------------------------------------------------

  /// Stadt manuell abhaken / abwählen. Manuelle Entscheidungen überleben
  /// das Auto-Tracking (dismissed-Zeilen blockieren INSERT OR IGNORE).
  /// Abhaken markiert auch Region und Land der Stadt als besucht.
  Future<void> setCityVisited(int cityId, bool visited) async {
    final city = geo.cityById[cityId];
    if (city == null) return;
    final regionId = regionIdForCity(city);
    if (visited) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.rawInsert('''
        INSERT INTO city_visits(city_id, country_code, region_id, first_ts, status, source)
        VALUES(?, ?, ?, ?, 'visited', 'manual')
        ON CONFLICT(city_id) DO UPDATE SET
          status = 'visited',
          source = 'manual',
          region_id = COALESCE(city_visits.region_id, excluded.region_id)
      ''', [cityId, city.countryCode, regionId, now]);
      // Stadt besucht ⇒ Region + Land besucht.
      await _applyManualEffects(
          city.countryCode, regionId, null, null, null, now);
    } else {
      await db.rawInsert('''
        INSERT INTO city_visits(city_id, country_code, region_id, first_ts, status, source)
        VALUES(?, ?, ?, NULL, 'dismissed', 'manual')
        ON CONFLICT(city_id) DO UPDATE SET status = 'dismissed', source = 'manual'
      ''', [cityId, city.countryCode, regionId]);
    }
  }

  /// Alle besuchten Städte-IDs (für die grünen Punkte auf der Karte).
  Future<Set<int>> allVisitedCityIds() async {
    final rows = await db.query('city_visits',
        columns: ['city_id'], where: "status = 'visited'");
    return {for (final r in rows) r['city_id'] as int};
  }

  Future<Map<int, CityVisit>> cityVisits(String countryCode) async {
    final rows = await db.query('city_visits',
        where: 'country_code = ?', whereArgs: [countryCode]);
    return {
      for (final r in rows)
        r['city_id'] as int: CityVisit(
          cityId: r['city_id'] as int,
          firstTs: r['first_ts'] as int?,
          status: r['status'] as String,
          source: r['source'] as String,
        ),
    };
  }

  // ------------------------------------------------------------------
  // Statistik-Abfragen (lesen nur Aggregate — schnell)
  // ------------------------------------------------------------------

  Future<Map<String, CountryStats>> allCountryStats({int topN = 25}) async {
    final visitRows = await db.query('country_visits');
    final visits = {for (final r in visitRows) r['country_code'] as String: r};

    final regionRows = await db.rawQuery(
        'SELECT country_code, COUNT(*) AS n FROM region_visits GROUP BY country_code');
    final regionCounts = {
      for (final r in regionRows) r['country_code'] as String: r['n'] as int,
    };

    final dayRows = await db.rawQuery(
        'SELECT country_code, COUNT(*) AS n FROM visit_days GROUP BY country_code');
    final dayCounts = {
      for (final r in dayRows) r['country_code'] as String: r['n'] as int,
    };

    final cityRows = await db.query('city_visits',
        columns: ['city_id', 'country_code'],
        where: "status = 'visited'");
    final visitedCityIds = <String, Set<int>>{};
    for (final r in cityRows) {
      visitedCityIds
          .putIfAbsent(r['country_code'] as String, () => {})
          .add(r['city_id'] as int);
    }

    final result = <String, CountryStats>{};
    for (final country in geo.countries) {
      final v = visits[country.id];
      final listed = geo.topCities(country.id, topN);
      final visitedSet = visitedCityIds[country.id] ?? const <int>{};
      final citiesVisited =
          listed.where((c) => visitedSet.contains(c.id)).length;
      result[country.id] = CountryStats(
        code: country.id,
        name: country.name,
        continent: country.continent,
        areaKm2: country.areaKm2,
        visitDays: dayCounts[country.id] ?? 0,
        exploredKm2: v == null ? 0 : (v['explored_km2'] as num).toDouble(),
        regionsVisited: regionCounts[country.id] ?? 0,
        regionsTotal: geo.regionsByCountry[country.id]?.length ?? 0,
        citiesVisited: citiesVisited,
        citiesListed: listed.length,
        firstTs: v?['first_ts'] as int?,
        lastTs: v?['last_ts'] as int?,
        hasAuto: (v?['has_auto'] as int? ?? 0) == 1,
        hasManual: (v?['has_manual'] as int? ?? 0) == 1,
      );
    }
    return result;
  }

  Future<Set<String>> visitedRegionIds(String countryCode) async {
    final rows = await db.query('region_visits',
        columns: ['region_id'],
        where: 'country_code = ?',
        whereArgs: [countryCode]);
    return {for (final r in rows) r['region_id'] as String};
  }

  Future<WorldStats> worldStats(Map<String, CountryStats> byCountry) async {
    const order = [
      'Europa',
      'Asien',
      'Afrika',
      'Nordamerika',
      'Südamerika',
      'Ozeanien',
      'Antarktis',
    ];
    final grouped = <String, List<CountryStats>>{};
    for (final s in byCountry.values) {
      grouped.putIfAbsent(s.continent, () => []).add(s);
    }
    final continents = <ContinentStats>[];
    for (final name in order) {
      final list = grouped[name] ?? const <CountryStats>[];
      if (list.isEmpty && name != 'Antarktis') continue;
      continents.add(ContinentStats(
        name: name,
        countriesVisited: list.where((s) => s.visited).length,
        countriesTotal: list.length,
        citiesVisited: list.fold(0, (a, s) => a + s.citiesVisited),
        citiesListed: list.fold(0, (a, s) => a + s.citiesListed),
        exploredKm2: list.fold(0.0, (a, s) => a + s.exploredKm2),
        areaKm2: list.fold(0.0, (a, s) => a + s.areaKm2),
      ));
    }
    final all = byCountry.values;
    return WorldStats(
      countriesVisited: all.where((s) => s.visited).length,
      countriesTotal: all.length,
      citiesVisited: all.fold(0, (a, s) => a + s.citiesVisited),
      citiesListed: all.fold(0, (a, s) => a + s.citiesListed),
      exploredKm2: all.fold(0.0, (a, s) => a + s.exploredKm2),
      areaKm2: all.fold(0.0, (a, s) => a + s.areaKm2),
      continents: continents,
    );
  }

  /// Alle erkundeten Zell-IDs (für den Fog-of-War-Layer; der Aufrufer
  /// filtert auf den sichtbaren Ausschnitt).
  Future<List<String>> visitedCellIds({int limit = 200000}) async {
    final rows =
        await db.query('visited_cells', columns: ['cell_id'], limit: limit);
    return [for (final r in rows) r['cell_id'] as String];
  }
}
