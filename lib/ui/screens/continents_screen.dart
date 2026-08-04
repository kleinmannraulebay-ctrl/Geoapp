import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../providers/providers.dart';
import '../widgets/progress_row.dart';

/// Dashboard: Welt-Gesamtstatistik + die sieben Kontinente mit
/// Fortschritt für Länder, Städte und erkundete Fläche.
class ContinentsScreen extends ConsumerWidget {
  const ContinentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worldAsync = ref.watch(worldStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Welt-Übersicht')),
      body: worldAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (world) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _WorldCard(world: world),
            const SizedBox(height: 16),
            for (final c in world.continents) ...[
              _ContinentCard(stats: c),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorldCard extends StatelessWidget {
  final WorldStats world;
  const _WorldCard({required this.world});

  @override
  Widget build(BuildContext context) {
    final pct = NumberFormat('0.000', 'de');
    return Card(
      color: const Color(0xFF16262E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gesamte Welt',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ProgressRow(
              label: 'Länder',
              value: world.countriesTotal == 0
                  ? 0
                  : world.countriesVisited / world.countriesTotal,
              detail: '${world.countriesVisited}/${world.countriesTotal}',
            ),
            ProgressRow(
              label: 'Städte',
              value: world.citiesListed == 0
                  ? 0
                  : world.citiesVisited / world.citiesListed,
              detail: '${world.citiesVisited}/${world.citiesListed}',
            ),
            ProgressRow(
              label: 'Weltfläche',
              value: world.areaPercent,
              detail: '${pct.format(world.areaPercent * 100)} %',
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinentCard extends StatelessWidget {
  final ContinentStats stats;
  const _ContinentCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final pct = NumberFormat('0.00', 'de');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stats.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ProgressRow(
              label: 'Länder',
              value: stats.countriesTotal == 0
                  ? 0
                  : stats.countriesVisited / stats.countriesTotal,
              detail: '${stats.countriesVisited}/${stats.countriesTotal}',
            ),
            ProgressRow(
              label: 'Städte',
              value: stats.citiesListed == 0
                  ? 0
                  : stats.citiesVisited / stats.citiesListed,
              detail: '${stats.citiesVisited}/${stats.citiesListed}',
            ),
            ProgressRow(
              label: 'Fläche',
              value: stats.areaPercent,
              detail: '${pct.format(stats.areaPercent * 100)} %',
            ),
          ],
        ),
      ),
    );
  }
}
