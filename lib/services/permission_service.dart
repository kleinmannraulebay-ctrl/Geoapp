import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Sauberer Permission-Flow mit Erklärungs-Dialog:
/// 1. Erklärung anzeigen, 2. Standort (App-Nutzung), 3. Hintergrund-Standort
/// ("Immer erlauben", ab Android 10 eigener Schritt), 4. Benachrichtigung.
class PermissionService {
  static Future<bool> requestTrackingPermissions(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Standortzugriff'),
        content: const Text(
          'Der Reise-Tracker zeichnet deinen Standort auch im Hintergrund '
          'auf, um besuchte Länder, Regionen und Städte automatisch zu '
          'erkennen.\n\n'
          'Alle Daten bleiben ausschließlich lokal auf diesem Gerät – die '
          'App hat keine Internet-Berechtigung.\n\n'
          'Bitte wähle im nächsten Schritt „Immer erlauben“, damit die '
          'Aufzeichnung auch bei ausgeschaltetem Bildschirm funktioniert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) {
        _snack(context, 'Bitte aktiviere die Standortdienste des Geräts.');
      }
      await Geolocator.openLocationSettings();
      return false;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (context.mounted) {
        _snack(context,
            'Ohne Standort-Berechtigung ist kein Tracking möglich.');
      }
      return false;
    }

    // Hintergrund-Standort ("Immer erlauben").
    final always = await ph.Permission.locationAlways.request();
    if (!always.isGranted && context.mounted) {
      _snack(
          context,
          'Hinweis: Ohne „Immer erlauben“ pausiert die Aufzeichnung, '
          'sobald die App geschlossen wird.');
    }

    // Benachrichtigung (Pflicht für den Foreground Service ab Android 13).
    final notif = await FlutterForegroundTask.checkNotificationPermission();
    if (notif != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Optional: Akku-Optimierung ausnehmen, damit Android den Service
    // nicht einschläfert.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    return true;
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
