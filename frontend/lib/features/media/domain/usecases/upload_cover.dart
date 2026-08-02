import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';

class UploadCoverParams {
  const UploadCoverParams({
    required this.mediaId,
    required this.filePath,
  });

  final int mediaId;
  final String filePath;
}

class UploadCover extends UseCase<Either<Failure, void>, UploadCoverParams> {
  UploadCover(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, void>> call(UploadCoverParams params) {
    return repository.uploadCover(params.mediaId, params.filePath);
  }
}
