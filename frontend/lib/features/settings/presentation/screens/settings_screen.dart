import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

@RoutePage()
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _serverUrlController = TextEditingController();

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  void _saveServerUrl() {
    final url = _serverUrlController.text.trim();
    if (url.isNotEmpty) {
      ref.read(settingsProvider.notifier).setServerUrl(url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server URL saved')),
      );
    }
  }

  void _logout() {
    ref.read(authProvider.notifier).logout();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged out')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsProvider);

    ref.listen(settingsProvider, (previous, next) {
      final url = next.settings.serverUrl ?? '';
      if (_serverUrlController.text != url) {
        _serverUrlController.text = url;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Server',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _serverUrlController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              border: OutlineInputBorder(),
              hintText: 'https://example.com',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveServerUrl,
              child: const Text('Save'),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Account',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (settingsState.settings.authToken != null)
            Text(
              'Token: ${settingsState.settings.authToken!.substring(0, settingsState.settings.authToken!.length > 16 ? 16 : settingsState.settings.authToken!.length)}...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              child: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}
