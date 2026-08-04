import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/permission_service.dart';
import '../../services/tracking_service.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final pointCount = ref.watch(trackPointCountProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          const _SectionHeader('Standort-Tracking'),
          SwitchListTile(
            title: const Text('Hintergrund-Tracking'),
            subtitle: Text(settings.trackingEnabled
                ? 'Aktiv – Foreground Service mit Benachrichtigung'
                : 'Aus – es werden keine Positionen aufgezeichnet'),
            value: settings.trackingEnabled,
            onChanged: (v) async {
              if (v) {
                final granted =
                    await PermissionService.requestTrackingPermissions(
                        context);
                if (!granted) return;
                final ok =
                    await TrackingController.start(settings.intervalMinutes);
                if (ok) {
                  notifier.setTracking(enabled: true, paused: false);
                } else if (context.mounted) {
                  _snack(context, 'Service konnte nicht gestartet werden.');
                }
              } else {
                await TrackingController.stop();
                notifier.setTracking(enabled: false);
              }
            },
          ),
          SwitchListTile(
            title: const Text('Pausieren'),
            subtitle:
                const Text('Aufzeichnung anhalten, Service bleibt bereit'),
            value: settings.trackingPaused,
            onChanged: settings.trackingEnabled
                ? (v) async {
                    await TrackingController.setPaused(v);
                    notifier.setTracking(paused: v);
                  }
                : null,
          ),
          ListTile(
            title: const Text('Abfrage-Intervall'),
            subtitle: const Text(
                'Positionsabfrage nur alle 10–15 Minuten (akkuschonend); '
                'bei Stillstand wird automatisch gedrosselt'),
            trailing: DropdownButton<int>(
              value: settings.intervalMinutes,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10 min')),
                DropdownMenuItem(value: 15, child: Text('15 min')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                notifier.setIntervalMinutes(v);
                await TrackingController.restartWithInterval(v);
              },
            ),
          ),
          ListTile(
            title: const Text('Aufgezeichnete Punkte'),
            trailing: Text('${pointCount ?? '–'}'),
          ),
          const Divider(),
          const _SectionHeader('Karte & Listen'),
          SwitchListTile(
            title: const Text('Erkundete Flächen anzeigen'),
            subtitle: const Text('„Fog of War“-Overlay auf der Karte'),
            value: settings.fogOverlay,
            onChanged: notifier.setFogOverlay,
          ),
          ListTile(
            title: const Text('Städte pro Land'),
            subtitle: const Text('Top-Städte nach Einwohnerzahl'),
            trailing: DropdownButton<int>(
              value: settings.citiesPerCountry,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 25, child: Text('25')),
                DropdownMenuItem(value: 40, child: Text('40')),
              ],
              onChanged: (v) {
                if (v != null) notifier.setCitiesPerCountry(v);
              },
            ),
          ),
          ListTile(
            title: const Text('Design'),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              items: const [
                DropdownMenuItem(
                    value: ThemeMode.dark, child: Text('Dunkel')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Hell')),
                DropdownMenuItem(
                    value: ThemeMode.system, child: Text('System')),
              ],
              onChanged: (v) {
                if (v != null) notifier.setThemeMode(v);
              },
            ),
          ),
          const Divider(),
          const _SectionHeader('Backup (lokal, ohne Cloud)'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Als JSON exportieren'),
            subtitle: const Text('Komplette Datenbank als Datei sichern'),
            onTap: () async {
              try {
                final svc = await ref.read(backupServiceProvider.future);
                final saved = await svc.exportToFile();
                if (context.mounted) {
                  _snack(context,
                      saved ? 'Sicherung gespeichert.' : 'Abgebrochen.');
                }
              } catch (e) {
                if (context.mounted) _snack(context, 'Export-Fehler: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Aus JSON importieren'),
            subtitle:
                const Text('Achtung: ersetzt alle vorhandenen Daten'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Import bestätigen'),
                  content: const Text(
                      'Beim Import werden alle vorhandenen Daten durch die '
                      'Sicherung ersetzt. Fortfahren?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Abbrechen')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Importieren')),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                final svc = await ref.read(backupServiceProvider.future);
                final done = await svc.importFromFile();
                ref.read(refreshTickProvider.notifier).state++;
                if (context.mounted) {
                  _snack(context,
                      done ? 'Sicherung importiert.' : 'Abgebrochen.');
                }
              } catch (e) {
                if (context.mounted) _snack(context, 'Import-Fehler: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Alle Daten löschen'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Wirklich alles löschen?'),
                  content: const Text(
                      'Alle Trackingpunkte, Statistiken und manuellen '
                      'Einträge werden unwiderruflich gelöscht.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Abbrechen')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Löschen')),
                  ],
                ),
              );
              if (ok != true) return;
              final db = await ref.read(databaseProvider.future);
              await db.deleteAllData();
              ref.read(refreshTickProvider.notifier).state++;
              if (context.mounted) _snack(context, 'Alle Daten gelöscht.');
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
