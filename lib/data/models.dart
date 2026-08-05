/// App-interne Datenmodelle (Statistik, manuelle Einträge).
library;

class CountryStats {
  final String code;
  final String name;
  final String continent;
  final double areaKm2;

  final int visitDays;
  final double exploredKm2;
  final int regionsVisited;
  final int regionsTotal;
  final int citiesVisited;
  final int citiesListed;
  final int? firstTs;
  final int? lastTs;
  final bool hasAuto;
  final bool hasManual;

  const CountryStats({
    required this.code,
    required this.name,
    required this.continent,
    required this.areaKm2,
    this.visitDays = 0,
    this.exploredKm2 = 0,
    this.regionsVisited = 0,
    this.regionsTotal = 0,
    this.citiesVisited = 0,
    this.citiesListed = 0,
    this.firstTs,
    this.lastTs,
    this.hasAuto = false,
    this.hasManual = false,
  });

  bool get visited => hasAuto || hasManual;

  double get areaPercent =>
      areaKm2 <= 0 ? 0 : (exploredKm2 / areaKm2).clamp(0.0, 1.0);
  double get regionPercent =>
      regionsTotal <= 0 ? 0 : (regionsVisited / regionsTotal).clamp(0.0, 1.0);
  double get cityPercent =>
      citiesListed <= 0 ? 0 : (citiesVisited / citiesListed).clamp(0.0, 1.0);
}

class ContinentStats {
  final String name;
  final int countriesVisited;
  final int countriesTotal;
  final int citiesVisited;
  final int citiesListed;
  final double exploredKm2;
  final double areaKm2;

  const ContinentStats({
    required this.name,
    required this.countriesVisited,
    required this.countriesTotal,
    required this.citiesVisited,
    required this.citiesListed,
    required this.exploredKm2,
    required this.areaKm2,
  });

  double get areaPercent =>
      areaKm2 <= 0 ? 0 : (exploredKm2 / areaKm2).clamp(0.0, 1.0);
}

class WorldStats {
  final int countriesVisited;
  final int countriesTotal;
  final int citiesVisited;
  final int citiesListed;
  final double exploredKm2;
  final double areaKm2;
  final List<ContinentStats> continents;

  const WorldStats({
    required this.countriesVisited,
    required this.countriesTotal,
    required this.citiesVisited,
    required this.citiesListed,
    required this.exploredKm2,
    required this.areaKm2,
    required this.continents,
  });

  double get areaPercent =>
      areaKm2 <= 0 ? 0 : (exploredKm2 / areaKm2).clamp(0.0, 1.0);
}

/// Besuchsstatus einer Stadt in der Checkliste.
class CityVisit {
  final int cityId;
  final int? firstTs;
  final String status; // 'visited' | 'dismissed'
  final String source; // 'auto' | 'manual'

  const CityVisit({
    required this.cityId,
    required this.firstTs,
    required this.status,
    required this.source,
  });

  bool get isVisited => status == 'visited';
  bool get isManual => source == 'manual';
}

class ManualEntry {
  final int id;
  final String type; // 'country' | 'region' | 'city'
  final String countryCode;
  final String? regionId;
  final int? cityId;
  final String? dateFrom; // ISO yyyy-MM-dd
  final String? dateTo;
  final String? note;
  final int createdTs;

  const ManualEntry({
    required this.id,
    required this.type,
    required this.countryCode,
    this.regionId,
    this.cityId,
    this.dateFrom,
    this.dateTo,
    this.note,
    required this.createdTs,
  });

  static ManualEntry fromRow(Map<String, Object?> row) => ManualEntry(
        id: row['id'] as int,
        type: row['type'] as String,
        countryCode: row['country_code'] as String,
        regionId: row['region_id'] as String?,
        cityId: row['city_id'] as int?,
        dateFrom: row['date_from'] as String?,
        dateTo: row['date_to'] as String?,
        note: row['note'] as String?,
        createdTs: row['created_ts'] as int,
      );
}
