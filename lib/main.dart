import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/tracking_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Kommunikationsport zum Foreground-Service (muss vor runApp stehen).
  TrackingController.initCommunication();
  runApp(const ProviderScope(child: ReiseTrackerApp()));
}
