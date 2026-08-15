import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/fake_repositories.dart';

void main() {
  late ProviderContainer container;
  late FakeFavoritesRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeFavoritesRepository();
    container = ProviderContainer(
      overrides: [
        favoritesRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('favoritesProvider', () {
    test('loads favorites', () async {
      fakeRepo.onGetFavorites = () async => Right(
            [favorite(mediaId: 1), favorite(id: 2, mediaId: 2)],
          );

      final result = await container.read(favoritesProvider.future);

      expect(result, hasLength(2));
      expect(fakeRepo.getFavoritesCalls, 1);
    });

    test('throws on repository failure', () async {
      fakeRepo.onGetFavorites =
          () async => const Left(ServerFailure(message: 'Boom'));

      await expectLater(
        container.read(favoritesProvider.future),
        throwsA(isA<Exception>()),
      );
    });

    test('addLocal appends without an extra GET', () async {
      fakeRepo.onGetFavorites =
          () async => Right([favorite(mediaId: 1)]);

      await container.read(favoritesProvider.future);
      container
          .read(favoritesProvider.notifier)
          .addLocal(favorite(id: 2, mediaId: 2));

      expect(fakeRepo.getFavoritesCalls, 1);
      final favorites = container.read(favoritesProvider).value;
      expect(favorites?.map((f) => f.id), [1, 2]);
    });

    test('addLocal dedupes by mediaId', () async {
      fakeRepo.onGetFavorites =
          () async => Right([favorite(mediaId: 1)]);

      await container.read(favoritesProvider.future);
      container
          .read(favoritesProvider.notifier)
          .addLocal(favorite(id: 99, mediaId: 1));

      final favorites = container.read(favoritesProvider).value;
      expect(favorites, hasLength(1));
      expect(favorites?.first.id, 1);
    });

    test('removeLocal removes by mediaId without an extra GET', () async {
      fakeRepo.onGetFavorites = () async => Right(
            [favorite(mediaId: 1), favorite(id: 2, mediaId: 2)],
          );

      await container.read(favoritesProvider.future);
      container.read(favoritesProvider.notifier).removeLocal(1);

      expect(fakeRepo.getFavoritesCalls, 1);
      final favorites = container.read(favoritesProvider).value;
      expect(favorites?.map((f) => f.mediaId), [2]);
    });
  });

  group('favoriteMediaIdsProvider', () {
    test('derives media ids and skips artist favorites', () async {
      fakeRepo.onGetFavorites = () async => Right(
            [
              favorite(mediaId: 1),
              favorite(id: 2, artistId: 3),
              favorite(id: 3, mediaId: 5),
            ],
          );

      final ids = await container.read(favoriteMediaIdsProvider.future);

      expect(ids, {1, 5});
    });
  });

  group('FavoriteToggleNotifier', () {
    late ProviderContainer toggleContainer;

    setUp(() {
      toggleContainer = ProviderContainer(
        overrides: [
          favoritesRepositoryProvider.overrideWithValue(fakeRepo),
          isOfflineProvider.overrideWithValue(false),
        ],
      );
    });

    tearDown(() => toggleContainer.dispose());

    /// Загружает избранное и дожидается пересчёта множества id.
    Future<void> loadState() async {
      await toggleContainer.read(favoritesProvider.future);
      await toggleContainer.read(favoriteMediaIdsProvider.future);
    }

    test('toggle adds a favorite without refetching the list', () async {
      fakeRepo
        ..onGetFavorites = (() async => const Right([]))
        ..onAddFavorite = ((mediaId) async =>
            Right(favorite(id: 10, mediaId: mediaId)));

      await loadState();
      await toggleContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();
      // Пересчёт ids после локальной мутации.
      await toggleContainer.read(favoriteMediaIdsProvider.future);

      expect(fakeRepo.addFavoriteCalls, [1]);
      // keepAlive-провайдер не пересоздаётся — никакого второго GET.
      expect(fakeRepo.getFavoritesCalls, 1);
      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isTrue);
      final favorites = toggleContainer.read(favoritesProvider).value;
      expect(favorites?.map((f) => f.mediaId), [1]);
    });

    test('toggle removes a favorite without refetching the list', () async {
      fakeRepo
        ..onGetFavorites =
            (() async => Right([favorite(id: 10, mediaId: 1)]))
        ..onRemoveFavorite = (_) async => const Right(null);

      await loadState();
      await toggleContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();
      await toggleContainer.read(favoriteMediaIdsProvider.future);

      expect(fakeRepo.removeFavoriteCalls, [1]);
      expect(fakeRepo.getFavoritesCalls, 1);
      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isFalse);
      final favorites = toggleContainer.read(favoritesProvider).value;
      expect(favorites, isEmpty);
    });

    test('toggle reverts state on repository failure', () async {
      fakeRepo
        ..onGetFavorites = (() async => const Right([]))
        ..onAddFavorite =
            ((_) async => const Left(ServerFailure(message: 'Conflict')));

      await loadState();
      await toggleContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();

      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isFalse);
      expect(fakeRepo.getFavoritesCalls, 1);
    });

    test(
        'icon stays in sync across screens when the list changes locally',
        () async {
      fakeRepo.onGetFavorites =
          () async => Right([favorite(id: 10, mediaId: 1)]);
      await loadState();
      // Эмуляция UI: экран следит за иконкой избранного трека.
      final sub = toggleContainer.listen(
        favoriteToggleProvider(1),
        (_, __) {},
      );
      addTearDown(sub.close);

      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isTrue);

      // «Другой экран» снял избранное через локальную мутацию.
      toggleContainer.read(favoritesProvider.notifier).removeLocal(1);
      await toggleContainer.read(favoriteMediaIdsProvider.future);
      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isFalse);

      toggleContainer
          .read(favoritesProvider.notifier)
          .addLocal(favorite(id: 11, mediaId: 1));
      await toggleContainer.read(favoriteMediaIdsProvider.future);
      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isTrue);
    });

    test('offline toggle keeps current state and makes no network calls',
        () async {
      fakeRepo.onGetFavorites =
          () async => Right([favorite(id: 10, mediaId: 1)]);
      final offlineContainer = ProviderContainer(
        overrides: [
          favoritesRepositoryProvider.overrideWithValue(fakeRepo),
          isOfflineProvider.overrideWithValue(true),
        ],
      );
      addTearDown(offlineContainer.dispose);
      await offlineContainer.read(favoritesProvider.future);
      await offlineContainer.read(favoriteMediaIdsProvider.future);
      final sub =
          offlineContainer.listen(favoriteToggleProvider(1), (_, __) {});
      addTearDown(sub.close);

      await offlineContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();

      // Офлайн: состояние не меняется на «снято», а остаётся текущим.
      expect(offlineContainer.read(favoriteToggleProvider(1)).value, isTrue);
      expect(fakeRepo.addFavoriteCalls, isEmpty);
      expect(fakeRepo.removeFavoriteCalls, isEmpty);
      expect(fakeRepo.getFavoritesCalls, 1);
    });

    test('toggle state derives from fresh list when recreated', () async {
      fakeRepo
        ..onGetFavorites = (() async => const Right([]))
        ..onAddFavorite = ((mediaId) async =>
            Right(favorite(id: 10, mediaId: mediaId)));

      await loadState();
      await toggleContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();
      await toggleContainer.read(favoriteMediaIdsProvider.future);

      // Пересоздание нотифаера (например, повторный вход на экран)
      // читает актуальное состояние из источника истины.
      final sub = toggleContainer.listen(
        favoriteToggleProvider(1),
        (_, __) {},
      );
      addTearDown(sub.close);
      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isTrue);
    });
  });
}
