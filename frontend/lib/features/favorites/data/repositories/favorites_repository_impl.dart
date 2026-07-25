import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/data/datasources/favorites_remote_datasource.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class FavoritesRepositoryImpl implements FavoritesRepository {
  FavoritesRepositoryImpl(this.remoteDataSource);

  final FavoritesRemoteDataSource remoteDataSource;

  Future<Either<Failure, T>> _wrap<T>(Future<T> Function() fn) async {
    try {
      return Right(await fn());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, List<Favorite>>> getFavorites({String? type}) =>
      _wrap(() => remoteDataSource.getFavorites(type: type));

  @override
  Future<Either<Failure, Favorite>> addFavorite(int mediaId) =>
      _wrap(() => remoteDataSource.addFavorite(mediaId));

  @override
  Future<Either<Failure, void>> removeFavorite(int mediaId) =>
      _wrap(() => remoteDataSource.removeFavorite(mediaId));

  @override
  Future<Either<Failure, Favorite>> addArtistFavorite(String artistName) =>
      _wrap(() => remoteDataSource.addArtistFavorite(artistName));

  @override
  Future<Either<Failure, void>> removeArtistFavorite(String artistName) =>
      _wrap(() => remoteDataSource.removeArtistFavorite(artistName));
}
