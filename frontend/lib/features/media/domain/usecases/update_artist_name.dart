import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:fpdart/fpdart.dart';

class UpdateArtistNameParams {
  const UpdateArtistNameParams({required this.artistId, required this.name});

  final int artistId;
  final String name;
}

/// Переименовывает артиста: имя меняется у всех треков, к которым он
/// привязан (привязки идут по id).
class UpdateArtistName
    extends UseCase<Either<Failure, Artist>, UpdateArtistNameParams> {
  UpdateArtistName(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, Artist>> call(UpdateArtistNameParams params) {
    return repository.updateArtistName(params.artistId, params.name);
  }
}
