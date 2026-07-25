import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';

class RemoveFavorite extends UseCase<Either<Failure, void>, int> {
  RemoveFavorite(this.repository);
  final FavoritesRepository repository;

  @override
  Future<Either<Failure, void>> call(int mediaId) {
    return repository.removeFavorite(mediaId);
  }
}
