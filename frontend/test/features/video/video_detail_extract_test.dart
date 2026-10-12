import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/extract_controller.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/video/presentation/providers/extracted_audio_provider.dart';
import 'package:flux_media_server/features/video/presentation/utils/extract_audio_flow.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_details_panel.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repositories.dart';

Media _video() => const Media(
  id: 7,
  title: 'Clip',
  type: MediaType.video,
  fileSize: 1024,
  duration: 100,
);

Media _track() => const Media(
  id: 9,
  title: 'Clip',
  type: MediaType.audio,
  fileSize: 100,
  duration: 100,
);

class _FakeMediaRepository implements MediaRepository {
  /// Связка для экрана (null — не извлекали). Сервер создаёт её
  /// к моменту done — фейк линкует сразу при POST.
  Media? linked;
  int extractCalls = 0;
  String? failPostWith;

  @override
  Future<Either<Failure, ({int? jobId, Media? media})>> extractAudio(
    int mediaId, {
    bool Function()? isCancelled,
  }) async {
    extractCalls++;
    final failure = failPostWith;
    if (failure != null) return Left(ServerFailure(message: failure));
    linked ??= _track();
    return const Right((jobId: 1, media: null));
  }

  @override
  Future<Either<Failure, UploadStatus>> getExtractStatus(
    int jobId, {
    bool Function()? isCancelled,
  }) async =>
      Right(UploadStatus(id: jobId, status: 'done', media: _track()));

  @override
  Future<Either<Failure, void>> cancelExtract(
    int jobId, {
    bool Function()? isCancelled,
  }) async =>
      const Right(null);

  @override
  Future<Either<Failure, Media?>> getExtractedAudio(int mediaId) async =>
      Right(linked);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache extends OfflineCacheService {
  new({required super.prefs}) : super('');

  @override
  Future<bool> isCached(int mediaId) async => false;

  @override
  Future<List<int>> getCachedIds() async => [];

  @override
  Future<List<Media>> getCachedMedia() async => [];
}

/// Координатор без плеера: панель слушает downloadState, а настоящий build
/// тянет audioHandlerProvider, которого в виджет-тестах нет.
class _IdleCoordinator extends PlaybackCoordinator {
  @override
  PlaybackState build() => const PlaybackState.initial();
}

/// Auth в начальном состоянии без поднятия цепочки API-клиентов.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.initial();
}

/// Хост с кнопкой, зовущей флоу: диалог → джоб → снекбар.
class _FlowHost extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: TextButton(
        onPressed: () => runExtractAudioFlow(ref, context, 7),
        child: const Text('go'),
      ),
    );
  }
}

void main() {
  late ProviderContainer container;
  late _FakeMediaRepository mediaRepo;
  late SharedPreferences prefs;
  late FakeFavoritesRepository favoritesRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    favoritesRepo = FakeFavoritesRepository()
      ..onGetFavorites = () async => const Right([]);
    mediaRepo = _FakeMediaRepository();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        baseUrlProvider.overrideWithValue('http://test/api'),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
        offlineCacheServiceProvider.overrideWith(
          (_) => _FakeCache(prefs: prefs),
        ),
        playbackCoordinatorProvider.overrideWith(_IdleCoordinator.new),
      ],
    );
    // extractControllerProvider — keepAlive (не autoDispose): подписка
    // не обязательна, но держим для симметрии с остальными тестами.
    final keepAlive = container.listen(extractControllerProvider, (_, _) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });
  });

  Future<void> pumpHost(WidgetTester tester) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _FlowHost(),
        ),
      ),
    );
  }

  group('runExtractAudioFlow', () {
    testWidgets('диалог → успех → снекбар + связка', (tester) async {
      await pumpHost(tester);

      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Extract audio?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Extract audio'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));

      expect(mediaRepo.extractCalls, 1);
      expect(find.text('Audio track saved to library'), findsOneWidget);
      // onSuccess инвалидировал связку: перечитывание видит трек.
      expect(
        await container.read(extractedAudioProvider(7).future),
        isNotNull,
      );
      expect(container.read(extractControllerProvider).isExtracting, isFalse);
    });

    testWidgets('отмена диалога — ни POST, ни снекбара', (tester) async {
      await pumpHost(tester);

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(mediaRepo.extractCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('ошибка POST — красный снекбар с текстом', (tester) async {
      mediaRepo.failPostWith = 'no audio stream';
      await pumpHost(tester);

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Extract audio'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(mediaRepo.extractCalls, 1);
      expect(find.text('Failed to extract audio: no audio stream'), findsOneWidget);
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, Colors.red);
      expect(find.text('Open audio track'), findsNothing);
    });

    testWidgets('успех морфирует панель в открытие трека', (tester) async {
      // Склейка флоу→морф: прогоняем флоу до успеха, затем строим панель
      // ровно той же проводкой, что VideoDetailScreen._buildLoaded
      // (сам экран не поднять: VideoPlayerPanel требует нативный libmpv).
      await pumpHost(tester);
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Extract audio'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));

      final track = await container.read(extractedAudioProvider(7).future);
      expect(track, isNotNull);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: VideoDetailsPanel(
                  media: _video(),
                  onExtractAudio: () async {},
                  onOpenExtractedAudio: track != null
                      ? () async {}
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Open audio track'), findsOneWidget);
      expect(find.text('Extract audio'), findsNothing);
    });
  });
}
