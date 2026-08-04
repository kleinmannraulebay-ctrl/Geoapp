import '../geo/geo_data.dart';
import '../geo/geo_models.dart';
import 'app_database.dart';

/// Aggregierte Kennzahlen eines Landes.
class CountryAgg {
  final GeoFeature country;
  final int regionsTotal;
  final int regionsVisited;
  final int citiesTotal;
  final int citiesVisited;
  final double exploredKm2;
  final double areaPct; // 0..1
  final int visitDays;
  final int? firstTs;
  final int? lastTs;
  final bool hasManual;

  const CountryAgg({
    required this.country,
    required this.regionsTotal,
    required this.regionsVisited,
    required this.citiesTotal,
    required this.citiesVisited,
    required this.exploredKm2,
    required this.areaPct,
    required this.visitDays,
    required this.firstTs,
    required this.lastTs,
    required this.hasManual,
  });

  bool get visited =>
      visitDays > 0 || exploredKm2 > 0 || citiesVisited > 0 || hasManual;

  double get regionPct =>
      regionsTotal == 0 ? 0 : regionsVisited / regionsTotal;

  double get cityPct => citiesTotal == 0 ? 0 : citiesVisited / citiesTotal;

  /// Choropleth-Stufe 0–5 nach Besuchsintensität (Besuchstage).
  int get level => levelFor(visitDays, visited);

  static int levelFor(int visitDays, bool visited) {
    if (!visited) return 0;
    if (visitDays >= 30) return 5;
    if (visitDays >= 15) return 4;
    if (visitDays >= 7) return 3;
    if (visitDays >= 3) return 2;
    return 1;
  }
}

/// Kennzahlen für Kontinent bzw. Welt.
class ScopeAgg {
  final String name;
  final int countriesTotal;
  final int countriesVisited;
  final int citiesTotal;
  final int citiesVisited;
  final double areaKm2;
  final double exploredKm2;

  const ScopeAgg({
    required this.name,
    required this.countriesTotal,
    required this.countriesVisited,
    required this.citiesTotal,
    required this.citiesVisited,
    required this.areaKm2,
    required this.exploredKm2,
  });

  double get areaPct => areaKm2 == 0 ? 0 : clampPct(exploredKm2 / areaKm2);
  double get countryPct =>
      countriesTotal == 0 ? 0 : countriesVisited / countriesTotal;
  double get cityPct => citiesTotal == 0 ? 0 : citiesVisited / citiesTotal;
}

/// Anteil auf 0..1 begrenzen (Rasterzellen können Grenzen überlappen).
double clampPct(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Gesamtergebnis eines Statistik-Laufs.
class StatsSnapshot {
  final Map<String, CountryAgg> byCountry;
  final List<ScopeAgg> continents;
  final ScopeAgg world;
  final Set<String> visitedRegions;
  final Map<String, AreaStats> regionStats;
  final Map<int, CityVisit> cityVisits;
  final Map<String, List<ManualEntry>> manualByCountry;

  const StatsSnapshot({
    required this.byCountry,
    required this.continents,
    required this.world,
    required this.visitedRegions,
    required this.regionStats,
    required this.cityVisits,
    required this.manualByCountry,
  });
}

class StatsService {
  /// Reine Berechnung aus DB-Snapshots + Geodaten (testbar, kein IO).
  static StatsSnapshot compute({
    required GeoData geo,
    required Map<String, AreaStats> countryStats,
    required Map<String, AreaStats> regionStats,
    required Map<String, int> visitDays,
    required Map<int, CityVisit> cityVisits,
    required List<ManualEntry> manualEntries,
    required int citiesPerCountry,
  }) {
    // Manuell besuchte Regionen/Länder einsammeln.
    final manualByCountry = <String, List<ManualEntry>>{};
    final manualRegions = <String>{};
    for (final e in manualEntries) {
      manualByCountry.putIfAbsent(e.country, () => []).add(e);
      if (e.region != null) manualRegions.add(e.region!);
    }

    // Besuchte Regionen: getrackte Zellen oder manueller Eintrag.
    final visitedRegions = <String>{
      for (final r in regionStats.values)
        if (r.cellCount > 0) r.id,
      ...manualRegions,
    };

    // Regionen & Städte je Land vorgruppieren.
    final regionsByCountry = <String, int>{};
    final regionsVisitedByCountry = <String, int>{};
    for (final r in geo.regions) {
      regionsByCountry[r.country] = (regionsByCountry[r.country] ?? 0) + 1;
      if (visitedRegions.contains(r.id)) {
        regionsVisitedByCountry[r.country] =
            (regionsVisitedByCountry[r.country] ?? 0) + 1;
      }
    }

    final byCountry = <String, CountryAgg>{};
    for (final c in geo.countries) {
      final cs = countryStats[c.id];
      final cities = geo.citiesOf(c.id, limit: citiesPerCountry);
      var citiesVisited = 0;
      for (final city in cities) {
        final v = cityVisits[city.id];
        if (v != null && v.source != VisitSource.suppressed) citiesVisited++;
      }

      final manual = manualByCountry[c.id] ?? const <ManualEntry>[];
      // Erst-/Letztbesuch: Tracking und manuelle Zeiträume kombinieren.
      int? firstTs = cs?.firstTs;
      int? lastTs = cs?.lastTs;
      for (final e in manual) {
        final from = _parseDay(e.dateFrom);
        final to = _parseDay(e.dateTo) ?? from;
        if (from != null && (firstTs == null || from < firstTs)) firstTs = from;
        if (to != null && (lastTs == null || to > lastTs)) lastTs = to;
      }

      byCountry[c.id] = CountryAgg(
        country: c,
        regionsTotal: regionsByCountry[c.id] ?? 0,
        regionsVisited: regionsVisitedByCountry[c.id] ?? 0,
        citiesTotal: cities.length,
        citiesVisited: citiesVisited,
        exploredKm2: cs?.exploredKm2 ?? 0,
        areaPct: c.areaKm2 == 0
            ? 0
            : clampPct((cs?.exploredKm2 ?? 0) / c.areaKm2),
        visitDays: visitDays[c.id] ?? 0,
        firstTs: firstTs,
        lastTs: lastTs,
        hasManual: manual.isNotEmpty,
      );
    }

    // Kontinente & Welt aus den Länder-Aggregaten ableiten.
    const continentOrder = [
      'Africa',
      'Antarctica',
      'Asia',
      'Europe',
      'North America',
      'Oceania',
      'South America',
    ];
    final continents = <ScopeAgg>[];
    for (final cont in continentOrder) {
      final aggs = byCountry.values
          .where((a) => a.country.continent == cont)
          .toList();
      if (aggs.isEmpty) continue;
      continents.add(_scope(_continentNameDe(cont), aggs));
    }
    final world = _scope('Welt', byCountry.values.toList());

    return StatsSnapshot(
      byCountry: byCountry,
      continents: continents,
      world: world,
      visitedRegions: visitedRegions,
      regionStats: regionStats,
      cityVisits: cityVisits,
      manualByCountry: manualByCountry,
    );
  }

  static ScopeAgg _scope(String name, List<CountryAgg> aggs) {
    var area = 0.0, explored = 0.0;
    var cities = 0, citiesVisited = 0, visited = 0;
    for (final a in aggs) {
      area += a.country.areaKm2;
      explored += a.exploredKm2;
      cities += a.citiesTotal;
      citiesVisited += a.citiesVisited;
      if (a.visited) visited++;
    }
    return ScopeAgg(
      name: name,
      countriesTotal: aggs.length,
      countriesVisited: visited,
      citiesTotal: cities,
      citiesVisited: citiesVisited,
      areaKm2: area,
      exploredKm2: explored > area ? area : explored,
    );
  }

  static int? _parseDay(String? day) {
    if (day == null || day.isEmpty) return null;
    final dt = DateTime.tryParse(day);
    return dt?.millisecondsSinceEpoch;
  }

  static String _continentNameDe(String en) => const {
        'Africa': 'Afrika',
        'Antarctica': 'Antarktis',
        'Asia': 'Asien',
        'Europe': 'Europa',
        'North America': 'Nordamerika',
        'Oceania': 'Ozeanien',
        'South America': 'Südamerika',
      }[en] ??
      en;
}
