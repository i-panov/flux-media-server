import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:fpdart/fpdart.dart';

class GetCollectionItems
    extends UseCase<Either<Failure, List<CollectionItem>>, int> {
  GetCollectionItems(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, List<CollectionItem>>> call(int collectionId) {
    return repository.getCollectionItems(collectionId);
  }
}
