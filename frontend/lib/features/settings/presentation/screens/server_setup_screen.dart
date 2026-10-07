import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/server_health.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/core/utils/url_utils.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class ServerSetupScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isChecking = false;
  bool _trustSelfSigned = false;

  @override
  void initState() {
    super.initState();
    // Load the current server URL from settings (loaded at app startup)
    final currentUrl = ref.read(settingsProvider).settings.serverUrl;
    _controller.text = currentUrl ?? 'http://localhost:8080';
    // Стартуем с сохранённого значения: иначе сброс чекбокса при повторном
    // открытии экрана молча отключал бы доверие сертификату.
    _trustSelfSigned = ref
        .read(settingsProvider)
        .settings
        .trustSelfSignedCertificates;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    // Заблокируем двойной сабмит: кнопка и onFieldSubmitted.
    if (_isChecking) return;
    if (!_formKey.currentState!.validate()) return;

    final url = _controller.text.trim();
    // Нормализуем один раз: храним полный baseUrl API (с /api).
    final normalized = normalizeServerUrl(url);

    setState(() => _isChecking = true);
    try {
      // Флаг доверия НЕ сохраняем до проверки: опечатка в адресе не
      // должна молча менять глобальный TLS-режим приложения. Локальный
      // клиент health-check использует значение чекбокса напрямую.
      // Check if server is reachable. Health-check — на /api/health
      // (нормализованный адрес уже содержит сегмент /api).
      try {
        await checkServerHealth(
          Uri.parse('$normalized/health'),
          trustSelfSigned: _trustSelfSigned,
        );
      } on ServerHealthException catch (e) {
        throw Exception(l.serverStatusError(e.statusCode));
      }

      // Server is reachable: сохраняем флаг и адрес только после
      // успешного health-check, затем выполняем полный logout как в
      // настройках — иначе старый токен уедет на новый хост, а кеш и
      // провайдеры сессии останутся от старого сервера.
      await ref
          .read(settingsProvider.notifier)
          .setTrustSelfSignedCertificates(value: _trustSelfSigned);
      await ref.read(settingsProvider.notifier).setServerUrl(normalized);
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      await context.router.replace(const LoginRoute());
    } catch (e) {
      if (!mounted) return;
      showTextSnackBar(
        context,
        l.connectionFailed(e.toString()),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
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
                    if (!isValidServerUrl(value)) {
                      return l.urlMustStartWithHttp;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.trustSelfSignedCertificate),
                  subtitle: Text(l.trustSelfSignedHint),
                  value: _trustSelfSigned,
                  onChanged: (value) {
                    setState(() => _trustSelfSigned = value ?? false);
                  },
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
