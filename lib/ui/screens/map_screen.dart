import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants.dart';
import '../../geo/exploration_grid.dart';
import '../../providers/providers.dart';
import '../widgets/choropleth.dart';
import 'country_detail_screen.dart';

/// Vollbild-Weltkarte: offline gerendert aus den GeoJSON-Assets.
/// Weit herausgezoomt Länder-Choropleth, ab Zoom 5 Regionsfärbung,
/// optional Fog-of-War-Overlay der erkundeten Rasterzellen.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = MapController();
  double _zoom = 2.2;
  LatLngBounds? _bounds;

  @override
  Widget build(BuildContext context) {
    final geoAsync = ref.watch(geoDataProvider);
    final statsAsync = ref.watch(countryStatsProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weltkarte'),
        actions: [
          IconButton(
            tooltip: settings.fogEnabled
                ? 'Erkundete Zellen ausblenden'
                : 'Erkundete Zellen einblenden („Fog of War“)',
            icon: Icon(
                settings.fogEnabled ? Icons.blur_on : Icons.blur_off),
            onPressed: () => ref
                .read(settingsProvider.notifier)
                .setFog(!settings.fogEnabled),
          ),
        ],
      ),
      body: geoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Geodaten-Fehler: $e')),
        data: (geo) {
          final stats = statsAsync.valueOrNull ?? const {};
          final showRegions = _zoom >= AppConst.regionZoomThreshold;

          final layers = <Widget>[];

          // Länder-Choropleth (immer als Basis).
          layers.add(PolygonLayer(
            polygons: countryChoropleth(
              geo.countries,
              (code) => AppConst.intensityStage(stats[code]?.visitDays ?? 0),
            ),
          ));

          // Regionsfärbung im hineingezoomten Zustand.
          if (showRegions && _bounds != null) {
            final b = _bounds!;
            final visible = geo.regionIndex.inBounds(
                b.west, b.south, b.east, b.north);
            final visitedIds = <String>{};
            for (final code in {for (final r in visible) r.countryCode}) {
              visitedIds.addAll(
                  ref.watch(visitedRegionsProvider(code)).valueOrNull ??
                      const <String>{});
            }
            layers.add(PolygonLayer(
              polygons: regionChoropleth(visible, visitedIds.contains),
            ));
          }

          // Fog of War: erkundete Zellen als aufgedeckte Rechtecke.
          if (settings.fogEnabled && _zoom >= AppConst.fogZoomThreshold) {
            final cells = ref.watch(visitedCellsProvider).valueOrNull;
            if (cells != null && _bounds != null) {
              layers.add(PolygonLayer(polygons: _fogPolygons(cells, _bounds!)));
            }
          }

          return FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: const LatLng(30, 10),
              initialZoom: 2.2,
              minZoom: 1.5,
              maxZoom: 12,
              backgroundColor: const Color(0xFF0D1B24),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(-85, -180),
                  const LatLng(85, 180),
                ),
              ),
              onPositionChanged: (camera, hasGesture) {
                setState(() {
                  _zoom = camera.zoom;
                  _bounds = camera.visibleBounds;
                });
              },
              onTap: (tapPos, latLng) {
                final country =
                    geo.countryIndex.locate(latLng.longitude, latLng.latitude);
                if (country != null) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        CountryDetailScreen(countryCode: country.id),
                  ));
                }
              },
            ),
            children: layers,
          );
        },
      ),
    );
  }

  List<Polygon> _fogPolygons(List<String> cellIds, LatLngBounds bounds,
      {int cap = 3000}) {
    final polygons = <Polygon>[];
    for (final id in cellIds) {
      final (latIdx, lonIdx) = ExplorationGrid.parseCellId(id);
      final (lat, lon) = ExplorationGrid.cellSouthWest(latIdx, lonIdx);
      const res = ExplorationGrid.res;
      if (lat + res < bounds.south ||
          lat > bounds.north ||
          lon + res < bounds.west ||
          lon > bounds.east) {
        continue;
      }
      polygons.add(Polygon(
        points: [
          LatLng(lat, lon),
          LatLng(lat, lon + res),
          LatLng(lat + res, lon + res),
          LatLng(lat + res, lon),
        ],
        color: const Color(0x55FFF59D),
        borderColor: const Color(0x88FFF59D),
        borderStrokeWidth: 0.4,
      ));
      if (polygons.length >= cap) break;
    }
    return polygons;
  }
}
