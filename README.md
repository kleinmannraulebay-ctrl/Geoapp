# Reise-Tracker (Offline)

Eine Android-App (Flutter), die deine Reisen **vollständig offline** aufzeichnet:

- **Hintergrund-Tracking** über einen Foreground-Service (dauerhafte Notification), akkuschonend: Position alle 10–15 Minuten *oder* nach > 250 m Bewegung; Positionen ungenauer als 200 m werden verworfen.
- **Offline-Weltkarte** (Choropleth) aus gebündelten Natural-Earth-GeoJSON-Assets — keine Online-Tiles, die App deklariert **keine INTERNET-Permission**.
- **Erkundungs-Prozentsatz** über ein globales 0,05°-Raster (≈ 20–31 km² pro Zelle, sphärisch korrekt berechnet), optional als „Fog of War“-Overlay.
- **Städte-Checkliste** (Top 10/25/50 pro Land, Radius nach Einwohnerzahl 5–25 km), **Länderliste** mit drei Prozentwerten (Regionen/Städte/Fläche), **Kontinent-Dashboard** mit Welt-Gesamtstatistik.
- **Manuelle Nachträge** früherer Reisen (Land/Region/Stadt, Zeitraum, Notiz), klar getrennt von automatischen Daten, einzeln editier-/löschbar.
- **Backup**: Export/Import der kompletten SQLite-Datenbank als JSON über den Android-Dateidialog.
- Dark Mode, deutsche UI. Alle Daten bleiben in einer lokalen SQLite-Datenbank.

## Projektstruktur (Kurzüberblick)

```
lib/
  core/constants.dart          Tuning-Konstanten (Intervalle, Radien, Stufen)
  data/database.dart           SQLite-Schema (sqflite) + Migrationen
  data/models.dart             Statistik-/Eintrags-Modelle
  geo/point_in_polygon.dart    Ray-Casting (Even-Odd) + BBox-Vorfilter
  geo/spatial_index.dart       Grid-Index über Polygone & Städte (<10 ms/Punkt)
  geo/exploration_grid.dart    0,05°-Erkundungsraster (Zell-IDs, Flächen)
  geo/geo_assets.dart          Laden/Parsen der gzip-GeoJSON-Assets (im Isolate)
  geo/assigner.dart            Punkt → Land/Region/Zelle/Städte (Isolate-Batch)
  services/tracking_service.dart  Foreground-Service + Permission-Flow
  services/stats_service.dart     inkrementelle Aggregat-Fortschreibung
  services/backup_service.dart    JSON-Export/-Import
  providers/providers.dart     Riverpod-Provider
  ui/…                         Screens (Karte, Länder, Welt, Nachträge, Settings)
assets/geo/                    countries/regions/cities (gzip, ~1,9 MB gesamt)
tool/prepare_assets.py         Geodaten-Aufbereitung (reproduzierbar)
test/                          Unit-Tests der Geo-Logik
```

Der Tracking-Service schreibt nur Roh-Punkte (`processed = 0`); die App ordnet sie beim Öffnen/Resume (und live per Service-Nachricht) im Isolate zu und schreibt Aggregat-Tabellen fort (`visited_cells`, `country_visits`, `region_visits`, `city_visits`, `visit_days`). Kein Screen rechnet je über alle Punkte.

## Benötigte Tools

| Tool | Version | Zweck |
| --- | --- | --- |
| Flutter SDK | aktuelle stable (≥ 3.24) | App bauen |
| Android SDK | API 35, Build-Tools, Platform-Tools | Kompilieren + `adb` |
| JDK | 17 | Gradle/Keystore |
| Python 3 | ≥ 3.9 | nur für `tool/prepare_assets.py` (optional, Assets liegen bei) |

Android Studio installiert Android SDK + JDK bequem mit; alternativ `sdkmanager`.

## 1. Geodaten-Assets (optional neu erzeugen)

Die fertigen Assets liegen bereits unter `assets/geo/`. Neu erzeugen (lädt Natural-Earth-Daten von GitHub, vereinfacht per Douglas-Peucker, berechnet Flächen, gzippt):

```bash
python3 tool/prepare_assets.py
```

Quellen: Natural Earth `admin_0_countries` (50m), `admin_1_states_provinces` (10m), `populated_places` (Public Domain). Hinweis: Der ursprünglich angedachte GeoNames-/simplemaps-Städtedatensatz war aus dieser Build-Umgebung nicht erreichbar; `populated_places` (7.333 Städte mit Einwohnerzahlen) deckt die Top-Städte aller Länder ab. Wer `cities15000` möchte, kann `process_places()` im Skript leicht auf das GeoNames-TSV-Format umstellen.

## 2. Abhängigkeiten & Tests

```bash
flutter pub get
flutter test          # Unit-Tests der Geo-Logik (Ray-Casting, Raster, Formeln)
flutter analyze
```

> Die Paketversionen sind in `pubspec.yaml` exakt gepinnt, weil dieses Projekt ohne lokale Flutter-Toolchain generiert wurde. Falls `flutter pub get` mit deiner Flutter-Version einen Konflikt meldet, hebe die betroffene Version an und prüfe die im Code verwendeten APIs (v. a. `flutter_foreground_task`, dessen API sich zwischen Major-Versionen ändert).
>
> Sollte das mitgelieferte `android/`-Gerüst nicht zu deiner Flutter-Version passen (Gradle-/AGP-Fehler): `flutter create --platforms=android .` regeneriert es; danach `AndroidManifest.xml` (Permissions + Service-Deklaration, **keine** INTERNET-Permission), `applicationId`, `minSdk 26` und den `key.properties`-Block in `android/app/build.gradle` aus diesem Repo übernehmen.

## 3. Debug-Build aufs Gerät

```bash
flutter run            # Gerät per USB, Entwickleroptionen + USB-Debugging aktiv
```

## 4. Signierte Release-APK

### 4.1 Keystore erzeugen (einmalig)

```bash
keytool -genkey -v \
  -keystore ~/reise-tracker-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias reisetracker
```

Passwörter gut aufbewahren — ohne den Keystore sind keine Updates derselben App-Signatur möglich.

### 4.2 `android/key.properties` anlegen (nicht einchecken!)

```properties
storeFile=/absoluter/pfad/zu/reise-tracker-release.jks
storePassword=DEIN_STORE_PASSWORT
keyAlias=reisetracker
keyPassword=DEIN_KEY_PASSWORT
```

`.gitignore` schließt `key.properties` und `*.jks` bereits aus.

### 4.3 Bauen

```bash
flutter build apk --release
# Ergebnis: build/app/outputs/flutter-apk/app-release.apk
```

Ohne `key.properties` wird automatisch mit dem Debug-Key signiert (nur zum Testen; Play-Store-tauglich ist nur die Keystore-Signatur).

## 5. Installation auf dem Gerät

**Per `adb` (USB-Debugging aktiv):**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**Per Sideload:** die APK aufs Gerät kopieren (USB/Dateimanager), dort antippen und die Installation aus unbekannten Quellen für den Dateimanager einmalig erlauben.

## 6. Erster Start

1. Einstellungen → „Standort-Tracking“ aktivieren.
2. Erklärungs-Dialog bestätigen, dann die System-Abfragen: Standort **„Während der Nutzung“** erlauben, anschließend in den Systemeinstellungen auf **„Immer erlauben“** stellen (nötig für Hintergrund-Tracking, Android 10+). Auf Android 13+ zusätzlich Benachrichtigungen erlauben (für die Service-Notification).
3. Optional: Akku-Optimierung für die App deaktivieren (Einstellungen → Apps → Reise-Tracker → Akku), sonst drosseln manche Hersteller (Xiaomi, Samsung …) den Service aggressiv.

## Datenschutz

Kein Konto, kein Backend, keine Analytics, keine Werbung. Die App fordert keine INTERNET-Permission an — sie *kann* technisch nichts hochladen. Backup/Restore läuft ausschließlich über lokale JSON-Dateien, die du selbst über den Android-Dateidialog wählst.

## Lizenz der Kartendaten

[Natural Earth](https://www.naturalearthdata.com/) — Public Domain.
