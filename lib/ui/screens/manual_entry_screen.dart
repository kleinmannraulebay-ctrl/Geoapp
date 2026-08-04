import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../geo/geo_data.dart';
import '../../geo/geo_models.dart';
import '../../state/providers.dart';
import '../format.dart';

/// Liste aller manuellen Einträge (unter „Mehr“).
class ManualEntriesScreen extends ConsumerWidget {
  const ManualEntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geoAsync = ref.watch(geoDataProvider);
    final statsAsync = ref.watch(statsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Manuelle Einträge')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Reise nachtragen'),
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ManualEntryScreen())),
      ),
      body: geoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (geo) {
          final entries = statsAsync.valueOrNull?.manualByCountry.values
                  .expand((e) => e)
                  .toList() ??
              [];
          entries.sort((b, a) => a.createdAt.compareTo(b.createdAt));
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine manuellen Einträge.\n\n'
                  'Hier kannst du frühere Reisen nachtragen: Land, Region '
                  'und/oder Stadt auswählen, optional mit Zeitraum und Notiz.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              for (final e in entries) ManualEntryTile(entry: e, geo: geo),
            ],
          );
        },
      ),
    );
  }
}

/// Einzelner manueller Eintrag mit Bearbeiten/Löschen.
class ManualEntryTile extends ConsumerWidget {
  final ManualEntry entry;
  final GeoData geo;
  const ManualEntryTile({super.key, required this.entry, required this.geo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final country = geo.countryById(entry.country);
    final region = entry.region == null
        ? null
        : geo.regions.where((r) => r.id == entry.region).firstOrNull;
    final city = entry.cityId == null
        ? null
        : geo.cities.where((c) => c.id == entry.cityId).firstOrNull;

    final parts = <String>[
      if (region != null) region.name,
      if (city != null) city.name,
    ];
    final dates = [
      if (entry.dateFrom != null) formatDay(entry.dateFrom),
      if (entry.dateTo != null && entry.dateTo != entry.dateFrom)
        formatDay(entry.dateTo),
    ].join(' – ');

    return ListTile(
      leading: const Icon(Icons.touch_app_outlined),
      title: Text(
          '${country?.name ?? entry.country}'
          '${parts.isEmpty ? '' : ' · ${parts.join(' · ')}'}'),
      subtitle: Text([
        if (dates.isNotEmpty) dates,
        if (entry.note?.isNotEmpty == true) entry.note!,
      ].join('\n')),
      isThreeLine: entry.note?.isNotEmpty == true && dates.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ManualEntryScreen(existing: entry))),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Eintrag löschen?'),
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
              if (ok == true && entry.id != null) {
                final db = await ref.read(databaseProvider.future);
                await db.deleteManualEntry(entry.id!);
                ref.read(refreshTickProvider.notifier).state++;
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Formular zum Anlegen/Bearbeiten eines manuellen Eintrags.
class ManualEntryScreen extends ConsumerStatefulWidget {
  final ManualEntry? existing;
  final String? prefillCountry;
  const ManualEntryScreen({super.key, this.existing, this.prefillCountry});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  String? _country;
  String? _region;
  int? _cityId;
  DateTime? _from;
  DateTime? _to;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _country = e?.country ?? widget.prefillCountry;
    _region = e?.region;
    _cityId = e?.cityId;
    _from = e?.dateFrom != null ? DateTime.tryParse(e!.dateFrom!) : null;
    _to = e?.dateTo != null ? DateTime.tryParse(e!.dateTo!) : null;
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_country == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte ein Land auswählen.')));
      return;
    }
    final db = await ref.read(databaseProvider.future);
    final entry = ManualEntry(
      id: widget.existing?.id,
      country: _country!,
      region: _region,
      cityId: _cityId,
      dateFrom: _from != null ? _fmt(_from!) : null,
      dateTo: _to != null ? _fmt(_to!) : null,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: widget.existing?.createdAt ??
          DateTime.now().millisecondsSinceEpoch,
    );
    if (widget.existing == null) {
      await db.insertManualEntry(entry);
    } else {
      await db.updateManualEntry(entry);
    }
    // Stadt gilt damit als manuell besucht.
    if (_cityId != null) {
      await db.setCityVisitManual(_cityId!, true);
    }
    ref.read(refreshTickProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop();
  }

  Future<T?> _pick<T>(
      String title, List<(T, String)> options, T? current) async {
    final controller = TextEditingController();
    return showDialog<T>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final q = controller.text.toLowerCase();
          final filtered = q.isEmpty
              ? options
              : options
                  .where((o) => o.$2.toLowerCase().contains(q))
                  .toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search), isDense: true),
                    onChanged: (_) => setDlgState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        title: Text(filtered[i].$2),
                        selected: filtered[i].$1 == current,
                        onTap: () => Navigator.pop(ctx, filtered[i].$1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Abbrechen')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final geoAsync = ref.watch(geoDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Reise nachtragen'
            : 'Eintrag bearbeiten'),
      ),
      body: geoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (geo) {
          final country = _country == null ? null : geo.countryById(_country!);
          final regions = _country == null
              ? <GeoFeature>[]
              : (geo.regionsOf(_country!)
                ..sort((a, b) => a.name.compareTo(b.name)));
          final cities = _country == null
              ? <City>[]
              : geo.citiesOf(_country!, limit: 40);
          final region = _region == null
              ? null
              : regions.where((r) => r.id == _region).firstOrNull;
          final city = _cityId == null
              ? null
              : cities.where((c) => c.id == _cityId).firstOrNull;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: Theme.of(context).dividerColor)),
                leading: Text(flagEmoji(country?.iso2 ?? ''),
                    style: const TextStyle(fontSize: 24)),
                title: Text(country?.name ?? 'Land auswählen *'),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final sel = await _pick<String>(
                    'Land auswählen',
                    [for (final c in geo.countries) (c.id, c.name)],
                    _country,
                  );
                  if (sel != null) {
                    setState(() {
                      _country = sel;
                      _region = null;
                      _cityId = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                enabled: regions.isNotEmpty,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: Theme.of(context).dividerColor)),
                leading: const Icon(Icons.map_outlined),
                title: Text(region?.name ?? 'Region (optional)'),
                trailing: _region != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _region = null))
                    : const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final sel = await _pick<String>(
                    'Region auswählen',
                    [for (final r in regions) (r.id, r.name)],
                    _region,
                  );
                  if (sel != null) setState(() => _region = sel);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                enabled: cities.isNotEmpty,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: Theme.of(context).dividerColor)),
                leading: const Icon(Icons.location_city_outlined),
                title: Text(city?.name ?? 'Stadt (optional)'),
                trailing: _cityId != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _cityId = null))
                    : const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final sel = await _pick<int>(
                    'Stadt auswählen',
                    [for (final c in cities) (c.id, c.name)],
                    _cityId,
                  );
                  if (sel != null) setState(() => _cityId = sel);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_from == null
                          ? 'Von (optional)'
                          : formatDay(_fmt(_from!))),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _from ?? DateTime.now(),
                          firstDate: DateTime(1950),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) setState(() => _from = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_to == null
                          ? 'Bis (optional)'
                          : formatDay(_fmt(_to!))),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _to ?? _from ?? DateTime.now(),
                          firstDate: DateTime(1950),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) setState(() => _to = d);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notiz (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
                onPressed: _save,
              ),
            ],
          );
        },
      ),
    );
  }
}
