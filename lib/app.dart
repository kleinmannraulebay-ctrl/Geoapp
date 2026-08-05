import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/providers.dart';
import 'services/tracking_service.dart';
import 'ui/screens/continents_screen.dart';
import 'ui/screens/country_list_screen.dart';
import 'ui/screens/manual_entry_screen.dart';
import 'ui/screens/map_screen.dart';
import 'ui/screens/settings_screen.dart';

class ReiseTrackerApp extends StatelessWidget {
  const ReiseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2DD4BF),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF101B28),
      primary: const Color(0xFF2DD4BF),
    );
    return MaterialApp(
      title: 'Reise-Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B141E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B141E),
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF152232),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0E1824),
          indicatorColor: const Color(0xFF2DD4BF).withValues(alpha: 0.18),
          height: 70,
        ),
        dividerColor: Colors.white12,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      themeMode: ThemeMode.dark,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TrackingController.addDataCallback(_onServiceData);
    // Beim Start: liegengebliebene Punkte verarbeiten, ggf. Service starten.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processPending();
      _resumeTrackingIfEnabled();
    });
  }

  @override
  void dispose() {
    TrackingController.removeDataCallback(_onServiceData);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _processPending();
  }

  void _onServiceData(Object data) {
    if (data is Map && data['newPoint'] == true) _processPending();
  }

  Future<void> _resumeTrackingIfEnabled() async {
    // Kurz warten, bis die Einstellungen aus der DB geladen sind.
    await ref.read(databaseProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final s = ref.read(settingsProvider);
    if (s.trackingEnabled && !await TrackingController.isRunning) {
      await TrackingController.start(intervalMin: s.intervalMin);
    }
  }

  Future<void> _processPending() async {
    if (_processing) return;
    _processing = true;
    try {
      final stats = await ref.read(statsServiceProvider.future);
      final n = await stats.processPendingPoints();
      if (n > 0 && mounted) {
        ref.read(statsVersionProvider.notifier).state++;
      }
    } catch (_) {
      // Geodaten noch nicht geladen o. Ä. – nächster Anlauf bei Resume.
    } finally {
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = const [
      MapScreen(),
      CountryListScreen(),
      ContinentsScreen(),
      ManualEntryScreen(),
      SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: 'Karte'),
          NavigationDestination(icon: Icon(Icons.flag), label: 'Länder'),
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Welt'),
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'Nachträge'),
          NavigationDestination(
              icon: Icon(Icons.settings), label: 'Einstellungen'),
        ],
      ),
    );
  }
}
