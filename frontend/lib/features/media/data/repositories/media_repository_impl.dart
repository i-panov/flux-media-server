import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

class MediaRepositoryImpl implements MediaRepository {
  MediaRepositoryImpl(this.remoteDataSource);

  final MediaRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    int? limit,
    int? offset,
  }) async {
    try {
      final result = await remoteDataSource.getMediaList(
        type: type,
        year: year,
        limit: limit,
        offset: offset,
      );
      final mediaList =
          result.items.map((json) => Media.fromJson(json)).toList();
      return Right((items: mediaList, total: result.total));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) async {
    try {
      final json = await remoteDataSource.getMedia(id);
      return Right(Media.fromJson(json));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }
}
