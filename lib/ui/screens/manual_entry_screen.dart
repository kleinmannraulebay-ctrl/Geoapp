import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../geo/geo_assets.dart';
import '../../geo/geo_models.dart';
import '../../providers/providers.dart';

/// Nachträge: frühere Reisen manuell erfassen (Land, optional Region/Stadt,
/// Zeitraum, Notiz). Einträge sind einzeln editier- und löschbar.
class ManualEntryScreen extends ConsumerWidget {
  const ManualEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(manualEntriesProvider);
    final geoAsync = ref.watch(geoDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nachträge')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Reise nachtragen',
        onPressed: () => _openEditor(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: geoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (geo) => entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Fehler: $e')),
          data: (entries) => entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Noch keine Nachträge.\n\nMit + kannst du frühere '
                      'Reisen erfassen – sie zählen dann in Listen, '
                      'Statistiken und auf der Karte mit.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) =>
                      _EntryTile(entry: entries[i], geo: geo),
                ),
        ),
      ),
    );
  }

  static Future<void> _openEditor(
      BuildContext context, WidgetRef ref, ManualEntry? existing) async {
    final geo = ref.read(geoDataProvider).valueOrNull;
    if (geo == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ManualEntryEditor(geo: geo, existing: existing),
    ));
  }
}

class _EntryTile extends ConsumerWidget {
  final ManualEntry entry;
  final GeoData geo;
  const _EntryTile({required this.entry, required this.geo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final country = geo.countryByCode[entry.countryCode]?.name ??
        entry.countryCode;
    final region =
        entry.regionId == null ? null : geo.regionById[entry.regionId!]?.name;
    final city = entry.cityId == null ? null : geo.cityById[entry.cityId!]?.name;
    final df = DateFormat('dd.MM.yyyy');
    String? range;
    if (entry.dateFrom != null) {
      final from = DateTime.tryParse(entry.dateFrom!);
      final to = entry.dateTo == null ? null : DateTime.tryParse(entry.dateTo!);
      if (from != null) {
        range = to == null || to == from
            ? df.format(from)
            : '${df.format(from)} – ${df.format(to)}';
      }
    }

    return ListTile(
      leading: const Tooltip(
        message: 'Manueller Eintrag',
        child: Icon(Icons.edit_note),
      ),
      title: Text([country, region, city].whereType<String>().join(' · ')),
      subtitle: Text([
        if (range != null) range,
        if (entry.note?.isNotEmpty == true) entry.note!,
      ].join('\n')),
      isThreeLine: entry.note?.isNotEmpty == true && range != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Bearbeiten',
            onPressed: () =>
                ManualEntryScreen._openEditor(context, ref, entry),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Löschen',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Eintrag löschen?'),
                  content: const Text(
                      'Der manuelle Eintrag wird entfernt. Automatisch '
                      'erfasste Daten bleiben erhalten.'),
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
              if (ok == true) {
                final stats = await ref.read(statsServiceProvider.future);
                await stats.deleteManualEntry(entry.id);
                ref.read(statsVersionProvider.notifier).state++;
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Formular zum Anlegen/Bearbeiten eines Nachtrags.
class ManualEntryEditor extends ConsumerStatefulWidget {
  final GeoData geo;
  final ManualEntry? existing;
  const ManualEntryEditor({super.key, required this.geo, this.existing});

  @override
  ConsumerState<ManualEntryEditor> createState() => _ManualEntryEditorState();
}

class _ManualEntryEditorState extends ConsumerState<ManualEntryEditor> {
  GeoFeature? _country;
  GeoFeature? _region;
  City? _city;
  DateTime? _from;
  DateTime? _to;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _note = TextEditingController(text: e?.note ?? '');
    if (e != null) {
      _country = widget.geo.countryByCode[e.countryCode];
      _region = e.regionId == null ? null : widget.geo.regionById[e.regionId!];
      _city = e.cityId == null ? null : widget.geo.cityById[e.cityId!];
      _from = e.dateFrom == null ? null : DateTime.tryParse(e.dateFrom!);
      _to = e.dateTo == null ? null : DateTime.tryParse(e.dateTo!);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geo = widget.geo;
    final countries = [...geo.countries]
      ..sort((a, b) => a.name.compareTo(b.name));
    final regions = _country == null
        ? const <GeoFeature>[]
        : (geo.regionsByCountry[_country!.id] ?? const []);
    final cities =
        _country == null ? const <City>[] : geo.topCities(_country!.id, 100);
    final df = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Reise nachtragen'
            : 'Nachtrag bearbeiten'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownMenu<GeoFeature>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('Land *'),
            initialSelection: _country,
            enableFilter: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: [
              for (final c in countries)
                DropdownMenuEntry(value: c, label: c.name),
            ],
            onSelected: (c) => setState(() {
              _country = c;
              _region = null;
              _city = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownMenu<GeoFeature?>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('Region (optional)'),
            initialSelection: _region,
            enableFilter: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: [
              const DropdownMenuEntry<GeoFeature?>(value: null, label: '—'),
              for (final r in regions)
                DropdownMenuEntry<GeoFeature?>(value: r, label: r.name),
            ],
            onSelected: (r) => setState(() => _region = r),
          ),
          const SizedBox(height: 12),
          DropdownMenu<City?>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('Stadt (optional)'),
            initialSelection: _city,
            enableFilter: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: [
              const DropdownMenuEntry<City?>(value: null, label: '—'),
              for (final c in cities)
                DropdownMenuEntry<City?>(value: c, label: c.name),
            ],
            onSelected: (c) => setState(() => _city = c),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_from == null ? 'Von …' : df.format(_from!)),
                  onPressed: () => _pickDate(isFrom: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_to == null ? 'Bis …' : df.format(_to!)),
                  onPressed: () => _pickDate(isFrom: false),
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
          FilledButton(
            onPressed: _country == null ? null : _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: now,
      initialDate: (isFrom ? _from : _to) ?? now,
    );
    if (picked != null) {
      setState(() => isFrom ? _from = picked : _to = picked);
    }
  }

  Future<void> _save() async {
    final stats = await ref.read(statsServiceProvider.future);
    String? iso(DateTime? d) =>
        d == null ? null : d.toIso8601String().substring(0, 10);
    final type = _city != null
        ? 'city'
        : _region != null
            ? 'region'
            : 'country';
    if (widget.existing == null) {
      await stats.addManualEntry(
        type: type,
        countryCode: _country!.id,
        regionId: _region?.id,
        cityId: _city?.id,
        dateFrom: iso(_from),
        dateTo: iso(_to),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    } else {
      await stats.updateManualEntry(ManualEntry(
        id: widget.existing!.id,
        type: type,
        countryCode: _country!.id,
        regionId: _region?.id,
        cityId: _city?.id,
        dateFrom: iso(_from),
        dateTo: iso(_to),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        createdTs: widget.existing!.createdTs,
      ));
    }
    if (mounted) {
      ref.read(statsVersionProvider.notifier).state++;
      Navigator.of(context).pop();
    }
  }
}
