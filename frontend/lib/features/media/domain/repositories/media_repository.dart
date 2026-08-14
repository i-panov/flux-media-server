import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';

abstract class MediaRepository {
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  });

  Future<Either<Failure, Media>> getMediaDetail(int id);
  Future<Either<Failure, void>> deleteMedia(int id);

  /// Все исполнители (для автодополнения в диалоге метаданных).
  Future<Either<Failure, List<Artist>>> getArtists();

  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>>
      checkHash(
    String hash,
  );

  Future<Either<Failure, Media>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
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
