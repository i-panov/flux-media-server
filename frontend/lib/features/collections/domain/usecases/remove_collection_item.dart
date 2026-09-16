import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:fpdart/fpdart.dart';

class RemoveCollectionItemParams {
  const new({required this.collectionId, required this.mediaId});
  final int collectionId;
  final int mediaId;
}

class RemoveCollectionItem
    extends UseCase<Either<Failure, void>, RemoveCollectionItemParams> {
  new(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, void>> call(RemoveCollectionItemParams params) {
    return repository.removeCollectionItem(params.collectionId, params.mediaId);
  }
}
