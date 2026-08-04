import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models.dart';
import '../../geo/geo_models.dart';
import '../../providers/providers.dart';
import '../widgets/choropleth.dart';
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
          appBar: AppBar(title: Text(country.name)),
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stats != null) ...[
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
                      const SizedBox(height: 8),
                      if (fmt(stats.firstTs) != null)
                        Text('Erstbesuch: ${fmt(stats.firstTs)}'
                            '   ·   Letzter Besuch: ${fmt(stats.lastTs)}'),
                      Text('Besuchstage: ${stats.visitDays}'),
                    ],
                  ],
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

  const _CityTile({
    required this.city,
    required this.visit,
    required this.onChanged,
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
      secondary: visited
          ? Tooltip(
              message: manual ? 'Manuell abgehakt' : 'Automatisch erkannt',
              child: Icon(manual ? Icons.edit : Icons.gps_fixed, size: 18),
            )
          : null,
    );
  }
}
