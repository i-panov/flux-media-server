import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:fpdart/fpdart.dart';

class CheckMediaHash extends UseCase<
    Either<Failure, ({bool exists, int? mediaId, String? title})>, String> {
  CheckMediaHash(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>> call(
    String params,
  ) {
    return repository.checkHash(params);
  }
}
