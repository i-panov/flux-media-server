import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:fpdart/fpdart.dart';

class UploadMediaParams {
  const UploadMediaParams({
    required this.filePath,
    required this.mediaType,
    required this.fileName,
    this.onProgress,
    this.isCancelled,
  });

  final String filePath;
  final String mediaType;
  final String fileName;

  /// Прогресс загрузки: (отправлено байт, всего байт или null).
  final void Function(int sent, int? total)? onProgress;

  /// Возвращает true, когда загрузку нужно прервать.
  final bool Function()? isCancelled;
}

class UploadMedia
    extends UseCase<Either<Failure, UploadResult>, UploadMediaParams> {
  UploadMedia(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, UploadResult>> call(UploadMediaParams params) {
    return repository.uploadFile(
      filePath: params.filePath,
      mediaType: params.mediaType,
      fileName: params.fileName,
      onProgress: params.onProgress,
      isCancelled: params.isCancelled,
    );
  }
}
