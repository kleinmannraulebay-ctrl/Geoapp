import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/stats_service.dart';
import '../../geo/geo_data.dart';
import '../../geo/grid.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../map/choropleth.dart';
import 'country_detail_screen.dart';

/// Ab dieser Zoomstufe wird von Länder- auf Regionsfärbung umgeschaltet.
const double kRegionZoom = 4.5;

/// Ab dieser Zoomstufe wird das Fog-of-War-Overlay gezeichnet.
const double kFogZoom = 5.5;

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _controller = MapController();
  Timer? _debounce;
  double _zoom = 2.2;
  LatLngBounds? _bounds;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _zoom = _controller.camera.zoom;
        _bounds = _controller.camera.visibleBounds;
      });
    });
  }

  void _onTap(GeoData geo, LatLng point) {
    final hit = geo.countryIndex.lookup(point.latitude, point.longitude);
    if (hit != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CountryDetailScreen(countryId: hit.id),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final geoAsync = ref.watch(geoDataProvider);
    final statsAsync = ref.watch(statsProvider);
    final fog = ref.watch(settingsProvider.select((s) => s.fogOverlay));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return geoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Geodaten-Fehler: $e')),
      data: (geo) {
        final stats = statsAsync.valueOrNull;
        return Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: const LatLng(30, 10),
                initialZoom: 2.2,
                minZoom: 1.6,
                maxZoom: 12,
                backgroundColor: isDark
                    ? ChoroplethPalette.ocean
                    : ChoroplethPalette.oceanLight,
                onMapEvent: _onMapEvent,
                onTap: (_, point) => _onTap(geo, point),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                PolygonLayer(polygons: _buildChoropleth(geo, stats)),
                if (fog && _zoom >= kFogZoom)
                  PolygonLayer(polygons: _buildFog()),
              ],
            ),
            _legend(context),
            _fogToggle(context, fog),
          ],
        );
      },
    );
  }

  List<Polygon> _buildChoropleth(GeoData geo, StatsSnapshot? stats) {
    final polygons = <Polygon>[];
    if (_zoom < kRegionZoom) {
      for (final c in geo.countries) {
        final level = stats?.byCountry[c.id]?.level ?? 0;
        polygons.addAll(
            PolygonCache.polygonsOf(c, ChoroplethPalette.forLevel(level)));
      }
    } else {
      final b = _bounds;
      final visible = b == null
          ? geo.regions
          : geo.regionIndex.inBounds(
              b.south - 1, b.west - 1, b.north + 1, b.east + 1);
      for (final r in visible) {
        var level = 0;
        if (stats != null && stats.visitedRegions.contains(r.id)) {
          final rs = stats.regionStats[r.id];
          final pct = (r.areaKm2 <= 0 || rs == null)
              ? 0.0
              : clampPct(rs.exploredKm2 / r.areaKm2);
          level = ChoroplethPalette.levelForAreaPct(pct);
        }
        polygons.addAll(PolygonCache.polygonsOf(
            r, ChoroplethPalette.forLevel(level),
            borderWidth: 0.4));
      }
    }
    return polygons;
  }

  /// Erkundete Rasterzellen als aufgedeckte Flächen ("Fog of War").
  List<Polygon> _buildFog() {
    final cells = ref.watch(exploredCellsProvider).valueOrNull;
    final b = _bounds;
    if (cells == null || b == null) return const [];
    final out = <Polygon>[];
    for (final cell in cells) {
      final (south, west, north, east) = ExplorationGrid.cellBounds(cell);
      if (north < b.south || south > b.north || east < b.west || west > b.east) {
        continue;
      }
      out.add(Polygon(
        points: [
          LatLng(south, west),
          LatLng(south, east),
          LatLng(north, east),
          LatLng(north, west),
        ],
        color: const Color(0x66FFE082),
        borderStrokeWidth: 0,
      ));
      if (out.length >= 4000) break; // Renderlimit
    }
    return out;
  }

  Widget _legend(BuildContext context) {
    return Positioned(
      left: 12,
      bottom: 12,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Besuchsintensität',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i <= 5; i++)
                    Container(
                      width: 18,
                      height: 10,
                      margin: const EdgeInsets.only(right: 2),
                      color: ChoroplethPalette.forLevel(i),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text('nie → oft', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fogToggle(BuildContext context, bool fog) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: FloatingActionButton.small(
        heroTag: 'fogToggle',
        tooltip: 'Erkundete Flächen ein-/ausblenden',
        onPressed: () =>
            ref.read(settingsProvider.notifier).setFogOverlay(!fog),
        child: Icon(fog ? Icons.blur_off : Icons.blur_on),
      ),
    );
  }
}
