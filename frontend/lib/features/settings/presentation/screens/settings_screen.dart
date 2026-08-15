import 'dart:async' show unawaited;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/url_utils.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

// Version is read from pubspec.yaml via package_info_plus in production.
// For now, keep it as a single source of truth here.
const String appVersion = '1.0.0';

/// Порог, при котором logout требует подтверждения (объём кеша в байтах).
const int _logoutConfirmCacheBytes = 100 * 1024 * 1024;

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

@RoutePage()
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _serverUrlController = TextEditingController();

  /// Размер офлайн-кеша (обновляется при открытии и после очистки).
  Future<int>? _cacheSizeFuture;

  @override
  void initState() {
    super.initState();
    _cacheSizeFuture =
        ref.read(offlineCacheServiceProvider).getCacheSize();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveServerUrl() async {
    final l = AppLocalizations.of(context)!;
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) return;
    // Validate URL format.
    if (!isValidServerUrl(url)) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.invalidServerUrl)),
      );
      return;
    }

    // Сначала меняем адрес сервера, затем выполняем полный logout
    // (authProvider): он чистит офлайн-кеш старого сервера и
    // инвалидирует провайдеры сессии (favorites/collections/progress).
    try {
      await ref.read(settingsProvider.notifier).setServerUrl(url);
      await ref.read(authProvider.notifier).logout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.failedToSaveSettings(e.toString())),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.serverUrlSaved),
      ),
    );
    // Navigate to login if authenticated.
    unawaited(
      context.router.replace(
        const LoginRoute(),
      ),
    );
  }

  Future<void> _logout() async {
    final l = AppLocalizations.of(context)!;
    final cacheSize =
        await ref.read(offlineCacheServiceProvider).getCacheSize();
    if (!mounted) return;
    if (cacheSize > _logoutConfirmCacheBytes) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.logoutConfirmTitle),
          content: Text(
            l.logoutConfirmMessage(_formatBytes(cacheSize)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Log out'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.loggedOut),
      ),
    );
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
                              decoration: const InputDecoration(
                                hintText: 'https://example.com',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(l.cancel),
                              ),
                              FilledButton(
                                onPressed: _saveServerUrl,
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

          // Offline cache section
          Text(l.offlineCache, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<int>(
                    future: _cacheSizeFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Text(l.cacheSizeCalculating);
                      }
                      final size = snapshot.data ?? 0;
                      return Text(
                        l.cacheSizeLabel(_formatBytes(size)),
                        style: Theme.of(context).textTheme.bodyMedium,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(offlineCacheServiceProvider)
                            .clearUserCache();
                        setState(() {
                          _cacheSizeFuture = ref
                              .read(offlineCacheServiceProvider)
                              .getCacheSize();
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.cacheCleared)),
                          );
                        }
                      },
                      child: Text(l.clearCache),
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
                  onPressed: _logout,
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
