import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/data/datasources/favorites_remote_datasource.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class FavoritesRepositoryImpl implements FavoritesRepository {
  FavoritesRepositoryImpl(this.remoteDataSource);

  final FavoritesRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, List<Favorite>>> getFavorites({String? type}) =>
      safeRepositoryCall(() => remoteDataSource.getFavorites(type: type));

  @override
  Future<Either<Failure, Favorite>> addFavorite(int mediaId) =>
      safeRepositoryCall(() => remoteDataSource.addFavorite(mediaId));

  @override
  Future<Either<Failure, void>> removeFavorite(int mediaId) =>
      safeRepositoryCall(() => remoteDataSource.removeFavorite(mediaId));

  @override
  Future<Either<Failure, Favorite>> addArtistFavorite(String artistName) =>
      safeRepositoryCall(() => remoteDataSource.addArtistFavorite(artistName));

  @override
  Future<Either<Failure, void>> removeArtistFavorite(String artistName) =>
      safeRepositoryCall(() => remoteDataSource.removeArtistFavorite(artistName));
}
