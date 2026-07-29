import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
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
  }) =>
      safeRepositoryCall(() async {
        final result = await remoteDataSource.getMediaList(
          type: type,
          year: year,
          q: q,
          limit: limit,
          offset: offset,
        );
        final mediaList =
            result.items.map((json) => Media.fromJson(json)).toList();
        return (items: mediaList, total: result.total);
      });

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) =>
      safeRepositoryCall(() async {
        final json = await remoteDataSource.getMedia(id);
        return Media.fromJson(json);
      });

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>>
      checkHash(String hash) =>
          safeRepositoryCall(() => remoteDataSource.checkHash(hash));

  @override
  Future<Either<Failure, Media>> uploadFile({
    required String filePath,
    required int libraryId,
    required String fileName,
  }) =>
      safeRepositoryCall(() => remoteDataSource.uploadFile(
            filePath: filePath,
            libraryId: libraryId,
            fileName: fileName,
          ));

  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() =>
      safeRepositoryCall(() => remoteDataSource.getProgress());

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    Map<String, dynamic> data,
  ) =>
      safeRepositoryCall(() => remoteDataSource.updateMetadata(mediaId, data));

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) =>
      safeRepositoryCall(() => remoteDataSource.updateProgress(
            mediaId,
            position: position,
            duration: duration,
            completed: completed,
          ));
}
