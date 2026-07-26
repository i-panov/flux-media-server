import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

class MediaRepositoryImpl implements MediaRepository {
  MediaRepositoryImpl(this.remoteDataSource);

  final MediaRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async {
    try {
      final result = await remoteDataSource.getMediaList(
        type: type,
        year: year,
        q: q,
        limit: limit,
        offset: offset,
      );
      final mediaList =
          result.items.map((json) => Media.fromJson(json)).toList();
      return Right((items: mediaList, total: result.total));
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
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
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>> checkHash(
    String hash,
  ) async {
    try {
      final result = await remoteDataSource.checkHash(hash);
      return Right(result);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Media>> uploadFile({
    required String filePath,
    required int libraryId,
    required String fileName,
  }) async {
    try {
      final media = await remoteDataSource.uploadFile(
        filePath: filePath,
        libraryId: libraryId,
        fileName: fileName,
      );
      return Right(media);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() async {
    try {
      final progress = await remoteDataSource.getProgress();
      return Right(progress);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async {
    try {
      final progress = await remoteDataSource.updateProgress(
        mediaId,
        position: position,
        duration: duration,
        completed: completed,
      );
      return Right(progress);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }
}
