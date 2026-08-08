import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

abstract class FavoritesRepository {
  Future<Either<Failure, List<Favorite>>> getFavorites();
  Future<Either<Failure, Favorite>> addFavorite(int mediaId);
  Future<Either<Failure, void>> removeFavorite(int mediaId);
  Future<Either<Failure, Favorite>> addArtistFavorite(String artistName);
  Future<Either<Failure, void>> removeArtistFavorite(String artistName);
}
