import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/video/presentation/screens/video_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repositories.dart';

Media _video(int id) => Media(
  id: id,
  title: 'Video $id',
  year: 2024,
  type: MediaType.video,
  fileSize: 1024,
  duration: 1000,
);

WatchProgress _progress(int mediaId, int position) => WatchProgress(
  id: mediaId,
  userId: 7,
  mediaId: mediaId,
  position: position,
  duration: 1000,
);

class _FakeMediaRepository implements MediaRepository {
  List<Media> items = [_video(1), _video(2)];
  int total = 2;
  List<WatchProgress> progress = [];
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
  Future<Either<Failure, List<WatchProgress>>> getProgress() async =>
      Right(progress);

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

/// Auth в начальном состоянии без поднятия цепочки API-клиентов.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.initial();
}

/// Коллекция для проверки секции «Мои коллекции» на главном экране.
Collection _collection(
  int id,
  String name, {
  int? parentId,
  MediaType type = MediaType.video,
}) => Collection(
  id: id,
  userId: 1,
  name: name,
  type: type,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  parentId: parentId,
);

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
        authProvider.overrideWith(_FakeAuthNotifier.new),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
        collectionsRepositoryProvider.overrideWithValue(collectionsRepo),
        offlineCacheServiceProvider.overrideWith(
          (_) => _FakeCache(prefs: prefs),
        ),
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
          home: VideoScreen(),
        ),
      ),
    );
  }

  group('VideoScreen', () {
    testWidgets('показывает видео из списка', (tester) async {
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Video 1'), findsOneWidget);
      expect(find.text('Video 2'), findsOneWidget);
      expect(find.text('Recently Added'), findsOneWidget);
    });

    testWidgets('показывает только корневые коллекции', (tester) async {
      // Подколлекции — на экране родителя, в ряд на главном им не место:
      // иначе одна и та же коллекция светится в двух местах.
      collectionsRepo.onGetCollections = () async => Right([
        _collection(1, 'Root'),
        _collection(2, 'Child', parentId: 1),
        _collection(3, 'GrandChild', parentId: 2),
      ]);

      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Root'), findsOneWidget);
      expect(find.text('Child'), findsNothing);
      expect(find.text('GrandChild'), findsNothing);
    });

    testWidgets('сирота с потерянным родителем остаётся видна', (tester) async {
      // Родитель удалён или в корзине: простой фильтр `parentId == null`
      // спрятал бы такую коллекцию навсегда — до неё не дошёл бы
      // никто. Корнем считается и сирота.
      collectionsRepo.onGetCollections = () async => Right([
        _collection(7, 'Orphan', parentId: 99),
      ]);

      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Orphan'), findsOneWidget);
    });

    testWidgets('коллекции другого типа не показываются', (tester) async {
      collectionsRepo.onGetCollections = () async => Right([
        _collection(1, 'VideoCol'),
        _collection(2, 'AudioCol', type: MediaType.audio),
      ]);

      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('VideoCol'), findsOneWidget);
      expect(find.text('AudioCol'), findsNothing);
    });

    testWidgets('пустая библиотека показывает заглушку', (tester) async {
      mediaRepo
        ..items = []
        ..total = 0;
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No media found'), findsOneWidget);
      expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
    });

    testWidgets('ошибка списка показывает retry', (tester) async {
      mediaRepo.listFailure = const ServerFailure(message: 'boom');
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      // Ошибка видна и не роняет экран; повторная попытка не бросает.
      expect(find.textContaining('boom'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('boom'), findsOneWidget);
    });

    testWidgets('прогресс попадает в «продолжить просмотр»', (tester) async {
      mediaRepo.progress = [_progress(1, 300)];
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Continue Watching'), findsOneWidget);
      // Бейдж остатка из секции, а не из сетки: трек 1 только там.
      expect(find.text('-11:40'), findsOneWidget);
      expect(find.text('Video 1'), findsOneWidget);
    });

    testWidgets('кнопка «показать все» разворачивает секцию', (tester) async {
      mediaRepo
        ..items = [for (var i = 1; i <= 11; i++) _video(i)]
        ..total = 11;
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Show all'), findsOneWidget);
      // До разворота 11-й трек только в сетке.
      expect(find.text('Video 11'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pump(const Duration(milliseconds: 100));

      // Секция развернулась: кнопка исчезла. (Счётчик виджетов не
      // подойдёт: горизонтальный список ленивый, 11-й элемент секции
      // не построен, пока не доскроллить.)
      expect(find.text('Show all'), findsNothing);
      expect(find.text('Video 11'), findsOneWidget);
    });

    testWidgets('избранное показывает отдельную секцию', (tester) async {
      mediaRepo
        ..items = [for (var i = 1; i <= 11; i++) _video(i)]
        ..total = 11;
      favoritesRepo.onGetFavorites = () async => Right([favorite(mediaId: 11)]);
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      // 11-й трек ушёл из сетки в секцию избранного.
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Video 11'), findsOneWidget);
    });
  });
}
