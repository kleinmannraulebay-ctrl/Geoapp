import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/app_database.dart';
import '../../data/stats_service.dart';
import '../../geo/geo_data.dart';
import '../../geo/geo_models.dart';
import '../../geo/grid.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../format.dart';
import '../map/choropleth.dart';
import '../widgets/percent_bar.dart';
import 'manual_entry_screen.dart';

class CountryDetailScreen extends ConsumerWidget {
  final String countryId;
  const CountryDetailScreen({super.key, required this.countryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geoAsync = ref.watch(geoDataProvider);
    final statsAsync = ref.watch(statsProvider);

    return geoAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (geo) {
        final country = geo.countryById(countryId);
        if (country == null) {
          return const Scaffold(body: Center(child: Text('Unbekanntes Land')));
        }
        final stats = statsAsync.valueOrNull;
        final agg = stats?.byCountry[countryId];
        final citiesPerCountry =
            ref.watch(settingsProvider.select((s) => s.citiesPerCountry));
        final cities = geo.citiesOf(countryId, limit: citiesPerCountry);
        final regions = geo.regionsOf(countryId)
          ..sort((a, b) => a.name.compareTo(b.name));

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Text(flagEmoji(country.iso2)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(country.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.edit_calendar),
            label: const Text('Nachtragen'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ManualEntryScreen(prefillCountry: countryId),
            )),
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _MiniMap(country: country, regions: regions, stats: stats),
              const SizedBox(height: 12),
              if (agg != null) _StatsCard(agg: agg),
              const SizedBox(height: 12),
              _RegionSection(regions: regions, stats: stats),
              const SizedBox(height: 12),
              _CitySection(cities: cities, stats: stats),
              const SizedBox(height: 12),
              _ManualSection(countryId: countryId, geo: geo, stats: stats),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }
}

class _MiniMap extends ConsumerWidget {
  final GeoFeature country;
  final List<GeoFeature> regions;
  final StatsSnapshot? stats;
  const _MiniMap({required this.country, required this.regions, this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellsAsync = ref.watch(exploredCellsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final polygons = <Polygon>[];
    for (final r in regions) {
      var level = 0;
      if (stats != null && stats!.visitedRegions.contains(r.id)) {
        final rs = stats!.regionStats[r.id];
        final pct = (r.areaKm2 <= 0 || rs == null)
            ? 0.0
            : clampPct(rs.exploredKm2 / r.areaKm2);
        level = ChoroplethPalette.levelForAreaPct(pct);
      }
      polygons.addAll(PolygonCache.polygonsOf(
          r, ChoroplethPalette.forLevel(level),
          borderWidth: 0.5));
    }
    if (regions.isEmpty) {
      polygons.addAll(PolygonCache.polygonsOf(
          country, ChoroplethPalette.forLevel(0)));
    }

    // Erkundete Zellen innerhalb der Landes-BBox einzeichnen.
    final fog = <Polygon>[];
    final cells = cellsAsync.valueOrNull ?? const <int>[];
    for (final cell in cells) {
      final (south, west, north, east) = ExplorationGrid.cellBounds(cell);
      if (north < country.minY ||
          south > country.maxY ||
          east < country.minX ||
          west > country.maxX) {
        continue;
      }
      fog.add(Polygon(
        points: [
          LatLng(south, west),
          LatLng(south, east),
          LatLng(north, east),
          LatLng(north, west),
        ],
        color: const Color(0x88FFE082),
        borderStrokeWidth: 0,
      ));
      if (fog.length >= 3000) break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds(
                LatLng(country.minY, country.minX),
                LatLng(country.maxY, country.maxX),
              ),
              padding: const EdgeInsets.all(16),
            ),
            backgroundColor: isDark
                ? ChoroplethPalette.ocean
                : ChoroplethPalette.oceanLight,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            PolygonLayer(polygons: polygons),
            if (fog.isNotEmpty) PolygonLayer(polygons: fog),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final CountryAgg agg;
  const _StatsCard({required this.agg});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PercentBar(
              label: 'Regionen',
              ratio: agg.regionPct,
              trailing: '${agg.regionsVisited} / ${agg.regionsTotal}',
            ),
            PercentBar(
              label: 'Städte',
              ratio: agg.cityPct,
              trailing: '${agg.citiesVisited} / ${agg.citiesTotal}',
            ),
            PercentBar(
              label: 'Erkundete Fläche',
              ratio: agg.areaPct,
              trailing: formatPct(agg.areaPct),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Erstbesuch: ${formatDateMs(agg.firstTs)}',
                    style: text.bodySmall),
                Text('Letzter Besuch: ${formatDateMs(agg.lastTs)}',
                    style: text.bodySmall),
              ],
            ),
            if (agg.visitDays > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Besuchstage: ${agg.visitDays}',
                    style: text.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _RegionSection extends StatelessWidget {
  final List<GeoFeature> regions;
  final StatsSnapshot? stats;
  const _RegionSection({required this.regions, this.stats});

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text('Regionen (${regions.length})'),
        children: [
          for (final r in regions)
            ListTile(
              dense: true,
              leading: stats?.visitedRegions.contains(r.id) == true
                  ? const Icon(Icons.check_circle, color: Color(0xFF52B87D))
                  : const Icon(Icons.radio_button_unchecked, size: 18),
              title: Text(r.name),
            ),
        ],
      ),
    );
  }
}

class _CitySection extends ConsumerWidget {
  final List<City> cities;
  final StatsSnapshot? stats;
  const _CitySection({required this.cities, this.stats});

  Future<void> _toggle(WidgetRef ref, City city, bool nowVisited) async {
    final db = await ref.read(databaseProvider.future);
    await db.setCityVisitManual(city.id, nowVisited);
    ref.read(refreshTickProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cities.isEmpty) return const SizedBox.shrink();
    final visits = stats?.cityVisits ?? const <int, CityVisit>{};
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('Städte (${cities.length})'),
        children: [
          for (final city in cities)
            Builder(builder: (context) {
              final v = visits[city.id];
              final visited =
                  v != null && v.source != VisitSource.suppressed;
              return CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: visited,
                onChanged: (nv) => _toggle(ref, city, nv == true),
                title: Text(
                  city.name,
                  style: visited
                      ? const TextStyle(
                          decoration: TextDecoration.lineThrough)
                      : null,
                ),
                subtitle: visited
                    ? Text(
                        '${v.source == VisitSource.manual ? 'manuell' : 'automatisch'}'
                        '${v.visitedAt != null ? ' · Erstbesuch ${formatDateMs(v.visitedAt)}' : ''}')
                    : null,
                secondary: visited
                    ? Icon(
                        v.source == VisitSource.manual
                            ? Icons.touch_app_outlined
                            : Icons.route_outlined,
                        size: 18,
                      )
                    : null,
              );
            }),
        ],
      ),
    );
  }
}

class _ManualSection extends ConsumerWidget {
  final String countryId;
  final GeoData geo;
  final StatsSnapshot? stats;
  const _ManualSection(
      {required this.countryId, required this.geo, this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = stats?.manualByCountry[countryId] ?? const <ManualEntry>[];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text('Manuelle Einträge (${entries.length})'),
        children: [
          for (final e in entries)
            ManualEntryTile(entry: e, geo: geo),
        ],
      ),
    );
  }
}
