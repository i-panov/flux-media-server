import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flux_media_server/app.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/session/settings_local_datasource.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/auth_guard.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/player/data/artwork_fetcher.dart';
import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Загрузчик обложек для audio_service собирается ДО контейнера:
  // хендлер создаётся в фоновом изоляте, куда нельзя пробросить ни
  // контейнер, ни общий http.Client с открытыми сокетами. Флаг доверия —
  // снимок из prefs на момент старта (синхронное чтение, без secure
  // storage: сам флаг лежит в SharedPreferences).
  final artworkFetcher = ArtworkFileFetcher(
    trustSelfSigned: SettingsLocalDataSource(
      prefs,
      const FlutterSecureStorage(),
    ).getTrustSelfSignedCertificates(),
  );

  // Initialize audio_service for background playback + system media controls.
  final audioHandler = await AudioService.init(
    builder: () => FluxAudioHandler(artworkFetcher: artworkFetcher.call),
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
    // Riverpod 3 по умолчанию ретраит упавшие build-и (до 10 раз с
    // бэкоффом), оставляя состояние в loading — экраны показывали бы
    // спиннер вместо ошибки. Отключаем: ошибки (в т.ч. NetworkFailure
    // для офлайн-детекта) должны сразу попадать в состояние, как в
    // Riverpod 2.
    retry: (_, _) => null,
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
        unawaited(
          container
              .read(favoriteToggleProvider(state.media.id).notifier)
              .toggle(),
        );
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
