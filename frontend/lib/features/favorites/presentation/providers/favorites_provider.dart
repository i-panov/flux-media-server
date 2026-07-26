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
  return FavoritesRemoteDataSource(ref.watch(apiClientProvider));
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

/// Fetches favorites, optionally filtered by type.
final favoritesProvider =
    FutureProvider.autoDispose.family<List<Favorite>, String?>((ref, type) async {
  final getFavorites = ref.watch(getFavoritesProvider);
  final result = await getFavorites(GetFavoritesParams(type: type));
  return result.fold(
    (failure) => throw Exception(failure.message),
    (favorites) => favorites,
  );
});

/// Tracks favorite media IDs for quick lookup.
final favoriteMediaIdsProvider =
    FutureProvider.autoDispose.family<Set<int>, String>((ref, type) async {
  final favorites = await ref.watch(favoritesProvider(type).future);
  return favorites
      .where((f) => f.mediaId != null)
      .map((f) => f.mediaId!)
      .toSet();
});
