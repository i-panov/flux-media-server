import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

class GetMediaDetail extends UseCase<Either<Failure, Media>, int> {
  GetMediaDetail(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, Media>> call(int id) {
    return repository.getMediaDetail(id);
  }
}
