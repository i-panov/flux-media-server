import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:fpdart/fpdart.dart';

abstract class FavoritesRepository {
  Future<Either<Failure, List<Favorite>>> getFavorites();
  Future<Either<Failure, Favorite>> addFavorite(int mediaId);
  Future<Either<Failure, void>> removeFavorite(int mediaId);
  Future<Either<Failure, Favorite>> addArtistFavorite(int artistId);
  Future<Either<Failure, void>> removeArtistFavorite(int artistId);
}
