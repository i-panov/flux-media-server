import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetUploadStatus extends UseCase<Either<Failure, UploadStatus>, int> {
  GetUploadStatus(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, UploadStatus>> call(int jobId) {
    return repository.getUploadStatus(jobId);
  }
}
