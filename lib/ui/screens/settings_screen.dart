import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/database.dart';
import '../../providers/providers.dart';
import '../../services/tracking_service.dart';

/// Einstellungen: Tracking (pausierbar), Intervall, Städte-Anzahl,
/// Fog-Standard, Backup (Export/Import), Daten löschen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          const _Header('Tracking'),
          SwitchListTile(
            title: const Text('Standort-Tracking'),
            subtitle: const Text(
                'Zeichnet deine Position im Hintergrund auf (Foreground-'
                'Service mit dauerhafter Benachrichtigung). Jederzeit '
                'pausierbar.'),
            value: settings.trackingEnabled,
            onChanged: _busy ? null : (on) => _toggleTracking(on),
          ),
          ListTile(
            title: const Text('Abfrage-Intervall'),
            subtitle: Text('${settings.intervalMin} Minuten '
                '(zusätzlich bei > ${AppConst.distanceFilterM} m Bewegung)'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              min: AppConst.minIntervalMin.toDouble(),
              max: AppConst.maxIntervalMin.toDouble(),
              divisions: AppConst.maxIntervalMin - AppConst.minIntervalMin,
              value: settings.intervalMin.toDouble(),
              label: '${settings.intervalMin} min',
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setInterval(v.round()),
              onChangeEnd: (v) async {
                // Laufenden Service mit neuem Intervall neu starten.
                if (settings.trackingEnabled) {
                  await TrackingController.start(intervalMin: v.round());
                }
              },
            ),
          ),

          const _Header('Anzeige'),
          SwitchListTile(
            title: const Text('Fog of War auf der Karte'),
            subtitle: const Text(
                'Zeigt erkundete Rasterzellen als aufgedeckte Flächen.'),
            value: settings.fogEnabled,
            onChanged: (v) => ref.read(settingsProvider.notifier).setFog(v),
          ),
          ListTile(
            title: const Text('Städte pro Land in der Checkliste'),
            trailing: DropdownButton<int>(
              value: settings.topCities,
              items: const [
                DropdownMenuItem(value: 10, child: Text('Top 10')),
                DropdownMenuItem(value: 25, child: Text('Top 25')),
                DropdownMenuItem(value: 50, child: Text('Top 50')),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).setTopCities(v);
                }
              },
            ),
          ),

          const _Header('Backup (lokal, ohne Cloud)'),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Daten als JSON exportieren'),
            subtitle: const Text('Speichert alles über den Dateidialog.'),
            enabled: !_busy,
            onTap: () => _run(() async {
              final backup = await ref.read(backupServiceProvider.future);
              final path = await backup.exportToFile();
              _snack(path == null
                  ? 'Export abgebrochen.'
                  : 'Backup gespeichert.');
            }),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('Backup importieren'),
            subtitle: const Text('Ersetzt alle lokalen Daten!'),
            enabled: !_busy,
            onTap: () => _run(() async {
              final ok = await _confirm(
                  'Backup importieren?',
                  'Alle aktuellen Daten werden durch das Backup ersetzt. '
                  'Fortfahren?');
              if (!ok) return;
              final backup = await ref.read(backupServiceProvider.future);
              final success = await backup.importFromFile();
              if (success) ref.read(statsVersionProvider.notifier).state++;
              _snack(success
                  ? 'Backup importiert.'
                  : 'Import fehlgeschlagen oder abgebrochen.');
            }),
          ),

          const _Header('Daten'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Alle Daten löschen'),
            subtitle: const Text(
                'Entfernt alle Punkte, Besuche und Nachträge unwiderruflich.'),
            enabled: !_busy,
            onTap: () => _run(() async {
              final ok = await _confirm('Wirklich alles löschen?',
                  'Diese Aktion kann nicht rückgängig gemacht werden.');
              if (!ok) return;
              final db = await ref.read(databaseProvider.future);
              await AppDatabase.wipeAllData(db);
              ref.read(statsVersionProvider.notifier).state++;
              _snack('Alle Daten gelöscht.');
            }),
          ),

          const _Header('Über'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Text(
              'Diese App arbeitet vollständig offline. Es gibt kein Konto, '
              'keine Cloud und keine Werbung – die App deklariert nicht '
              'einmal die INTERNET-Berechtigung. Alle Daten liegen in einer '
              'lokalen SQLite-Datenbank auf diesem Gerät.\n\n'
              'Kartendaten: Natural Earth (Public Domain).',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTracking(bool on) async {
    if (!on) {
      ref.read(settingsProvider.notifier).setTracking(false);
      await TrackingController.stop();
      _snack('Tracking pausiert.');
      return;
    }

    // Erklärungs-Dialog vor dem Permission-Flow (Android-Vorgabe).
    final ok = await _confirm(
      'Standortzugriff',
      'Für das automatische Reise-Tagebuch braucht die App Zugriff auf '
      'deinen Standort – auch im Hintergrund („Immer erlauben“).\n\n'
      'Die Daten bleiben ausschließlich auf deinem Gerät. Die App hat '
      'keinen Internetzugriff.\n\n'
      'Es wird alle ${AppConst.minIntervalMin}–${AppConst.maxIntervalMin} '
      'Minuten bzw. nach ${AppConst.distanceFilterM} m Bewegung eine '
      'Position gespeichert. Positionen, die ungenauer als '
      '${AppConst.maxAccuracyM.toInt()} m sind, werden verworfen. Flüge '
      'werden erkannt und nicht gewertet.',
    );
    if (!ok) return;

    await _run(() async {
      final status = await TrackingController.requestPermissions();
      switch (status) {
        case PermissionStatus.denied:
          _snack('Standort-Berechtigung verweigert – Tracking nicht möglich.');
          return;
        case PermissionStatus.whileInUseOnly:
          _snack('Hinweis: Ohne „Immer erlauben“ pausiert das Tracking, '
              'sobald die App geschlossen wird.');
        case PermissionStatus.granted:
          break;
      }
      final settings = ref.read(settingsProvider);
      final started =
          await TrackingController.start(intervalMin: settings.intervalMin);
      if (started) {
        ref.read(settingsProvider.notifier).setTracking(true);
        _snack('Tracking gestartet.');
      } else {
        _snack('Service konnte nicht gestartet werden.');
      }
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    return r == true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: const Color(0xFF4DB6AC)),
        ),
      );
}
