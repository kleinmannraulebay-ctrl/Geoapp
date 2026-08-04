import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
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
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => _CountryTile(stats: list[i]),
          );
        },
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final CountryStats stats;
  const _CountryTile({required this.stats});

  @override
  Widget build(BuildContext context) {
    String pct(double v) => '${(v * 100).toStringAsFixed(v >= 0.1 ? 0 : 1)} %';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: stats.visited
            ? const Color(0xFF26A69A)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(stats.code.substring(0, 2)),
      ),
      title: Text(stats.name),
      subtitle: Text(
        '${stats.continent} · Regionen ${stats.regionsVisited}/${stats.regionsTotal}'
        ' · Städte ${stats.citiesVisited}/${stats.citiesListed}'
        ' · Fläche ${pct(stats.areaPercent)}',
      ),
      trailing: stats.visited
          ? const Icon(Icons.check_circle, color: Color(0xFF26A69A))
          : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CountryDetailScreen(countryCode: stats.code),
      )),
    );
  }
}
