import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';

class DeleteMedia extends UseCase<Either<Failure, void>, int> {
  DeleteMedia(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, void>> call(int id) {
    return repository.deleteMedia(id);
  }
}
