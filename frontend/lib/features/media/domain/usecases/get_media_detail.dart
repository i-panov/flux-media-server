import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

class GetMediaDetail {
  GetMediaDetail(this.repository);

  final MediaRepository repository;

  Future<Either<Failure, Media>> call(int id) {
    return repository.getMediaDetail(id);
  }
}
