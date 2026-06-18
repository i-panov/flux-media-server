import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/media.dart';

abstract class MediaRepository {
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    int? limit,
    int? offset,
  });

  Future<Either<Failure, Media>> getMediaDetail(int id);
}
