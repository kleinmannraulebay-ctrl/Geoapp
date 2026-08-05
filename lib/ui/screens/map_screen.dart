import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants.dart';
import '../../geo/exploration_grid.dart';
import '../../geo/geo_assets.dart';
import '../../geo/geo_models.dart';
import '../../providers/providers.dart';
import '../widgets/choropleth.dart';
import '../widgets/mark_visited_sheet.dart';
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

          // Länder-Choropleth (immer als Basis); beim Herauszoomen mit
          // kräftigeren Grenzen, damit die Länder besser herausstechen.
          layers.add(PolygonLayer(
            polygons: countryChoropleth(
              geo.countries,
              (code) => AppConst.intensityStage(stats[code]?.visitDays ?? 0),
              borderWidth: _zoom < 5 ? 1.1 : 0.6,
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

          // Ländernamen beim Herauszoomen (große Länder zuerst).
          if (_zoom < 7 && _bounds != null) {
            layers.add(MarkerLayer(
                markers: _countryLabels(geo, _bounds!, _zoom), rotate: false));
          }

          // Städte-Marker (zoomabhängig, wichtigste zuerst; besuchte grün).
          if (_zoom >= 4 && _bounds != null) {
            final visitedCities =
                ref.watch(visitedCityIdsProvider).valueOrNull ?? const <int>{};
            layers.add(MarkerLayer(
                markers: _cityMarkers(geo, _bounds!, _zoom, visitedCities),
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
              // Langes Drücken: „Da war ich schon“ für Land/Region/Stadt
              // am Tipppunkt, optional mit Zeitraum.
              onLongPress: (tapPos, latLng) {
                final lat = latLng.latitude, lon = latLng.longitude;
                final country = geo.countryIndex.locate(lon, lat);
                if (country == null) return;
                final region = geo.regionIndex.locate(lon, lat);
                final validRegion =
                    (region != null && region.countryCode == country.id)
                        ? region
                        : null;
                City? nearestCity;
                var bestKm = 30.0;
                for (final c in geo.cityIndex.nearby(lat, lon, 30)) {
                  final d = ExplorationGrid.distanceKm(lat, lon, c.lat, c.lon);
                  if (d < bestKm) {
                    bestKm = d;
                    nearestCity = c;
                  }
                }
                showMarkVisitedSheet(
                  context,
                  country: country,
                  region: validRegion,
                  city: nearestCity,
                );
              },
            ),
            children: layers,
          );
        },
      ),
    );
  }

  /// Beschriftungs-Anker pro Land (Mitte der BBox des größten Polygons).
  static final Map<String, LatLng> _labelPointCache = {};

  LatLng _labelPoint(GeoFeature f) => _labelPointCache.putIfAbsent(f.id, () {
        var best = f.polygons.first;
        var bestSize = 0.0;
        for (final p in f.polygons) {
          final size = (p.maxLon - p.minLon) * (p.maxLat - p.minLat);
          if (size > bestSize) {
            bestSize = size;
            best = p;
          }
        }
        return LatLng(
            (best.minLat + best.maxLat) / 2, (best.minLon + best.maxLon) / 2);
      });

  /// Ländernamen-Labels: weit herausgezoomt nur die großen Länder,
  /// beim Hineinzoomen zunehmend alle. Labels, die sich auf dem Bildschirm
  /// überlappen würden, werden ausgeblendet — große Länder haben Vorrang.
  List<Marker> _countryLabels(GeoData geo, LatLngBounds b, double zoom,
      {int cap = 60}) {
    final minArea = zoom < 3
        ? 400000.0
        : zoom < 4
            ? 90000.0
            : zoom < 5
                ? 15000.0
                : 0.0;

    // Web-Mercator-Projektion in Pixel für die Kollisionsprüfung.
    final worldPx = 256.0 * math.pow(2, zoom);
    double xOf(double lon) => (lon + 180) / 360 * worldPx;
    double yOf(double lat) {
      final s =
          math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999).toDouble();
      return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * worldPx;
    }

    final fontSize = zoom < 4 ? 10.0 : 11.0;
    final placed = <Rect>[];
    final markers = <Marker>[];
    final candidates = geo.countryIndex.inBounds(b.west, b.south, b.east, b.north)
      ..sort((x, y) => y.areaKm2.compareTo(x.areaKm2));
    for (final c in candidates) {
      if (c.areaKm2 < minArea) continue;
      final p = _labelPoint(c);
      if (p.latitude < b.south ||
          p.latitude > b.north ||
          p.longitude < b.west ||
          p.longitude > b.east) {
        continue;
      }
      // Geschätzte Label-Größe (Großbuchstaben + Letter-Spacing).
      final w = math.min(160.0, c.name.length * fontSize * 0.78 + 10);
      final rect = Rect.fromCenter(
        center: Offset(xOf(p.longitude), yOf(p.latitude)),
        width: w,
        height: fontSize * 2.4,
      );
      if (placed.any((r) => r.overlaps(rect.inflate(3)))) continue;
      placed.add(rect);
      markers.add(Marker(
        point: p,
        width: 160,
        height: 32,
        child: Center(
          child: Text(
            c.name.toUpperCase(),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: zoom < 4 ? 10 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: const Color(0xE6FFFFFF),
              shadows: const [
                Shadow(color: Colors.black87, blurRadius: 4),
                Shadow(color: Colors.black54, blurRadius: 8),
              ],
            ),
          ),
        ),
      ));
      if (markers.length >= cap) break;
    }
    return markers;
  }

  /// Wichtigste Städte im Ausschnitt: je weiter hineingezoomt, desto mehr.
  /// geo.cities ist global nach Einwohnerzahl absteigend sortiert.
  List<Marker> _cityMarkers(
      GeoData geo, LatLngBounds b, double zoom, Set<int> visitedCities,
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
      final visited = visitedCities.contains(c.id);
      markers.add(Marker(
        point: LatLng(c.lat, c.lon),
        width: showLabels ? 140 : 12,
        height: showLabels ? 44 : 12,
        alignment: Alignment.center,
        child: showLabels
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _cityDot(c.isCapital, visited),
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: visited ? const Color(0xFF69F0AE) : Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 3),
                        Shadow(color: Colors.black, blurRadius: 6),
                      ],
                    ),
                  ),
                ],
              )
            : Center(child: _cityDot(c.isCapital, visited)),
      ));
      if (markers.length >= cap) break;
    }
    return markers;
  }

  /// Besuchte Städte leuchten grün, Hauptstädte tragen einen gelben Rand.
  Widget _cityDot(bool capital, bool visited) => Container(
        width: capital ? 10 : 8,
        height: capital ? 10 : 8,
        decoration: BoxDecoration(
          color: visited ? const Color(0xFF00E676) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: capital ? const Color(0xFFFFD54F) : Colors.black87,
            width: capital ? 1.5 : 1,
          ),
        ),
      );

  List<Polygon> _fogPolygons(List<String> cellIds, LatLngBounds bounds,
      {int cap = 6000}) {
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
        color: const Color(0x4DFFF176),
        borderStrokeWidth: 0,
      ));
      if (polygons.length >= cap) break;
    }
    return polygons;
  }
}
