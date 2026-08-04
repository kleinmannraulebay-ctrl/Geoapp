import 'package:flutter/material.dart';

import 'manual_entry_screen.dart';
import 'settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mehr')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Manuelle Einträge'),
            subtitle: const Text('Frühere Reisen nachtragen und verwalten'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ManualEntriesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Einstellungen'),
            subtitle: const Text('Tracking, Karte, Backup'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SettingsScreen())),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Privatsphäre'),
            subtitle: Text(
                'Alle Daten bleiben lokal auf diesem Gerät. Die App hat '
                'keine Internet-Berechtigung – kein Account, keine Cloud, '
                'keine Analytics.'),
          ),
          const ListTile(
            leading: Icon(Icons.map_outlined),
            title: Text('Datenquellen'),
            subtitle: Text(
                'Karten: Natural Earth (gemeinfrei) · '
                'Städte: GeoNames (CC BY 4.0)'),
          ),
        ],
      ),
    );
  }
}
