import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

abstract class MediaRepository {
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
    int? libraryId,
  });

  Future<Either<Failure, Media>> getMediaDetail(int id);

  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>> checkHash(
    String hash,
  );

  Future<Either<Failure, Media>> uploadFile({
    required String filePath,
    required int libraryId,
    required String fileName,
  });

  Future<Either<Failure, List<WatchProgress>>> getProgress();

  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    Map<String, dynamic> data,
  );

  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  });

  Future<Either<Failure, void>> uploadCover(int mediaId, String filePath);
}
