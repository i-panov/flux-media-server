import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

class GetMediaListParams {
  const GetMediaListParams({
    this.type,
    this.year,
    this.q,
    this.limit,
    this.offset,
    this.libraryId,
  });

  final String? type;
  final int? year;
  final String? q;
  final int? limit;
  final int? offset;
  final int? libraryId;
}

class GetMediaList
    extends UseCase<Either<Failure, ({List<Media> items, int total})>, GetMediaListParams> {
  GetMediaList(this.repository);

  final MediaRepository repository;

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> call(
    GetMediaListParams params,
  ) {
    return repository.getMediaList(
      type: params.type,
      year: params.year,
      q: params.q,
      limit: params.limit,
      offset: params.offset,
      libraryId: params.libraryId,
    );
  }
}
