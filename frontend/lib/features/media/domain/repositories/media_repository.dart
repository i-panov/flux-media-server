import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
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

  /// Асинхронный upload: POST возвращает id джоба, файл обрабатывается
  /// сервером в фоне. Статус — через [getUploadStatus], отмена — через
  /// [cancelUpload].
  Future<Either<Failure, UploadResult>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  });

  Future<Either<Failure, UploadStatus>> getUploadStatus(int jobId);
  Future<Either<Failure, void>> cancelUpload(int jobId);

  /// Пакетная загрузка медиа по id (для офлайн-кеша вместо N+1).
  Future<Either<Failure, List<Media>>> getMediaBulk(List<int> ids);

  Future<Either<Failure, List<WatchProgress>>> getProgress();

  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    MetadataEdit edit,
  );

  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  });

  Future<Either<Failure, void>> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  });

  /// Переименовывает артиста (имя меняется у всех его треков).
  Future<Either<Failure, Artist>> updateArtistName(int artistId, String name);

  /// Загружает обложку артиста.
  Future<Either<Failure, void>> uploadArtistCover(
    int artistId,
    String filePath, {
    bool Function()? isCancelled,
  });
}
