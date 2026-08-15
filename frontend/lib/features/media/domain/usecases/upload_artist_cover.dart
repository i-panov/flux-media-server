import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:fpdart/fpdart.dart';

class UploadArtistCoverParams {
  const UploadArtistCoverParams({
    required this.artistId,
    required this.filePath,
    this.isCancelled,
  });

  final int artistId;
  final String filePath;

  /// Пользователь отменил загрузку — прервать запрос.
  final bool Function()? isCancelled;
}

/// Загружает обложку артиста.
class UploadArtistCover
    extends UseCase<Either<Failure, void>, UploadArtistCoverParams> {
  UploadArtistCover(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, void>> call(UploadArtistCoverParams params) {
    return repository.uploadArtistCover(
      params.artistId,
      params.filePath,
      isCancelled: params.isCancelled,
    );
  }
}
