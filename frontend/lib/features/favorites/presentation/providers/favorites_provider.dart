import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/favorites/data/datasources/favorites_remote_datasource.dart';
import 'package:flux_media_server/features/favorites/data/repositories/favorites_repository_impl.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/features/favorites/domain/usecases/add_favorite.dart';
import 'package:flux_media_server/features/favorites/domain/usecases/get_favorites.dart';
import 'package:flux_media_server/features/favorites/domain/usecases/remove_favorite.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

final favoritesRemoteDataSourceProvider =
    Provider<FavoritesRemoteDataSource>((ref) {
  return FavoritesRemoteDataSource(ref.watch(libraryApiClientProvider));
});

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepositoryImpl(
    ref.watch(favoritesRemoteDataSourceProvider),
  );
});

final getFavoritesProvider = Provider<GetFavorites>((ref) {
  return GetFavorites(ref.watch(favoritesRepositoryProvider));
});

final addFavoriteProvider = Provider<AddFavorite>((ref) {
  return AddFavorite(ref.watch(favoritesRepositoryProvider));
});

final removeFavoriteProvider = Provider<RemoveFavorite>((ref) {
  return RemoveFavorite(ref.watch(favoritesRepositoryProvider));
});

/// Избранное текущего пользователя.
///
/// Notifier-обёртка нужна для локальных мутаций кеша при toggle: после
/// успешного add/remove мы обновляем список напрямую (без лишнего GET).
class FavoritesNotifier extends AutoDisposeAsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() async {
    final getFavorites = ref.watch(getFavoritesProvider);
    final result = await getFavorites(const GetFavoritesParams());
    return result.fold(
      (failure) => throw Exception(failure.message),
      (favorites) => favorites,
    );
  }

  /// Добавляет [favorite] в кеш без сетевого запроса.
  void addLocal(Favorite favorite) {
    final current = state.valueOrNull;
    if (current == null) {
      // Данные ещё не загружены — перечитываем с сервера.
      ref.invalidateSelf();
      return;
    }
    if (current.any((f) => f.mediaId == favorite.mediaId)) return;
    state = AsyncValue.data([...current, favorite]);
  }

  /// Удаляет избранное [mediaId] из кеша без сетевого запроса.
  void removeLocal(int mediaId) {
    final current = state.valueOrNull;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncValue.data(
      current.where((f) => f.mediaId != mediaId).toList(),
    );
  }
}

/// Fetches all favorites for the current user.
final favoritesProvider = AsyncNotifierProvider.autoDispose<FavoritesNotifier,
    List<Favorite>>(FavoritesNotifier.new);

/// Tracks favorite media IDs for quick lookup.
final favoriteMediaIdsProvider =
    FutureProvider.autoDispose<Set<int>>((ref) async {
  final favorites = await ref.watch(favoritesProvider.future);
  return favorites
      .where((f) => f.mediaId != null)
      .map((f) => f.mediaId!)
      .toSet();
});
