import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/flags.dart';
import '../../data/models.dart';
import '../../geo/geo_models.dart';
import '../../providers/providers.dart';
import '../widgets/choropleth.dart';
import '../widgets/mark_visited_sheet.dart';
import '../widgets/progress_row.dart';

/// Detailseite eines Landes: Mini-Karte, drei Prozentwerte, Regionsliste
/// mit Häkchen und Städte-Checkliste (abhaken/abwählen).
class CountryDetailScreen extends ConsumerWidget {
  final String countryCode;
  const CountryDetailScreen({super.key, required this.countryCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geoAsync = ref.watch(geoDataProvider);
    final statsAsync = ref.watch(countryStatsProvider);

    return geoAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (geo) {
        final country = geo.countryByCode[countryCode];
        if (country == null) {
          return const Scaffold(body: Center(child: Text('Unbekanntes Land')));
        }
        final stats = statsAsync.valueOrNull?[countryCode];
        final visitedRegions =
            ref.watch(visitedRegionsProvider(countryCode)).valueOrNull ??
                const <String>{};
        final cityVisits =
            ref.watch(cityVisitsProvider(countryCode)).valueOrNull ?? const {};
        final topN = ref.watch(settingsProvider.select((s) => s.topCities));
        final regions = geo.regionsByCountry[countryCode] ?? const [];
        final cities = geo.topCities(countryCode, topN);
        final df = DateFormat('dd.MM.yyyy');
        String? fmt(int? ts) => ts == null
            ? null
            : df.format(DateTime.fromMillisecondsSinceEpoch(ts));

        return Scaffold(
          appBar: AppBar(
              title: Text('${flagEmoji(country.iso2)}  ${country.name}')),
          body: ListView(
            children: [
              // ---- Mini-Karte ----
              SizedBox(
                height: 220,
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: _boundsOf(country),
                        padding: const EdgeInsets.all(16),
                      ),
                      backgroundColor: const Color(0xFF0D1B24),
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none),
                    ),
                    children: [
                      PolygonLayer(
                        polygons: [
                          ...featurePolygons(country,
                              fill: const Color(0x33455A64)),
                          for (final r in regions)
                            ...featurePolygons(
                              r,
                              fill: visitedRegions.contains(r.id)
                                  ? const Color(0xB326A69A)
                                  : const Color(0x14FFFFFF),
                              borderWidth: 0.5,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ---- Kennzahlen ----
              if (stats != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProgressRow(
                              label: 'Regionen',
                              value: stats.regionPercent,
                              detail:
                                  '${stats.regionsVisited}/${stats.regionsTotal}'),
                          ProgressRow(
                              label: 'Städte',
                              value: stats.cityPercent,
                              detail:
                                  '${stats.citiesVisited}/${stats.citiesListed}'),
                          ProgressRow(
                              label: 'Fläche',
                              value: stats.areaPercent,
                              detail:
                                  '${(stats.areaPercent * 100).toStringAsFixed(2)} %'),
                          if (fmt(stats.firstTs) != null ||
                              stats.visitDays > 0) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (fmt(stats.firstTs) != null)
                                  _InfoChip(
                                      icon: Icons.flight_land,
                                      text: 'Erstbesuch ${fmt(stats.firstTs)}'),
                                if (fmt(stats.lastTs) != null)
                                  _InfoChip(
                                      icon: Icons.history,
                                      text: 'Zuletzt ${fmt(stats.lastTs)}'),
                                _InfoChip(
                                    icon: Icons.calendar_month,
                                    text: '${stats.visitDays} Besuchstage'),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

              // ---- Regionen ----
              if (regions.isNotEmpty) ...[
                const _SectionHeader('Regionen'),
                for (final r in regions)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      visitedRegions.contains(r.id)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: visitedRegions.contains(r.id)
                          ? const Color(0xFF26A69A)
                          : null,
                    ),
                    title: Text(r.name),
                    trailing: const Icon(Icons.add_location_alt, size: 18),
                    // Tippen: „Da war ich schon“ – Region als besucht
                    // markieren, optional mit Zeitraum.
                    onTap: () => showMarkVisitedSheet(
                      context,
                      country: country,
                      region: r,
                    ),
                  ),
              ],

              // ---- Städte-Checkliste ----
              const _SectionHeader('Wichtigste Städte'),
              for (final city in cities)
                _CityTile(
                  city: city,
                  visit: cityVisits[city.id],
                  onChanged: (checked) async {
                    final stats =
                        await ref.read(statsServiceProvider.future);
                    await stats.setCityVisited(city.id, checked);
                    ref.read(statsVersionProvider.notifier).state++;
                  },
                  onAddEntry: () => showMarkVisitedSheet(
                    context,
                    country: country,
                    city: city,
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  LatLngBounds _boundsOf(GeoFeature f) {
    final (minLon, minLat, maxLon, maxLat) = f.bbox;
    return LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF2DD4BF)),
            const SizedBox(width: 5),
            Text(text,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _CityTile extends StatelessWidget {
  final City city;
  final CityVisit? visit;
  final ValueChanged<bool> onChanged;
  final VoidCallback onAddEntry;

  const _CityTile({
    required this.city,
    required this.visit,
    required this.onChanged,
    required this.onAddEntry,
  });

  @override
  Widget build(BuildContext context) {
    final visited = visit?.isVisited ?? false;
    final manual = visit?.isManual ?? false;
    final firstTs = visit?.firstTs;
    final df = DateFormat('dd.MM.yyyy');
    final popFmt = NumberFormat.decimalPattern('de');

    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: visited,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(
        city.isCapital ? '★ ${city.name}' : city.name,
        style: visited
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text([
        '${popFmt.format(city.population)} Einw.',
        if (visited && firstTs != null)
          'besucht am ${df.format(DateTime.fromMillisecondsSinceEpoch(firstTs))}',
      ].join(' · ')),
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (visited)
            Tooltip(
              message: manual ? 'Manuell abgehakt' : 'Automatisch erkannt',
              child: Icon(manual ? Icons.edit : Icons.gps_fixed, size: 18),
            ),
          IconButton(
            tooltip: 'Besuch mit Zeitraum eintragen',
            icon: const Icon(Icons.event_available, size: 20),
            onPressed: onAddEntry,
          ),
        ],
      ),
    );
  }
}
