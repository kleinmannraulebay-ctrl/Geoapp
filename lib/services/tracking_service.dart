import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';

/// Schlüssel für die Kommunikation Service ↔ App.
class TrackingPrefs {
  static const paused = 'tracking_paused';
  static const enabled = 'tracking_enabled';
  static const intervalMinutes = 'tracking_interval_min';
  static const lastLat = 'tracking_last_lat';
  static const lastLon = 'tracking_last_lon';
  static const lastTs = 'tracking_last_ts';
}

/// Mindestdistanz, ab der ein neuer Punkt gespeichert wird.
const double kMinDistanceMeters = 250;

/// Punkte mit schlechterer Genauigkeit werden verworfen.
const double kMaxAccuracyMeters = 200;

@pragma('vm:entry-point')
void trackerStartCallback() {
  FlutterForegroundTask.setTaskHandler(TrackerTaskHandler());
}

/// Läuft im Service-Isolate (eigene Flutter-Engine, Plugins verfügbar).
///
/// Akku-Strategie: Standard-Abfrage alle 10–15 Minuten (konfigurierbar).
/// Bewegt sich das Gerät nicht (< 250 m seit letztem Punkt), wird auf jeden
/// zweiten Zyklus gedrosselt; erst eine erneute Bewegung hebt das auf.
class TrackerTaskHandler extends TaskHandler {
  AppDatabase? _db;
  double? _lastLat;
  double? _lastLon;
  bool _paused = false;
  bool _stationary = false;
  bool _skipTick = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    _paused = prefs.getBool(TrackingPrefs.paused) ?? false;
    _lastLat = prefs.getDouble(TrackingPrefs.lastLat);
    _lastLon = prefs.getDouble(TrackingPrefs.lastLon);
    _db = await AppDatabase.open();
    await _updateNotification();
    // Direkt beim Start eine Position erfassen.
    if (!_paused) await _sample();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (_paused) return;
    if (_stationary && !_skipTick) {
      // Stillstand: jeden zweiten Zyklus auslassen (Drosselung).
      _skipTick = true;
      return;
    }
    _skipTick = false;
    await _sample();
  }

  Future<void> _sample() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 50),
        ),
      );
      if (pos.accuracy > kMaxAccuracyMeters) return;

      final movedMeters = (_lastLat == null)
          ? double.infinity
          : Geolocator.distanceBetween(
              _lastLat!, _lastLon!, pos.latitude, pos.longitude);
      _stationary = movedMeters < kMinDistanceMeters;
      if (_stationary) {
        await _updateNotification();
        return;
      }

      _lastLat = pos.latitude;
      _lastLon = pos.longitude;
      final ts = pos.timestamp.millisecondsSinceEpoch;
      await _db?.insertTrackPoint(
          pos.latitude, pos.longitude, ts, pos.accuracy);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(TrackingPrefs.lastLat, pos.latitude);
      await prefs.setDouble(TrackingPrefs.lastLon, pos.longitude);
      await prefs.setInt(TrackingPrefs.lastTs, ts);
      await _updateNotification();
      // Falls die App offen ist: sofort zuordnen.
      FlutterForegroundTask.sendDataToMain('new_point');
    } on Exception {
      // Kein Fix (Timeout, Flugmodus …) – nächster Zyklus versucht es erneut.
    }
  }

  Future<void> _updateNotification() async {
    final state = _paused
        ? 'pausiert'
        : (_stationary ? 'aktiv – Stillstand erkannt' : 'aktiv');
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Reise-Tracker',
      notificationText: 'Aufzeichnung $state',
    );
  }

  @override
  Future<void> onReceiveData(Object data) async {
    if (data is Map && data['cmd'] == 'setPaused') {
      _paused = data['value'] == true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(TrackingPrefs.paused, _paused);
      await _updateNotification();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'pauseToggle') {
      onReceiveData({'cmd': 'setPaused', 'value': !_paused});
      FlutterForegroundTask.sendDataToMain({'pausedChanged': !_paused});
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// Steuerung des Services aus der App heraus (Haupt-Isolate).
class TrackingController {
  static Future<void> init(int intervalMinutes) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'reise_tracker_tracking',
        channelName: 'Standort-Aufzeichnung',
        channelDescription:
            'Dauerhafte Benachrichtigung während der Reiseaufzeichnung.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction:
            ForegroundTaskEventAction.repeat(intervalMinutes * 60 * 1000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<bool> start(int intervalMinutes) async {
    await init(intervalMinutes);
    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Reise-Tracker',
      notificationText: 'Aufzeichnung aktiv',
      notificationButtons: [
        const NotificationButton(id: 'pauseToggle', text: 'Pause/Weiter'),
      ],
      callback: trackerStartCallback,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(TrackingPrefs.enabled, true);
    return result is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(TrackingPrefs.enabled, false);
  }

  static Future<void> setPaused(bool paused) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(TrackingPrefs.paused, paused);
    if (await isRunning) {
      FlutterForegroundTask.sendDataToTask({'cmd': 'setPaused', 'value': paused});
    }
  }

  /// Startet den Service neu, wenn das Intervall geändert wurde.
  static Future<void> restartWithInterval(int intervalMinutes) async {
    if (await isRunning) {
      await FlutterForegroundTask.stopService();
      await start(intervalMinutes);
    }
  }
}
