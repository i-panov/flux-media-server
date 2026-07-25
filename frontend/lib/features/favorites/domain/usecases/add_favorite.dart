import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class AddFavorite extends UseCase<Either<Failure, Favorite>, int> {
  AddFavorite(this.repository);
  final FavoritesRepository repository;

  @override
  Future<Either<Failure, Favorite>> call(int mediaId) {
    return repository.addFavorite(mediaId);
  }
}
