import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ingest_service.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import 'country_list_screen.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'more_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;
  Timer? _ingestDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ingest());
  }

  @override
  void dispose() {
    _ingestDebounce?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ingest();
  }

  void _onTaskData(Object data) {
    if (data == 'new_point') {
      // Mehrere Punkte kurz hintereinander bündeln.
      _ingestDebounce?.cancel();
      _ingestDebounce = Timer(const Duration(seconds: 2), _ingest);
    } else if (data is Map && data.containsKey('pausedChanged')) {
      ref
          .read(settingsProvider.notifier)
          .setTracking(paused: data['pausedChanged'] == true);
    }
  }

  Future<void> _ingest() async {
    try {
      final geo = await ref.read(geoDataProvider.future);
      final db = await ref.read(databaseProvider.future);
      final processed = await IngestService(db, geo).ingestPending();
      if (processed > 0 && mounted) {
        ref.read(refreshTickProvider.notifier).state++;
      }
    } catch (_) {
      // Geodaten noch nicht bereit – nächster Anlauf beim Resume.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          MapScreen(),
          DashboardScreen(),
          CountryListScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Karte'),
          NavigationDestination(
              icon: Icon(Icons.public_outlined), label: 'Übersicht'),
          NavigationDestination(
              icon: Icon(Icons.flag_outlined), label: 'Länder'),
          NavigationDestination(
              icon: Icon(Icons.more_horiz), label: 'Mehr'),
        ],
      ),
    );
  }
}
