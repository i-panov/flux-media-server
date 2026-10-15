import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/features/collections/data/datasources/collections_remote_datasource.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

class CollectionsRepositoryImpl implements CollectionsRepository {
  new(this.remoteDataSource);

  final CollectionsRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, List<Collection>>> getCollections() =>
      safeRepositoryCall(remoteDataSource.getCollections);

  @override
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
    int? parentId,
  }) => safeRepositoryCall(
    () => remoteDataSource.createCollection(
      name: name,
      type: type,
      parentId: parentId,
    ),
  );

  @override
  Future<Either<Failure, Collection>> moveCollection(int id, int? parentId) =>
      safeRepositoryCall(() => remoteDataSource.moveCollection(id, parentId));

  @override
  Future<Either<Failure, CollectionItem>> moveCollectionItem(
    int sourceId,
    int targetId,
    int mediaId,
  ) => safeRepositoryCall(
    () => remoteDataSource.moveCollectionItem(sourceId, targetId, mediaId),
  );

  @override
  Future<Either<Failure, void>> deleteCollection(int id) =>
      safeRepositoryCall(() => remoteDataSource.deleteCollection(id));

  @override
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  ) => safeRepositoryCall(
    () => remoteDataSource.addCollectionItem(collectionId, mediaId),
  );

  @override
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  ) => safeRepositoryCall(
    () => remoteDataSource.removeCollectionItem(collectionId, mediaId),
  );

  @override
  Future<Either<Failure, List<Media>>> getCollectionItemsFull(
    int collectionId,
  ) => safeRepositoryCall(
    () => remoteDataSource.getCollectionItemsFull(collectionId),
  );
}
