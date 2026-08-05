/// Lokale SQLite-Datenbank (sqflite). Einzige Datenablage der App —
/// kein Backend, keine Cloud.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const int schemaVersion = 2;
  static Database? _db;

  /// Öffnet (bzw. liefert) die Datenbank. Von jedem Isolate aufrufbar;
  /// WAL erlaubt parallele Zugriffe aus App und Tracking-Service.
  static Future<Database> open() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'reise_tracker.db'),
      version: schemaVersion,
      onConfigure: (db) async {
        // PRAGMAs mit Rückgabewert müssen bei sqflite über rawQuery laufen,
        // sonst: "Queries can be performed using SQLiteDatabase query or
        // rawQuery methods only".
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.rawQuery('PRAGMA busy_timeout=5000');
      },
      onCreate: _createSchema,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v2: Region der Stadt speichern, damit ein Stadt-Besuch auch
          // ihre Region (und ihr Land) als besucht markieren kann.
          await db.execute(
              'ALTER TABLE city_visits ADD COLUMN region_id TEXT');
        }
      },
    );
    _db = db;
    return db;
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE track_points(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        ts INTEGER NOT NULL,
        accuracy REAL NOT NULL,
        processed INTEGER NOT NULL DEFAULT 0,
        cell_id TEXT,
        country_code TEXT,
        region_id TEXT
      )''');
    await db.execute(
        'CREATE INDEX idx_points_processed ON track_points(processed)');
    await db.execute('CREATE INDEX idx_points_ts ON track_points(ts)');

    await db.execute('''
      CREATE TABLE visited_cells(
        cell_id TEXT PRIMARY KEY,
        country_code TEXT,
        region_id TEXT,
        area_km2 REAL NOT NULL,
        first_ts INTEGER NOT NULL,
        last_ts INTEGER NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX idx_cells_country ON visited_cells(country_code)');

    await db.execute('''
      CREATE TABLE country_visits(
        country_code TEXT PRIMARY KEY,
        first_ts INTEGER,
        last_ts INTEGER,
        explored_km2 REAL NOT NULL DEFAULT 0,
        has_auto INTEGER NOT NULL DEFAULT 0,
        has_manual INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE region_visits(
        region_id TEXT PRIMARY KEY,
        country_code TEXT NOT NULL,
        first_ts INTEGER,
        last_ts INTEGER,
        explored_km2 REAL NOT NULL DEFAULT 0,
        has_auto INTEGER NOT NULL DEFAULT 0,
        has_manual INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
        'CREATE INDEX idx_region_visits_country ON region_visits(country_code)');

    await db.execute('''
      CREATE TABLE city_visits(
        city_id INTEGER PRIMARY KEY,
        country_code TEXT NOT NULL,
        region_id TEXT,
        first_ts INTEGER,
        status TEXT NOT NULL DEFAULT 'visited',
        source TEXT NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX idx_city_visits_country ON city_visits(country_code)');

    await db.execute('''
      CREATE TABLE visit_days(
        country_code TEXT NOT NULL,
        day TEXT NOT NULL,
        PRIMARY KEY(country_code, day)
      )''');

    await db.execute('''
      CREATE TABLE manual_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        country_code TEXT NOT NULL,
        region_id TEXT,
        city_id INTEGER,
        date_from TEXT,
        date_to TEXT,
        note TEXT,
        created_ts INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  // ---- Settings ----

  static Future<String?> getSetting(Database db, String key) async {
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  static Future<void> setSetting(Database db, String key, String value) =>
      db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace).then((_) {});

  /// Löscht sämtliche Nutzerdaten (nicht die statischen Assets).
  static Future<void> wipeAllData(Database db) async {
    await db.transaction((txn) async {
      for (final t in [
        'track_points',
        'visited_cells',
        'country_visits',
        'region_visits',
        'city_visits',
        'visit_days',
        'manual_entries',
      ]) {
        await txn.delete(t);
      }
    });
  }
}
