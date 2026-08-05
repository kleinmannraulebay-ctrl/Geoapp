/// Export/Import der kompletten Datenbank als JSON über den
/// Android-Dateidialog (Storage Access Framework – keine Extra-Permissions,
/// kein Internet).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';

class BackupService {
  final Database db;
  BackupService(this.db);

  static const _tables = [
    'track_points',
    'visited_cells',
    'country_visits',
    'region_visits',
    'city_visits',
    'visit_days',
    'manual_entries',
    'settings',
  ];

  /// Exportiert alle Tabellen als JSON. Liefert den gewählten Pfad oder null.
  Future<String?> exportToFile() async {
    final data = <String, Object>{
      'app': 'reise_tracker',
      'schema': 1,
      'exported': DateTime.now().toIso8601String(),
    };
    for (final t in _tables) {
      data[t] = await db.query(t);
    }
    final bytes =
        Uint8List.fromList(utf8.encode(const JsonEncoder().convert(data)));
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 10);
    // Auf Android schreibt saveFile die Bytes direkt an den gewählten Ort.
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Backup speichern',
      fileName: 'reise_tracker_backup_$stamp.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    return path;
  }

  /// Importiert ein zuvor exportiertes Backup. ERSETZT alle lokalen Daten.
  /// Liefert true bei Erfolg.
  Future<bool> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Backup auswählen',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return false;
    final file = result.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return false;

    final decoded = json.decode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'reise_tracker') {
      return false;
    }

    await db.transaction((txn) async {
      for (final t in _tables) {
        await txn.delete(t);
        final rows = decoded[t];
        if (rows is! List) continue;
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(t, Map<String, Object?>.from(row as Map));
        }
        await batch.commit(noResult: true);
      }
    });
    return true;
  }
}
