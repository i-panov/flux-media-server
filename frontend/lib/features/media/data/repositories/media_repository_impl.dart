import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';

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
        final mediaList = result.items.map(Media.fromJson).toList();
        return (items: mediaList, total: result.total);
      });

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) =>
      safeRepositoryCall(() async {
        final json = await remoteDataSource.getMedia(id);
        return Media.fromJson(json);
      });

  @override
  Future<Either<Failure, void>> deleteMedia(int id) =>
      safeRepositoryCall(() => remoteDataSource.deleteMedia(id));

  @override
  Future<Either<Failure, List<Artist>>> getArtists() =>
      safeRepositoryCall(remoteDataSource.getArtists);

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>>
      checkHash(String hash) =>
          safeRepositoryCall(() => remoteDataSource.checkHash(hash));

  @override
  Future<Either<Failure, Media>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) =>
      _cancellableCall(
        () => remoteDataSource.uploadFile(
          filePath: filePath,
          mediaType: mediaType,
          fileName: fileName,
          onProgress: onProgress,
          isCancelled: isCancelled,
        ),
      );

  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() =>
      safeRepositoryCall(remoteDataSource.getProgress);

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    MetadataEdit edit,
  ) =>
      safeRepositoryCall(
        () => remoteDataSource.updateMetadata(mediaId, _editToJson(edit)),
      );

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) =>
      safeRepositoryCall(
        () => remoteDataSource.updateProgress(
          mediaId,
          position: position,
          duration: duration,
          completed: completed,
        ),
      );

  @override
  Future<Either<Failure, void>> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  }) =>
      _cancellableCall(
        () => remoteDataSource.uploadCover(
          mediaId,
          filePath,
          isCancelled: isCancelled,
        ),
      );

  /// Обёртка над [safeRepositoryCall] для операций с отменой: общий маппинг
  /// уже превращает [UploadCancelledException] в [UploadCancelledFailure],
  /// этот catch — дополнительная страховка на случай будущих изменений.
  Future<Either<Failure, T>> _cancellableCall<T>(
    Future<T> Function() call,
  ) async {
    try {
      return await safeRepositoryCall(call);
      // ignore: avoid_catching_errors
    } on UploadCancelledException {
      return const Left(UploadCancelledFailure());
    }
  }

  /// Маппинг типизированного редактирования в JSON — остаётся в data-слое.
  static Map<String, dynamic> _editToJson(MetadataEdit edit) => {
        'title': edit.title,
        'artists': edit.artists,
        if (edit.album != null) 'album': edit.album,
        if (edit.genre != null) 'genre': edit.genre,
        if (edit.year != null) 'year': edit.year,
        if (edit.description != null) 'description': edit.description,
      };
}
