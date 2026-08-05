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

const _continentEmoji = {
  'Europa': '🏰',
  'Asien': '🏯',
  'Afrika': '🦁',
  'Nordamerika': '🗽',
  'Südamerika': '🦜',
  'Ozeanien': '🏝️',
  'Antarktis': '🐧',
};

class _WorldCard extends StatelessWidget {
  final WorldStats world;
  const _WorldCard({required this.world});

  @override
  Widget build(BuildContext context) {
    final pct = NumberFormat('0.000', 'de');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF134E4A), Color(0xFF152232)],
        ),
        border: Border.all(color: const Color(0x332DD4BF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌍', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Text('Gesamte Welt',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                '${pct.format(world.areaPercent * 100)} %',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2DD4BF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
            Row(
              children: [
                Text(_continentEmoji[stats.name] ?? '🌐',
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Text(stats.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  '${stats.countriesVisited}/${stats.countriesTotal}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: stats.countriesVisited > 0
                        ? const Color(0xFF2DD4BF)
                        : Colors.white38,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
