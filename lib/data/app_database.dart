import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../geo/classifier.dart';

/// Quelle eines Städte-Hakens / Eintrags.
class VisitSource {
  static const auto = 'auto';
  static const manual = 'manual';

  /// Manuell entfernt – Auto-Tracking darf den Haken nicht wieder setzen.
  static const suppressed = 'suppressed';
}

class CityVisit {
  final int cityId;
  final String source;
  final int? visitedAt;
  const CityVisit(this.cityId, this.source, this.visitedAt);
}

class ManualEntry {
  final int? id;
  final String country;
  final String? region;
  final int? cityId;
  final String? dateFrom; // 'yyyy-MM-dd'
  final String? dateTo;
  final String? note;
  final int createdAt;

  const ManualEntry({
    this.id,
    required this.country,
    this.region,
    this.cityId,
    this.dateFrom,
    this.dateTo,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'country': country,
        'region': region,
        'city_id': cityId,
        'date_from': dateFrom,
        'date_to': dateTo,
        'note': note,
        'created_at': createdAt,
      };

  static ManualEntry fromMap(Map<String, Object?> m) => ManualEntry(
        id: m['id'] as int?,
        country: m['country'] as String,
        region: m['region'] as String?,
        cityId: m['city_id'] as int?,
        dateFrom: m['date_from'] as String?,
        dateTo: m['date_to'] as String?,
        note: m['note'] as String?,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

/// Inkrementell gepflegte Aggregate pro Land bzw. Region.
class AreaStats {
  final String id;
  final String? country;
  final double exploredKm2;
  final int cellCount;
  final int? firstTs;
  final int? lastTs;
  const AreaStats(this.id, this.country, this.exploredKm2, this.cellCount,
      this.firstTs, this.lastTs);
}

class AppDatabase {
  static const _dbName = 'reise_tracker.db';
  final Database db;

  AppDatabase._(this.db);

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(path, version: 1, onCreate: _onCreate);
    return AppDatabase._(db);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE track_points(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        accuracy REAL NOT NULL,
        processed INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
        'CREATE INDEX idx_points_processed ON track_points(processed)');
    await db.execute('''
      CREATE TABLE explored_cells(
        cell INTEGER PRIMARY KEY,
        country TEXT,
        region TEXT,
        area_km2 REAL NOT NULL,
        first_ts INTEGER,
        last_ts INTEGER
      )''');
    await db.execute('CREATE INDEX idx_cells_country ON explored_cells(country)');
    await db.execute('''
      CREATE TABLE country_stats(
        country TEXT PRIMARY KEY,
        explored_km2 REAL NOT NULL DEFAULT 0,
        cell_count INTEGER NOT NULL DEFAULT 0,
        first_ts INTEGER,
        last_ts INTEGER
      )''');
    await db.execute('''
      CREATE TABLE region_stats(
        region TEXT PRIMARY KEY,
        country TEXT,
        explored_km2 REAL NOT NULL DEFAULT 0,
        cell_count INTEGER NOT NULL DEFAULT 0,
        first_ts INTEGER,
        last_ts INTEGER
      )''');
    await db.execute('''
      CREATE TABLE country_days(
        country TEXT NOT NULL,
        day TEXT NOT NULL,
        PRIMARY KEY(country, day)
      )''');
    await db.execute('''
      CREATE TABLE city_visits(
        city_id INTEGER PRIMARY KEY,
        source TEXT NOT NULL,
        visited_at INTEGER
      )''');
    await db.execute('''
      CREATE TABLE manual_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        country TEXT NOT NULL,
        region TEXT,
        city_id INTEGER,
        date_from TEXT,
        date_to TEXT,
        note TEXT,
        created_at INTEGER NOT NULL
      )''');
  }

  // ------------------------------------------------------------ Tracking

  Future<void> insertTrackPoint(
      double lat, double lon, int timestamp, double accuracy) async {
    await db.insert('track_points', {
      'lat': lat,
      'lon': lon,
      'timestamp': timestamp,
      'accuracy': accuracy,
    });
  }

  Future<List<RawPoint>> unprocessedPoints({int limit = 2000}) async {
    final rows = await db.query('track_points',
        where: 'processed = 0', orderBy: 'id', limit: limit);
    return [
      for (final r in rows)
        RawPoint(r['id'] as int, r['lat'] as double, r['lon'] as double,
            r['timestamp'] as int)
    ];
  }

  Future<int> trackPointCount() async {
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM track_points')) ??
        0;
  }

  Future<Map<String, Object?>?> lastTrackPoint() async {
    final rows =
        await db.query('track_points', orderBy: 'timestamp DESC', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ------------------------------------------------------------ Ingest

  /// Wendet Zuordnungs-Ergebnisse transaktional an und schreibt die
  /// Aggregate inkrementell fort. Liefert die Anzahl neuer Zellen.
  Future<int> applyClassified(List<ClassifiedPoint> points) async {
    var newCells = 0;
    await db.transaction((txn) async {
      for (final cp in points) {
        // Neue Rasterzelle?
        final existing = await txn.query('explored_cells',
            columns: ['cell', 'last_ts'],
            where: 'cell = ?',
            whereArgs: [cp.cellId]);
        if (existing.isEmpty) {
          newCells++;
          await txn.insert('explored_cells', {
            'cell': cp.cellId,
            'country': cp.country,
            'region': cp.region,
            'area_km2': cp.cellAreaKm2,
            'first_ts': cp.timestamp,
            'last_ts': cp.timestamp,
          });
          // Hinweis: klassisches INSERT OR IGNORE + UPDATE statt Upsert-Syntax,
          // da Android 8/9 nur SQLite < 3.24 mitbringt.
          if (cp.country != null) {
            await txn.rawInsert(
                'INSERT OR IGNORE INTO country_stats(country) VALUES(?)',
                [cp.country]);
            await txn.rawUpdate('''
              UPDATE country_stats SET
                explored_km2 = explored_km2 + ?,
                cell_count = cell_count + 1,
                first_ts = MIN(COALESCE(first_ts, ?), ?),
                last_ts = MAX(COALESCE(last_ts, 0), ?)
              WHERE country = ?
            ''', [
              cp.cellAreaKm2,
              cp.timestamp,
              cp.timestamp,
              cp.timestamp,
              cp.country
            ]);
          }
          if (cp.region != null) {
            await txn.rawInsert(
                'INSERT OR IGNORE INTO region_stats(region, country) VALUES(?, ?)',
                [cp.region, cp.country]);
            await txn.rawUpdate('''
              UPDATE region_stats SET
                explored_km2 = explored_km2 + ?,
                cell_count = cell_count + 1,
                first_ts = MIN(COALESCE(first_ts, ?), ?),
                last_ts = MAX(COALESCE(last_ts, 0), ?)
              WHERE region = ?
            ''', [
              cp.cellAreaKm2,
              cp.timestamp,
              cp.timestamp,
              cp.timestamp,
              cp.region
            ]);
          }
        } else {
          await txn.update('explored_cells', {'last_ts': cp.timestamp},
              where: 'cell = ?', whereArgs: [cp.cellId]);
          if (cp.country != null) {
            await txn.rawUpdate(
                'UPDATE country_stats SET last_ts = MAX(COALESCE(last_ts,0), ?) WHERE country = ?',
                [cp.timestamp, cp.country]);
          }
          if (cp.region != null) {
            await txn.rawUpdate(
                'UPDATE region_stats SET last_ts = MAX(COALESCE(last_ts,0), ?) WHERE region = ?',
                [cp.timestamp, cp.region]);
          }
        }

        // Besuchstag je Land (lokale Zeit).
        if (cp.country != null) {
          final d =
              DateTime.fromMillisecondsSinceEpoch(cp.timestamp).toLocal();
          final day = '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';
          await txn.rawInsert(
              'INSERT OR IGNORE INTO country_days(country, day) VALUES(?, ?)',
              [cp.country, day]);
        }

        // Städte: nur setzen, wenn noch kein Eintrag existiert – manuelle
        // Häkchen und manuell Entferntes ('suppressed') bleiben unberührt.
        for (final cityId in cp.cityIds) {
          await txn.rawInsert(
              'INSERT OR IGNORE INTO city_visits(city_id, source, visited_at) '
              "VALUES(?, '${VisitSource.auto}', ?)",
              [cityId, cp.timestamp]);
        }

        await txn.update('track_points', {'processed': 1},
            where: 'id = ?', whereArgs: [cp.pointId]);
      }
    });
    return newCells;
  }

  // ------------------------------------------------------------ Statistik

  Future<Map<String, AreaStats>> countryStats() async {
    final rows = await db.query('country_stats');
    return {
      for (final r in rows)
        r['country'] as String: AreaStats(
          r['country'] as String,
          null,
          (r['explored_km2'] as num).toDouble(),
          r['cell_count'] as int,
          r['first_ts'] as int?,
          r['last_ts'] as int?,
        )
    };
  }

  Future<Map<String, AreaStats>> regionStats() async {
    final rows = await db.query('region_stats');
    return {
      for (final r in rows)
        r['region'] as String: AreaStats(
          r['region'] as String,
          r['country'] as String?,
          (r['explored_km2'] as num).toDouble(),
          r['cell_count'] as int,
          r['first_ts'] as int?,
          r['last_ts'] as int?,
        )
    };
  }

  Future<Map<String, int>> countryVisitDays() async {
    final rows = await db.rawQuery(
        'SELECT country, COUNT(*) AS days FROM country_days GROUP BY country');
    return {
      for (final r in rows) r['country'] as String: r['days'] as int,
    };
  }

  Future<Map<int, CityVisit>> cityVisits() async {
    final rows = await db.query('city_visits');
    return {
      for (final r in rows)
        r['city_id'] as int: CityVisit(r['city_id'] as int,
            r['source'] as String, r['visited_at'] as int?)
    };
  }

  /// Erkundete Zellen (für Fog-of-War-Overlay), optional auf ein Land begrenzt.
  Future<List<int>> exploredCells({String? country}) async {
    final rows = await db.query('explored_cells',
        columns: ['cell'],
        where: country != null ? 'country = ?' : null,
        whereArgs: country != null ? [country] : null);
    return [for (final r in rows) r['cell'] as int];
  }

  // ------------------------------------------------------------ Städte

  Future<void> setCityVisitManual(int cityId, bool visited) async {
    if (visited) {
      await db.insert(
          'city_visits',
          {
            'city_id': cityId,
            'source': VisitSource.manual,
            'visited_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      // Manuell entfernt: Auto darf nicht erneut abhaken.
      await db.insert(
          'city_visits',
          {
            'city_id': cityId,
            'source': VisitSource.suppressed,
            'visited_at': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ------------------------------------------------------------ Manuell

  Future<int> insertManualEntry(ManualEntry e) =>
      db.insert('manual_entries', e.toMap());

  Future<void> updateManualEntry(ManualEntry e) async {
    await db.update('manual_entries', e.toMap(),
        where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> deleteManualEntry(int id) async {
    await db.delete('manual_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ManualEntry>> manualEntries({String? country}) async {
    final rows = await db.query('manual_entries',
        where: country != null ? 'country = ?' : null,
        whereArgs: country != null ? [country] : null,
        orderBy: 'created_at DESC');
    return [for (final r in rows) ManualEntry.fromMap(r)];
  }

  // ------------------------------------------------------------ Backup

  static const _exportTables = [
    'track_points',
    'explored_cells',
    'country_stats',
    'region_stats',
    'country_days',
    'city_visits',
    'manual_entries',
  ];

  Future<Map<String, Object?>> exportAll() async {
    final out = <String, Object?>{
      'app': 'reise_tracker',
      'schema': 1,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    for (final t in _exportTables) {
      out[t] = await db.query(t);
    }
    return out;
  }

  Future<void> importAll(Map<String, Object?> data) async {
    if (data['app'] != 'reise_tracker') {
      throw const FormatException('Keine gültige Reise-Tracker-Sicherung.');
    }
    await db.transaction((txn) async {
      for (final t in _exportTables) {
        await txn.delete(t);
        final rows = (data[t] as List?) ?? const [];
        final batch = txn.batch();
        for (final r in rows) {
          batch.insert(t, Map<String, Object?>.from(r as Map));
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<void> deleteAllData() async {
    await db.transaction((txn) async {
      for (final t in _exportTables) {
        await txn.delete(t);
      }
    });
  }
}
