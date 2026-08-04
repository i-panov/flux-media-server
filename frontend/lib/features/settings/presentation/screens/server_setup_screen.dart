import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    // Load the current server URL from settings (loaded at app startup)
    final currentUrl = ref.read(settingsProvider).settings.serverUrl;
    _controller.text = currentUrl ?? 'http://localhost:8080';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final url = _controller.text.trim();
      final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

      setState(() => _isChecking = true);
      try {
        // Check if server is reachable
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse('$baseUrl/api/health'));
        final response = await request.close();
        client.close();

        if (response.statusCode != HttpStatus.ok) {
          throw Exception('Сервер вернул статус ${response.statusCode}');
        }

        // Server is reachable, save URL and proceed
        await ref.read(settingsProvider.notifier).setServerUrl(baseUrl);
        if (!mounted) return;
        context.router.replace(const LoginRoute());
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось подключиться к серверу: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _isChecking = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.dns_outlined,
                  size: 64,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 24),
                Text(
                  l.appTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l.enterServerAddress,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l.serverUrl,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                    hintText: 'http://localhost:8080',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l.pleaseEnterServerUrl;
                    }
                    final trimmed = value.trim();
                    if (!trimmed.startsWith('http://') &&
                        !trimmed.startsWith('https://')) {
                      return l.urlMustStartWithHttp;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _save,
                    child: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l.connect),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
