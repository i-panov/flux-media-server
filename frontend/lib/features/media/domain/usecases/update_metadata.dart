import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

class UpdateMetadataParams {
  const UpdateMetadataParams({
    required this.mediaId,
    required this.data,
  });

  final int mediaId;
  final Map<String, dynamic> data;
}

class UpdateMetadata
    extends UseCase<Either<Failure, Media>, UpdateMetadataParams> {
  UpdateMetadata(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, Media>> call(UpdateMetadataParams params) {
    return repository.updateMetadata(params.mediaId, params.data);
  }
}
