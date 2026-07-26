import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/data/datasources/collections_remote_datasource.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class CollectionsRepositoryImpl implements CollectionsRepository {
  CollectionsRepositoryImpl(this.remoteDataSource);

  final CollectionsRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, List<Collection>>> getCollections() =>
      safeRepositoryCall(() => remoteDataSource.getCollections());

  @override
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
  }) =>
      safeRepositoryCall(() => remoteDataSource.createCollection(name: name, type: type));

  @override
  Future<Either<Failure, Collection>> updateCollection(int id, {String? name}) =>
      safeRepositoryCall(() => remoteDataSource.updateCollection(id, name: name));

  @override
  Future<Either<Failure, void>> deleteCollection(int id) =>
      safeRepositoryCall(() => remoteDataSource.deleteCollection(id));

  @override
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  ) =>
      safeRepositoryCall(() => remoteDataSource.addCollectionItem(collectionId, mediaId));

  @override
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  ) =>
      safeRepositoryCall(() => remoteDataSource.removeCollectionItem(collectionId, mediaId));

  @override
  Future<Either<Failure, List<CollectionItem>>> getCollectionItems(
    int collectionId,
  ) =>
      safeRepositoryCall(() => remoteDataSource.getCollectionItems(collectionId));
}
