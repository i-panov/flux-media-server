import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';

class DeleteCollection extends UseCase<Either<Failure, void>, int> {
  DeleteCollection(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, void>> call(int id) {
    return repository.deleteCollection(id);
  }
}
