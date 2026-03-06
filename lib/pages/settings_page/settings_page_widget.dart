import 'package:flutter/material.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

class SettingsPageWidget extends StatelessWidget {
  const SettingsPageWidget({super.key});

  static String routeName = 'SettingsPage';
  static String routePath = '/settingsPage';

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: theme.titleMedium),
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Settings', style: theme.titleLarge.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.brightness_6_outlined), title: const Text('Theme'), subtitle: const Text('System / Light / Dark')),
          ListTile(leading: const Icon(Icons.language_outlined), title: const Text('Language'), subtitle: const Text('English (en)')),
        ]),
      ),
    );
  }
}

