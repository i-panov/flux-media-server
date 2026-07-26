import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/progress.dart';

/// Parameters for GetWatchProgress use case (none required).
class GetWatchProgressParams {
  const GetWatchProgressParams();
}

/// Fetches the user's watch progress for all media.
class GetWatchProgress
    extends UseCase<Either<Failure, List<WatchProgress>>, GetWatchProgressParams> {
  GetWatchProgress(this._repository);

  final MediaRepository _repository;

  @override
  Future<Either<Failure, List<WatchProgress>>> call(
    GetWatchProgressParams params,
  ) async {
    return _repository.getProgress();
  }
}
