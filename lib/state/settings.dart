import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final ThemeMode themeMode;
  final bool fogOverlay;
  final int citiesPerCountry; // 10 / 25 / 40
  final int intervalMinutes; // 10 oder 15
  final bool trackingEnabled;
  final bool trackingPaused;

  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.fogOverlay = false,
    this.citiesPerCountry = 25,
    this.intervalMinutes = 10,
    this.trackingEnabled = false,
    this.trackingPaused = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? fogOverlay,
    int? citiesPerCountry,
    int? intervalMinutes,
    bool? trackingEnabled,
    bool? trackingPaused,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        fogOverlay: fogOverlay ?? this.fogOverlay,
        citiesPerCountry: citiesPerCountry ?? this.citiesPerCountry,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        trackingEnabled: trackingEnabled ?? this.trackingEnabled,
        trackingPaused: trackingPaused ?? this.trackingPaused,
      );
}

/// Wird in main() mit der echten Instanz überschrieben.
final sharedPrefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences prefs;

  SettingsNotifier(this.prefs)
      : super(AppSettings(
          themeMode:
              ThemeMode.values[prefs.getInt('ui_theme_mode') ?? ThemeMode.dark.index],
          fogOverlay: prefs.getBool('ui_fog_overlay') ?? false,
          citiesPerCountry: prefs.getInt('ui_cities_per_country') ?? 25,
          intervalMinutes: prefs.getInt('tracking_interval_min') ?? 10,
          trackingEnabled: prefs.getBool('tracking_enabled') ?? false,
          trackingPaused: prefs.getBool('tracking_paused') ?? false,
        ));

  void setThemeMode(ThemeMode m) {
    state = state.copyWith(themeMode: m);
    prefs.setInt('ui_theme_mode', m.index);
  }

  void setFogOverlay(bool v) {
    state = state.copyWith(fogOverlay: v);
    prefs.setBool('ui_fog_overlay', v);
  }

  void setCitiesPerCountry(int v) {
    state = state.copyWith(citiesPerCountry: v);
    prefs.setInt('ui_cities_per_country', v);
  }

  void setIntervalMinutes(int v) {
    state = state.copyWith(intervalMinutes: v);
    prefs.setInt('tracking_interval_min', v);
  }

  void setTracking({bool? enabled, bool? paused}) {
    state = state.copyWith(trackingEnabled: enabled, trackingPaused: paused);
    if (enabled != null) prefs.setBool('tracking_enabled', enabled);
    if (paused != null) prefs.setBool('tracking_paused', paused);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.watch(sharedPrefsProvider));
});
