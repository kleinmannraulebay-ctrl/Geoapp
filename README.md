# Reise-Tracker – Offline-Android-App

Ein vollständig **offline** arbeitender Reise-Tracker als Flutter-App:

- **Kein Internet**: Die Release-App deklariert keine `INTERNET`-Permission.
  Kein Account, kein Backend, keine Cloud, keine Analytics, keine Werbung.
- **Hintergrund-Standorttracking** über einen Foreground Service mit
  dauerhafter Notification, akkuschonend (Abfrage alle 10–15 min, Drosselung
  bei Stillstand, Punkte erst ab 250 m Bewegung, Genauigkeitsfilter 200 m).
- **Offline-Weltkarte** (Choropleth) aus gebündelten, vereinfachten
  Natural-Earth-Polygonen – keine Online-Tiles. Länderfärbung in 5 Stufen
  nach Besuchsintensität, ab Zoomstufe 4,5 Regionsfärbung, Tap öffnet die
  Länder-Detailseite.
- **Erkundungs-Prozentsatz** über ein globales 0,05°-Raster (~31 km²/Zelle
  am Äquator): erkundete Fläche ÷ Landes-/Regions-/Kontinent-/Weltfläche,
  optional als „Fog of War“-Overlay.
- **Städte-Checkliste** pro Land (Top 10/25/40 nach Einwohnerzahl,
  GeoNames-Daten). Automatische Erkennung im Radius 5–25 km (skaliert mit
  der Einwohnerzahl), manuelles Abhaken möglich; manuelle Häkchen werden
  vom Auto-Tracking nie überschrieben.
- **Länderliste** (~240 Länder/Gebiete) mit Suche, Filtern und drei
  Prozentwerten (Regionen, Städte, Fläche) plus Detailseite mit Mini-Karte.
- **Kontinent-Dashboard** mit Welt-Gesamtstatistik.
- **Manuelle Einträge** (Land/Region/Stadt, Zeitraum, Notiz) – klar von
  automatischen getrennt (`source: auto|manual`), einzeln editier-/löschbar.
- **Backup**: Export/Import der kompletten Datenbank als JSON über den
  Android-Dateidialog (SAF) – ohne Cloud.
- Dark Mode (Standard) und deutsche UI.

## Projektstruktur

```
assets/geo/            Gebündelte Offline-Geodaten (gzip, ~2 MB)
  countries.geojson.gz   240 Länder (Natural Earth 50m, vereinfacht)
  regions.geojson.gz     4.416 Regionen (Natural Earth 10m, vereinfacht)
  cities.json.gz         5.543 Städte (GeoNames, Top 40 je Land)
lib/
  geo/                 Pure-Dart-Geo-Logik (unit-getestet)
    spherical.dart       Haversine, sphärische Ringfläche
    grid.dart            0,05°-Erkundungsraster (Zellen-IDs, Flächen)
    point_in_polygon.dart  Ray-Casting mit BBox-Vorfilter
    geo_index.dart       2°-Bucket-Index (Punkt→Feature < 10 ms)
    geo_data.dart        Asset-Parsing, Städte-Buckets
    classifier.dart      Punkt → Land/Region/Zelle/Städte
  data/
    app_database.dart    SQLite-Schema + inkrementelle Aggregate
    stats_service.dart   Prozentformeln, Kontinent-/Welt-Aggregation
    geo_repository.dart  Asset-Laden im Isolate
  services/
    tracking_service.dart   Foreground Service (flutter_foreground_task)
    ingest_service.dart     Zuordnung im Isolate + DB-Transaktion
    permission_service.dart Permission-Flow mit Erklärungs-Dialog
    backup_service.dart     JSON-Export/-Import (SAF)
  state/               Riverpod-Provider + Einstellungen
  ui/                  Screens (Karte, Übersicht, Länder, Detail,
                       manuelle Einträge, Einstellungen)
test/                  Unit-Tests der Geo-/Statistik-Logik
tool/prepare_assets.py Aufbereitung der Geodaten-Assets
```

## Datenbankschema (SQLite)

| Tabelle | Zweck |
|---|---|
| `track_points` | Roh-Punkte (`lat`, `lon`, `timestamp`, `accuracy`, `processed`) |
| `explored_cells` | Erkundete Rasterzellen mit Land/Region/Fläche |
| `country_stats` / `region_stats` | **Inkrementell** fortgeschriebene Aggregate (Fläche, Zellzahl, Erst-/Letztbesuch) |
| `country_days` | Distinkte Besuchstage je Land (Choropleth-Intensität) |
| `city_visits` | Städte-Häkchen (`auto` / `manual` / `suppressed`) |
| `manual_entries` | Manuell nachgetragene Reisen (Land, Region, Stadt, Zeitraum, Notiz) |

Statistiken werden beim Ingest inkrementell fortgeschrieben – Screens lesen
nur die kleinen Aggregat-Tabellen, nie alle Punkte.

## Voraussetzungen

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable,
  ≥ 3.24; getestet mit 3.35) inkl. Android-Toolchain (Android SDK,
  Platform-Tools). `flutter doctor` muss für Android grün sein.
- Java 17 (bei aktuellen Android-Studio-Installationen enthalten).
- Nur für die Neu-Aufbereitung der Geodaten: Python 3 + `pip install geonamescache`.

## Build: Schritt für Schritt zur signierten APK

### 1. Projekt vorbereiten

```bash
git clone <dieses-Repo> && cd Geoapp
# fehlende Plattform-Dateien (u. a. Gradle-Wrapper) ergänzen – vorhandene
# Dateien werden dabei NICHT überschrieben:
flutter create --platforms=android --project-name reise_tracker .
flutter pub get
flutter test          # 34 Unit-Tests der Geo-/Statistik-Logik
```

Die fertigen Geodaten-Assets liegen bereits unter `assets/geo/`.
Neu erzeugen (optional, z. B. mit anderem Vereinfachungsgrad):

```bash
mkdir -p tool/raw && cd tool/raw
curl -LO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
curl -LO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson
mv ne_50m_admin_0_countries.geojson ne_50m_admin_0.geojson
mv ne_10m_admin_1_states_provinces.geojson ne_10m_admin_1.geojson
cd ../..
pip install geonamescache
python3 tool/prepare_assets.py tool/raw assets/geo
```

### 2. Keystore erzeugen (einmalig)

```bash
keytool -genkey -v -keystore ~/reise-tracker.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias reisetracker
```

Dann `android/key.properties` anlegen (liegt in `.gitignore`, landet nie im Repo):

```properties
storeFile=/absoluter/pfad/zu/reise-tracker.jks
storePassword=DEIN_STORE_PASSWORT
keyAlias=reisetracker
keyPassword=DEIN_KEY_PASSWORT
```

Ohne `key.properties` wird der Release-Build automatisch mit dem
Debug-Schlüssel signiert (praktisch zum Ausprobieren, nicht für die Weitergabe).

### 3. APK bauen

```bash
flutter build apk --release
# Ergebnis: build/app/outputs/flutter-apk/app-release.apk
```

Optional kleinere APKs je CPU-Architektur:

```bash
flutter build apk --release --split-per-abi
```

### 4. Auf dem Gerät installieren

**Per USB/adb** (Entwickleroptionen + USB-Debugging aktivieren):

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

**Per Sideload**: die APK aufs Gerät kopieren (USB, Dateimanager),
antippen und die Installation aus unbekannten Quellen für die jeweilige
App (z. B. den Dateimanager) erlauben.

### 5. Erste Schritte in der App

1. „Mehr → Einstellungen → Hintergrund-Tracking“ aktivieren.
2. Im Permission-Dialog **„Immer erlauben“** wählen (Hintergrund-Standort).
3. Optional die Ausnahme von der Akku-Optimierung bestätigen, damit Android
   den Service nicht beendet.
4. Frühere Reisen unter „Mehr → Manuelle Einträge“ nachtragen.

## Troubleshooting

- **Gradle-/AGP-Fehler nach `flutter create`**: Die Versionen sind in
  `android/settings.gradle` gepinnt (AGP 8.7.3, Kotlin 2.1.0,
  Gradle-Wrapper 8.12). Bei einer deutlich neueren Flutter-Version ggf. an
  die dort empfohlenen Versionen anpassen.
- **`Namespace not specified`**: Tritt nur auf, wenn `flutter create` die
  App-Gradle-Datei überschrieben hätte – `git checkout android/app/build.gradle`.
- **Tracking stoppt nach Stunden**: Akku-Optimierung für die App
  deaktivieren (Einstellungen → Apps → Reise-Tracker → Akku).

## Datenquellen & Lizenzen

- Länder/Regionen: [Natural Earth](https://www.naturalearthdata.com/)
  (Public Domain), per `tool/prepare_assets.py` vereinfacht
  (Douglas-Peucker, Koordinaten auf ~110 m gerundet).
- Städte: [GeoNames](https://www.geonames.org/) über das Python-Paket
  `geonamescache` (Daten CC BY 4.0) – Namensnennung in der App unter
  „Mehr → Datenquellen“.
