import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class GetCollections
    extends UseCase<Either<Failure, List<Collection>>, NoParams> {
  GetCollections(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, List<Collection>>> call(NoParams params) {
    return repository.getCollections();
  }
}
