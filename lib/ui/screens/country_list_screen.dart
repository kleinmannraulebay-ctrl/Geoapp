import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flags.dart';
import '../../data/models.dart';
import '../../geo/geo_assets.dart';
import '../../providers/providers.dart';
import 'country_detail_screen.dart';

enum _Sort { alphabet, continent, percent }

enum _Filter { all, visited, unvisited }

/// Alle Länder, sortier- und filterbar, mit drei Prozentwerten pro Land.
class CountryListScreen extends ConsumerStatefulWidget {
  const CountryListScreen({super.key});

  @override
  ConsumerState<CountryListScreen> createState() => _CountryListScreenState();
}

class _CountryListScreenState extends ConsumerState<CountryListScreen> {
  _Sort _sort = _Sort.alphabet;
  _Filter _filter = _Filter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(countryStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Länder'),
        actions: [
          PopupMenuButton<_Sort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sortieren',
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.alphabet, child: Text('Alphabet')),
              PopupMenuItem(value: _Sort.continent, child: Text('Kontinent')),
              PopupMenuItem(value: _Sort.percent, child: Text('Prozent')),
            ],
          ),
          PopupMenuButton<_Filter>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtern',
            onSelected: (f) => setState(() => _filter = f),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Filter.all, child: Text('Alle')),
              PopupMenuItem(
                  value: _Filter.visited, child: Text('Nur besuchte')),
              PopupMenuItem(
                  value: _Filter.unvisited, child: Text('Nur unbesuchte')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Land suchen …',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (stats) {
          var list = stats.values.toList();
          if (_query.isNotEmpty) {
            list = list
                .where((s) => s.name.toLowerCase().contains(_query))
                .toList();
          }
          list = switch (_filter) {
            _Filter.all => list,
            _Filter.visited => list.where((s) => s.visited).toList(),
            _Filter.unvisited => list.where((s) => !s.visited).toList(),
          };
          switch (_sort) {
            case _Sort.alphabet:
              list.sort((a, b) => a.name.compareTo(b.name));
            case _Sort.continent:
              list.sort((a, b) {
                final c = a.continent.compareTo(b.continent);
                return c != 0 ? c : a.name.compareTo(b.name);
              });
            case _Sort.percent:
              list.sort((b, a) => (a.areaPercent + a.regionPercent +
                      a.cityPercent)
                  .compareTo(b.areaPercent + b.regionPercent + b.cityPercent));
          }
          final geo = ref.watch(geoDataProvider).valueOrNull;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (_, i) => _CountryTile(stats: list[i], geo: geo),
          );
        },
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final CountryStats stats;
  final GeoData? geo;
  const _CountryTile({required this.stats, this.geo});

  @override
  Widget build(BuildContext context) {
    String pct(double v) => '${(v * 100).toStringAsFixed(v >= 0.1 ? 0 : 1)} %';
    final iso2 = geo?.countryByCode[stats.code]?.iso2 ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CountryDetailScreen(countryCode: stats.code),
          )),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Text(flagEmoji(iso2), style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              stats.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (stats.visited) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle,
                                size: 15, color: Color(0xFF2DD4BF)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _StatChip(
                              icon: Icons.map,
                              text:
                                  '${stats.regionsVisited}/${stats.regionsTotal}'),
                          _StatChip(
                              icon: Icons.location_city,
                              text:
                                  '${stats.citiesVisited}/${stats.citiesListed}'),
                          _StatChip(
                              icon: Icons.grid_on,
                              text: pct(stats.areaPercent)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pct(stats.areaPercent),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: stats.visited
                            ? const Color(0xFF2DD4BF)
                            : Colors.white38,
                      ),
                    ),
                    const Text('Fläche',
                        style:
                            TextStyle(fontSize: 10, color: Colors.white38)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white54),
            const SizedBox(width: 4),
            Text(text,
                style:
                    const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      );
}
