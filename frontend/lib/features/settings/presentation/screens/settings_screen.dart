import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

// Version is read from pubspec.yaml via package_info_plus in production.
// For now, keep it as a single source of truth here.
const String appVersion = '1.0.0';

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final settingsState = ref.watch(settingsProvider);

    ref.listen(settingsProvider, (previous, next) {
      final url = next.settings.serverUrl ?? '';
      if (_serverUrlController.text != url) {
        _serverUrlController.text = url;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server section
          Text(l.server, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settingsState.settings.serverUrl ?? '—',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l.serverUrl),
                            content: TextField(
                              controller: _serverUrlController,
                              decoration: InputDecoration(
                                hintText: 'https://example.com',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(l.cancel),
                              ),
                              FilledButton(
                                onPressed: () {
                                  final url =
                                      _serverUrlController.text.trim();
                                  if (url.isNotEmpty) {
                                    ref
                                        .read(settingsProvider.notifier)
                                        .setServerUrl(url);
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(
                                      SnackBar(content: Text(l.serverUrlSaved)),
                                    );
                                  }
                                },
                                child: Text(l.save),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Text(l.edit),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Language section
          Text(l.language, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'en',
                          label: Text('English'),
                        ),
                        ButtonSegment(
                          value: 'ru',
                          label: Text('Русский'),
                        ),
                      ],
                      selected: {settingsState.settings.locale},
                      onSelectionChanged: (selection) {
                        ref
                            .read(settingsProvider.notifier)
                            .setLocale(selection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Account section
          Text(l.account, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(authProvider.notifier).logout();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.loggedOut)),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: Text(l.logout),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // About section
          Text(l.about, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${l.version}: $appVersion'),
            ),
          ),
        ],
      ),
    );
  }
}
