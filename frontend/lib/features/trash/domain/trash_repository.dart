import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/features/trash/data/trash_remote_datasource.dart';
import 'package:fpdart/fpdart.dart';

abstract class TrashRepository {
  Future<Either<Failure, TrashContents>> getTrash();
  Future<Either<Failure, void>> restoreMedia(int id);
  Future<Either<Failure, void>> purgeMedia(int id);
  Future<Either<Failure, void>> restoreCollection(int id);
  Future<Either<Failure, void>> purgeCollection(int id);
  Future<Either<Failure, void>> emptyTrash();
  Future<Either<Failure, CollectionStats>> getCollectionStats(int id);
}

class TrashRepositoryImpl implements TrashRepository {
  new(this.remoteDataSource);

  final TrashRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, TrashContents>> getTrash() =>
      safeRepositoryCall(remoteDataSource.getTrash);

  @override
  Future<Either<Failure, void>> restoreMedia(int id) =>
      safeRepositoryCall(() => remoteDataSource.restoreMedia(id));

  @override
  Future<Either<Failure, void>> purgeMedia(int id) =>
      safeRepositoryCall(() => remoteDataSource.purgeMedia(id));

  @override
  Future<Either<Failure, void>> restoreCollection(int id) =>
      safeRepositoryCall(() => remoteDataSource.restoreCollection(id));

  @override
  Future<Either<Failure, void>> purgeCollection(int id) =>
      safeRepositoryCall(() => remoteDataSource.purgeCollection(id));

  @override
  Future<Either<Failure, void>> emptyTrash() =>
      safeRepositoryCall(remoteDataSource.emptyTrash);

  @override
  Future<Either<Failure, CollectionStats>> getCollectionStats(int id) =>
      safeRepositoryCall(() => remoteDataSource.getCollectionStats(id));
}
