import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/features/favorites/data/datasources/favorites_remote_datasource.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:fpdart/fpdart.dart';

class FavoritesRepositoryImpl implements FavoritesRepository {
  FavoritesRepositoryImpl(this.remoteDataSource);

  final FavoritesRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, List<Favorite>>> getFavorites() =>
      safeRepositoryCall(remoteDataSource.getFavorites);

  @override
  Future<Either<Failure, Favorite>> addFavorite(int mediaId) =>
      safeRepositoryCall(() => remoteDataSource.addFavorite(mediaId));

  @override
  Future<Either<Failure, void>> removeFavorite(int mediaId) =>
      safeRepositoryCall(() => remoteDataSource.removeFavorite(mediaId));

  @override
  Future<Either<Failure, Favorite>> addArtistFavorite(int artistId) =>
      safeRepositoryCall(() => remoteDataSource.addArtistFavorite(artistId));

  @override
  Future<Either<Failure, void>> removeArtistFavorite(int artistId) =>
      safeRepositoryCall(() => remoteDataSource.removeArtistFavorite(artistId));
}
