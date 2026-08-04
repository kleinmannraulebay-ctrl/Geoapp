import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/stats_service.dart';
import '../../state/providers.dart';
import '../format.dart';
import 'country_detail_screen.dart';

enum _SortMode { name, continent, percent }

enum _VisitFilter { all, visited, unvisited }

class CountryListScreen extends ConsumerStatefulWidget {
  const CountryListScreen({super.key});

  @override
  ConsumerState<CountryListScreen> createState() => _CountryListScreenState();
}

class _CountryListScreenState extends ConsumerState<CountryListScreen> {
  String _search = '';
  _SortMode _sort = _SortMode.name;
  _VisitFilter _filter = _VisitFilter.all;
  String? _continent;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Länder'),
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sortieren',
            onSelected: (m) => setState(() => _sort = m),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _SortMode.name, child: Text('Alphabetisch')),
              PopupMenuItem(
                  value: _SortMode.continent, child: Text('Nach Kontinent')),
              PopupMenuItem(
                  value: _SortMode.percent, child: Text('Nach Fortschritt')),
            ],
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (stats) {
          final continents = stats.byCountry.values
              .map((a) => a.country.continent)
              .toSet()
              .toList()
            ..sort();
          var list = stats.byCountry.values.toList();

          if (_search.isNotEmpty) {
            final q = _search.toLowerCase();
            list = list
                .where((a) =>
                    a.country.name.toLowerCase().contains(q) ||
                    a.country.id.toLowerCase().contains(q))
                .toList();
          }
          if (_continent != null) {
            list = list
                .where((a) => a.country.continent == _continent)
                .toList();
          }
          list = switch (_filter) {
            _VisitFilter.all => list,
            _VisitFilter.visited => list.where((a) => a.visited).toList(),
            _VisitFilter.unvisited => list.where((a) => !a.visited).toList(),
          };
          switch (_sort) {
            case _SortMode.name:
              list.sort((a, b) => a.country.name.compareTo(b.country.name));
            case _SortMode.continent:
              list.sort((a, b) {
                final c = a.country.continent.compareTo(b.country.continent);
                return c != 0 ? c : a.country.name.compareTo(b.country.name);
              });
            case _SortMode.percent:
              list.sort((b, a) => (a.areaPct + a.cityPct + a.regionPct)
                  .compareTo(b.areaPct + b.cityPct + b.regionPct));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Land suchen …',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    FilterChip(
                      label: const Text('Besucht'),
                      selected: _filter == _VisitFilter.visited,
                      onSelected: (v) => setState(() =>
                          _filter = v ? _VisitFilter.visited : _VisitFilter.all),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Unbesucht'),
                      selected: _filter == _VisitFilter.unvisited,
                      onSelected: (v) => setState(() => _filter =
                          v ? _VisitFilter.unvisited : _VisitFilter.all),
                    ),
                    const SizedBox(width: 6),
                    for (final cont in continents) ...[
                      FilterChip(
                        label: Text(cont),
                        selected: _continent == cont,
                        onSelected: (v) =>
                            setState(() => _continent = v ? cont : null),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => _CountryTile(agg: list[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final CountryAgg agg;
  const _CountryTile({required this.agg});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      leading: Text(flagEmoji(agg.country.iso2),
          style: const TextStyle(fontSize: 26)),
      title: Text(agg.country.name),
      subtitle: Text(
        'Regionen ${agg.regionsVisited}/${agg.regionsTotal} · '
        'Städte ${agg.citiesVisited}/${agg.citiesTotal} · '
        'Fläche ${formatPct(agg.areaPct)}',
        style: text.bodySmall,
      ),
      trailing: agg.visited
          ? const Icon(Icons.check_circle, color: Color(0xFF52B87D))
          : const Icon(Icons.radio_button_unchecked, size: 18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CountryDetailScreen(countryId: agg.country.id),
      )),
    );
  }
}
