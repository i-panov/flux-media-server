import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/scaffold_messenger.dart';
import 'package:flux_media_server/features/auth/presentation/auth_guard.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Initialize audio_service for background playback + system media controls.
  final audioHandler = await AudioService.init(
    builder: FluxAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'ru.ithub24.flux.channel.audio',
      androidNotificationChannelName: 'Flux Audio Playback',
      androidNotificationOngoing: true,
    ),
  );

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      audioHandlerProvider.overrideWithValue(audioHandler),
    ],
  );

  // Load settings synchronously at app startup so they're available
  // before any provider that depends on them is created
  await container.read(settingsProvider.notifier).init();

  // Wire up audio handler callbacks to the play queue.
  final queue = container.read(playQueueProvider.notifier);
  audioHandler
    ..onNext = queue.next
    ..onPrevious = queue.previous
    ..onPlay = () async {
      final playback = container.read(playbackCoordinatorProvider);
      if (playback is PlaybackPlaying &&
          playback.type == MediaType.audio &&
          playback.isPaused) {
        await container.read(playbackCoordinatorProvider.notifier).resume();
      } else if (playback is PlaybackCompleted) {
        // Перезапускаем текущий трек: прямой player.play() оставил бы
        // UI в состоянии completed, а музыка играла бы «в фоне».
        await queue.playCurrent();
      }
    }
    ..onToggleFavorite = () {
      final state = container.read(playbackCoordinatorProvider);
      if (state is PlaybackPlaying) {
        container
            .read(favoriteToggleProvider(state.media.id).notifier)
            .toggle();
      }
    };

  final settings = container.read(settingsProvider).settings;
  if (settings.serverUrl != null && settings.authToken != null) {
    // Non-blocking: splash screen handles loading state
    unawaited(container.read(authProvider.notifier).checkAuthStatus());
  }

  final router = AppRouter(authGuard: AuthGuard(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: FluxApp(router: router),
    ),
  );
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

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
  const FluxApp({required this.router, super.key});

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
        widget.router.replaceAll([const MainRoute()]);
      } else if (next is AuthError && _hasServerUrl) {
        // Редирект — только для стартовой проверки сессии и перехода
        // из авторизованного состояния; ошибки форм (verifyCode,
        // requestCode) маршрут не меняют — экран показывает ошибку сам.
        final shouldRedirect = previous == null ||
            previous is AuthLoading ||
            previous is AuthAuthenticated;
        if (!shouldRedirect) return;
        if (next.isOffline) {
          // Server unreachable — enter offline mode.
          widget.router.replaceAll([const MainRoute()]);
        } else if (previous is AuthAuthenticated) {
          // Session expired — back to login.
          widget.router.replaceAll([const LoginRoute()]);
        }
      } else if (next is AuthInitial && _hasServerUrl) {
        // Выход из офлайн-режима (AuthError → AuthInitial) тоже ведёт
        // на экран логина.
        final shouldRedirect = previous == null ||
            previous is AuthAuthenticated ||
            previous is AuthLoading ||
            previous is AuthError;
        if (shouldRedirect) {
          widget.router.replace(const LoginRoute());
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

    final showSplash = authState is AuthLoading ||
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
