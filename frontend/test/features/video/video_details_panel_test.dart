import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
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

class _FakeMediaRepository implements MediaRepository {
  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async => const Right((items: [], total: 0));

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

void main() {
  late SharedPreferences prefs;
  late FakeFavoritesRepository favoritesRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    favoritesRepo = FakeFavoritesRepository()
      ..onGetFavorites = () async => const Right([]);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        baseUrlProvider.overrideWithValue('http://test/api'),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        mediaRepositoryProvider.overrideWithValue(_FakeMediaRepository()),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
        offlineCacheServiceProvider.overrideWith(
          (_) => _FakeCache(prefs: prefs),
        ),
        playbackCoordinatorProvider.overrideWith(_IdleCoordinator.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    Future<void> Function()? onExtractAudio,
    Future<void> Function()? onCancelExtract,
    Future<void> Function()? onOpenExtractedAudio,
    bool isExtracting = false,
    bool linkLoading = false,
  }) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: makeContainer(),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoDetailsPanel(
                media: _video(),
                onExtractAudio: onExtractAudio,
                onCancelExtract: onCancelExtract,
                onOpenExtractedAudio: onOpenExtractedAudio,
                isExtracting: isExtracting,
                linkLoading: linkLoading,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('VideoDetailsPanel audio extraction', () {
    testWidgets('кнопка извлечения зовёт колбэк', (tester) async {
      var calls = 0;
      await pumpPanel(
        tester,
        onExtractAudio: () async => calls++,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extract audio'), findsOneWidget);
      expect(find.text('Open audio track'), findsNothing);

      await tester.tap(find.text('Extract audio'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('готовый трек: кнопка открытия вместо извлечения', (
      tester,
    ) async {
      var calls = 0;
      await pumpPanel(
        tester,
        onExtractAudio: () async {},
        onOpenExtractedAudio: () async => calls++,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Open audio track'), findsOneWidget);
      expect(find.text('Extract audio'), findsNothing);

      await tester.tap(find.text('Open audio track'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('во время извлечения — кнопка отмены', (tester) async {
      var calls = 0;
      await pumpPanel(
        tester,
        onExtractAudio: () async {},
        onCancelExtract: () async => calls++,
        isExtracting: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extracting audio…'), findsOneWidget);
      await tester.tap(find.text('Extracting audio…'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('пока связка грузится — извлечение заблокировано', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        onExtractAudio: () async {},
        linkLoading: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extract audio'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Extract audio'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('без колбэков кнопок извлечения нет', (tester) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extract audio'), findsNothing);
      expect(find.text('Open audio track'), findsNothing);
    });
  });
}
