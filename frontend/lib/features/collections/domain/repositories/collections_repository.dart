import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/collection.dart';

abstract class CollectionsRepository {
  Future<Either<Failure, List<Collection>>> getCollections();
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
  });
  Future<Either<Failure, Collection>> updateCollection(int id, {String? name});
  Future<Either<Failure, void>> deleteCollection(int id);
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  );
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  );
  Future<Either<Failure, List<CollectionItem>>> getCollectionItems(
    int collectionId,
  );
}
