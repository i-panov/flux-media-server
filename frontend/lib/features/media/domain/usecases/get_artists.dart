import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:fpdart/fpdart.dart';

class GetArtists extends UseCase<Either<Failure, List<Artist>>, NoParams> {
  GetArtists(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, List<Artist>>> call(NoParams params) {
    return repository.getArtists();
  }
}
