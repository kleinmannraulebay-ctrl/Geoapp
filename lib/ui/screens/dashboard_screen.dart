import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/stats_service.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/percent_bar.dart';

/// Kontinent-Übersicht mit Welt-Gesamtstatistik.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Übersicht')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (stats) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _WorldCard(world: stats.world),
            const SizedBox(height: 8),
            for (final cont in stats.continents) ...[
              _ContinentCard(agg: cont),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorldCard extends StatelessWidget {
  final ScopeAgg world;
  const _WorldCard({required this.world});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🌍', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Text('Welt', style: text.titleLarge),
              ],
            ),
            const SizedBox(height: 10),
            PercentBar(
              label: 'Länder',
              ratio: world.countryPct,
              trailing:
                  '${world.countriesVisited} / ${world.countriesTotal}',
            ),
            PercentBar(
              label: 'Städte',
              ratio: world.cityPct,
              trailing: '${world.citiesVisited} / ${world.citiesTotal}',
            ),
            PercentBar(
              label: 'Erkundete Fläche',
              ratio: world.areaPct,
              trailing: formatPct(world.areaPct),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinentCard extends StatelessWidget {
  final ScopeAgg agg;
  const _ContinentCard({required this.agg});

  static const _icons = {
    'Afrika': '🌍',
    'Antarktis': '🧊',
    'Asien': '🌏',
    'Europa': '🌍',
    'Nordamerika': '🌎',
    'Ozeanien': '🌏',
    'Südamerika': '🌎',
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_icons[agg.name] ?? '🌐',
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(agg.name, style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            PercentBar(
              label: 'Länder',
              ratio: agg.countryPct,
              trailing: '${agg.countriesVisited} / ${agg.countriesTotal}',
            ),
            PercentBar(
              label: 'Städte',
              ratio: agg.cityPct,
              trailing: '${agg.citiesVisited} / ${agg.citiesTotal}',
            ),
            PercentBar(
              label: 'Erkundete Fläche',
              ratio: agg.areaPct,
              trailing: formatPct(agg.areaPct),
            ),
          ],
        ),
      ),
    );
  }
}
