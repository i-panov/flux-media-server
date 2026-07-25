import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/data/datasources/collections_remote_datasource.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class CollectionsRepositoryImpl implements CollectionsRepository {
  CollectionsRepositoryImpl(this.remoteDataSource);

  final CollectionsRemoteDataSource remoteDataSource;

  Future<Either<Failure, T>> _wrap<T>(Future<T> Function() fn) async {
    try {
      return Right(await fn());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, List<Collection>>> getCollections() =>
      _wrap(() => remoteDataSource.getCollections());

  @override
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
  }) =>
      _wrap(() => remoteDataSource.createCollection(name: name, type: type));

  @override
  Future<Either<Failure, Collection>> updateCollection(int id, {String? name}) =>
      _wrap(() => remoteDataSource.updateCollection(id, name: name));

  @override
  Future<Either<Failure, void>> deleteCollection(int id) =>
      _wrap(() => remoteDataSource.deleteCollection(id));

  @override
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  ) =>
      _wrap(() => remoteDataSource.addCollectionItem(collectionId, mediaId));

  @override
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  ) =>
      _wrap(() => remoteDataSource.removeCollectionItem(collectionId, mediaId));

  @override
  Future<Either<Failure, List<CollectionItem>>> getCollectionItems(
    int collectionId,
  ) =>
      _wrap(() => remoteDataSource.getCollectionItems(collectionId));
}
