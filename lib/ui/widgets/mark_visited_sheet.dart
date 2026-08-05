import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../geo/geo_models.dart';
import '../../providers/providers.dart';

/// Bottom-Sheet: „Da war ich schon“ — markiert Land/Region/Stadt als besucht,
/// optional mit Zeitraum und Notiz. Legt einen manuellen Eintrag an
/// (erscheint unter „Nachträge“, dort bearbeit-/löschbar).
Future<void> showMarkVisitedSheet(
  BuildContext context, {
  required GeoFeature country,
  GeoFeature? region,
  City? city,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MarkVisitedSheet(country: country, region: region, city: city),
  );
}

class _MarkVisitedSheet extends ConsumerStatefulWidget {
  final GeoFeature country;
  final GeoFeature? region;
  final City? city;

  const _MarkVisitedSheet({required this.country, this.region, this.city});

  @override
  ConsumerState<_MarkVisitedSheet> createState() => _MarkVisitedSheetState();
}

class _MarkVisitedSheetState extends ConsumerState<_MarkVisitedSheet> {
  late String _target; // 'country' | 'region' | 'city'
  DateTimeRange? _range;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Tiefste verfügbare Ebene vorauswählen.
    _target = widget.city != null
        ? 'city'
        : widget.region != null
            ? 'region'
            : 'country';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');
    final parts = [
      if (widget.city != null) widget.city!.name,
      if (widget.region != null) widget.region!.name,
      widget.country.name,
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Da war ich schon',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(parts.join(' · '),
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),

          // Ebene wählen (nur anzeigen, was am Tipppunkt verfügbar ist).
          if (widget.city != null)
            RadioListTile<String>(
              dense: true,
              value: 'city',
              groupValue: _target,
              onChanged: (v) => setState(() => _target = v!),
              title: Text('Stadt: ${widget.city!.name}'),
              secondary: const Icon(Icons.location_city),
            ),
          if (widget.region != null)
            RadioListTile<String>(
              dense: true,
              value: 'region',
              groupValue: _target,
              onChanged: (v) => setState(() => _target = v!),
              title: Text('Region: ${widget.region!.name}'),
              secondary: const Icon(Icons.map),
            ),
          RadioListTile<String>(
            dense: true,
            value: 'country',
            groupValue: _target,
            onChanged: (v) => setState(() => _target = v!),
            title: Text('Land: ${widget.country.name}'),
            secondary: const Icon(Icons.flag),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null
                      ? 'Zeitraum wählen (optional)'
                      : '${df.format(_range!.start)} – ${df.format(_range!.end)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(1950),
                      lastDate: now,
                      initialDateRange: _range,
                      helpText: 'Wann warst du dort?',
                    );
                    if (picked != null) setState(() => _range = picked);
                  },
                ),
              ),
              if (_range != null)
                IconButton(
                  tooltip: 'Zeitraum entfernen',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _range = null),
                ),
            ],
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Notiz (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Als besucht speichern'),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final stats = await ref.read(statsServiceProvider.future);
      String? iso(DateTime? d) =>
          d == null ? null : d.toIso8601String().substring(0, 10);
      // Tiefere Ebenen implizieren die höheren (Stadt ⇒ Region ⇒ Land).
      await stats.addManualEntry(
        type: _target,
        countryCode: widget.country.id,
        regionId: _target == 'country' ? null : widget.region?.id,
        cityId: _target == 'city' ? widget.city?.id : null,
        dateFrom: iso(_range?.start),
        dateTo: iso(_range?.end),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      ref.read(statsVersionProvider.notifier).state++;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Als besucht gespeichert.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
