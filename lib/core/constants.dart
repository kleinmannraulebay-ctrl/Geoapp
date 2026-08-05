/// Zentrale Konstanten der App.
library;

class AppConst {
  AppConst._();

  // ---- Tracking ----
  /// Positionen mit schlechterer Genauigkeit werden verworfen (Meter).
  static const double maxAccuracyM = 200;

  /// Distanzfilter des Positions-Streams (Meter).
  static const int distanceFilterM = 250;

  /// Standard-Intervall der periodischen Abfrage (Minuten, 10–15 einstellbar).
  static const int defaultIntervalMin = 12;

  // ---- Flug-Filter ----
  /// Über dieser Geschwindigkeit (m/s) ist kein Bodenfahrzeug mehr plausibel
  /// (100 m/s = 360 km/h) – Punkt wird verworfen.
  static const double hardMaxSpeedMs = 100;

  /// Ab dieser Kombination aus Geschwindigkeit und Höhe gilt der Punkt als
  /// Flug (200 km/h in > 2.500 m Höhe fährt kein Auto/Zug).
  static const double flightSpeedMs = 55;
  static const double flightAltitudeM = 2500;

  /// Überflüge zählen nicht als Besuch: Punkte mit Fluggeschwindigkeit
  /// werden gar nicht erst gespeichert (z. B. Spanien beim Flug nach
  /// Marokko).
  static bool isLikelyFlight(double speedMs, double altitudeM) {
    if (speedMs > hardMaxSpeedMs) return true;
    return speedMs > flightSpeedMs && altitudeM > flightAltitudeM;
  }

  // ---- Erkundungsraster ----
  /// Rasterauflösung in Grad (0,05° ≈ 5,5 km in N-S-Richtung).
  static const double gridRes = 0.05;

  // ---- Städte ----
  /// Standard: Top-N-Städte pro Land in der Checkliste.
  static const int defaultTopCities = 25;

  /// Auto-Besuchs-Radius (km) abhängig von der Einwohnerzahl.
  static double cityRadiusKm(int population) {
    if (population >= 5000000) return 25;
    if (population >= 1000000) return 18;
    if (population >= 500000) return 12;
    if (population >= 200000) return 10;
    if (population >= 50000) return 8;
    return 5;
  }

  /// Größter möglicher Städte-Radius (für die Kandidatensuche im Index).
  static const double maxCityRadiusKm = 25;

  // ---- Choropleth ----
  /// Ab dieser Zoomstufe werden Regionen statt Länder eingefärbt.
  static const double regionZoomThreshold = 5.0;

  /// Ab dieser Zoomstufe wird der Fog-of-War-Layer gezeichnet.
  static const double fogZoomThreshold = 7.0;

  /// Stufe 1–5 anhand der Anzahl unterschiedlicher Besuchstage.
  static int intensityStage(int visitDays) {
    if (visitDays <= 0) return 0;
    if (visitDays >= 30) return 5;
    if (visitDays >= 14) return 4;
    if (visitDays >= 7) return 3;
    if (visitDays >= 3) return 2;
    return 1;
  }

  // ---- Statistik ----
  /// Flächen-Prozent, robust gegen Rundungsfehler (0..1).
  static double areaPercent(double exploredKm2, double totalKm2) {
    if (totalKm2 <= 0) return 0;
    final p = exploredKm2 / totalKm2;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }

  static double ratioPercent(int visited, int total) {
    if (total <= 0) return 0;
    final p = visited / total;
    return p > 1 ? 1 : p;
  }
}
