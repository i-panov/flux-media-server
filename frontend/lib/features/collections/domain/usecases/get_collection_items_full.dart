import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

class GetCollectionItemsFull extends UseCase<Either<Failure, List<Media>>, int> {
  GetCollectionItemsFull(this.repository);

  final CollectionsRepository repository;

  @override
  Future<Either<Failure, List<Media>>> call(int collectionId) {
    return repository.getCollectionItemsFull(collectionId);
  }
}
