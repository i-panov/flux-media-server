import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:fpdart/fpdart.dart';

Favorite _favorite({
  int id = 1,
  int? mediaId,
  int? artistId,
}) =>
    Favorite(
      id: id,
      userId: 7,
      createdAt: DateTime.utc(2024),
      mediaId: mediaId,
      artistId: artistId,
    );

class FakeFavoritesRepository implements FavoritesRepository {
  Future<Either<Failure, List<Favorite>>> Function()? onGetFavorites;
  Future<Either<Failure, Favorite>> Function(int)? onAddFavorite;
  Future<Either<Failure, void>> Function(int)? onRemoveFavorite;

  int getFavoritesCalls = 0;
  final List<int> addFavoriteCalls = [];
  final List<int> removeFavoriteCalls = [];

  @override
  Future<Either<Failure, List<Favorite>>> getFavorites() {
    getFavoritesCalls++;
    return onGetFavorites!();
  }

  @override
  Future<Either<Failure, Favorite>> addFavorite(int mediaId) {
    addFavoriteCalls.add(mediaId);
    return onAddFavorite!(mediaId);
  }

  @override
  Future<Either<Failure, void>> removeFavorite(int mediaId) {
    removeFavoriteCalls.add(mediaId);
    return onRemoveFavorite!(mediaId);
  }

  @override
  Future<Either<Failure, Favorite>> addArtistFavorite(int artistId) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, void>> removeArtistFavorite(int artistId) async =>
      const Left(ServerFailure(message: 'not used'));
}

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
            [_favorite(mediaId: 1), _favorite(id: 2, mediaId: 2)],
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
          () async => Right([_favorite(mediaId: 1)]);

      await container.read(favoritesProvider.future);
      container
          .read(favoritesProvider.notifier)
          .addLocal(_favorite(id: 2, mediaId: 2));

      expect(fakeRepo.getFavoritesCalls, 1);
      final favorites = container.read(favoritesProvider).value;
      expect(favorites?.map((f) => f.id), [1, 2]);
    });

    test('addLocal dedupes by mediaId', () async {
      fakeRepo.onGetFavorites =
          () async => Right([_favorite(mediaId: 1)]);

      await container.read(favoritesProvider.future);
      container
          .read(favoritesProvider.notifier)
          .addLocal(_favorite(id: 99, mediaId: 1));

      final favorites = container.read(favoritesProvider).value;
      expect(favorites, hasLength(1));
      expect(favorites?.first.id, 1);
    });

    test('removeLocal removes by mediaId without an extra GET', () async {
      fakeRepo.onGetFavorites = () async => Right(
            [_favorite(mediaId: 1), _favorite(id: 2, mediaId: 2)],
          );

      await container.read(favoritesProvider.future);
      container.read(favoritesProvider.notifier).removeLocal(1);

      expect(fakeRepo.getFavoritesCalls, 1);
      final favorites = container.read(favoritesProvider).value;
      expect(favorites?.map((f) => f.mediaId), [2]);
    });
  });

  group('favoriteMediaIdsProvider', () {
    test('derives media ids and skips nulls', () async {
      fakeRepo.onGetFavorites = () async => Right(
            [
              _favorite(mediaId: 1),
              _favorite(id: 2, artistId: 3),
              _favorite(id: 3, mediaId: 5),
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

    test('toggle adds a favorite without refetching the list', () async {
      fakeRepo
        ..onGetFavorites = (() async => const Right([]))
        ..onAddFavorite = ((mediaId) async =>
            Right(_favorite(id: 10, mediaId: mediaId)));
      // Держим провайдер живым, чтобы проверить состояние после toggle.
      final sub = toggleContainer.listen(favoritesProvider, (_, __) {});
      addTearDown(sub.close);

      await toggleContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();

      expect(fakeRepo.addFavoriteCalls, [1]);
      expect(fakeRepo.getFavoritesCalls, 1);
      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isTrue);
      final favorites = toggleContainer.read(favoritesProvider).value;
      expect(favorites?.map((f) => f.mediaId), [1]);
    });

    test('toggle removes a favorite without refetching the list', () async {
      fakeRepo
        ..onGetFavorites =
            (() async => Right([_favorite(id: 10, mediaId: 1)]))
        ..onRemoveFavorite = ((_) async => const Right(null));
      final sub = toggleContainer.listen(favoritesProvider, (_, __) {});
      addTearDown(sub.close);

      await toggleContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();

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

      await toggleContainer
          .read(favoriteToggleProvider(1).notifier)
          .toggle();

      expect(toggleContainer.read(favoriteToggleProvider(1)).value, isFalse);
    });
  });
}
