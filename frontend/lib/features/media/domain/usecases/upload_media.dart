import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

class UploadMediaParams {
  const UploadMediaParams({
    required this.filePath,
    required this.mediaType,
    required this.fileName,
  });

  final String filePath;
  final String mediaType;
  final String fileName;
}

class UploadMedia extends UseCase<Either<Failure, Media>, UploadMediaParams> {
  UploadMedia(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, Media>> call(UploadMediaParams params) {
    return repository.uploadFile(
      filePath: params.filePath,
      mediaType: params.mediaType,
      fileName: params.fileName,
    );
  }
}
