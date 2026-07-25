import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class GetFavoritesParams {
  const GetFavoritesParams({this.type});
  final String? type;
}

class GetFavorites
    extends UseCase<Either<Failure, List<Favorite>>, GetFavoritesParams> {
  GetFavorites(this.repository);
  final FavoritesRepository repository;

  @override
  Future<Either<Failure, List<Favorite>>> call(GetFavoritesParams params) {
    return repository.getFavorites(type: params.type);
  }
}
