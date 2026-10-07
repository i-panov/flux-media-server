import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/core/utils/scaffold_messenger.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Канал запроса runtime-разрешения на уведомления (Android 13+).
/// Реализация — в `MainActivity.kt`; на остальных платформах канала нет,
/// поэтому вызов безопасно игнорируется.
const MethodChannel _notificationChannel = MethodChannel(
  'ru.ithub24.flux/notifications',
);

Future<void> _requestNotificationPermission() async {
  try {
    await _notificationChannel.invokeMethod<bool>(
      'requestNotificationPermission',
    );
  } on MissingPluginException {
    // Не Android — разрешение не требуется.
  } catch (e) {
    AppLogger.warn('Notification permission request failed: $e');
  }
}

class SplashScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l?.checkingAuthentication ?? 'Checking authentication...'),
          ],
        ),
      ),
    );
  }
}

class FluxApp extends ConsumerStatefulWidget {
  const new({required this.router, super.key});

  final AppRouter router;

  @override
  ConsumerState<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends ConsumerState<FluxApp> {
  @override
  void initState() {
    super.initState();
    // Обрабатываем только первоначальное состояние; все последующие
    // переходы ловит ref.listen в build через тот же обработчик.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleAuthStateChange(null, ref.read(authProvider));
      // Android 13+: без POST_NOTIFICATIONS foreground service не может
      // показать уведомление с медиакнопками, и системный плеер выглядит
      // пропавшим. Запрашиваем после первого кадра: до onResume вызов
      // Activity.requestPermissions может быть проигнорирован.
      unawaited(_requestNotificationPermission());
    });
  }

  /// Наличие адреса сервера читается реактивно из настроек.
  bool get _hasServerUrl =>
      ref.read(settingsProvider).settings.serverUrl != null;

  /// Общий обработчик переходов состояния авторизации.
  void _handleAuthStateChange(AuthState? previous, AuthState next) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next is AuthAuthenticated) {
        unawaited(widget.router.replaceAll([const MainRoute()]));
      } else if (next is AuthError && _hasServerUrl) {
        // Редирект — только для стартовой проверки сессии и перехода
        // из авторизованного состояния; ошибки форм (verifyCode,
        // requestCode) маршрут не меняют — экран показывает ошибку сам.
        final shouldRedirect =
            previous == null ||
            previous is AuthLoading ||
            previous is AuthAuthenticated;
        if (!shouldRedirect) return;
        if (next.isOffline) {
          // Server unreachable — enter offline mode.
          unawaited(widget.router.replaceAll([const MainRoute()]));
        } else if (previous is AuthAuthenticated) {
          // Session expired — back to login.
          unawaited(widget.router.replaceAll([const LoginRoute()]));
        }
      } else if (next is AuthInitial && _hasServerUrl) {
        // Выход из офлайн-режима (AuthError → AuthInitial) тоже ведёт
        // на экран логина.
        final shouldRedirect =
            previous == null ||
            previous is AuthAuthenticated ||
            previous is AuthLoading ||
            previous is AuthError;
        if (shouldRedirect) {
          unawaited(widget.router.replace(const LoginRoute()));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Суженный watch: MaterialApp пересоздаётся только при реальной
    // смене локали или условий показа splash, а не при любой смене
    // настроек (токены и пр.).
    final settings = ref.watch(
      settingsProvider.select(
        (s) => (
          locale: s.settings.locale,
          serverUrl: s.settings.serverUrl,
          authToken: s.settings.authToken,
        ),
      ),
    );
    final authState = ref.watch(authProvider);

    ref.listen(authProvider, _handleAuthStateChange);

    final showSplash =
        authState is AuthLoading ||
        (authState is AuthInitial &&
            settings.serverUrl != null &&
            settings.authToken != null);

    return MaterialApp.router(
      title: 'Flux',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      locale: Locale(settings.locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: widget.router.config(),
      builder: showSplash ? (context, child) => const SplashScreen() : null,
    );
  }
}
