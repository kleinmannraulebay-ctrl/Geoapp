import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants.dart';
import '../../geo/exploration_grid.dart';
import '../../geo/geo_assets.dart';
import '../../providers/providers.dart';
import '../widgets/choropleth.dart';
import 'country_detail_screen.dart';

/// Vollbild-Weltkarte: offline gerendert aus den GeoJSON-Assets.
/// Weit herausgezoomt Länder-Choropleth, ab Zoom 5 Regionsfärbung,
/// zoomabhängige Städte-Marker, aktueller Standort, optional
/// Fog-of-War-Overlay der erkundeten Rasterzellen.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = MapController();
  double _zoom = 2.2;
  LatLngBounds? _bounds;
  LatLng? _myPos;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // Standort einmalig holen (nur wenn Berechtigung schon erteilt ist).
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMyPosition());
  }

  Future<void> _updateMyPosition({bool moveCamera = false}) async {
    if (_locating) return;
    _locating = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() => _myPos = LatLng(pos.latitude, pos.longitude));
      if (moveCamera) {
        _controller.move(_myPos!, _zoom < 8 ? 9.5 : _zoom);
      }
    } catch (_) {
      // Kein Fix (Timeout, Flugmodus …) – Marker bleibt ggf. beim alten Wert.
    } finally {
      _locating = false;
    }
  }

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
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Zu meinem Standort',
        onPressed: () => _updateMyPosition(moveCamera: true),
        child: const Icon(Icons.my_location),
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

          // Städte-Marker (zoomabhängig, wichtigste zuerst).
          if (_zoom >= 4 && _bounds != null) {
            layers.add(MarkerLayer(
                markers: _cityMarkers(geo, _bounds!, _zoom),
                rotate: false));
          }

          // Aktueller Standort.
          final myPos = _myPos;
          if (myPos != null) {
            layers.add(MarkerLayer(rotate: false, markers: [
              Marker(
                point: myPos,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF448AFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ]));
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

  /// Wichtigste Städte im Ausschnitt: je weiter hineingezoomt, desto mehr.
  /// geo.cities ist global nach Einwohnerzahl absteigend sortiert.
  List<Marker> _cityMarkers(GeoData geo, LatLngBounds b, double zoom,
      {int cap = 120}) {
    final minPop = zoom >= 8.5
        ? 15000
        : zoom >= 7
            ? 100000
            : zoom >= 5.5
                ? 500000
                : 1000000;
    final showLabels = zoom >= 5.5;
    final markers = <Marker>[];
    for (final c in geo.cities) {
      final important = c.population >= minPop || (c.isCapital && zoom >= 4.5);
      if (!important) continue;
      if (c.lat < b.south ||
          c.lat > b.north ||
          c.lon < b.west ||
          c.lon > b.east) {
        continue;
      }
      markers.add(Marker(
        point: LatLng(c.lat, c.lon),
        width: showLabels ? 140 : 12,
        height: showLabels ? 44 : 12,
        alignment: Alignment.center,
        child: showLabels
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _cityDot(c.isCapital),
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 3),
                        Shadow(color: Colors.black, blurRadius: 6),
                      ],
                    ),
                  ),
                ],
              )
            : Center(child: _cityDot(c.isCapital)),
      ));
      if (markers.length >= cap) break;
    }
    return markers;
  }

  Widget _cityDot(bool capital) => Container(
        width: capital ? 9 : 7,
        height: capital ? 9 : 7,
        decoration: BoxDecoration(
          color: capital ? const Color(0xFFFFD54F) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black87, width: 1),
        ),
      );

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
