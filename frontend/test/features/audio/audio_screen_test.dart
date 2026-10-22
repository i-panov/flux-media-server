import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/audio/presentation/screens/audio_screen.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repositories.dart';

Media _track(int id, {List<Artist> artists = const []}) => Media(
  id: id,
  title: 'Track $id',
  type: MediaType.audio,
  fileSize: 1024,
  artists: artists,
);

class _FakeMediaRepository implements MediaRepository {
  List<Media> items = [_track(1), _track(2)];
  int total = 2;
  Failure? listFailure;

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async {
    final failure = listFailure;
    if (failure != null) return Left(failure);
    return Right((items: items, total: total));
  }

  @override
  Future<Either<Failure, List<Artist>>> getArtists() async => const Right([]);

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

/// Координатор без плеера: ряды слушают его состояние, а настоящий build
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
  late _FakeMediaRepository mediaRepo;
  late FakeFavoritesRepository favoritesRepo;
  late FakeCollectionsRepository collectionsRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mediaRepo = _FakeMediaRepository();
    favoritesRepo = FakeFavoritesRepository()
      ..onGetFavorites = () async => const Right([]);
    collectionsRepo = FakeCollectionsRepository()
      ..onGetCollections = () async => const Right([]);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      // Как в main.dart: без отключения ретраев упавший build висел бы
      // в loading (до 10 попыток с бэкоффом), и тест ошибки был бы
      // недетерминирован.
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        baseUrlProvider.overrideWithValue('http://test/api'),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
        collectionsRepositoryProvider.overrideWithValue(collectionsRepo),
        offlineCacheServiceProvider.overrideWith(
          (_) => _FakeCache(prefs: prefs),
        ),
        playbackCoordinatorProvider.overrideWith(_IdleCoordinator.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpScreen(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AudioScreen(),
        ),
      ),
    );
  }

  group('AudioScreen', () {
    testWidgets('показывает треки из списка', (tester) async {
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Track 1'), findsWidgets);
      expect(find.text('All Tracks'), findsOneWidget);
    });

    testWidgets('пустая библиотека показывает заглушку', (tester) async {
      mediaRepo
        ..items = []
        ..total = 0;
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No media found'), findsOneWidget);
      expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
    });

    testWidgets('ошибка списка показывает retry', (tester) async {
      mediaRepo.listFailure = const ServerFailure(message: 'boom');
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('boom'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('boom'), findsOneWidget);
    });

    testWidgets('избранный трек показывает секцию', (tester) async {
      favoritesRepo.onGetFavorites = () async => Right([favorite(mediaId: 2)]);
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Liked Tracks'), findsOneWidget);
    });

    testWidgets('кнопка «показать все» разворачивает лайки', (tester) async {
      mediaRepo
        ..items = [for (var i = 1; i <= 11; i++) _track(i)]
        ..total = 11;
      favoritesRepo.onGetFavorites = () async => Right([
        for (var i = 1; i <= 11; i++) favorite(id: i, mediaId: i),
      ]);
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Show all'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Show all'), findsNothing);
    });

    testWidgets('артисты треков показывают секцию', (tester) async {
      mediaRepo.items = [
        _track(1, artists: const [Artist(id: 1, name: 'Artist One')]),
        _track(2),
      ];
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Artists'), findsOneWidget);
      // Дважды: в карточке артиста и в строке трека.
      expect(find.text('Artist One'), findsNWidgets(2));
    });

    testWidgets('коллекции аудио показываются своей секцией', (tester) async {
      // Регрессия: секция коллекций жила приватным виджетом в
      // video_screen, поэтому коллекцию для аудио можно было создать, но
      // нельзя было увидеть и открыть — тупик.
      collectionsRepo.onGetCollections = () async =>
          Right([collection(1, 'Плейлист')]);
      await pumpScreen(tester, makeContainer());
      // Два кадра: первый строит секцию (провайдер коллекций стартует
      // только здесь — в аудио-разделе его больше никто не слушает),
      // второй — перерисовывает её уже с данными.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('My Collections'), findsOneWidget);
      expect(find.text('Плейлист'), findsOneWidget);
    });

  });
}
