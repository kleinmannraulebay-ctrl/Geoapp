/// Hintergrund-Standorttracking über einen Android-Foreground-Service
/// (flutter_foreground_task) mit dauerhafter Notification.
///
/// Akkuschonend: Der Positions-Stream feuert nur bei > 250 m Bewegung
/// (distanceFilter); zusätzlich fragt ein periodischer Timer (10–15 min,
/// einstellbar) die Position ab. Beim Stillstand liefert der Stream nichts —
/// die App drosselt sich also automatisch.
///
/// Der Service schreibt ausschließlich Roh-Punkte in SQLite
/// (`processed = 0`); die Geo-Zuordnung passiert später in der App
/// (StatsService), damit im Hintergrund keine Polygondaten im Speicher
/// gehalten werden.
library;

import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../data/database.dart';

// ---------------------------------------------------------------------
// Hintergrund-Isolate (läuft auch bei geschlossener App)
// ---------------------------------------------------------------------

@pragma('vm:entry-point')
void trackingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_TrackingTaskHandler());
}

class _TrackingTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _stream;
  Database? _db;
  double? _lastLat;
  double? _lastLon;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _db = await AppDatabase.open();
    _stream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: AppConst.distanceFilterM,
        intervalDuration: const Duration(minutes: 1),
      ),
    ).listen(_onPosition, onError: (_) {});
    // Direkt eine erste Position holen.
    await _pollPosition();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _pollPosition();
  }

  Future<void> _pollPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 45),
        ),
      );
      await _onPosition(pos);
    } catch (_) {
      // Kein Fix (Flugmodus, Gebäude, Timeout) – nächster Versuch später.
    }
  }

  Future<void> _onPosition(Position pos) async {
    // Qualitätsfilter: grobe Positionen verwerfen.
    if (pos.accuracy > AppConst.maxAccuracyM) return;

    // Flug-Filter: Überflüge (hohe Geschwindigkeit, große Höhe) zählen
    // nicht als Besuch – z. B. Spanien beim Flug nach Marokko.
    final speed = pos.speed.isFinite && pos.speed > 0 ? pos.speed : 0.0;
    final altitude = pos.altitude.isFinite ? pos.altitude : 0.0;
    if (AppConst.isLikelyFlight(speed, altitude)) {
      FlutterForegroundTask.updateService(
          notificationText: 'Flug erkannt – Position wird nicht gewertet');
      return;
    }

    // Stillstand: Punkte < 50 m neben dem letzten nur einmal pro Poll
    // aufnehmen (hält Besuchstage aktuell, vermeidet aber Duplikat-Fluten).
    final lastLat = _lastLat, lastLon = _lastLon;
    if (lastLat != null && lastLon != null) {
      final d = Geolocator.distanceBetween(
          lastLat, lastLon, pos.latitude, pos.longitude);
      if (d < 50) {
        FlutterForegroundTask.updateService(
            notificationText: 'Tracking aktiv – Stillstand erkannt');
      }
    }
    _lastLat = pos.latitude;
    _lastLon = pos.longitude;

    final db = _db ?? await AppDatabase.open();
    _db = db;
    await db.insert('track_points', {
      'lat': pos.latitude,
      'lon': pos.longitude,
      'ts': pos.timestamp.millisecondsSinceEpoch,
      'accuracy': pos.accuracy,
      'processed': 0,
    });

    // App (falls offen) informieren, damit sie sofort verarbeitet.
    FlutterForegroundTask.sendDataToMain({'newPoint': true});
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _stream?.cancel();
  }

  @override
  void onReceiveData(Object data) {}
}

// ---------------------------------------------------------------------
// Steuerung aus der App (Haupt-Isolate)
// ---------------------------------------------------------------------

enum PermissionStatus { granted, whileInUseOnly, denied }

class TrackingController {
  /// In main() vor runApp() aufrufen.
  static void initCommunication() {
    FlutterForegroundTask.initCommunicationPort();
  }

  static void _initService(int intervalMin) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'reise_tracking',
        channelName: 'Reise-Tracking',
        channelDescription:
            'Dauerhafte Benachrichtigung, solange das Standort-Tracking läuft.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(intervalMin * 60 * 1000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Kompletter Permission-Flow. Liefert den erreichten Status.
  /// Der Erklärungs-Dialog muss vorher von der UI gezeigt werden.
  static Future<PermissionStatus> requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return PermissionStatus.denied;
    }

    // Benachrichtigungs-Permission (Android 13+) für die Service-Notification.
    final np = await FlutterForegroundTask.checkNotificationPermission();
    if (np != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Hintergrund-Standort ("Immer erlauben", Android 10+): zweiter Request
    // öffnet die System-Einstellungen.
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.always) {
        return PermissionStatus.whileInUseOnly;
      }
    }
    return PermissionStatus.granted;
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<bool> start({int intervalMin = AppConst.defaultIntervalMin}) async {
    _initService(intervalMin);
    if (await FlutterForegroundTask.isRunningService) {
      final r = await FlutterForegroundTask.restartService();
      return r is ServiceRequestSuccess;
    }
    final r = await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'Reise-Tracker',
      notificationText: 'Standort-Tracking aktiv',
      callback: trackingTaskCallback,
    );
    return r is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Callback registrieren, mit dem der Service neue Punkte meldet.
  static void addDataCallback(void Function(Object) cb) =>
      FlutterForegroundTask.addTaskDataCallback(cb);

  static void removeDataCallback(void Function(Object) cb) =>
      FlutterForegroundTask.removeTaskDataCallback(cb);
}
