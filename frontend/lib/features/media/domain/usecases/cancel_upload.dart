import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:fpdart/fpdart.dart';

class CancelUpload extends UseCase<Either<Failure, void>, int> {
  CancelUpload(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, void>> call(int jobId) {
    return repository.cancelUpload(jobId);
  }
}
