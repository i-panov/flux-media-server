import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class AddCollectionItemParams {
  const AddCollectionItemParams({
    required this.collectionId,
    required this.mediaId,
  });
  final int collectionId;
  final int mediaId;
}

class AddCollectionItem
    extends UseCase<Either<Failure, CollectionItem>, AddCollectionItemParams> {
  AddCollectionItem(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, CollectionItem>> call(AddCollectionItemParams params) {
    return repository.addCollectionItem(params.collectionId, params.mediaId);
  }
}
