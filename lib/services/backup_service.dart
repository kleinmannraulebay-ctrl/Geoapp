import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../data/app_database.dart';

/// Export/Import der kompletten Datenbank als JSON über den
/// Android-Dateidialog (Storage Access Framework – kein Internet nötig).
class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  /// Liefert `true`, wenn die Datei gespeichert wurde.
  Future<bool> exportToFile() async {
    final data = await db.exportAll();
    final bytes =
        Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ')
            .convert(data)));
    final now = DateTime.now();
    final name = 'reise_tracker_backup_'
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.json';
    final path = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(data: bytes, fileName: name),
    );
    return path != null;
  }

  /// Liefert `true`, wenn importiert wurde. Ersetzt alle lokalen Daten!
  Future<bool> importFromFile() async {
    final path = await FlutterFileDialog.pickFile(
      params: const OpenFileDialogParams(
        dialogType: OpenFileDialogType.document,
        fileExtensionsFilter: ['json'],
      ),
    );
    if (path == null) return false;
    final content = await File(path).readAsString();
    final data = jsonDecode(content) as Map<String, Object?>;
    await db.importAll(data);
    return true;
  }
}
