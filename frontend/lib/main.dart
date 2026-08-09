import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/router/auth_guard.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  const keyPrefix = kDebugMode ? 'debug_' : 'release_';
  final serverUrl = prefs.getString('${keyPrefix}server_url');

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
    ..onToggleFavorite = () {
      final state = container.read(playbackCoordinatorProvider);
      if (state is PlaybackPlaying) {
        container
            .read(favoriteToggleProvider(state.media.id).notifier)
            .toggle(state.media.id);
      }
    };

  if (serverUrl != null) {
    if (container.read(settingsProvider).settings.authToken != null) {
      // Non-blocking: splash screen handles loading state
      unawaited(container.read(authProvider.notifier).checkAuthStatus());
    }
  }

  final router = AppRouter(authGuard: AuthGuard(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: FluxApp(router: router, hasServerUrl: serverUrl != null),
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
  const FluxApp({required this.router, required this.hasServerUrl, super.key});

  final AppRouter router;
  final bool hasServerUrl;

  @override
  ConsumerState<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends ConsumerState<FluxApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      if (authState is AuthAuthenticated) {
        widget.router.replaceAll([const MainRoute()]);
      } else if (authState is AuthError && widget.hasServerUrl) {
        // Server unreachable — enter offline mode, show downloaded content.
        widget.router.replaceAll([const MainRoute()]);
      } else if (authState is! AuthLoading && widget.hasServerUrl) {
        widget.router.replace(const LoginRoute());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(settingsProvider.select((s) => s.settings.locale));
    final authState = ref.watch(authProvider);

    ref.listen(authProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.router.replaceAll([const MainRoute()]);
        });
      } else if (next is AuthError && widget.hasServerUrl) {
        // Server unreachable — enter offline mode.
        final shouldRedirect =
            previous is AuthLoading || previous is AuthAuthenticated;
        if (shouldRedirect) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.router.replaceAll([const MainRoute()]);
          });
        }
      } else if (next is AuthInitial && widget.hasServerUrl) {
        if (previous is AuthAuthenticated || previous is AuthLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.router.replace(const LoginRoute());
          });
        }
      }
    });

    final showSplash = authState is AuthLoading ||
        (authState is AuthInitial &&
            widget.hasServerUrl &&
            ref.read(settingsProvider).settings.authToken != null);

    return MaterialApp.router(
      title: 'Flux',
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
      locale: Locale(locale),
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
