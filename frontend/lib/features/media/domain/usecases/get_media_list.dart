import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

class GetMediaListParams {
  const GetMediaListParams({
    this.type,
    this.year,
    this.limit,
    this.offset,
  });

  final String? type;
  final int? year;
  final int? limit;
  final int? offset;
}

class GetMediaList {
  GetMediaList(this.repository);

  final MediaRepository repository;

  Future<Either<Failure, ({List<Media> items, int total})>> call(
    GetMediaListParams params,
  ) {
    return repository.getMediaList(
      type: params.type,
      year: params.year,
      limit: params.limit,
      offset: params.offset,
    );
  }
}
